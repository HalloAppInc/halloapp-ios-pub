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

    static func unreadMessagesHeaderSingle(unreadCount: String) -> String {
        return String(
            format: NSLocalizedString("comment.unread.messages.header.single", value: "%@ Unread Comment", comment: "Header that appears above one single unread message in the comments view."),
            unreadCount)
    }

    static func unreadMessagesHeaderPlural(unreadCount: String) -> String {
        return String(
            format: NSLocalizedString("comment.unread.messages.header.plural", value: "%@ Unread Comments", comment: "Header that appears above all the unread comments in the comments view when there are more than one unread message"),
            unreadCount)
    }
}

fileprivate enum MessageRow: Hashable, Equatable {
    case comment(FeedPostComment)
    case unreadCountHeader(Int32)
}

class FlatCommentsViewController: UIViewController, UICollectionViewDelegate, NSFetchedResultsControllerDelegate {
    fileprivate typealias CommentDataSource = UICollectionViewDiffableDataSource<String, MessageRow>
    fileprivate typealias CommentSnapshot = NSDiffableDataSourceSnapshot<String, MessageRow>
    static private let messageViewCellReuseIdentifier = "MessageViewCell"
    static private let cellHighlightAnimationDuration = 0.15

    private var mediaPickerController: MediaPickerViewController?
    private var cancellableSet: Set<AnyCancellable> = []
    private var parentCommentID: FeedPostCommentID?

    var highlightedCommentId: FeedPostCommentID?
    private var commentToScrollTo: FeedPostCommentID?
    private var isFirstLaunch: Bool = true

    // Key used to encode/decode array of comment drafts from `UserDefaults`.
    static let postCommentDraftKey = "posts.comments.drafts"

    // List of colors to cycle through while setting user names
    private var colors: [UIColor] = [
        UIColor.userColor1,
        UIColor.userColor2,
        UIColor.userColor3,
        UIColor.userColor4,
        UIColor.userColor5,
        UIColor.userColor6,
        UIColor.userColor7,
        UIColor.userColor8,
        UIColor.userColor9,
        UIColor.userColor10,
        UIColor.userColor11,
        UIColor.userColor12
    ]

    private var feedPostId: FeedPostID {
        didSet {
            // TODO Remove this if not needed for mentions
        }
    }

    private var commentParticipants: [String: Int] = [:]
    private var feedPost: FeedPost?

    // MARK: Jump Button

    private var jumpButtonUnreadCount: Int32 = 0
    private var jumpButtonConstraint: NSLayoutConstraint?

