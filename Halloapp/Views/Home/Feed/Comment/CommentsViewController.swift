//
//  CommentsView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/23/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import CoreData
import UIKit
import XMPPFramework

class CommentsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, CommentInputViewDelegate, NSFetchedResultsControllerDelegate, TextLabelDelegate {
    static private let cellReuseIdentifier = "CommentCell"
    static private let sectionMain = 0

    typealias ReplyContext = (parentCommentId: String, userId: String)

    private var feedPostId: FeedPostID?
    private var replyContext: ReplyContext? {
        didSet {
            self.refreshCommentInputViewReplyPanel()
            if let indexPaths = self.tableView.indexPathsForVisibleRows {
                self.tableView.reloadRows(at: indexPaths, with: .none)
            }
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
        tableView.backgroundColor = .feedBackground
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
        self.hidesBottomBarWhenPushed = true
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
        guard let feedPost = MainAppContext.shared.feedData.feedPost(with: self.feedPostId!) else { return }

        self.navigationItem.title = "Comments"

        if feedPost.userId == MainAppContext.shared.userData.userId {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .done, target: self, action: #selector(retractPost))
        }

        self.view.addSubview(self.tableView)
        self.tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor).isActive = true
        self.tableView.topAnchor.constraint(equalTo: self.view.topAnchor).isActive = true
        self.tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor).isActive = true
        self.tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true

        let headerView = CommentsTableHeaderView(frame: CGRect(x: 0, y: 0, width: self.tableView.bounds.size.width, height: 200))
        headerView.configure(withPost: feedPost)
        headerView.textLabel.delegate = self
        self.tableView.tableHeaderView = headerView

