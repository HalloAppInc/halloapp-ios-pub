//
//  CommentsView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/23/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import CoreData
import UIKit

class CommentsViewController: UIViewController, CommentInputViewDelegate, NSFetchedResultsControllerDelegate {
    static private let cellReuseIdentifier = "CommentCell"
    static private let sectionMain = 0

    typealias ReplyContext = (parentCommentId: String, userId: String)

    private var feedItemId: String?
    private var replyContext: ReplyContext? {
        didSet {
            self.refreshCommentInputViewReplyPanel()
        }
    }
    private var dataSource: UITableViewDiffableDataSource<Int, FeedComment>?
    private var fetchedResultsController: NSFetchedResultsController<FeedComments>?
    private var scrollToBottomOnContentChange = false

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: self.view.bounds, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.contentInsetAdjustmentBehavior = .scrollableAxes
        tableView.keyboardDismissMode = .interactive
        tableView.preservesSuperviewLayoutMargins = true
        tableView.register(CommentsTableViewCell.self, forCellReuseIdentifier: CommentsViewController.cellReuseIdentifier)
        return tableView
    }()

    init(feedItemId: String) {
        DDLogDebug("CommentsViewController/init/\(feedItemId)")
        self.feedItemId = feedItemId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func dismantle() {
        DDLogDebug("CommentsViewController/dismantle/\(feedItemId ?? "")")
        self.fetchedResultsController = nil
    }

    override func viewDidLoad() {
        guard self.feedItemId != nil else { return }
        guard let feedDataItem = AppContext.shared.feedData.feedDataItem(with: self.feedItemId!) else { return }

        self.view.addSubview(self.tableView)
        self.tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
        self.tableView.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        self.tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
        self.tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true

        let headerView = CommentsTableHeaderView(frame: CGRect(x: 0, y: 0, width: self.tableView.bounds.size.width, height: 200))
        headerView.commentView.updateWith(feedItem: feedDataItem)
        self.tableView.tableHeaderView = headerView

        self.dataSource = UITableViewDiffableDataSource<Int, FeedComment>(tableView: self.tableView) { [weak self] tableView, indexPath, feedComment in
            let cell = tableView.dequeueReusableCell(withIdentifier: CommentsViewController.cellReuseIdentifier, for: indexPath) as! CommentsTableViewCell
            cell.update(with: feedComment)
            cell.replyAction = {
                guard let self = self else { return }
                self.replyContext = (parentCommentId: feedComment.id, userId: feedComment.username)
                self.commentsInputView.showKeyboard(from: self)
            }
            return cell
        }

        let fetchRequest = NSFetchRequest<FeedComments>(entityName: "FeedComments")
        fetchRequest.predicate = NSPredicate(format: "feedItemId = %@", self.feedItemId!)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedComments.timestamp, ascending: true) ]
        self.fetchedResultsController =
            NSFetchedResultsController<FeedComments>(fetchRequest: fetchRequest,
                                                     managedObjectContext: CoreDataManager.sharedManager.persistentContainer.viewContext,
                                                     sectionNameKeyPath: nil, cacheName: nil)
        self.fetchedResultsController?.delegate = self
        do {
            try self.fetchedResultsController!.performFetch()
            self.updateData(animatingDifferences: false)
        } catch {
            return
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.commentsInputView.willAppear(in: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if let itemId = self.feedItemId {
            AppContext.shared.feedData.markFeedItemUnreadComments(feedItemId: itemId)
        }

        self.commentsInputView.didAppear(in: self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if let itemId = self.feedItemId {
            AppContext.shared.feedData.markFeedItemUnreadComments(feedItemId: itemId)
        }

        self.commentsInputView.willDisappear(in: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if let headerView = self.tableView.tableHeaderView {
            let targetSize = CGSize(width: self.tableView.bounds.size.width, height: UIView.layoutFittingCompressedSize.height)
            let size = headerView.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
            if size.height != headerView.bounds.size.height {
                headerView.frame.size.height = size.height
                self.tableView.tableHeaderView = headerView
            }
        }
    }

    // MARK: Data

    func updateData(animatingDifferences: Bool = true) {
        guard let coreDataResults = self.fetchedResultsController?.fetchedObjects else { return }
        let allComments = coreDataResults.map{ FeedComment($0) }
        var results: [FeedComment] = []

        func findChildren(of commendID: String?) {
            let children = allComments.filter{ $0.parentCommentId == commendID }
            for child in children {
                results.append(child)
                findChildren(of: child.id)
            }
        }

        findChildren(of: nil)

        var diffableDataSourceSnapshot = NSDiffableDataSourceSnapshot<Int, FeedComment>()
        diffableDataSourceSnapshot.appendSections([ CommentsViewController.sectionMain ])
        diffableDataSourceSnapshot.appendItems(results)
        self.dataSource?.apply(diffableDataSourceSnapshot, animatingDifferences: animatingDifferences)
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        let animateChanges = self.view.window != nil && UIApplication.shared.applicationState == .active
        self.updateData(animatingDifferences: animateChanges)
        // TODO: Scroll table view on new comment from someone else.
        if self.scrollToBottomOnContentChange {
            self.scrollToBottom()
            self.scrollToBottomOnContentChange = false
        }
    }

    private func scrollToBottom(_ animated: Bool = true) {
        if let dataSnapshot = self.dataSource?.snapshot() {
            let numberOfRows = dataSnapshot.numberOfItems(inSection: CommentsViewController.sectionMain)
            let indexPath = IndexPath(row: numberOfRows - 1, section: CommentsViewController.sectionMain)
            self.tableView.scrollToRow(at: indexPath, at: .none, animated: animated)
        }
    }

    // MARK: Input view

    lazy var commentsInputView: CommentInputView = {
        let inputView = CommentInputView(frame: CGRect(x: 0, y: 0, width: self.view.frame.size.width, height: 90))
        inputView.delegate = self
        return inputView
    }()

    override var canBecomeFirstResponder: Bool {
        get {
            return true
        }
    }

    override var inputAccessoryView: UIView? {
        self.commentsInputView.setInputViewWidth(self.view.bounds.size.width)
        return self.commentsInputView
    }

    func updateTableViewContentInsets(with keyboardHeight: CGFloat, adjustContentOffset: Bool) {
        let topInset = self.tableView.contentInset.top
        let bottomInset = keyboardHeight - self.tableView.safeAreaInsets.bottom

        let currentInset = self.tableView.contentInset
        var contentOffset = self.tableView.contentOffset
        var adjustContentOffset = adjustContentOffset
        if bottomInset > currentInset.bottom && currentInset.bottom == 0 {
            // Because of the SwiftUI the accessory view appears with a slight delay
            // and bottom inset increased from 0 to some value. Do not scroll when that happens.
            adjustContentOffset = false
        }
        if adjustContentOffset {
            contentOffset.y += bottomInset - currentInset.bottom
        }
        if (adjustContentOffset) {
            self.tableView.contentOffset = contentOffset
        }
        // Setting contentInset below will also adjust contentOffset as needed if it is outside of the
        // UITableView's scrollable range.
        self.tableView.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        let scrollIndicatorInsets = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        self.tableView.scrollIndicatorInsets = scrollIndicatorInsets
    }

    func commentInputView(_ inputView: CommentInputView, didChangeBottomInsetWith animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {
        var animationDuration = animationDuration
        if self.transitionCoordinator != nil {
            animationDuration = 0
        }
        var adjustContentOffset = true
        // Prevent the content offset from changing when the user drags the keyboard down.
        if self.tableView.panGestureRecognizer.state == .ended || self.tableView.panGestureRecognizer.state == .changed {
            adjustContentOffset = false
        }
        let updateBlock = {
            self.updateTableViewContentInsets(with: inputView.bottomInset, adjustContentOffset: adjustContentOffset)
        }
        if animationDuration > 0 {
            updateBlock()
        } else {
            UIView.performWithoutAnimation(updateBlock)
        }
    }

    func commentInputView(_ inputView: CommentInputView, wantsToSend text: String) {
        guard let feedDataItem = AppContext.shared.feedData.feedDataItem(with: self.feedItemId!) else { return }
        self.scrollToBottomOnContentChange = true
        AppContext.shared.feedData.post(comment: text, to: feedDataItem, replyingTo: self.replyContext?.parentCommentId)
        self.commentsInputView.text = ""
        self.replyContext = nil
    }

    func commentInputViewResetReplyContext(_ inputView: CommentInputView) {
        self.replyContext = nil
    }

    private func refreshCommentInputViewReplyPanel() {
        if let context = self.replyContext {
            let contactName = AppContext.shared.contactStore.fullName(for: context.userId)
            self.commentsInputView.showReplyPanel(with: contactName)
        } else {
            self.commentsInputView.removeReplyPanel()
        }
    }
}


class CommentsTableHeaderView: UIView {
    lazy var commentView: CommentView = {
        let commentView = CommentView()
        commentView.isReplyButtonVisible = false
        return commentView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        self.preservesSuperviewLayoutMargins = true

        self.commentView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.commentView)

        let separatorView = UIView()
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = UIColor.separator
        self.addSubview(separatorView)

        let views = [ "content": self.commentView, "separator": separatorView]
        self.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "|-[content]-|", options: .directionLeadingToTrailing, metrics: nil, views: views))
        self.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "|[separator]|", options: .directionLeadingToTrailing, metrics: nil, views: views))
        self.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-[content]-[separator]|", options: [], metrics: nil, views: views))
        let separatorHeight = 1.0 / UIScreen.main.scale
        self.addConstraint(NSLayoutConstraint(item: separatorView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1.0, constant: separatorHeight))
    }
}


class CommentsTableViewCell: UITableViewCell {
    private lazy var commentView: CommentView = {
        CommentView()
    }()

    var replyAction: (() -> ()) = {}

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupTableViewCell()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTableViewCell()
    }

    private func setupTableViewCell() {
        self.selectionStyle = .none
        
        self.contentView.addSubview(self.commentView)
        self.commentView.translatesAutoresizingMaskIntoConstraints = false
        self.commentView.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        self.commentView.topAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.topAnchor).isActive = true
        self.commentView.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor).isActive = true
        self.commentView.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor).isActive = true

        self.commentView.replyButton.addTarget(self, action: #selector(self.replyButtonAction), for: .touchUpInside)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.replyAction = {}
    }

    @objc private func replyButtonAction() {
        self.replyAction()
    }

    func update(with comment: FeedComment) {
        self.commentView.updateWith(commentItem: comment)
        self.commentView.isContentInset = !(comment.parentCommentId?.isEmpty ?? false)
    }
}
