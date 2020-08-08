//
//  CommentsView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/23/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import CoreData
import UIKit
import XMPPFramework

class CommentsViewController: UIViewController {

    private let feedPostId: FeedPostID
    var highlightedCommentId: FeedPostCommentID?

    private var commentsViewController: CommentsViewControllerInternal!
    private var loadingViewController: LoadingViewController!

    private var postLoadingCancellable: AnyCancellable?

    init(feedPostId: FeedPostID) {
        self.feedPostId = feedPostId
        super.init(nibName: nil, bundle: nil)
        self.hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if MainAppContext.shared.feedData.feedPost(with: feedPostId) != nil {
            showCommentsViewController()
        } else {
            loadingViewController = LoadingViewController()
            self.view.addSubview(loadingViewController.view)
            self.addChild(loadingViewController)
            loadingViewController.didMove(toParent: self)

            postLoadingCancellable = MainAppContext.shared.feedData.didReceiveFeedPost.sink { [weak self] (feedPost) in
                guard let self = self else { return }
                guard self.feedPostId == feedPost.id else { return }
                self.showCommentsViewController()
            }
        }
    }

    private func showCommentsViewController() {
        if loadingViewController != nil {
            loadingViewController.willMove(toParent: nil)
            loadingViewController.view.removeFromSuperview()
            loadingViewController.removeFromParent()
            loadingViewController = nil
        }

        commentsViewController = CommentsViewControllerInternal(feedPostId: feedPostId)
        commentsViewController.highlightedCommentId = highlightedCommentId
        self.view.addSubview(commentsViewController.view)
        self.addChild(commentsViewController)
        commentsViewController.didMove(toParent: self)

        if postLoadingCancellable != nil {
            postLoadingCancellable?.cancel()
            postLoadingCancellable = nil
        }
    }

}

