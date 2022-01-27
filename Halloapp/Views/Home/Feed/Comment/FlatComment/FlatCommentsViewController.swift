//
//  FlatCommentsViewController.swift
//  HalloApp
//
//  Created by Nandini Shetty on 11/30/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//
import CocoaLumberjackSwift
import Combine
import Core
import CoreData
import UIKit

private extension Localizations {
    static var newComment: String {
        NSLocalizedString("title.comments.picker", value: "New Comment", comment: "Title for the picker screen.")
    }

    static var titleComments: String {
        NSLocalizedString("title.comments", value: "Comments", comment: "Title for the Comments screen.")
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
}

class FlatCommentsViewController: UIViewController, UICollectionViewDelegate, NSFetchedResultsControllerDelegate {
    typealias CommentDataSource = UICollectionViewDiffableDataSource<String, FeedPostComment>
    typealias CommentSnapshot = NSDiffableDataSourceSnapshot<String, FeedPostComment>
    static private let messageViewCellReuseIdentifier = "MessageViewCell"
    static private let cellHighlightAnimationDuration = 0.15

    private var mediaPickerController: MediaPickerViewController?
    private var cancellableSet: Set<AnyCancellable> = []
    private var parentCommentID: FeedPostCommentID?

    var highlightedCommentId: FeedPostCommentID?
    private var commentToScrollTo: FeedPostCommentID?

    // Key used to encode/decode array of comment drafts from `UserDefaults`.
    static let postCommentDraftKey = "posts.comments.drafts"

    private var feedPostId: FeedPostID {
        didSet {
            // TODO Remove this if not needed for mentions
        }
    }

    private var feedPost: FeedPost?