    private lazy var jumpButton: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ jumpButtonUnreadCountLabel, jumpButtonImageView ])
        view.axis = .horizontal
        view.alignment = .center
        view.spacing = 5
        view.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view.isLayoutMarginsRelativeArrangement = true
        view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            jumpButtonImageView.widthAnchor.constraint(equalToConstant: 30),
            jumpButtonImageView.heightAnchor.constraint(equalToConstant: 30)
        ])

        let subView = UIView(frame: view.bounds)
        subView.layer.cornerRadius = 10
        subView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]

        subView.clipsToBounds = true
        subView.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.9)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(subView, at: 0)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(scrollToLastComment))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)

        return view
    }()

    private lazy var jumpButtonUnreadCountLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.textColor = .systemBlue
        return label
    }()

    private lazy var jumpButtonImageView: UIImageView = {
        let view = UIImageView()
        view.image = UIImage(systemName: "chevron.down.circle")
        view.contentMode = .scaleAspectFill
        view.tintColor = .systemBlue

        view.layer.masksToBounds = true

        return view
    }()

    private lazy var dataSource: CommentDataSource = {
        let dataSource = CommentDataSource(
            collectionView: collectionView,
            cellProvider: { [weak self] (collectionView, indexPath, messageRow) -> UICollectionViewCell? in
                switch messageRow {
                case .comment(let feedComment):
                    let cell = collectionView.dequeueReusableCell(
                        withReuseIdentifier: FlatCommentsViewController.messageViewCellReuseIdentifier,
                        for: indexPath)
                    if let itemCell = cell as? MessageViewCell, let self = self {
                        // Get user name colors
                        let userColorAssignment = self.getUserColorAssignment(userId: feedComment.userId)
                        var parentUserColorAssignment = UIColor.secondaryLabel
                        if let parentCommentUserId = feedComment.parent?.userId {
                            parentUserColorAssignment = self.getUserColorAssignment(userId: parentCommentUserId)
                        }

                        let isPreviousMessageFromSameSender = self.isPreviousMessageSameSender(currentComment: feedComment)
                        itemCell.configureWithComment(comment: feedComment, userColorAssignment: userColorAssignment, parentUserColorAssignment: parentUserColorAssignment, isPreviousMessageFromSameSender: isPreviousMessageFromSameSender)
                        itemCell.delegate = self
                        itemCell.textLabel.delegate = self
                    }
                    return cell
                case .unreadCountHeader(let unreadCount):
                    let cell = collectionView.dequeueReusableCell(
                        withReuseIdentifier: MessageUnreadHeaderView.elementKind,
                        for: indexPath)
                    if let itemCell = cell as? MessageUnreadHeaderView {
                        if unreadCount == 1 {
                            itemCell.configure(headerText: Localizations.unreadMessagesHeaderSingle(unreadCount: String(unreadCount)))
                        } else {
                            itemCell.configure(headerText: Localizations.unreadMessagesHeaderPlural(unreadCount: String(unreadCount)))
                        }
                    }
                    return cell
                }
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
                    messageCommentHeaderView.textLabel.delegate = self
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

    private func isPreviousMessageSameSender(currentComment: FeedPostComment) -> Bool {
        var previousComment: FeedPostComment?
        guard let comments = fetchedResultsController?.fetchedObjects else { return false }
        for comment in comments {
            if comment.id == currentComment.id {
                guard let previousComment = previousComment else { return false }
                return previousComment.userId == currentComment.userId
            } else {
                previousComment = comment
            }
        }
        return false
    }

    private func getUserColorAssignment(userId: UserID) -> UIColor {
        guard let userColorIndex = commentParticipants[userId] else {
            commentParticipants[userId] = commentParticipants.count
            return colors[(commentParticipants.count - 1) % colors.count]
        }
        return colors[userColorIndex % colors.count]
    }

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
        collectionView.register(MessageUnreadHeaderView.self, forCellWithReuseIdentifier: MessageUnreadHeaderView.elementKind)
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
            setupUI(with: feedPost)
        }
        messageInputView.delegate = self
        // Long press message options
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(getMessageOptions))
        longPressGesture.delaysTouchesBegan = true
        collectionView.addGestureRecognizer(longPressGesture)
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

        // Add jump to last message button
        guard let keyWindow = UIApplication.shared.windows.filter({$0.isKeyWindow}).first else { return }
        keyWindow.addSubview(jumpButton)
        jumpButton.trailingAnchor.constraint(equalTo: keyWindow.trailingAnchor).isActive = true
        jumpButtonConstraint = jumpButton.bottomAnchor.constraint(equalTo: keyWindow.bottomAnchor, constant: -100)
        jumpButtonConstraint?.isActive = true
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
            if cell.feedPostComment?.id == commentId && cell.isCellHighlighted {
                UIView.animate(withDuration: Self.cellHighlightAnimationDuration) {
                    cell.isCellHighlighted = false
                }
            }
        }
    }

    // Call this method only during initial setting up of the view as it has scroll consequences that should only be done on first load.
    private func setupUI(with feedPost: FeedPost) {
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
        } else if feedPost.unreadCount > 0 {
            setScrollToFirstUnreadComment()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveCommentDraft()
        jumpButton.removeFromSuperview()
        messageInputView.willDisappear(in: self)
        // TODO @Dini check if post is available first
        MainAppContext.shared.feedData.markCommentsAsRead(feedPostId: feedPostId)
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
            DDLogError("FlatCommentsViewController/initFetchedResultsController/fetching comments for post \(feedPostId)")
            try fetchedResultsController?.performFetch()
        } catch {
            DDLogError("FlatCommentsViewController/initFetchedResultsController/failed to fetch comments for post \(feedPostId)")
        }
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        var snapshot = CommentSnapshot()
        if let sections = fetchedResultsController?.sections {
            snapshot.appendSections(sections.map { $0.name } )
            for section in sections {
                if let comments = section.objects as? [FeedPostComment] {
                    comments.forEach { comment in
                        snapshot.appendItems([MessageRow.comment(comment)], toSection: section.name)
                    }
                }
            }
            // Insert the unread messages header. We insert this header only on first launch to avoid
            // the header jumping around as new comments come in while the user is viewing the comments - @Dini
            if let unreadCount = self.feedPost?.unreadCount, unreadCount > 0, isFirstLaunch {
                let unreadHeaderIndex = snapshot.numberOfItems - Int(unreadCount)
                if unreadHeaderIndex > 0 && unreadHeaderIndex < (snapshot.numberOfItems) {
                    let item = snapshot.itemIdentifiers[unreadHeaderIndex]
                    snapshot.insertItems([MessageRow.unreadCountHeader(Int32(unreadCount))], beforeItem: item)
                }
            }
        }
        dataSource.apply(snapshot, animatingDifferences: true) { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.updateScrollingWhenDataChanges()
                self.scrollToTarget(withAnimation: true)
                self.isFirstLaunch = false
            }
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
            // Get user name colors
            let userColorAssignment = self.getUserColorAssignment(userId: comment.userId)
            var parentUserColorAssignment = UIColor.secondaryLabel
            if let parentCommentUserId = comment.parent?.userId {
                parentUserColorAssignment = self.getUserColorAssignment(userId: parentCommentUserId)
            }
            let isPreviousMessageFromSameSender = self.isPreviousMessageSameSender(currentComment: comment)
            cell.configureWithComment(comment: comment, userColorAssignment: userColorAssignment, parentUserColorAssignment: parentUserColorAssignment, isPreviousMessageFromSameSender: isPreviousMessageFromSameSender)
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

    // MARK: Scrolling and Highlighting

    private func updateScrollingWhenDataChanges() {
        // When data changes, if the jump button is not visible, the user is viewing the bottom of the comments,
        // we scroll to bottom so they can see the new comments as they come in.
        guard !jumpButton.isHidden else {
            scrollToLastComment()
            return
        }
        // if the jump button is visible, update jump button counter, letting them know new comments have come.
        // We do not scroll to the bottom so the user can continue viewing at the current position.
        jumpButtonUnreadCount = feedPost?.unreadCount ?? 0
        if self.jumpButtonUnreadCount > 0 {
            jumpButtonUnreadCountLabel.text =  String(jumpButtonUnreadCount)
        } else {
            jumpButtonUnreadCountLabel.text = ""
        }
    }

    func updateJumpButtonVisibility() {
        let windowHeight = view.window?.bounds.height ?? UIScreen.main.bounds.height
        let fromTheBottom =  windowHeight*1.5 - messageInputView.bottomInset
        if collectionView.contentSize.height - collectionView.contentOffset.y > fromTheBottom {
            let aboveMessageInput = messageInputView.bottomInset + 50
            jumpButtonConstraint?.constant = -aboveMessageInput
            jumpButton.isHidden = false
        } else {
            jumpButton.isHidden = true
            jumpButtonUnreadCount = 0
            jumpButtonUnreadCountLabel.text = nil
        }
    }

    @objc private func scrollToLastComment() {
        // Find the last comment and scroll to it
        guard let comments = fetchedResultsController?.fetchedObjects else { return }
        let commentToScrollToIndex = comments.count - 1
        guard commentToScrollToIndex > 0 else { return }
        // On tapping jumpButton, user is taken to the last comment.
        // Mark all comments as read
        jumpButtonUnreadCount = 0
        MainAppContext.shared.feedData.markCommentsAsRead(feedPostId: feedPostId)
        commentToScrollTo = comments[commentToScrollToIndex].id
        scrollToTarget(withAnimation: true)
    }

    private func setScrollToFirstUnreadComment() {
        guard let comments = fetchedResultsController?.fetchedObjects, let feedPost = feedPost else { return }
        var commentToScrollToIndex = (comments.count - 1)
        if feedPost.unreadCount > 1 {
            commentToScrollToIndex -= Int(feedPost.unreadCount - 1)
        }
        if commentToScrollToIndex < 0 { return }
        commentToScrollTo = comments[commentToScrollToIndex].id
    }

    private func scrollToTarget(withAnimation: Bool) {
        DDLogDebug("FlatCommentsView/scrollToTarget/withAnimation: \(withAnimation)")
        let animated = withAnimation && isViewLoaded && view.window != nil && transitionCoordinator == nil
        DDLogDebug("FlatCommentsView/scrollToTarget/commentToScrollTo: \(commentToScrollTo ?? "")")
        if let commentId = commentToScrollTo  {
            scroll(toComment: commentId, animated: animated, highlightAfterScroll: commentId)
        }

       func scroll(toComment commentId: FeedPostCommentID, animated: Bool, highlightAfterScroll: FeedPostCommentID?) {
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
                    resetCommentHighlightingIfNeeded()
                } else {
                    // comment does not need highlighting, we can safely reset commentToScrollTo
                    commentToScrollTo = nil
                }
            }
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateJumpButtonVisibility()
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
            parentCommentID = parentComment
        }
        messageInputView.mentionText = draft.text
        messageInputView.updateInputView()
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
        guard let feedPostComment = messageViewCell.feedPostComment else { return }
        guard let comment = fetchedResultsController?.fetchedObjects?.first(where: {$0.id == feedPostComment.id }) else { return }
        guard !comment.isRetracted else { return }
        parentCommentID = comment.id
        let userColorAssignment = self.getUserColorAssignment(userId: comment.userId)
        messageInputView.showQuotedReplyPanel(comment: comment, userColorAssignment: userColorAssignment)
    }

    func messageView(_ messageViewCell: MessageViewCell, didTapUserId userId: UserID) {
        showUserFeed(for: userId)
    }
    
    func messageView(_ messageViewCell: MessageViewCell, jumpTo feedPostCommentID: FeedPostCommentID) {
        highlightedCommentId = feedPostCommentID
        commentToScrollTo = feedPostCommentID
        scrollToTarget(withAnimation: true)
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
        label.numberOfLines = 0
        collectionView.collectionViewLayout.invalidateLayout()
    }
}

