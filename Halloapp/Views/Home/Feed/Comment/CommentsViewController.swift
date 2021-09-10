//
//  CommentsView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/23/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreData
import UIKit

private extension Localizations {

    static var titleComments: String {
        NSLocalizedString("title.comments", value: "Comments", comment: "Title for the Comments screen.")
    }

    static var commentDelete: String {
        NSLocalizedString("comment.delete",
                          value: "Delete",
                          comment: "Button revealed when user swipes on their comment.")
    }

    static var deleteCommentConfirmation: String {
        NSLocalizedString("comment.delete.confirmation",
                          value: "Delete this comment? This action cannot be undone.",
                          comment: "Confirmation text displayed at comment deletion prompt")
    }

    static var deleteCommentAction: String {
        NSLocalizedString("comment.delete.action",
                          value: "Delete Comment",
                          comment: "Title for the button in comment deletion confirmation prompt.")
    }

    static var resendCommentConfirmation: String {
        NSLocalizedString("comment.resend.confirmation",
                          value: "Resend Comment?",
                          comment: "Confirmation prompt for when resending comment that previously failed to send.")
    }

    static var resendCommentAction: String {
        NSLocalizedString("comment.resend.action",
                          value:"Resend",
                          comment: "Title for the button in comment resend confirmation prompt.")
    }

    static var micAccessDeniedTitle: String {
        NSLocalizedString("comment.mic.access.denied.title", value: "Unable to access microphone", comment: "Alert title when missing microphone access")
    }

    static var micAccessDeniedMessage: String {
        NSLocalizedString("comment.mic.access.denied.message", value: "To enable audio recording, please tap on Settings and then turn on Microphone", comment: "Alert message when missing microphone access")
    }
}

class CommentsViewController: UITableViewController, CommentInputViewDelegate, NSFetchedResultsControllerDelegate, TextLabelDelegate {

    static private let cellReuseIdentifier = "CommentCell"
    static private let cellHighlightAnimationDuration = 0.15
    static private let sectionMain = 0

    private var mediaPickerController: MediaPickerViewController?
    private var cancellableSet: Set<AnyCancellable> = []

    /// Key used to encode/decode array of comment drafts from `UserDefaults`.
    static let postCommentDraftKey = "posts.comments.drafts"

    typealias ReplyContext = (parentCommentId: FeedPostCommentID, userId: UserID)

    private var feedPostId: FeedPostID {
        didSet {
            mentionableUsers = computeMentionableUsers()
        }
    }
    