    private lazy var dataSource: CommentDataSource = {
        let dataSource = CommentDataSource(
            collectionView: collectionView,
            cellProvider: { [weak self] (collectionView, indexPath, comment) -> UICollectionViewCell? in
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: FlatCommentsViewController.messageViewCellReuseIdentifier,
                    for: indexPath)
                if let itemCell = cell as? MessageViewCell {
                    itemCell.configureWithComment(comment: comment)
                    itemCell.textLabel.delegate = self
                    itemCell.delegate = self
                }
                return cell
            })
        // Setup comment header view
        dataSource.supplementaryViewProvider = { [weak self] ( view, kind, index) in
            if kind == MessageTimeHeaderView.elementKind {
                let headerView = view.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: MessageTimeHeaderView.elementKind, for: index)
                if let messageTimeHeaderView = headerView as? MessageTimeHeaderView, let self = self, let feedPost = self.feedPost, let sections = self.fetchedResultsController?.sections{
                    let section = sections[index.section ]
                    messageTimeHeaderView.configure(headerText: section.name)
                    return messageTimeHeaderView
                } else {
                    // TODO(@dini) add post loading here
                    DDLogInfo("FlatCommentsViewController/configureHeader/time header info not available")
                    return headerView
                }
            } else {
                let headerView = view.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: MessageCommentHeaderView.elementKind, for: index)
                if let messageCommentHeaderView = headerView as? MessageCommentHeaderView, let self = self, let feedPost = self.feedPost {
                    messageCommentHeaderView.configure(withPost: feedPost)
                    messageCommentHeaderView.delegate = self
                    return messageCommentHeaderView
                } else {
                    // TODO(@dini) add post loading here
                    DDLogInfo("FlatCommentsViewController/configureHeader/header info not available")
                    return headerView
                }
            }
        }
        return dataSource
    }()

    private var fetchedResultsController: NSFetchedResultsController<FeedPostComment>?

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: self.view.bounds, collectionViewLayout: createLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = UIColor.primaryBg
        collectionView.allowsSelection = false
        collectionView.contentInsetAdjustmentBehavior = .scrollableAxes
        collectionView.preservesSuperviewLayoutMargins = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.register(MessageViewCell.self, forCellWithReuseIdentifier: FlatCommentsViewController.messageViewCellReuseIdentifier)
        collectionView.register(MessageCommentHeaderView.self, forSupplementaryViewOfKind: MessageCommentHeaderView.elementKind, withReuseIdentifier: MessageCommentHeaderView.elementKind)
        collectionView.register(MessageTimeHeaderView.self, forSupplementaryViewOfKind: MessageTimeHeaderView.elementKind, withReuseIdentifier: MessageTimeHeaderView.elementKind)
        collectionView.delegate = self
        return collectionView
    }()

    private lazy var mentionableUsers: [MentionableUser] = {
        computeMentionableUsers()
    }()

    init(feedPostId: FeedPostID) {
        self.feedPostId = feedPostId
        self.feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId)
        super.init(nibName: nil, bundle: nil)
        self.hidesBottomBarWhenPushed = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = Localizations.titleComments
        view.backgroundColor = UIColor.primaryBg
        view.addSubview(collectionView)
        collectionView.constrain(to: view)
        if let feedPost = feedPost {
            configureUI(with: feedPost)
        }
        messageInputView.delegate = self
        // Long press message options
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(getMessageOptions))
        longPressGesture.delaysTouchesBegan = true
        collectionView.addGestureRecognizer(longPressGesture)
        // Dismiss keyboard when user taps comments
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard(_:)))
        view.addGestureRecognizer(tapGesture)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.messageInputView.willAppear(in: self)
        loadCommentsDraft()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // TODO @dini check if post is available first
        MainAppContext.shared.feedData.markCommentsAsRead(feedPostId: feedPostId)
        resetCommentHighlightingIfNeeded()
    }

    private func resetCommentHighlightingIfNeeded() {
        if let commentId = highlightedCommentId, fetchedResultsController?.fetchedObjects?.firstIndex(where: {$0.id == commentId }) != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self = self else { return }
                self.unhighlightComment(commentId)
            }
            highlightedCommentId = nil
        }
    }

    private func unhighlightComment(_ commentId: FeedPostCommentID) {
        for cell in collectionView.visibleCells.compactMap({ $0 as? MessageViewCell }) {
            if cell.feedPostCommentID == commentId && cell.isCellHighlighted {
                UIView.animate(withDuration: Self.cellHighlightAnimationDuration) {
                    cell.isCellHighlighted = false
                }
            }
        }
    }

    private func configureUI(with feedPost: FeedPost) {
        // Setup the diffable data source so it can be used for first fetch of data
        collectionView.dataSource = dataSource
        initFetchedResultsController()
        // Initiate download of media that were not yet downloaded. TODO Ask if this is needed
        if let comments = fetchedResultsController?.fetchedObjects {
            MainAppContext.shared.feedData.downloadMedia(in: comments)
        }
        // Coming from notification
        if let highlightedCommentId = highlightedCommentId {
            commentToScrollTo = highlightedCommentId
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollToTarget(withAnimation: true)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveCommentDraft()
        messageInputView.willDisappear(in: self)
    }

    private func initFetchedResultsController() {
        let fetchRequest: NSFetchRequest<FeedPostComment> = FeedPostComment.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "post.id = %@", feedPostId)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPostComment.timestamp, ascending: true) ]
        fetchedResultsController = NSFetchedResultsController<FeedPostComment>(
            fetchRequest: fetchRequest,
            managedObjectContext: MainAppContext.shared.feedData.viewContext,
            sectionNameKeyPath: "headerTime",
            cacheName: nil
        )
        fetchedResultsController?.delegate = self
        // The diffable data source should handle the first fetch
        do {
            DDLogError("FlatCommentsViewController/configureUI/fetching comments for post \(feedPostId)")
            try fetchedResultsController?.performFetch()
        } catch {
            DDLogError("FlatCommentsViewController/configureUI/failed to fetch comments for post \(feedPostId)")
        }
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        var snapshot = CommentSnapshot()
        if let sections = fetchedResultsController?.sections {
            snapshot.appendSections(sections.map { $0.name } )
            for section in sections {
                if let comments = section.objects as? [FeedPostComment] {
                    snapshot.appendItems(comments, toSection: section.name)
                }

            }
        }
        dataSource.apply(snapshot, animatingDifferences: true) {
            self.scrollToTarget(withAnimation: true)
        }
    }

    private func createLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])


        let sectionHeaderSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44))
        let sectionHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: sectionHeaderSize, elementKind: MessageTimeHeaderView.elementKind, alignment: .top)
        sectionHeader.pinToVisibleBounds = true

        let section = NSCollectionLayoutSection(group: group)
        section.boundarySupplementaryItems = [sectionHeader]

        // Setup the comment view header with post information as the global header of the collection view.
        let layoutHeaderSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(55))
        let layoutHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: layoutHeaderSize, elementKind: MessageCommentHeaderView.elementKind, alignment: .top)
        let layoutConfig = UICollectionViewCompositionalLayoutConfiguration()
        layoutConfig.boundarySupplementaryItems = [layoutHeader]

        let layout = UICollectionViewCompositionalLayout(section: section)
        layout.configuration = layoutConfig
        return layout
    }

    func computeMentionableUsers() -> [MentionableUser] {
        return Mentions.mentionableUsers(forPostID: feedPostId)
    }

    @objc func getMessageOptions(_ gestureRecognizer: UILongPressGestureRecognizer) {
        if let indexPath = collectionView.indexPathForItem(at: gestureRecognizer.location(in: collectionView)) {
            if let cell = collectionView.cellForItem(at: indexPath) as? MessageViewCell, let comment = fetchedResultsController?.object(at: indexPath), comment.status != .retracted {
                // Only the author can delete a comment
                guard comment.userId == MainAppContext.shared.userData.userId else { return }
                cell.markViewSelected()
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                // Setup action sheet
                let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
                actionSheet.addAction(UIAlertAction(title: Localizations.messageDelete, style: .destructive) { [weak self] _ in
                    guard let self = self else { return }
                    self.presentDeleteConfirmationActionSheet(indexPath: indexPath, cell: cell, comment: comment)
                })
                actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel) { _ in
                    cell.markViewUnselected()
                })
                self.present(actionSheet, animated: true)
            }
        }
    }

    private func presentDeleteConfirmationActionSheet(indexPath: IndexPath, cell: MessageViewCell, comment: FeedPostComment) {
        let confirmationActionSheet = UIAlertController(title: nil, message: Localizations.deleteCommentConfirmation, preferredStyle: .actionSheet)
        confirmationActionSheet.addAction(UIAlertAction(title: Localizations.deleteCommentAction, style: .destructive) { _ in
            guard let comment = MainAppContext.shared.feedData.feedComment(with: comment.id) else { return }
            MainAppContext.shared.feedData.retract(comment: comment)
            cell.configureWithComment(comment: comment)
        })
        confirmationActionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel) { _ in
            cell.markViewUnselected()
        })
        self.present(confirmationActionSheet, animated: true)
    }

    // MARK: UI Actions

    @objc private func showUserFeedForPostAuthor() {
        if let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId) {
            showUserFeed(for: feedPost.userId)
        }
    }
    
    @objc private func showGroupFeed(groupId: GroupID) {
        guard let feedPost = self.feedPost, let groupId = feedPost.groupId else { return }
        guard MainAppContext.shared.chatData.chatGroup(groupId: groupId) != nil else { return }
        let vc = GroupFeedViewController(groupId: groupId)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func showUserFeed(for userID: UserID) {
        let userViewController = UserFeedViewController(userId: userID)
        self.navigationController?.pushViewController(userViewController, animated: true)
    }

    @objc func dismissKeyboard (_ sender: UITapGestureRecognizer) {
        messageInputView.hideKeyboard()
    }

    // MARK: Input view

    private let messageInputView: CommentInputView = CommentInputView(frame: .zero)

    override var canBecomeFirstResponder: Bool {
        get {
            return true
        }
    }

    override var inputAccessoryView: CommentInputView? {
        self.messageInputView.setInputViewWidth(self.view.bounds.size.width)
        return self.messageInputView
    }

    // MARK: Draft Comments

    private func saveCommentDraft() {
        guard !messageInputView.mentionText.collapsedText.isEmpty else {
            FeedData.deletePostCommentDrafts { existingDraft in
                existingDraft.postID == feedPostId
            }
            return
        }
        let draft = CommentDraft(postID: feedPostId, text: messageInputView.mentionText, parentComment: parentCommentID)
        var draftsArray: [CommentDraft] = []
        if let draftsDecoded: [CommentDraft] = try? AppContext.shared.userDefaults.codable(forKey: Self.postCommentDraftKey) {
            draftsArray = draftsDecoded
        }
        draftsArray.removeAll { existingDraft in
            existingDraft.postID == draft.postID
        }
        draftsArray.append(draft)
        do {
            try AppContext.shared.userDefaults.setCodable(draftsArray, forKey: Self.postCommentDraftKey)
        } catch {
            DDLogError("FlatCommentsViewController/saveCommentDraft/failed to save comment draft foPost: \(feedPostId) error: \(error)")
        }
    }

    private func loadCommentsDraft() {
        guard let draftsArray: [CommentDraft] = try? AppContext.shared.userDefaults.codable(forKey: Self.postCommentDraftKey) else { return }
        guard let draft = draftsArray.first(where: { draft in
            draft.postID == feedPostId
        }) else { return }

        if let parentComment = draft.parentComment {
            let parentCommentUserID = MainAppContext.shared.feedData.feedComment(with: parentComment)?.userId ?? ""
            parentCommentID = parentComment
        }
        messageInputView.mentionText = draft.text
        messageInputView.updateInputView()
  
    // MARK: Scrolling and Highlighting

    private func scrollToTarget(withAnimation: Bool) {
        DDLogDebug("FlatCommentsView/scrollToTarget/withAnimation: \(withAnimation)")
        let animated = withAnimation && isViewLoaded && view.window != nil && transitionCoordinator == nil
        DDLogDebug("FlatCommentsView/scrollToTarget/commentToScrollTo: \(commentToScrollTo ?? "")")
        if let commentId = commentToScrollTo  {
            scroll(toComment: commentId, animated: animated, highlightAfterScroll: commentId)
        }
    }

    private func scroll(toComment commentId: FeedPostCommentID, animated: Bool, highlightAfterScroll: FeedPostCommentID?) {
        DDLogDebug("FlatCommentsView/scroll/called/toComment: \(commentId)")
        guard let index = fetchedResultsController?.fetchedObjects?.firstIndex(where: {$0.id == commentId }) else {
            return
        }
        let commentObj = fetchedResultsController?.fetchedObjects?[index]
        if let commentObj = commentObj, let indexp = fetchedResultsController?.indexPath(forObject: commentObj) {
            DDLogDebug("FlatCommentsView/scroll/scrolling/toComment: \(commentId)")
            collectionView.scrollToItem(at: indexp, at: .centeredVertically, animated: animated)
            // if this comment needs to be highlighted after scroll, reset commentToScrollTo after highlighting
            if let highlightedCommentId = highlightedCommentId, highlightedCommentId == commentId {
                guard let cell = collectionView.cellForItem(at: indexp) as? MessageViewCell else { return }
                    DDLogDebug("FlatCommentsView/scroll/highlighting/toComment: \(commentId)")
                UIView.animate(withDuration: Self.cellHighlightAnimationDuration) {
                    cell.isCellHighlighted = true
                }
                commentToScrollTo = nil
            } else {
                // comment does not need highlighting, we can safely reset commentToScrollTo
                commentToScrollTo = nil
            }
        }
    }
}

extension FlatCommentsViewController: MessageCommentHeaderViewDelegate {

    func messageCommentHeaderView(_ view: MessageCommentHeaderView, didTapGroupWithID groupId: GroupID) {
        showGroupFeed(groupId: groupId)
    }

    func messageCommentHeaderView(_ view: MessageCommentHeaderView, didTapProfilePictureUserId userId: UserID) {
        showUserFeed(for: userId)
    }

    func messageCommentHeaderView(_ view: MediaCarouselView, didTapMediaAtIndex index: Int) {
        guard let media = MainAppContext.shared.feedData.media(postID: feedPostId) else { return }

        var canSavePost = false

        if let post = MainAppContext.shared.feedData.feedPost(with: feedPostId) {
            canSavePost = post.canSaveMedia
        }

        let controller = MediaExplorerController(media: media, index: index, canSaveMedia: canSavePost)
        controller.delegate = view
        present(controller, animated: true)
    }
}

extension FlatCommentsViewController: MessageViewDelegate {
    func messageView(_ view: MediaCarouselView, forComment feedPostCommentID: FeedPostCommentID, didTapMediaAtIndex index: Int) {
        var canSavePost = false
        if let post = MainAppContext.shared.feedData.feedPost(with: feedPostId) {
            canSavePost = post.canSaveMedia
        }
        guard let media = MainAppContext.shared.feedData.media(commentID: feedPostCommentID) else { return }
        let controller = MediaExplorerController(media: media, index: index, canSaveMedia: canSavePost)
        controller.delegate = view
        present(controller, animated: true)
    }

    func messageView(_ messageViewCell: MessageViewCell, replyTo feedPostCommentID: FeedPostCommentID) {
        guard let indexPath = collectionView.indexPath(for: messageViewCell) else { return }
        guard let comment = fetchedResultsController?.object(at: indexPath) else { return }
        guard !comment.isRetracted else { return }
        parentCommentID = comment.id
        messageInputView.showQuotedReplyPanel(comment: comment)
    }
}

extension FeedPostComment {
  @objc var headerTime: String {
      get {
          return timestamp.chatMsgGroupingTimestamp(Date())
      }
  }
}

extension FlatCommentsViewController: TextLabelDelegate {
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
    }
}