extension FlatCommentsViewController: CommentInputViewDelegate {

    func commentInputView(_ inputView: CommentInputView, didChangeBottomInsetWith animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve) {
            self.updateCollectionViewContentOffset(forKeyboardHeight: inputView.bottomInset)
            // Manually adjust insets to account for inputView
            let bottomContentInset = inputView.bottomInset - collectionView.safeAreaInsets.bottom
            collectionView.contentInset.bottom = bottomContentInset
            collectionView.verticalScrollIndicatorInsets.bottom = bottomContentInset
            updateJumpButtonVisibility()
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
            guard let self = self else { return }
            if media[selected].ready.value {
                controller.dismiss(animated: true)
                self.messageInputView.showMediaPanel(with: media[selected])
            } else {
                self.cancellableSet.insert(
                    media[selected].ready.sink { [weak self] ready in
                        guard let self = self else { return }
                        guard ready else { return }
                        controller.dismiss(animated: true)
                        self.messageInputView.showMediaPanel(with: media[selected])
                    }
                )
            }
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
        parentCommentID = nil
        messageInputView.clear()
    }
}

fileprivate extension NSFetchedResultsController {
    @objc func getOptionalObject(at indexPath: IndexPath) -> AnyObject? {
        guard indexPath.row >= 0 else { return nil }
        guard let sections = sections, indexPath.section < sections.count else { return nil }
        let sectionInfo = sections[indexPath.section]
        guard sectionInfo.numberOfObjects > indexPath.row else { return nil }
        return object(at: indexPath)
    }
}