    private var isCommentingEnabled: Bool = true
    private var isPostTextExpanded = false

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
        self.hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        postLoadingCancellable?.cancel()
        DDLogDebug("CommentsView/deinit/\(feedPostId)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        preventNavLoop()

        navigationItem.title = Localizations.titleComments

        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.backgroundColor = .feedBackground
        tableView.contentInsetAdjustmentBehavior = .scrollableAxes
        tableView.keyboardDismissMode = .interactive
        tableView.preservesSuperviewLayoutMargins = true
        tableView.register(CommentsTableViewCell.self, forCellReuseIdentifier: Self.cellReuseIdentifier)

        commentsInputView.delegate = self

        if let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId) {
            configureUI(with: feedPost)
        } else {
            commentsInputView.isEnabled = false

            loadingViewController = LoadingViewController()
            self.view.addSubview(loadingViewController!.view)
            loadingViewController!.view.translatesAutoresizingMaskIntoConstraints = false
            loadingViewController!.view.constrainMargins([ .leading, .trailing], to: self.view)
            loadingViewController!.view.centerYAnchor.constraint(equalTo: self.view.layoutMarginsGuide.centerYAnchor).isActive = true
            self.addChild(loadingViewController!)
            loadingViewController?.didMove(toParent: self)

            postLoadingCancellable = MainAppContext.shared.feedData.didReceiveFeedPost.sink { [weak self] (feedPost) in
                guard let self = self else { return }
                guard self.feedPostId == feedPost.id else { return }
                self.configureUI(with: feedPost)
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.commentsInputView.willAppear(in: self)

        if view.window == nil {
            setNeedsScrollToTarget(withAnimation: false)
        }
        
        if let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId) {
            showNotInGroupBannerIfNeeded(with: feedPost)
        }
        
        loadCommentsDraft()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        viewDidAppear = true
        self.commentsInputView.didAppear(in: self)

        if isFeedPostAvailable {
            MainAppContext.shared.feedData.markCommentsAsRead(feedPostId: feedPostId)

            if sortedComments.isEmpty {
                DispatchQueue.main.async {
                    self.commentsInputView.showKeyboard(from: self)
                }
            }

            resetCommentHighlightingIfNeeded()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if isFeedPostAvailable {
            MainAppContext.shared.feedData.markCommentsAsRead(feedPostId: feedPostId)
        }

        saveCommentDraft()
        
        commentsInputView.willDisappear(in: self)
    }
    
    private func saveCommentDraft() {
        guard !commentsInputView.mentionText.collapsedText.isEmpty else {
            FeedData.deletePostCommentDrafts { existingDraft in
                existingDraft.postID == feedPostId
            }
          
            return
        }
        
        let draft = CommentDraft(postID: feedPostId, text: commentsInputView.mentionText, parentComment: replyContext?.parentCommentId)
        
        var draftsArray: [CommentDraft] = []
        
        if let draftsDecoded: [CommentDraft] = try? AppContext.shared.userDefaults.codable(forKey: Self.postCommentDraftKey) {
            draftsArray = draftsDecoded
        }
        
        draftsArray.removeAll { existingDraft in
            existingDraft.postID == draft.postID
        }
        
        draftsArray.append(draft)
        

        try? AppContext.shared.userDefaults.setValue(value: draftsArray, forKey: Self.postCommentDraftKey)
    }
  
    private func loadCommentsDraft() {
        guard let draftsArray: [CommentDraft] = try? AppContext.shared.userDefaults.codable(forKey: Self.postCommentDraftKey) else { return }
        
        guard let draft = draftsArray.first(where: { draft in
            draft.postID == feedPostId
        }) else { return }
        
        if let parentComment = draft.parentComment {
            let parentCommentUserID = MainAppContext.shared.feedData.feedComment(with: parentComment)?.userId ?? ""
            replyContext = (parentComment, parentCommentUserID)
        }
        
        commentsInputView.mentionText = draft.text
        commentsInputView.updateInputView()
    }
    
    private func removeCommentDraft() {
        var draftsArray: [CommentDraft] = []
        
        if let draftsDecoded: [CommentDraft] = try? AppContext.shared.userDefaults.codable(forKey: "posts.comments.drafts") {
            draftsArray = draftsDecoded
        }
        
        draftsArray.removeAll { existingDraft in
            existingDraft.postID == feedPostId
        }
        
        try? AppContext.shared.userDefaults.setValue(value: draftsArray, forKey: "posts.comments.drafts")
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

    // MARK: Delayed Post Loading

    private var isFeedPostAvailable: Bool = false

    private var postLoadingCancellable: AnyCancellable?

    private var loadingViewController: LoadingViewController?

    private var viewDidAppear: Bool = false

    private func configureUI(with feedPost: FeedPost) {
        isFeedPostAvailable = true

        // Remove "Loading" view if any.
        if let loadingViewController = loadingViewController {
            loadingViewController.willMove(toParent: nil)
            loadingViewController.view.removeFromSuperview()
            loadingViewController.removeFromParent()
            self.loadingViewController = nil
        }

        if postLoadingCancellable != nil {
            postLoadingCancellable?.cancel()
            postLoadingCancellable = nil
        }

        commentsInputView.isEnabled = true
        
        if let highlightedCommentId = highlightedCommentId {
            setNeedsScroll(toComment: highlightedCommentId, highlightAfterScroll: false, animated: false)
        }

        let headerView = CommentsTableHeaderView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.size.width, height: 200))
        headerView.configure(withPost: feedPost)
        headerView.textLabel.numberOfLines = isPostTextExpanded ? 0 : 8
        headerView.textLabel.delegate = self
        headerView.profilePictureButton.addTarget(self, action: #selector(showUserFeedForPostAuthor), for: .touchUpInside)
        tableView.tableHeaderView = headerView

        if let mediaView = headerView.mediaView {
            mediaView.delegate = self
        }

        let fetchRequest: NSFetchRequest<FeedPostComment> = FeedPostComment.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "post.id = %@", feedPostId)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPostComment.timestamp, ascending: true) ]
        fetchedResultsController =
            NSFetchedResultsController<FeedPostComment>(fetchRequest: fetchRequest, managedObjectContext: MainAppContext.shared.feedData.viewContext,
                                                        sectionNameKeyPath: nil, cacheName: nil)
        fetchedResultsController!.delegate = self
        do {
            try fetchedResultsController!.performFetch()
            reloadComments()
            if viewDidAppear {
                tableView.reloadData()
            }
        } catch {
            return
        }

        if viewDidAppear {
            MainAppContext.shared.feedData.markCommentsAsRead(feedPostId: feedPostId)
        }
    }

    private func showNotInGroupBannerIfNeeded(with feedPost: FeedPost) {
        guard let groupID = feedPost.groupId else { return }
        guard MainAppContext.shared.chatData.chatGroupMember(groupId: groupID, memberUserId: MainAppContext.shared.userData.userId) == nil else { return }

        isCommentingEnabled = false
        commentsInputView.isEnabled = false
        commentsInputView.isHidden = true

        view.addSubview(notInGroupBanner)
        notInGroupBanner.constrain([.leading, .trailing, .bottom], to: view.safeAreaLayoutGuide)
    }
    
    private lazy var notInGroupBanner: NotInGroupBannerView = {
        let view = NotInGroupBannerView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // MARK: Scrolling / highlighting

    private var preventAdjustContentOffsetOnChatBarBottomInsetChangeCounter = 0
    private var commentToScrollTo: FeedPostCommentID?
    private var needsHighlightCommentToScrollTo: Bool = false
    private var needsScrollToTargetWithAnimation: Bool?
    private var commentToHighlightAfterScrollingEnds: FeedPostCommentID?

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
            if viewDidAppear {
                scrollToBottom(animated: animated)
            }
        }
    }

    private func scroll(toComment commentId: FeedPostCommentID, animated: Bool, highlightAfterScroll: FeedPostCommentID?) {
        guard let indexPath = indexPath(forCommentId: commentId) else {
            return
        }

        let cellRect = tableView.rectForRow(at: indexPath)
        let isCellCompletelyVisible = tableView.bounds.contains(cellRect)

        DDLogDebug("CommentsView/scroll/animated/\(animated)/comment/\(indexPath)")
        if isCellCompletelyVisible {
            tableView.scrollToRow(at: indexPath, at: .middle, animated: animated)
        } else {
            // scroll to the bottom of the cell if the cell's content is too tall
            tableView.scrollToRow(at: indexPath, at: .bottom, animated: animated)
        }

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
    
    // MARK: Helpers

    private func preventNavLoop() {
        guard let nc = navigationController else { return }
        var viewControllers = nc.viewControllers
        guard viewControllers.count >= 3 else { return }
        let secondLast = viewControllers.count - 2
        let thirdLast = viewControllers.count - 3
        guard viewControllers[secondLast].isKind(of: UserFeedViewController.self),
              viewControllers[thirdLast].isKind(of: CommentsViewController.self) else { return }
        DDLogInfo("CommentsViewController/preventNavLoop")
        viewControllers.remove(at: secondLast)
        viewControllers.remove(at: thirdLast)
        navigationController?.viewControllers = viewControllers
    }

    // MARK: UI Actions

    @objc private func showUserFeedForPostAuthor() {
        if let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId) {
            showUserFeed(for: feedPost.userId)
        }
    }

    private func showUserFeed(for userID: UserID) {
        let userViewController = UserFeedViewController(userId: userID)
        self.navigationController?.pushViewController(userViewController, animated: true)
    }

    private func retractComment(with commentId: FeedPostCommentID, completionHandler: @escaping (Bool) -> Void) {
        let actionSheet = UIAlertController(title: nil, message: Localizations.deleteCommentConfirmation, preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: Localizations.deleteCommentAction, style: .destructive) { _ in
            self.reallyRetract(commentWithId: commentId)
            completionHandler(true)
        })
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel) { _ in
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
        let actionSheet = UIAlertController(title: nil, message: Localizations.resendCommentConfirmation, preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: Localizations.resendCommentAction, style: .default, handler: { _ in
            MainAppContext.shared.feedData.resend(commentWithId: commentId)
        }))
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        self.present(actionSheet, animated: true)
    }

    // MARK: Data

    private var trackingPerRowFRCChanges = false

    private var needsScrollToTargetAfterTableUpdates = false
    private var isCATransactionInProgress = false

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
            if !isCATransactionInProgress {
                CATransaction.begin()
                isCATransactionInProgress = true
            }
        }

        DDLogDebug("CommentsView/frc/will-change perRowChanges=[\(trackingPerRowFRCChanges)]")
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {

        DDLogDebug("CommentsView/frc/\(type) indexpath=[\(String(describing: indexPath))] object=[\(anObject)]")

        guard trackingPerRowFRCChanges else {
            return
        }

        func insert(_ newComment: FeedPostComment) {
            var currentRoot = newComment
            while let parent = currentRoot.parent {
                currentRoot = parent
            }
            var commentIndex = sortedComments.endIndex
            if let nextRootCommentIndex = sortedComments.firstIndex(where: { $0.parent == nil && $0.timestamp > currentRoot.timestamp }) {
                commentIndex = nextRootCommentIndex
            }
            sortedComments.insert(newComment, at: commentIndex)
            DDLogDebug("CommentsView/frc/insert Position: [\(commentIndex)] Comment: [\(newComment)]")
            tableView.insertRows(at: [ IndexPath(row: commentIndex, section: Self.sectionMain) ], with: .none)
        }

        let comment = anObject as! FeedPostComment
        switch type {
        case .insert:
            insert(comment)
            numberOfInsertedItems += 1
            needsScrollToTargetAfterTableUpdates = true

        case .move:
            // We receive .move when the timestamp of a comment is updated with server timestamp which causes changes in the relative
            // ordering of comments. For now we will not move comment rows live.
            DDLogInfo("CommentsView/frc/move for comment id : \(comment.id)")


        case .delete:
            guard let commentIndex = sortedComments.firstIndex(where: { $0 == comment }) else { return }
            DDLogDebug("CommentsView/frc/delete Position: [\(commentIndex)]  Comment: [\(comment)] ")
            sortedComments.remove(at: commentIndex)
            tableView.deleteRows(at: [ IndexPath(row: commentIndex, section: Self.sectionMain) ], with: .none)

        case .update:
            guard let commentIndex = sortedComments.firstIndex(where: { $0 == comment }) else { return }

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

        if isCATransactionInProgress {
            CATransaction.setCompletionBlock {
                if needsNotify {
                    needsNotify = false
                    self.didUpdateCommentsTableAfterControllerDidChangeContent()
                }
            }

            CATransaction.commit() // triggers a full layout pass
            isCATransactionInProgress = false
        }

        trackingPerRowFRCChanges = false
        if needsNotify && notifyImmediately {
            needsNotify = false
            didUpdateCommentsTableAfterControllerDidChangeContent()
        }

        // Navigate back if the post was deleted.
        if let post = MainAppContext.shared.feedData.feedPost(with: feedPostId), post.isPostRetracted {
            DDLogInfo("CommentsView/\(feedPostId) Post deleted - popping view controller.")
            if let presentedVC = presentedViewController {
                presentedVC.dismiss(animated: false) {
                    self.navigationController?.popViewController(animated: true)
                }
            } else {
                navigationController?.popViewController(animated: true)
            }
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

        // Initiate download for images that were not yet downloaded.
        MainAppContext.shared.feedData.downloadMedia(in: [feedPostComment])

        let commentId = feedPostComment.id
        let commentAuthorUserId = feedPostComment.userId
        cell.commentView.delegate = self
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
        cell.retryAction = { [weak self] in
            guard let self = self else { return }
            self.confirmResending(commentWithId: commentId)
        }
        cell.commentView.nameTextLabel.delegate = self
        cell.isCellHighlighted = self.replyContext?.parentCommentId == commentId || self.highlightedCommentId == commentId
        if !isCommentingEnabled {
            cell.isReplyingEnabled = false
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        let feedPostComment = self.sortedComments[indexPath.row]
        if feedPostComment.canBeRetracted {
            return abs(feedPostComment.timestamp.timeIntervalSinceNow) < Date.hours(1)
        }
        return false
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        // Use this method instead of tableView(_:commit:forRowAt:) because this method
        // allows in-cell Delete button to stay visible when confirmation (action sheet) is presented.
        let feedPostComment = self.sortedComments[indexPath.row]
        let commentId = feedPostComment.id
        let deleteAction = UIContextualAction(style: .destructive, title: Localizations.commentDelete) { (_, _, completionHandler) in
            self.retractComment(with: commentId, completionHandler: completionHandler)
        }
        return UISwipeActionsConfiguration(actions: [ deleteAction ])
    }

    // MARK: Input view

    private let commentsInputView: CommentInputView = CommentInputView(frame: .zero)

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

    func commentInputViewPickMedia(_ inputView: CommentInputView) {
        presentMediaPicker()
    }

    func commentInputView(_ inputView: CommentInputView, wantsToSend text: MentionText, andMedia media: PendingMedia?) {
        postComment(text: text, media: media)
    }

    func postComment(text: MentionText, media: PendingMedia?) {
        let parentCommentId = replyContext?.parentCommentId
        var sendMedia: [PendingMedia] = []
        if let media = media {
            sendMedia.append(media)
        }
        commentToScrollTo = MainAppContext.shared.feedData.post(comment: text, media: sendMedia, to: feedPostId, replyingTo: parentCommentId)
        FeedData.deletePostCommentDrafts { existingDraft in
            existingDraft.postID == feedPostId
        }

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

    func commentInputViewResetInputMedia(_ inputView: CommentInputView) {
        commentsInputView.removeMediaPanel()
    }

    func commentInputViewMicrophoneAccessDenied(_ inputView: CommentInputView) {
        let alert = UIAlertController(title: Localizations.micAccessDeniedTitle, message: Localizations.micAccessDeniedMessage, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        alert.addAction(UIAlertAction(title: Localizations.settingsAppName, style: .default, handler: { _ in
            guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(settingsUrl)
        }))

        present(alert, animated: true)
    }

    func commentInputViewDidTapSelectedMedia(_ inputView: CommentInputView, mediaToEdit: PendingMedia) {
        let editController = MediaEditViewController(mediaToEdit: [mediaToEdit], selected: nil) { controller, media, selected, cancel in
            controller.dismiss(animated: true)
            self.commentsInputView.showMediaPanel(with: media[selected])
        }.withNavigationController()
        present(editController, animated: true)
    }

    private func refreshCommentInputViewReplyPanel() {
        if let context = replyContext {
            var contactName: String? = nil // `nil` when replying to myself
            if context.userId == MainAppContext.shared.userData.userId {
                commentsInputView.removeReplyMentionIfPossible()
            } else {
                contactName = MainAppContext.shared.contactStore.fullName(for: context.userId)
                commentsInputView.addReplyMentionIfPossible(for: context.userId, name: contactName!)
            }
            // Dispatch to fix case when replyPanel was not sized correctly on first load of CommentInputView
            DispatchQueue.main.async { [weak self] in
                self?.commentsInputView.showReplyPanel(with: contactName)
            }
        } else {
            commentsInputView.removeReplyMentionIfPossible()
            commentsInputView.removeReplyPanel()
        }
    }

    // MARK: TextLabelDelegate

    func textLabel(_ label: TextLabel, didRequestHandle link: AttributedTextLink) {
        switch link.linkType {
        case .link, .phoneNumber:
            if let url = link.result?.url {
                guard MainAppContext.shared.chatData.proceedIfNotGroupInviteLink(url) else { break }
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

    func textLabelDidRequestToExpand(_ label: TextLabel) {
        label.numberOfLines = 0
        isPostTextExpanded = true
        tableView.reloadData()
    }

    func presentMediaPicker() {
        guard  mediaPickerController == nil else {
            return
        }
        mediaPickerController = MediaPickerViewController(filter: .all, multiselect: false, camera: false) {[weak self] controller, media, cancel in
            guard let self = self else { return }
            guard let media = media.first, !cancel else {
                DDLogInfo("CommentsView/media comment cancelled")
                self.dismissMediaPicker(animated: true)
                return
            }
            if media.ready.value {
                self.commentsInputView.showMediaPanel(with: media)
            } else {
                self.cancellableSet.insert(
                    media.ready.sink { [weak self] ready in
                        guard let self = self else { return }
                        guard ready else { return }
                        self.commentsInputView.showMediaPanel(with: media)
                    }
                )
            }

            self.dismissMediaPicker(animated: true)
            self.commentsInputView.showKeyboard(from: self)
        }
        present(UINavigationController(rootViewController: mediaPickerController!), animated: true)
    }

    func dismissMediaPicker(animated: Bool) {
        if mediaPickerController != nil && presentedViewController != nil {
            dismiss(animated: true)
        }
        mediaPickerController = nil
    }
}

extension CommentsViewController: CommentViewDelegate {
    func commentView(_ view: MediaCarouselView, forComment feedPostCommentID: FeedPostCommentID, didTapMediaAtIndex index: Int) {
        commentToScrollTo = feedPostCommentID
        let canSavePost = false
        guard let media = MainAppContext.shared.feedData.media(commentID: feedPostCommentID) else { return }
        let controller = MediaExplorerController(media: media, index: index, canSaveMedia: canSavePost)
        controller.delegate = view
        present(controller.withNavigationController(), animated: true)
    }
}

extension CommentsViewController: MediaCarouselViewDelegate {

    func mediaCarouselView(_ view: MediaCarouselView, didTapMediaAtIndex index: Int) {
        guard let media = MainAppContext.shared.feedData.media(postID: feedPostId) else { return }
        // By default we scroll to the last comment. On dismissing the medi explorer for the post media, we want to stay on top of the comments list.
        if let firstComment = sortedComments.first {
            commentToScrollTo = firstComment.id
        }

        var canSavePost = false
        
        if let post = MainAppContext.shared.feedData.feedPost(with: feedPostId) {
            canSavePost = post.canSaveMedia
        }

        let controller = MediaExplorerController(media: media, index: index, canSaveMedia: canSavePost)
        controller.delegate = view

        present(controller.withNavigationController(), animated: true)
    }

    func mediaCarouselView(_ view: MediaCarouselView, indexChanged newIndex: Int) {

    }

    func mediaCarouselView(_ view: MediaCarouselView, didDoubleTapMediaAtIndex index: Int) {

    }

    func mediaCarouselView(_ view: MediaCarouselView, didZoomMediaAtIndex index: Int, withScale scale: CGFloat) {

    }
}

fileprivate class CommentsTableViewCell: UITableViewCell {
    private(set) lazy var commentView: CommentView = {
        CommentView()
    }()

    var commentId: FeedPostCommentID?
    var openProfileAction: (() -> ()) = {}
    var replyAction: (() -> ()) = {}
    var retryAction: (() -> ()) = {}
    var isReplyingEnabled: Bool = true {
        didSet {
            commentView.replyButton.isHidden = !isReplyingEnabled
        }
    }

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
        isReplyingEnabled = true
    }

    @objc private func profileButtonAction() {
        openProfileAction()
    }

    @objc private func replyButtonAction() {
        replyAction()
    }

    @objc private func retryButtonAction() {
        retryAction()
    }

    func update(with comment: FeedPostComment) {
        commentId = comment.id
        commentView.updateWith(comment: comment)
        if comment.status == .sendError {
            if accessoryView == nil {
                accessoryView = {
                    let button = UIButton(type: .system)
                    button.setImage(UIImage(systemName: "exclamationmark.circle"), for: .normal)
                    button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 6, bottom: 12, right: 6)
                    button.tintColor = .red
                    button.sizeToFit()
                    button.addTarget(self, action: #selector(retryButtonAction), for: .touchUpInside)
                    return button
                }()
            }
        } else {
            accessoryView = nil
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
        label.text = NSLocalizedString("comments.post.loading.failed",
                                       value: "An error occured while trying to load this post. Please try again later.",
                                       comment: "Warning text displayed in Comments when post wasn't available.")
        return label
    }()

    override func loadView() {
        let width = UIScreen.main.bounds.width
        view = UIView(frame: CGRect(origin: .zero, size: CGSize(width: width, height: width)))
        view.backgroundColor = .feedBackground

        view.addSubview(activityIndicator)
        activityIndicator.centerXAnchor.constraint(equalTo: view.layoutMarginsGuide.centerXAnchor).isActive = true
        activityIndicator.centerYAnchor.constraint(equalTo: view.layoutMarginsGuide.centerYAnchor).isActive = true
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