extension FlatCommentsViewController: CommentInputViewDelegate {
    func commentInputViewCouldNotRecordDuringCall(_ inputView: CommentInputView) {
        // TODO Dini
    }

    func commentInputView(_ inputView: CommentInputView, didChangeBottomInsetWith animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {
            self.updateCollectionViewContentOffset(forKeyboardHeight: inputView.bottomInset)
            // Manually adjust insets to account for inputView
            let bottomContentInset = inputView.bottomInset - collectionView.safeAreaInsets.bottom
            collectionView.contentInset.bottom = bottomContentInset
            collectionView.verticalScrollIndicatorInsets.bottom = bottomContentInset
        }

        func updateCollectionViewContentOffset(forKeyboardHeight keyboardHeight: CGFloat) {
            let bottomInset = keyboardHeight
            let currentInset = self.collectionView.adjustedContentInset
            var contentOffset = self.collectionView.contentOffset

            DDLogDebug("FlatCommentsView/keyboard Bottom inset: [\(bottomInset)]  Current insets: [\(currentInset)]")

            if bottomInset > currentInset.bottom && currentInset.bottom == collectionView.safeAreaInsets.bottom {
                // Because of the SwiftUI the accessory view appears with a slight delay
                // and bottom inset increased from 0 to some value. Do not scroll when that happens.
                return
            }

            contentOffset.y += bottomInset - currentInset.bottom

            contentOffset.y = min(contentOffset.y, collectionView.contentSize.height - (collectionView.frame.height - currentInset.top - bottomInset))
            contentOffset.y = max(contentOffset.y, -currentInset.top)

            DDLogDebug("FlatCommentsView/keyboard Content offset: [\(collectionView.contentOffset)] -> [\(contentOffset)]")
            self.collectionView.contentOffset = contentOffset
    }

    func commentInputView(_ inputView: CommentInputView, wantsToSend text: MentionText, andMedia media: PendingMedia?, linkPreviewData: LinkPreviewData?, linkPreviewMedia: PendingMedia?) {
        postComment(text: text, media: media, linkPreviewData: linkPreviewData, linkPreviewMedia: linkPreviewMedia)
    }

    func commentInputView(_ inputView: CommentInputView, possibleMentionsForInput input: String) -> [MentionableUser] {
        return mentionableUsers.filter { Mentions.isPotentialMatch(fullName: $0.fullName, input: input) }
    }

    func commentInputViewPickMedia(_ inputView: CommentInputView) {
        presentMediaPicker()
    }

    func commentInputViewResetInputMedia(_ inputView: CommentInputView) {
        messageInputView.removeMediaPanel()
    }

    func commentInputViewDidTapSelectedMedia(_ inputView: CommentInputView, mediaToEdit: PendingMedia) {
        let editController = MediaEditViewController(mediaToEdit: [mediaToEdit], selected: nil) { [weak self] controller, media, selected, cancel in
            controller.dismiss(animated: true)
            self?.messageInputView.showMediaPanel(with: media[selected])
        }.withNavigationController()
        present(editController, animated: true)
    }

    func commentInputViewResetReplyContext(_ inputView: CommentInputView) {
        parentCommentID = nil
        messageInputView.removeQuotedReplyPanel()
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

    func commentInputViewCouldNotRecordDuringCall(_ inputView: CommentInputView) {
        let alert = UIAlertController(title: Localizations.failedActionDuringCallTitle, message: Localizations.failedActionDuringCallNoticeText, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: { _ in }))
        present(alert, animated: true)
    }

    func commentInputView(_ inputView: CommentInputView, didInterruptRecorder recorder: AudioRecorder) {
        guard let url = recorder.saveVoiceComment(for: feedPostId) else { return }
        DispatchQueue.main.async {
            self.messageInputView.show(voiceNote: url)
        }
    }

    func presentMediaPicker() {
        guard  mediaPickerController == nil else {
            return
        }
        mediaPickerController = MediaPickerViewController(filter: .all, multiselect: false, camera: true) {[weak self] controller, media, cancel in
            guard let self = self else { return }
            guard let media = media.first, !cancel else {
                DDLogInfo("FlatCommentsViewController/media comment cancelled")
                self.dismissMediaPicker(animated: true)
                return
            }
            if media.ready.value {
                self.messageInputView.showMediaPanel(with: media)
            } else {
                self.cancellableSet.insert(
                    media.ready.sink { [weak self] ready in
                        guard let self = self else { return }
                        guard ready else { return }
                        self.messageInputView.showMediaPanel(with: media)
                    }
                )
            }

            self.dismissMediaPicker(animated: true)
            self.messageInputView.showKeyboard(from: self)
        }
        mediaPickerController?.title = Localizations.newComment

        present(UINavigationController(rootViewController: mediaPickerController!), animated: true)
    }

    func dismissMediaPicker(animated: Bool) {
        if mediaPickerController != nil && presentedViewController != nil {
            dismiss(animated: true)
        }
        mediaPickerController = nil
    }

    func postComment(text: MentionText, media: PendingMedia?, linkPreviewData: LinkPreviewData?, linkPreviewMedia : PendingMedia?) {
        var sendMedia: [PendingMedia] = []
        if let media = media {
            sendMedia.append(media)
        }
        commentToScrollTo = MainAppContext.shared.feedData.post(comment: text, media: sendMedia, linkPreviewData: linkPreviewData, linkPreviewMedia : linkPreviewMedia, to: feedPostId, replyingTo: parentCommentID)
        messageInputView.clear()
    }
}
