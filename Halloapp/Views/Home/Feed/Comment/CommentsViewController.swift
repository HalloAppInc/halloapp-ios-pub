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
import XMPPFramework

class CommentsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, CommentInputViewDelegate, NSFetchedResultsControllerDelegate {
    static private let cellReuseIdentifier = "CommentCell"

    typealias ReplyContext = (parentCommentId: String, userId: String)

    private var feedPostId: FeedPostID?
    private var replyContext: ReplyContext? {
        didSet {
            self.refreshCommentInputViewReplyPanel()
        }
    }
    private var fetchedResultsController: NSFetchedResultsController<FeedPostComment>?
    private var scrollToBottomOnContentChange = false

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: self.view.bounds, style: .plain)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.contentInsetAdjustmentBehavior = .scrollableAxes
        tableView.keyboardDismissMode = .interactive
        tableView.preservesSuperviewLayoutMargins = true
        tableView.register(CommentsTableViewCell.self, forCellReuseIdentifier: CommentsViewController.cellReuseIdentifier)
        return tableView
    }()

    init(feedPostId: FeedPostID) {
        DDLogDebug("CommentsViewController/init/\(feedPostId)")
        self.feedPostId = feedPostId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        DDLogDebug("CommentsViewController/deinit/\(feedPostId ?? "")")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard self.feedPostId != nil else { return }
        guard let feedPost = AppContext.shared.feedData.feedPost(with: self.feedPostId!) else { return }

        self.navigationItem.title = "Comments"

        if feedPost.userId == AppContext.shared.userData.userId {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .done, target: self, action: #selector(retractPost))
        }

        self.view.addSubview(self.tableView)
        self.tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
        self.tableView.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        self.tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
        self.tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true

        let headerView = CommentsTableHeaderView(frame: CGRect(x: 0, y: 0, width: self.tableView.bounds.size.width, height: 200))
        headerView.commentView.updateWith(feedPost: feedPost)
        self.tableView.tableHeaderView = headerView

        let fetchRequest: NSFetchRequest<FeedPostComment> = FeedPostComment.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "post.id = %@", self.feedPostId!)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPostComment.timestamp, ascending: true) ]
        self.fetchedResultsController =
            NSFetchedResultsController<FeedPostComment>(fetchRequest: fetchRequest, managedObjectContext: AppContext.shared.feedData.viewContext,
                                                        sectionNameKeyPath: nil, cacheName: nil)
        self.fetchedResultsController?.delegate = self
        do {
            try self.fetchedResultsController!.performFetch()
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

        if let itemId = self.feedPostId {
            AppContext.shared.feedData.markCommentsAsRead(feedPostId: itemId)
        }

        self.commentsInputView.didAppear(in: self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if let itemId = self.feedPostId {
            AppContext.shared.feedData.markCommentsAsRead(feedPostId: itemId)
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

    // MARK: UI Actions

    @objc(deletePost)
    private func retractPost() {
        let actionSheet = UIAlertController(title: nil, message: "Delete this post? This action cannot be undone.", preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: "Delete Post", style: .destructive) { _ in
            self.reallyRetractPost()
        })
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        self.present(actionSheet, animated: true)
    }

    private func reallyRetractPost() {
        guard let feedPost = AppContext.shared.feedData.feedPost(with: self.feedPostId!) else {
            self.navigationController?.popViewController(animated: true)
            return
        }
        // Stop processing data changes because all comments are about to be deleted.
        self.fetchedResultsController?.delegate = nil
        AppContext.shared.feedData.retract(post: feedPost)
        self.navigationController?.popViewController(animated: true)
    }

    private func retractComment(with commentId: FeedPostCommentID, completionHandler: @escaping (Bool) -> Void) {
        let actionSheet = UIAlertController(title: nil, message: "Delete this comment? This action cannot be undone.", preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: "Delete Comment", style: .destructive) { _ in
            self.reallyRetract(commentWithId: commentId)
            completionHandler(true)
        })
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completionHandler(false)
        })
        self.present(actionSheet, animated: true)
    }

    private func reallyRetract(commentWithId commentId: FeedPostCommentID) {
        guard let comment = AppContext.shared.feedData.feedComment(with: commentId) else { return }
        AppContext.shared.feedData.retract(comment: comment)
    }

    // MARK: Data

    private var trackPerRowFRCChanges = false

    private var reloadTableViewInDidChangeContent = false

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        reloadTableViewInDidChangeContent = false
        trackPerRowFRCChanges = self.view.window != nil && UIApplication.shared.applicationState == .active
        DDLogDebug("CommentsView/frc/will-change perRowChanges=[\(trackPerRowFRCChanges)]")
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            guard let indexPath = newIndexPath, let comment = anObject as? FeedPostComment else { break }
            DDLogDebug("CommentsView/frc/insert [\(comment)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                self.tableView.insertRows(at: [ indexPath ], with: .fade)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .delete:
            guard let indexPath = indexPath, let comment = anObject as? FeedPostComment else { break }
            DDLogDebug("CommentsView/frc/delete [\(comment)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                self.tableView.deleteRows(at: [ indexPath ], with: .fade)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .move:
            guard let fromIndexPath = indexPath, let toIndexPath = newIndexPath, let comment = anObject as? FeedPostComment else { break }
            DDLogDebug("CommentsView/frc/move [\(comment)] from [\(fromIndexPath)] to [\(toIndexPath)]")
            if trackPerRowFRCChanges {
                self.tableView.moveRow(at: fromIndexPath, to: toIndexPath)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .update:
            guard let indexPath = indexPath, let comment = anObject as? FeedPostComment else { return }
            DDLogDebug("CommentsView/frc/update [\(comment)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                // Update cell directly if there are animations attached to the UITableView.
                // This is done to prevent multiple animation from overlapping and breaking
                // smooth animation on new comment send.
                if self.tableView.layer.animationKeys()?.isEmpty ?? true {
                    self.tableView.reloadRows(at: [ indexPath ], with: .fade)
                } else {
                    if let cell = self.tableView.cellForRow(at: indexPath) as? CommentsTableViewCell {
                        cell.update(with: comment)
                    }
                }
            } else {
                reloadTableViewInDidChangeContent = true
            }

        default:
            break
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DDLogDebug("CommentsView/frc/did-change perRowChanges=[\(trackPerRowFRCChanges)]  reload=[\(reloadTableViewInDidChangeContent)]")
        if reloadTableViewInDidChangeContent {
            self.tableView.reloadData()
        }
        // TODO: Scroll table view on new comment from someone else.
        if self.scrollToBottomOnContentChange {
            DispatchQueue.main.async {
                self.scrollToBottom(true)
            }
            self.scrollToBottomOnContentChange = false
        }
    }

    private func scrollToBottom(_ animated: Bool = true) {
        if let numSections = self.fetchedResultsController?.sections?.count, let numRows = self.fetchedResultsController?.sections?.last?.numberOfObjects {
            if numSections > 0 && numRows > 0 {
                let indexPath = IndexPath(row: numRows - 1, section: numSections - 1)
                self.tableView.scrollToRow(at: indexPath, at: .none, animated: animated)
            }
        }
    }

    // MARK: UITableView

    func numberOfSections(in tableView: UITableView) -> Int {
        return self.fetchedResultsController?.sections?.count ?? 0
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sections = self.fetchedResultsController?.sections else { return 0 }
        return sections[section].numberOfObjects
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: CommentsViewController.cellReuseIdentifier, for: indexPath) as! CommentsTableViewCell
        if let feedPostComment = fetchedResultsController?.object(at: indexPath) {
            cell.update(with: feedPostComment)
            cell.replyAction = { [ weak self ] in
                guard let self = self else { return }
                self.replyContext = (parentCommentId: feedPostComment.id, userId: feedPostComment.userId)
                self.commentsInputView.showKeyboard(from: self)
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Only allow to delete your own comments.
        guard let feedPostComment = self.fetchedResultsController?.object(at: indexPath) else { return false }
        guard !feedPostComment.isCommentRetracted else { return false }
        return feedPostComment.userId == AppContext.shared.userData.userId
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        // Use this method instead of tableView(_:commit:forRowAt:) because this method
        // allows in-cell Delete button to stay visible when confirmation (action sheet) is presented.
        guard let feedPostComment = self.fetchedResultsController?.object(at: indexPath) else { return nil }
        let commentId = feedPostComment.id
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { (_, _, completionHandler) in
            self.retractComment(with: commentId, completionHandler: completionHandler)
        }
        return UISwipeActionsConfiguration(actions: [ deleteAction ])
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
        guard let feedDataItem = AppContext.shared.feedData.feedDataItem(with: self.feedPostId!) else { return }
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


fileprivate class CommentsTableHeaderView: UIView {
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
        self.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|-8-[content]-[separator]|", options: [], metrics: nil, views: views))
        let separatorHeight = 1.0 / UIScreen.main.scale
        self.addConstraint(NSLayoutConstraint(item: separatorView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1.0, constant: separatorHeight))
    }
}


fileprivate class CommentsTableViewCell: UITableViewCell {
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

    func update(with comment: FeedPostComment) {
        self.commentView.updateWith(comment: comment)
        self.commentView.isContentInset = comment.parent != nil
    }
}