fileprivate class CommentsViewControllerInternal: UITableViewController, CommentInputViewDelegate, NSFetchedResultsControllerDelegate, TextLabelDelegate {

    static private let cellReuseIdentifier = "CommentCell"
    static private let cellHighlightAnimationDuration = 0.15
    static private let sectionMain = 0

    typealias ReplyContext = (parentCommentId: String, userId: String)

    private var feedPostId: FeedPostID {
        didSet {
            mentionableUsers = computeMentionableUsers()
        }
    }
    var highlightedCommentId: FeedPostCommentID?
    private var replyContext: ReplyContext? {
        // Manually update cell highlighting to avoid conflicts with potential keyboard animations.
        willSet {
            if let replyContext = replyContext {
                for cell in tableView.visibleCells.compactMap({ $0 as? CommentsTableViewCell }) {
                    if cell.commentId == replyContext.parentCommentId {
                        UIView.animate(withDuration: Self.cellHighlightAnimationDuration) {
                            cell.isCellHighlighted = cell.commentId == self.highlightedCommentId
                        }
                        break
                    }
                }
            }
        }
        didSet {
            self.refreshCommentInputViewReplyPanel()
        }
    }
    private var fetchedResultsController: NSFetchedResultsController<FeedPostComment>?
    private lazy var mentionableUsers: [MentionableUser] = {
        computeMentionableUsers()
    }()

    init(feedPostId: FeedPostID) {
        DDLogDebug("CommentsView/init/\(feedPostId)")
        self.feedPostId = feedPostId
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        DDLogDebug("CommentsView/deinit/\(feedPostId)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.backgroundColor = .feedBackground
        tableView.contentInsetAdjustmentBehavior = .scrollableAxes
        tableView.keyboardDismissMode = .interactive
        tableView.preservesSuperviewLayoutMargins = true
        tableView.register(CommentsTableViewCell.self, forCellReuseIdentifier: Self.cellReuseIdentifier)

        if let highlightedCommentId = highlightedCommentId {
            setNeedsScroll(toComment: highlightedCommentId, highlightAfterScroll: false, animated: false)
        }

        guard let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId) else { return }

        let headerView = CommentsTableHeaderView(frame: CGRect(x: 0, y: 0, width: self.tableView.bounds.size.width, height: 200))
        headerView.configure(withPost: feedPost)
        headerView.textLabel.delegate = self
        headerView.profilePictureButton.addTarget(self, action: #selector(showUserFeedForPostAuthor), for: .touchUpInside)
        self.tableView.tableHeaderView = headerView

        let fetchRequest: NSFetchRequest<FeedPostComment> = FeedPostComment.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "post.id = %@", feedPostId)
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

    override func willMove(toParent parent: UIViewController?) {
        super.willMove(toParent: parent)
        if let parent = parent, let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId) {
            parent.navigationItem.title = "Comments"
            if feedPost.userId == MainAppContext.shared.userData.userId {
                parent.navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .done, target: self, action: #selector(retractPost))
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewWillAppear()
        self.commentsInputView.willAppear(in: self)

        if view.window == nil {
            setNeedsScrollToTarget(withAnimation: false)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewDidAppear()

        MainAppContext.shared.feedData.markCommentsAsRead(feedPostId: feedPostId)

        self.commentsInputView.didAppear(in: self)
        if self.sortedComments.isEmpty {
            self.commentsInputView.showKeyboard(from: self)
        }

        allowScrollToBottom = true

        resetCommentHighlightingIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewWillDisappear()

        MainAppContext.shared.feedData.markCommentsAsRead(feedPostId: feedPostId)

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

        if let animated = needsScrollToTargetWithAnimation {
            if animated {
                scrollToTarget(withAnimation: true)
            } else {
                UIView.performWithoutAnimation {
                    self.scrollToTarget(withAnimation: false)
                    self.tableView.layoutIfNeeded()
                }
            }
            needsScrollToTargetWithAnimation = nil

            commentToScrollTo = nil
            needsHighlightCommentToScrollTo = false

        }
    }

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == tableView {
            updateNavigationBarStyleUsing(scrollView: scrollView)
        }
    }

    // MARK: Scrolling / highlighting

    private var preventAdjustContentOffsetOnChatBarBottomInsetChangeCounter = 0
    private var commentToScrollTo: FeedPostCommentID?
    private var needsHighlightCommentToScrollTo: Bool = false
    private var needsScrollToTargetWithAnimation: Bool?
    private var commentToHighlightAfterScrollingEnds: FeedPostCommentID?
    private var allowScrollToBottom = false

    private func scrollToBottom(animated: Bool) {
        guard let indexPath = bottomMostIndexPath() else {
            return
        }
        scrollIndexPathToBottom(indexPath, animated: animated)
    }

    private func scrollIndexPathToBottom(_ indexPath: IndexPath, animated: Bool) {
        tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
    }

    private func setNeedsScrollToTarget(withAnimation: Bool) {
        needsScrollToTargetWithAnimation = withAnimation
        tableView.setNeedsLayout()
    }

    private func setNeedsScroll(toComment comment: FeedPostCommentID, highlightAfterScroll: Bool, animated: Bool) {
        commentToScrollTo = comment
        needsHighlightCommentToScrollTo = highlightAfterScroll
        setNeedsScrollToTarget(withAnimation: animated)
    }

    private func scrollToTarget(withAnimation: Bool) {
        var animated = withAnimation
        if animated {
            animated = isViewLoaded && view.window != nil && transitionCoordinator == nil
        }
        if let comment = commentToScrollTo  {
            scroll(toComment: comment, animated: animated, highlightAfterScroll: needsHighlightCommentToScrollTo ? comment : nil)
        } else {
            if allowScrollToBottom {
                scrollToBottom(animated: animated)
            }
        }
    }

    private func scroll(toComment commentId: FeedPostCommentID, animated: Bool, highlightAfterScroll: FeedPostCommentID?) {

        guard let indexPath = indexPath(forCommentId: commentId) else {
            return
        }

        DDLogDebug("CommentsView/scroll/animated/\(animated)/comment/\(indexPath)")
        tableView.scrollToRow(at: indexPath, at: .middle, animated: animated)

        if let commentToHighlight = highlightAfterScroll {
            if tableView.hasScrollAnimation {
                commentToHighlightAfterScrollingEnds = commentToHighlight
            } else {
                highlightComment(commentToHighlight)
            }
        }
    }

    private func highlightComment(_ commentId: FeedPostCommentID) {
        for cell in tableView.visibleCells.compactMap({ $0 as? CommentsTableViewCell }) {
            if cell.commentId == commentId {
                UIView.animate(withDuration: Self.cellHighlightAnimationDuration) {
                    cell.isCellHighlighted = true
                }
                break
            }
        }
    }

    private func resetCommentHighlightingIfNeeded() {
        func unhighlightComment(_ commentId: FeedPostCommentID) {
            for cell in tableView.visibleCells.compactMap({ $0 as? CommentsTableViewCell }) {
                if cell.commentId == commentId && cell.isCellHighlighted {
                    UIView.animate(withDuration: Self.cellHighlightAnimationDuration) {
                        cell.isCellHighlighted = false
                    }
                }
            }
        }

        // It is possible that comment isn't received yet - when opening Comments from an iOS notification.
        // We'll wait until the comment arrives and then flash its cell.
        if let commentId = highlightedCommentId, indexPath(forCommentId: commentId) != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                unhighlightComment(commentId)
            }
            highlightedCommentId = nil
        }
    }

    override func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        if let commentId = commentToHighlightAfterScrollingEnds{
            DDLogDebug("CommentsView/content-offset-change/animated/ended: [\(tableView.contentOffset)]")
            highlightComment(commentId)
            commentToHighlightAfterScrollingEnds = nil
        }
    }

    // MARK: UI Actions

    @objc private func showUserFeedForPostAuthor() {
        if let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId) {
            showUserFeed(for: feedPost.userId)
        }
    }

    private func showUserFeed(for userID: UserID) {
        let userViewController = UserFeedViewController(userID: userID)
        self.navigationController?.pushViewController(userViewController, animated: true)
    }

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
        guard let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId) else {
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

    private var trackingPerRowFRCChanges = false

    private var needsScrollToTargetAfterTableUpdates = false

    private var numberOfInsertedItems = 0

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

    private func indexPath(forCommentId commentId: FeedPostCommentID) -> IndexPath? {
        guard let commentIndex = sortedComments.firstIndex(where: { $0.id == commentId }) else { return nil }
        return IndexPath(row: commentIndex, section: Self.sectionMain)
    }

    private func bottomMostIndexPath() -> IndexPath? {
        guard !sortedComments.isEmpty else {
            return nil
        }
        return IndexPath(row: sortedComments.count - 1, section: Self.sectionMain)
    }

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        trackingPerRowFRCChanges = isViewLoaded && view.window != nil && UIApplication.shared.applicationState == .active
        if trackingPerRowFRCChanges {
            numberOfInsertedItems = 0
            CATransaction.begin()
        }

        DDLogDebug("CommentsView/frc/will-change perRowChanges=[\(trackingPerRowFRCChanges)]")
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {

        DDLogDebug("CommentsView/frc/\(type) indexpath=[\(String(describing: indexPath))] object=[\(anObject)]")

        guard trackingPerRowFRCChanges else {
            return
        }

        func insert(comment: FeedPostComment) {
            var currentRoot = comment
            while let parent = currentRoot.parent {
                currentRoot = parent
            }
            var commentIndex = self.sortedComments.endIndex
            if let nextRootCommentIndex = self.sortedComments.firstIndex(where: { $0.parent == nil && $0.timestamp > currentRoot.timestamp }) {
                commentIndex = nextRootCommentIndex
            }
            sortedComments.insert(comment, at: commentIndex)
            DDLogDebug("CommentsView/frc/insert Position: [\(commentIndex)] Comment: [\(comment)]")
            tableView.insertRows(at: [ IndexPath(row: commentIndex, section: Self.sectionMain) ], with: .none)
        }

        switch type {
        case .insert:
            insert(comment: anObject as! FeedPostComment)
            numberOfInsertedItems += 1
            needsScrollToTargetAfterTableUpdates = true

        case .delete, .move:
            // Delete and Move should not happen at this time.
            assert(false, "Unexpected FRC operation.")

        case .update:
            guard let comment = anObject as? FeedPostComment,
                let commentIndex = sortedComments.firstIndex(where: { $0 == comment }) else { return }

            DDLogDebug("CommentsView/frc/update Position: [\(commentIndex)]  Comment: [\(comment)] ")
            // Update cell directly if there are animations attached to the UITableView.
            // This is done to prevent multiple animation from overlapping and breaking
            // smooth animation on new comment send.
            let tableViewIndexPath = IndexPath(row: commentIndex, section: Self.sectionMain)
            if tableView.hasScrollAnimation {
                if let cell = tableView.cellForRow(at: tableViewIndexPath) as? CommentsTableViewCell {
                    cell.update(with: comment)
                }
            } else {
                tableView.reloadRows(at: [ tableViewIndexPath ], with: .none)
            }

        default:
            break
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DDLogDebug("CommentsView/frc/did-change perRowChanges=[\(trackingPerRowFRCChanges)]")

        if !trackingPerRowFRCChanges {
            reloadComments()
            tableView.reloadData()
            didUpdateCommentsTableAfterControllerDidChangeContent()
            return
        }

        var needsNotify = true
        var notifyImmediately = false
        if numberOfInsertedItems == 1 {
            // Special case when the user hits Send from the chat bar - in this case we know
            // that scrolling will always work right away. Deferring scrolling until the table
            // view update animation finishes ruins the effect -- we want the new message to
            // scroll in while the chat bar shrinks back to its original height.
            notifyImmediately = true
        }

        CATransaction.setCompletionBlock {
            if needsNotify {
                needsNotify = false
                self.didUpdateCommentsTableAfterControllerDidChangeContent()
            }
        }

        CATransaction.commit() // triggers a full layout pass

        trackingPerRowFRCChanges = false
        if needsNotify && notifyImmediately {
            needsNotify = false
            didUpdateCommentsTableAfterControllerDidChangeContent()
        }
    }

    private func didUpdateCommentsTableAfterControllerDidChangeContent() {
        if needsScrollToTargetAfterTableUpdates {
            needsScrollToTargetAfterTableUpdates = false
            DispatchQueue.main.async {
                self.setNeedsScrollToTarget(withAnimation: true)
            }
        }
    }

    // MARK: UITableView

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.sortedComments.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellReuseIdentifier, for: indexPath) as! CommentsTableViewCell
        let feedPostComment = self.sortedComments[indexPath.row]
        let commentId = feedPostComment.id
        let commentAuthorUserId = feedPostComment.userId
        cell.update(with: feedPostComment)
        cell.openProfileAction = { [weak self] in
            guard let self = self else { return }
            self.showUserFeed(for: commentAuthorUserId)
        }
        cell.replyAction = { [ weak self ] in
            guard let self = self else { return }
            self.replyContext = (parentCommentId: commentId, userId: commentAuthorUserId)
            self.setNeedsScroll(toComment: commentId, highlightAfterScroll: true, animated: true)
            self.commentsInputView.showKeyboard(from: self)
        }
        cell.accessoryViewAction = { [weak self] in
            guard let self = self else { return }
            self.confirmResending(commentWithId: commentId)
        }
        cell.commentView.textLabel.delegate = self
        cell.isCellHighlighted = self.replyContext?.parentCommentId == commentId || self.highlightedCommentId == commentId
        return cell
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Only allow to delete your own comments.
        let feedPostComment = self.sortedComments[indexPath.row]
        guard !feedPostComment.isCommentRetracted else { return false }
        return feedPostComment.userId == AppContext.shared.userData.userId && abs(feedPostComment.timestamp.timeIntervalSinceNow) < Date.hours(1)
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
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

    func updateTableViewContentOffset(forKeyboardHeight keyboardHeight: CGFloat) {
        let bottomInset = keyboardHeight
        let currentInset = self.tableView.adjustedContentInset
        var contentOffset = self.tableView.contentOffset

        DDLogDebug("CommentsView/keyboard Bottom inset: [\(bottomInset)]  Current insets: [\(currentInset)]")

        if bottomInset > currentInset.bottom && currentInset.bottom == tableView.safeAreaInsets.bottom {
            // Because of the SwiftUI the accessory view appears with a slight delay
            // and bottom inset increased from 0 to some value. Do not scroll when that happens.
            return
        }

        contentOffset.y += bottomInset - currentInset.bottom

        contentOffset.y = min(contentOffset.y, tableView.contentSize.height - (tableView.frame.height - currentInset.top - bottomInset))
        contentOffset.y = max(contentOffset.y, -currentInset.top)

        DDLogDebug("CommentsView/keyboard Content offset: [\(tableView.contentOffset)] -> [\(contentOffset)]")
        self.tableView.contentOffset = contentOffset
    }

    func commentInputView(_ inputView: CommentInputView, didChangeBottomInsetWith animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {

        // Prevent the content offset from changing when the user drags the keyboard down.
        if self.tableView.panGestureRecognizer.state == .ended || self.tableView.panGestureRecognizer.state == .changed {
            return
        }
        guard preventAdjustContentOffsetOnChatBarBottomInsetChangeCounter == 0 else {
            return
        }

        let animationDuration = self.transitionCoordinator == nil ? animationDuration : 0
        let updateBlock = {
            self.updateTableViewContentOffset(forKeyboardHeight: inputView.bottomInset)
        }
        if animationDuration > 0 {
            let animationOptions = UIView.AnimationOptions(rawValue: UInt(animationCurve.rawValue) << 16)
            UIView.animate(withDuration: animationDuration, delay: 0, options: animationOptions, animations: updateBlock)
        } else {
            UIView.performWithoutAnimation(updateBlock)
        }
    }

    func computeMentionableUsers() -> [MentionableUser] {
        return Mentions.mentionableUsers(forPostID: feedPostId)
    }

    func commentInputView(_ inputView: CommentInputView, possibleMentionsForInput input: String) -> [MentionableUser] {
        return mentionableUsers.filter { Mentions.isPotentialMatch(fullName: $0.fullName, input: input) }
    }

    func commentInputView(_ inputView: CommentInputView, wantsToSend text: MentionText) {
        guard let feedDataItem = MainAppContext.shared.feedData.feedDataItem(with: feedPostId) else { return }

        let parentCommentId = replyContext?.parentCommentId
        MainAppContext.shared.feedData.post(comment: text, to: feedDataItem, replyingTo: parentCommentId)

        replyContext = nil
        commentsInputView.clear()

        preventAdjustContentOffsetOnChatBarBottomInsetChangeCounter += 1
        DispatchQueue.main.async {
            self.preventAdjustContentOffsetOnChatBarBottomInsetChangeCounter -= 1
        }
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
                self.commentsInputView.addReplyMentionIfPossible(for: context.userId, name: contactName)
            }
            self.commentsInputView.showReplyPanel(with: contactName)
        } else {
            self.commentsInputView.removeReplyPanel()
        }
    }

    // MARK: TextLabelDelegate

    func textLabel(_ label: TextLabel, didRequestHandle link: AttributedTextLink) {
        switch link.linkType {
        case .link, .phoneNumber:
            if let url = link.result?.url {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    UIApplication.shared.open(url, options: [:])
                }
            }
        case .userMention:
            if let userID = link.userID {
                showUserFeed(for: userID)
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

    var commentId: FeedPostCommentID?
    var openProfileAction: (() -> ()) = {}
    var replyAction: (() -> ()) = {}
    var accessoryViewAction: (() -> ()) = {}

    var isCellHighlighted: Bool = false {
        didSet {
            self.backgroundColor = isCellHighlighted ? UIColor.systemBlue.withAlphaComponent(0.1) : .clear
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

        self.commentView.profilePictureButton.addTarget(self, action: #selector(profileButtonAction), for: .touchUpInside)
        self.commentView.replyButton.addTarget(self, action: #selector(replyButtonAction), for: .touchUpInside)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.replyAction = {}
        commentId = nil
    }

    @objc private func profileButtonAction() {
        openProfileAction()
    }

    @objc private func replyButtonAction() {
        replyAction()
    }

    @objc private func accessoryButtonAction() {
        accessoryViewAction()
    }

    func update(with comment: FeedPostComment) {
        commentId = comment.id
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

fileprivate class LoadingViewController: UIViewController {

    private let activityIndicator: UIActivityIndicatorView = {
        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.color = .secondaryLabel
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        return activityIndicator
    }()

    private let tryAgainLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .title2)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "An error occured while trying to load this post. Please try again later."
        return label
    }()

    override func loadView() {
        view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .feedBackground

        view.addSubview(activityIndicator)
        activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        activityIndicator.startAnimating()

        view.addSubview(tryAgainLabel)
        tryAgainLabel.constrainMargins(to: view)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self else { return }
            self.activityIndicator.stopAnimating()
            self.tryAgainLabel.isHidden = false
        }
    }
}

extension UITableView {

    var hasScrollAnimation: Bool {
        get {
            let result = self.value(forKey: "animation") != nil
            return result
        }
    }

}