        let fetchRequest: NSFetchRequest<FeedPostComment> = FeedPostComment.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "post.id = %@", self.feedPostId!)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPostComment.timestamp, ascending: true) ]
        self.fetchedResultsController =
            NSFetchedResultsController<FeedPostComment>(fetchRequest: fetchRequest, managedObjectContext: MainAppContext.shared.feedData.viewContext,
                                                        sectionNameKeyPath: nil, cacheName: nil)
        self.fetchedResultsController?.delegate = self
        do {
            try self.fetchedResultsController!.performFetch()
            self.reloadComments()
        } catch {
            return
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewWillAppear()
        self.commentsInputView.willAppear(in: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewDidAppear()

        if let itemId = self.feedPostId {
            MainAppContext.shared.feedData.markCommentsAsRead(feedPostId: itemId)
        }

        self.commentsInputView.didAppear(in: self)
        if self.sortedComments.isEmpty {
            self.commentsInputView.showKeyboard(from: self)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewWillDisappear()

        if let itemId = self.feedPostId {
            MainAppContext.shared.feedData.markCommentsAsRead(feedPostId: itemId)
        }

        self.commentsInputView.willDisappear(in: self)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewDidDisappear()
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

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == tableView {
            updateNavigationBarStyleUsing(scrollView: scrollView)
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
        guard let feedPost = MainAppContext.shared.feedData.feedPost(with: self.feedPostId!) else {
            self.navigationController?.popViewController(animated: true)
            return
        }
        // Stop processing data changes because all comments are about to be deleted.
        self.fetchedResultsController?.delegate = nil
        MainAppContext.shared.feedData.retract(post: feedPost)
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
        guard let comment = MainAppContext.shared.feedData.feedComment(with: commentId) else { return }
        MainAppContext.shared.feedData.retract(comment: comment)
    }

    private func confirmResending(commentWithId commentId: FeedPostCommentID) {
        guard  let comment = MainAppContext.shared.feedData.feedComment(with: commentId) else { return }
        guard comment.status == .sendError else { return }
        let actionSheet = UIAlertController(title: nil, message: "Resend comment?", preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: "Resend", style: .default, handler: { _ in
            MainAppContext.shared.feedData.resend(commentWithId: commentId)
        }))
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        self.present(actionSheet, animated: true)
    }

    // MARK: Data

    private var trackPerRowFRCChanges = false

    private var reloadTableViewInDidChangeContent = false

    private var sortedComments: [FeedPostComment] = []

    private func reloadComments() {
        guard let comments = self.fetchedResultsController?.fetchedObjects else { return }

        func descendants(of comment: FeedPostComment) -> [FeedPostComment] {
            var comments = Array<FeedPostComment>(comment.replies ?? [])
            guard !comments.isEmpty else { return [ ] }
            comments.append(contentsOf: comments.flatMap{ descendants(of: $0) })
            return comments
        }

        var sorted: [FeedPostComment] = []
        comments.filter{ $0.parent == nil }.forEach { (comment) in
            sorted.append(comment)
            sorted.append(contentsOf: descendants(of: comment).sorted { $0.timestamp < $1.timestamp })
        }
        self.sortedComments = sorted
    }

    private func insert(comment: FeedPostComment) {
        var parent = comment
        while parent.parent != nil {
            parent = parent.parent!
        }
        var commentIndex = self.sortedComments.endIndex
        if let nextRootCommentIndex = self.sortedComments.firstIndex(where: { $0.parent == nil && $0.timestamp > parent.timestamp }) {
            commentIndex = nextRootCommentIndex
        }
        self.sortedComments.insert(comment, at: commentIndex)
        DDLogDebug("CommentsView/frc/insert Position: [\(commentIndex)] Comment: [\(comment)]")
        self.tableView.insertRows(at: [ IndexPath(row: commentIndex, section: CommentsViewController.sectionMain) ], with: .fade)
    }

    private func delete(comment: FeedPostComment) {
        guard let commentIndex = self.sortedComments.firstIndex(where: { $0 == comment }) else { return }
        self.sortedComments.remove(at: commentIndex)
        DDLogDebug("CommentsView/frc/delete Position: [\(commentIndex)] Comment: [\(comment)]")
        self.tableView.deleteRows(at: [ IndexPath(row: commentIndex, section: CommentsViewController.sectionMain) ], with: .fade)
    }

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        reloadTableViewInDidChangeContent = false
        trackPerRowFRCChanges = self.view.window != nil && UIApplication.shared.applicationState == .active
        DDLogDebug("CommentsView/frc/will-change perRowChanges=[\(trackPerRowFRCChanges)]")
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            if trackPerRowFRCChanges {
                if let comment = anObject as? FeedPostComment {
                    self.insert(comment: comment)
                }
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .delete:
            if trackPerRowFRCChanges {
                if let comment = anObject as? FeedPostComment {
                    self.delete(comment: comment)
                }
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .move:
            guard let fromIndexPath = indexPath, let toIndexPath = newIndexPath, let comment = anObject as? FeedPostComment else { break }
            DDLogDebug("CommentsView/frc/move [\(comment)] from [\(fromIndexPath)] to [\(toIndexPath)]")
            trackPerRowFRCChanges = false
            reloadTableViewInDidChangeContent = true

        case .update:
            guard let comment = anObject as? FeedPostComment else { return }
            let commentIndex = self.sortedComments.firstIndex(where: { $0 == comment })
            if trackPerRowFRCChanges && commentIndex != nil {
                DDLogDebug("CommentsView/frc/update Position: [\(commentIndex!)]  Comment: [\(comment)] ")
                // Update cell directly if there are animations attached to the UITableView.
                // This is done to prevent multiple animation from overlapping and breaking
                // smooth animation on new comment send.
                let tableViewIndexPath = IndexPath(row: commentIndex!, section: CommentsViewController.sectionMain)
                if self.tableView.layer.animationKeys()?.isEmpty ?? true {
                    self.tableView.reloadRows(at: [ tableViewIndexPath ], with: .fade)
                } else {
                    if let cell = self.tableView.cellForRow(at: tableViewIndexPath) as? CommentsTableViewCell {
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
        if !trackPerRowFRCChanges {
            self.reloadComments()
        }
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
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.sortedComments.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: CommentsViewController.cellReuseIdentifier, for: indexPath) as! CommentsTableViewCell
        let feedPostComment = self.sortedComments[indexPath.row]
        let commentId = feedPostComment.id
        let commentAuthorUserId = feedPostComment.userId
        cell.update(with: feedPostComment)
        cell.replyAction = { [ weak self ] in
            guard let self = self else { return }
            self.replyContext = (parentCommentId: commentId, userId: commentAuthorUserId)
            self.commentsInputView.showKeyboard(from: self)
        }
        cell.accessoryViewAction = { [weak self] in
            guard let self = self else { return }
            self.confirmResending(commentWithId: commentId)
        }
        cell.commentView.textLabel.delegate = self
        cell.isCellHighlighted = self.replyContext?.parentCommentId == commentId
        return cell
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Only allow to delete your own comments.
        let feedPostComment = self.sortedComments[indexPath.row]
        guard !feedPostComment.isCommentRetracted else { return false }
        return feedPostComment.userId == AppContext.shared.userData.userId && abs(feedPostComment.timestamp.timeIntervalSinceNow) < Date.hours(1)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        // Use this method instead of tableView(_:commit:forRowAt:) because this method
        // allows in-cell Delete button to stay visible when confirmation (action sheet) is presented.
        let feedPostComment = self.sortedComments[indexPath.row]
        let commentId = feedPostComment.id
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { (_, _, completionHandler) in
            self.retractComment(with: commentId, completionHandler: completionHandler)
        }
        return UISwipeActionsConfiguration(actions: [ deleteAction ])
    }

    // MARK: Input view

    lazy var commentsInputView: CommentInputView = {
        let inputView = CommentInputView(frame: .zero)
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
        guard let feedDataItem = MainAppContext.shared.feedData.feedDataItem(with: self.feedPostId!) else { return }
        self.scrollToBottomOnContentChange = true
        MainAppContext.shared.feedData.post(comment: text, to: feedDataItem, replyingTo: self.replyContext?.parentCommentId)
        self.commentsInputView.text = ""
        self.replyContext = nil
    }

    func commentInputViewResetReplyContext(_ inputView: CommentInputView) {
        self.replyContext = nil
    }

    private func refreshCommentInputViewReplyPanel() {
        if let context = self.replyContext {
            let contactName: String
            if context.userId == MainAppContext.shared.userData.userId {
                contactName = "myself"
            } else {
                contactName = AppContext.shared.contactStore.fullName(for: context.userId)
            }
            self.commentsInputView.showReplyPanel(with: contactName)
        } else {
            self.commentsInputView.removeReplyPanel()
        }
    }

    // MARK: TextLabelDelegate

    func textLabel(_ label: TextLabel, didRequestHandle link: AttributedTextLink) {
        switch link.textCheckingResult {
        case .link, .phoneNumber:
            if let url = link.url {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    UIApplication.shared.open(url, options: [:])
                }
            }

        default:
            break
        }
    }
}

fileprivate class CommentsTableViewCell: UITableViewCell {
    private(set) lazy var commentView: CommentView = {
        CommentView()
    }()

    var replyAction: (() -> ()) = {}

    var accessoryViewAction: (() -> ()) = {}

    var isCellHighlighted: Bool = false {
        didSet {
            self.backgroundColor = isCellHighlighted ? UIColor.lavaOrange.withAlphaComponent(0.1) : .clear
        }
    }

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
        self.backgroundColor = .clear
        
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

    @objc private func accessoryButtonAction() {
        self.accessoryViewAction()
    }

    func update(with comment: FeedPostComment) {
        self.commentView.updateWith(comment: comment)
        if comment.status == .sendError {
            self.accessoryView = {
                let button = UIButton(type: .system)
                button.setImage(UIImage(systemName: "exclamationmark.circle"), for: .normal)
                button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 6, bottom: 12, right: 6)
                button.tintColor = .red
                button.sizeToFit()
                button.addTarget(self, action: #selector(accessoryButtonAction), for: .touchUpInside)
                return button
            }()
        } else {
            self.accessoryView = nil
        }
    }
}
