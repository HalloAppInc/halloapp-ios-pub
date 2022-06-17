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
import CoreCommon
import CoreData
import UIKit
import AVFoundation

private extension Localizations {
    static var commentsInputPlaceholder: String {
        NSLocalizedString("comment.textfield.placeholder",
                   value: "New Comment",
                 comment: "Placeholder text for the comment input field when there is no user input.")
    }

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

    static func unreadCommentsHeader(unreadCount: Int) -> String {
        let format = NSLocalizedString("n.unread.comments.title", comment: "Header that appears above unread messages in the comments view.")
        return String.localizedStringWithFormat(format, unreadCount)
    }
}

fileprivate enum MessageRow: Hashable, Equatable {
    case comment(FeedPostComment)
    case retracted(FeedPostComment)
    case media(FeedPostComment)
    case audio(FeedPostComment)
    case text(FeedPostComment)
    case linkPreview(FeedPostComment)
    case quoted(FeedPostComment)
    case unreadCountHeader(Int32)
}

class FlatCommentsViewController: UIViewController, UICollectionViewDelegate, NSFetchedResultsControllerDelegate {

    private var loadingTimer = Timer()

    fileprivate typealias CommentDataSource = UICollectionViewDiffableDataSource<String, MessageRow>
    fileprivate typealias CommentSnapshot = NSDiffableDataSourceSnapshot<String, MessageRow>
    static private let messageViewCellReuseIdentifier = "MessageViewCell"
    static private let messageCellViewTextReuseIdentifier = "MessageCellViewText"
    static private let messageCellViewMediaReuseIdentifier = "MessageCellViewMedia"
    static private let messageCellViewAudioReuseIdentifier = "MessageCellViewAudio"
    static private let messageCellViewLinkPreviewReuseIdentifier = "MessageCellViewLinkPreview"
    static private let messageCellViewQuotedReuseIdentifier = "MessageCellViewQuoted"

    private var mediaPickerController: MediaPickerViewController?
    private var cancellableSet: Set<AnyCancellable> = []
    private var parentCommentID: FeedPostCommentID?

    private var initiallyScrolledCommentID: FeedPostCommentID?
    var initiallyHighlightedCommentID: FeedPostCommentID?
    private var isFirstLaunch: Bool = true
    private var scrollToLastCommentOnNextUpdate = false

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
    
    private lazy var activityIndicator: UIActivityIndicatorView = {
        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.color = .secondaryLabel
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        return activityIndicator
    }()

    private lazy var tryAgainLabel: UILabel = {
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

    private lazy var loadingView: UIView = {
        let loadingView = UIView()
        loadingView.translatesAutoresizingMaskIntoConstraints = true
        loadingView.addSubview(activityIndicator)
        loadingView.addSubview(tryAgainLabel)
        return loadingView
    }()

    private func configureCell(itemCell: MessageCellViewBase, for comment: FeedPostComment) {
        // Get user name colors
        let userColorAssignment = getUserColorAssignment(userId: comment.userId)
        var parentUserColorAssignment = UIColor.secondaryLabel
        if let parentCommentUserId = comment.parent?.userId {
            parentUserColorAssignment = getUserColorAssignment(userId: parentCommentUserId)
        }

        let isPreviousMessageFromSameSender = isPreviousMessageSameSender(currentComment: comment)
        itemCell.configureWith(comment: comment, userColorAssignment: userColorAssignment, parentUserColorAssignment: parentUserColorAssignment, isPreviousMessageFromSameSender: isPreviousMessageFromSameSender)
        itemCell.commentDelegate = self
        itemCell.textLabel.delegate = self
    }

    private lazy var dataSource: CommentDataSource = {
        let dataSource = CommentDataSource(
            collectionView: collectionView,
            cellProvider: { [weak self] (collectionView, indexPath, messageRow) -> UICollectionViewCell? in
                switch messageRow {
                case .comment(let feedComment), .retracted(let feedComment):
                    let cell = collectionView.dequeueReusableCell(
                        withReuseIdentifier: FlatCommentsViewController.messageViewCellReuseIdentifier,
                        for: indexPath)
                    if let itemCell = cell as? MessageViewCell, let self = self {
                        self.configureCell(itemCell: itemCell, for: feedComment)
                    }
                    return cell
                case .media(let feedComment):
                    let cell = collectionView.dequeueReusableCell(
                        withReuseIdentifier: FlatCommentsViewController.messageCellViewMediaReuseIdentifier,
                        for: indexPath)
                    if let itemCell = cell as? MessageCellViewMedia, let self = self {
                        self.configureCell(itemCell: itemCell, for: feedComment)
                    }
                    return cell
                case .audio(let feedComment):
                    let cell = collectionView.dequeueReusableCell(
                        withReuseIdentifier: FlatCommentsViewController.messageCellViewAudioReuseIdentifier,
                        for: indexPath)
                    if let itemCell = cell as? MessageCellViewAudio, let self = self {
                        self.configureCell(itemCell: itemCell, for: feedComment)
                    }
                    return cell
                case .linkPreview(let feedComment):
                    let cell = collectionView.dequeueReusableCell(
                        withReuseIdentifier: FlatCommentsViewController.messageCellViewLinkPreviewReuseIdentifier,
                        for: indexPath)
                    if let itemCell = cell as? MessageCellViewLinkPreview, let self = self {
                        self.configureCell(itemCell: itemCell, for: feedComment)
                    }
                    return cell
                case .quoted(let feedComment):
                    let cell = collectionView.dequeueReusableCell(
                        withReuseIdentifier: FlatCommentsViewController.messageCellViewQuotedReuseIdentifier,
                        for: indexPath)
                    if let itemCell = cell as? MessageCellViewQuoted, let self = self {
                        self.configureCell(itemCell: itemCell, for: feedComment)
                    }
                    return cell
                case .text(let feedComment):
                    let cell = collectionView.dequeueReusableCell(
                        withReuseIdentifier: FlatCommentsViewController.messageCellViewTextReuseIdentifier,
                        for: indexPath)
                    if let itemCell = cell as? MessageCellViewText, let self = self {
                        self.configureCell(itemCell: itemCell, for: feedComment)
                    }
                    return cell
                case .unreadCountHeader(let unreadCount):
                    let cell = collectionView.dequeueReusableCell(
                        withReuseIdentifier: MessageUnreadHeaderView.elementKind,
                        for: indexPath)
                    if let itemCell = cell as? MessageUnreadHeaderView {
                        itemCell.configure(headerText: Localizations.unreadCommentsHeader(unreadCount: Int(unreadCount)))
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
                    messageCommentHeaderView.textView.delegate = self
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
    private var feedPostFetchedResultsController: NSFetchedResultsController<FeedPost>?

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: self.view.bounds, collectionViewLayout: createLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = UIColor.primaryBg
        collectionView.allowsSelection = false
        collectionView.contentInsetAdjustmentBehavior = .scrollableAxes
        collectionView.preservesSuperviewLayoutMargins = true
        collectionView.keyboardDismissMode = .interactive
        collectionView.register(MessageViewCell.self, forCellWithReuseIdentifier: FlatCommentsViewController.messageViewCellReuseIdentifier)
        collectionView.register(MessageCellViewText.self, forCellWithReuseIdentifier: FlatCommentsViewController.messageCellViewTextReuseIdentifier)
        collectionView.register(MessageCellViewMedia.self, forCellWithReuseIdentifier: FlatCommentsViewController.messageCellViewMediaReuseIdentifier)
        collectionView.register(MessageCellViewAudio.self, forCellWithReuseIdentifier: FlatCommentsViewController.messageCellViewAudioReuseIdentifier)
        collectionView.register(MessageCellViewLinkPreview.self, forCellWithReuseIdentifier: FlatCommentsViewController.messageCellViewLinkPreviewReuseIdentifier)
        collectionView.register(MessageCellViewQuoted.self, forCellWithReuseIdentifier: FlatCommentsViewController.messageCellViewQuotedReuseIdentifier)
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
        super.init(nibName: nil, bundle: nil)
        self.hidesBottomBarWhenPushed = true
        initPostFetchedResultsController()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.titleView = navigationTitleView

        // If we are the only view controller in our navigation stack, add a dismiss button
        if navigationController?.viewControllers.count == 1, navigationController?.topViewController === self {
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "chevron.down"),
                                                               style: .plain,
                                                               target: self,
                                                               action: #selector(dismissAnimated))
        }

        view.backgroundColor = UIColor.primaryBg
        view.addSubview(collectionView)
        collectionView.constrain(to: view)

        updatePost()

        if let feedPost = feedPost {
            setupUI(with: feedPost)
        } else {
            showInputView = false
            self.view.addSubview(loadingView)
            activityIndicator.startAnimating()
            NSLayoutConstraint.activate([
                activityIndicator.centerXAnchor.constraint(equalTo: view.layoutMarginsGuide.centerXAnchor),
                activityIndicator.centerYAnchor.constraint(equalTo: view.layoutMarginsGuide.centerYAnchor)
            ])
            tryAgainLabel.constrainMargins(to: view)
            loadingTimer = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(updateAfterTimerEnds), userInfo: nil, repeats: false)
        }

        // Long press message options
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(getMessageOptions))
        longPressGesture.delaysTouchesBegan = true
        collectionView.addGestureRecognizer(longPressGesture)
    }

    @objc private func updateAfterTimerEnds() {
        loadingTimer.invalidate()
        activityIndicator.stopAnimating()
        self.tryAgainLabel.isHidden = false
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadCommentsDraft()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId, in: MainAppContext.shared.feedData.viewContext) {
            MainAppContext.shared.feedData.sendSeenReceiptIfNecessary(for: feedPost)
        }

        // TODO @dini check if post is available first
        MainAppContext.shared.feedData.markCommentsAsRead(feedPostId: feedPostId)

        if let commentID = initiallyHighlightedCommentID {
            highlightComment(id: commentID)
            initiallyHighlightedCommentID = nil
        }

        // Add jump to last message button
        view.addSubview(jumpButton)
        jumpButton.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        jumpButtonConstraint = jumpButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -(collectionView.contentInset.bottom + 50))
        jumpButtonConstraint?.isActive = true
    }

    private var postLoadingCancellable: AnyCancellable?

    // Call this method only during initial setting up of the view as it has scroll consequences that should only be done on first load.
    private func setupUI(with feedPost: FeedPost) {
        if loadingView.isDescendant(of: view) {
            loadingView.removeFromSuperview()
        }
        if postLoadingCancellable != nil {
            postLoadingCancellable?.cancel()
            postLoadingCancellable = nil
        }
        navigationTitleView.headerView.configure(withPost: feedPost)
        showInputView = true
        // Setup the diffable data source so it can be used for first fetch of data
        collectionView.dataSource = dataSource
        initCommentsFetchedResultsController()
        updateComments()

        // Initiate download of media that were not yet downloaded. TODO Ask if this is needed
        if let comments = fetchedResultsController?.fetchedObjects {
            MainAppContext.shared.feedData.downloadMedia(in: comments)
        }
        // Coming from notification
        if let initiallyHighlightedCommentID = initiallyHighlightedCommentID {
            initiallyScrolledCommentID = initiallyHighlightedCommentID
        } else if feedPost.unreadCount > 0, let comments = fetchedResultsController?.fetchedObjects, !comments.isEmpty {
            initiallyScrolledCommentID = comments[max(0, min(comments.endIndex - Int(feedPost.unreadCount) + 1, comments.count - 1))].id
        } else {
            initiallyScrolledCommentID = fetchedResultsController?.fetchedObjects?.last?.id
        }
        MainAppContext.shared.feedData.markCommentsAsRead(feedPostId: feedPostId)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if let commentID = initiallyScrolledCommentID {
            scrollToComment(id: commentID)
            initiallyScrolledCommentID = nil
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveCommentDraft()
        jumpButton.removeFromSuperview()
        // TODO @Dini check if post is available first
        MainAppContext.shared.feedData.markCommentsAsRead(feedPostId: feedPostId)
    }

    private func initCommentsFetchedResultsController() {
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

    private func initPostFetchedResultsController() {
        // Setup feedPost fetched results controller
        let feedPostFetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        feedPostFetchRequest.predicate = NSPredicate(format: "id == %@", feedPostId)
        feedPostFetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: true) ]
        feedPostFetchRequest.fetchLimit = 1
        feedPostFetchedResultsController = NSFetchedResultsController<FeedPost>(
            fetchRequest: feedPostFetchRequest,
            managedObjectContext: MainAppContext.shared.feedData.viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        feedPostFetchedResultsController?.delegate = self
        do {
            DDLogError("FlatCommentsViewController/initFetchedResultsController/fetching post \(feedPostId)")
            try feedPostFetchedResultsController?.performFetch()
        } catch {
            DDLogError("FlatCommentsViewController/initFetchedResultsController/failed to fetch post \(feedPostId)")
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        switch controller {
        case fetchedResultsController:
            updateComments()
        case feedPostFetchedResultsController:
            updatePost()
        default:
            break
        }
    }

    func updateComments() {
        var snapshot = CommentSnapshot()
        if let sections = fetchedResultsController?.sections {
            snapshot.appendSections(sections.map { $0.name } )
            for section in sections {
                if let comments = section.objects as? [FeedPostComment] {
                    comments.forEach { comment in
                        let messageRow = messagerow(for: comment)
                        snapshot.appendItems([messageRow], toSection: section.name)
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
                self.isFirstLaunch = false
            }
        }
    }

    func updatePost() {
        guard let post = feedPostFetchedResultsController?.fetchedObjects?.first(where: {$0.id == feedPostId }) else { return }
        if feedPost == nil {
            feedPost = post
        }
        switch post.status {
        case .retracted:
            if let presentedVC = self.presentedViewController {
                presentedVC.dismiss(animated: false) {
                    self.navigationController?.popViewController(animated: true)
                }
            } else {
                self.navigationController?.popViewController(animated: true)
            }
        default:
            break
        }
    }
    
    private func messagerow(for comment: FeedPostComment) -> MessageRow {
        if [.retracted, .retracting, .rerequesting, .unsupported].contains(comment.status) {
            return MessageRow.comment(comment)
        }
        // Quoted Comment
        if comment.parent != nil {
            return MessageRow.quoted(comment)
        }
        // Media
        if let media = MainAppContext.shared.feedData.media(commentID: comment.id, in: MainAppContext.shared.feedData.viewContext), media.count > 0 {
            if commentHasAudio(media: media) {
                return MessageRow.audio(comment)
            }
            return MessageRow.media(comment)
        }
        // Link Preview
        if let feedLinkPreviews = comment.linkPreviews, feedLinkPreviews.first != nil {
            return MessageRow.linkPreview(comment)
        }
        return MessageRow.text(comment)
    }
    
    private func commentHasAudio(media: [FeedMedia]) -> Bool {
        if media.count == 1 && media[0].type == .audio {
            return true
        } else {
            return false
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
        return Mentions.mentionableUsers(forPostID: feedPostId, in: MainAppContext.shared.feedData.viewContext)
    }

    func comment(at indexPath: IndexPath) -> FeedPostComment? {
        guard let identifier = dataSource.itemIdentifier(for: indexPath) else {
            return nil
        }

        switch identifier {
        case .comment(let feedPostComment), .retracted(let feedPostComment), .media(let feedPostComment),
                .audio(let feedPostComment), .text(let feedPostComment), .linkPreview(let feedPostComment),
                .quoted(let feedPostComment):
            return feedPostComment
        case .unreadCountHeader(_):
            return nil
        }
    }

    @objc func getMessageOptions(_ gestureRecognizer: UILongPressGestureRecognizer) {
        guard let indexPath = collectionView.indexPathForItem(at: gestureRecognizer.location(in: collectionView)),
              let cell = collectionView.cellForItem(at: indexPath) as? MessageCellViewBase,
              let comment = comment(at: indexPath),
              comment.status != .retracted,
              // Only the author can delete a comment
              comment.userId == MainAppContext.shared.userData.userId else {
            return
        }

        cell.markViewSelected()
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        // Setup action sheet
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: Localizations.messageDelete, style: .destructive) { [weak self] _ in
            self?.presentDeleteConfirmationActionSheet(indexPath: indexPath, cell: cell, comment: comment)
        })
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel) { _ in
            cell.markViewUnselected()
        })
        present(actionSheet, animated: true)
    }

    private func presentDeleteConfirmationActionSheet(indexPath: IndexPath, cell: MessageCellViewBase, comment: FeedPostComment) {
        let confirmationActionSheet = UIAlertController(title: nil, message: Localizations.deleteCommentConfirmation, preferredStyle: .actionSheet)
        confirmationActionSheet.addAction(UIAlertAction(title: Localizations.deleteCommentAction, style: .destructive) { _ in
            guard let comment = MainAppContext.shared.feedData.feedComment(with: comment.id, in: MainAppContext.shared.feedData.viewContext) else { return }
            MainAppContext.shared.feedData.retract(comment: comment)
        })
        confirmationActionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel) { _ in
            cell.markViewUnselected()
        })
        self.present(confirmationActionSheet, animated: true)
    }

    // MARK: UI Actions

    @objc private func showUserFeedForPostAuthor() {
        if let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId, in: MainAppContext.shared.feedData.viewContext) {
            showUserFeed(for: feedPost.userId)
        }
    }
    
    @objc private func showGroupFeed(groupId: GroupID) {
        guard let feedPost = self.feedPost, let groupId = feedPost.groupId else { return }
        guard MainAppContext.shared.chatData.chatGroup(groupId: groupId, in: MainAppContext.shared.feedData.viewContext) != nil else { return }
        let vc = GroupFeedViewController(groupId: groupId)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func showUserFeed(for userID: UserID) {
        let userViewController = UserFeedViewController(userId: userID)
        self.navigationController?.pushViewController(userViewController, animated: true)
    }

    @objc func dismissKeyboard (_ sender: UITapGestureRecognizer) {
        messageInputView.textView.resignFirstResponder()
    }

    // MARK: Scrolling and Highlighting

    private func updateScrollingWhenDataChanges() {
        jumpButtonUnreadCount = feedPost?.unreadCount ?? 0
        updateJumpButtonText()

        guard !isFirstLaunch else {
            return
        }

        // When data changes, if the jump button is not visible, the user is viewing the bottom of the comments,
        // we scroll to bottom so they can see the new comments as they come in.
        // Do not scroll to bottom if all comments are unread
        if scrollToLastCommentOnNextUpdate || jumpButton.alpha == 0 {
            scrollToLastCommentOnNextUpdate = false
            scrollToLastComment()
            return
        }
    }

    func updateJumpButtonVisibility() {
        let hideJumpButton: Bool
        if let lastComment = fetchedResultsController?.fetchedObjects?.last,
           let lastCommentIndexPath = indexPath(for: lastComment.id),
           let lastCommentLayoutAttributes = collectionView.layoutAttributesForItem(at: lastCommentIndexPath) {
            // Display jump button when the last comment is no longer visible
            let insetBounds = collectionView.bounds.inset(by: collectionView.adjustedContentInset)
            hideJumpButton = insetBounds.intersects(lastCommentLayoutAttributes.frame)
        } else {
            hideJumpButton = true
        }

        let jumpButtonAlpha: CGFloat = hideJumpButton ? 0.0 : 1.0
        if jumpButton.alpha != jumpButtonAlpha {
            UIView.animate(withDuration: 0.25, delay: 0.0, options: .curveEaseInOut) {
                self.jumpButton.alpha = jumpButtonAlpha
            }
        }

        // Mark all comments as read on scrolling to bottom
        if !hideJumpButton {
            jumpButtonUnreadCount = 0
            MainAppContext.shared.feedData.markCommentsAsRead(feedPostId: feedPostId)
            updateJumpButtonText()
        }

        jumpButtonConstraint?.constant = -(collectionView.contentInset.bottom + 50)
    }

    private func updateJumpButtonText() {
        jumpButtonUnreadCountLabel.text = jumpButtonUnreadCount > 0 ? String(jumpButtonUnreadCount) : nil
    }

    @objc private func scrollToLastComment() {
        // Find the last comment and scroll to it
        guard let comment = fetchedResultsController?.fetchedObjects?.last else {
            return
        }

        scrollToComment(id: comment.id, animated: true)
        updateJumpButtonText()
    }

    private func scrollToComment(id: FeedPostCommentID, animated: Bool = false, highlightAfterScroll: Bool = false) {
        guard let indexPath = indexPath(for: id) else {
            DDLogDebug("FlatCommentsView/scrollToComment failed for \(id)")
            return
        }
        DDLogDebug("FlatCommentsView/scrollToComment:\(id) animated:\(animated)")
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: animated)
        if !animated {
            // Attempt to get a more exact position than provided from estimated sizes.
            // Not compatible with animation, but useful for finding initial scroll positions
            collectionView.layoutIfNeeded()
            collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        }

        if highlightAfterScroll {
            highlightComment(id: id)
        }
    }

    private func highlightComment(id: FeedPostCommentID) {
        guard let indexPath = indexPath(for: id),
              let cell = collectionView.cellForItem(at: indexPath) as? MessageCellViewBase else {
            DDLogDebug("FlatCommentsView/highlightComment failed for \(id)")
            return
        }

        DDLogDebug("FlatCommentsView/highlightComment: \(id)")
        cell.runHighlightAnimation()
    }

    private func indexPath(for id: FeedPostCommentID) -> IndexPath? {
        guard let comment = fetchedResultsController?.fetchedObjects?.first(where: { $0.id == id }) else {
            return nil
        }
        return dataSource.indexPath(for: messagerow(for: comment))
    }

    private let navigationTitleView = NavigationTitleView()

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateJumpButtonVisibility()
        let x = -(scrollView.adjustedContentInset.top)
        // height of the header is approx 20.
        let headerHeight = 20.0
        
        if scrollView.contentOffset.y < x + headerHeight  {
            //  comment title scroll down and fade in
            // headerView scroll out and fade out
            UIView.animate(withDuration: 0.5, animations: { [self] in
                navigationTitleView.titleLabel.alpha = 1
                navigationController?.navigationBar.standardAppearance.shadowColor = nil
                navigationController?.navigationBar.scrollEdgeAppearance?.shadowColor = nil
                navigationController?.navigationBar.compactAppearance?.shadowColor = nil
            })
            
            navigationTitleView.headerView.alpha = 0
        } else {
            //  comment title scroll up and fade out
            // headerView scroll in and fade in
            UIView.animate(withDuration: 0.5, animations: { [self] in
                navigationTitleView.titleLabel.alpha = 0
                navigationTitleView.headerView.alpha = 1
                navigationController?.navigationBar.standardAppearance.shadowColor = .separator
                navigationController?.navigationBar.scrollEdgeAppearance?.shadowColor = .separator
                navigationController?.navigationBar.compactAppearance?.shadowColor = .separator
            })
        }
    }

    // MARK: Input view

    private lazy var messageInputView: ContentInputView = {
        let inputView = ContentInputView(options: .comments)
        inputView.autoresizingMask = [.flexibleHeight]
        inputView.placeholderText = Localizations.commentsInputPlaceholder
        inputView.delegate = self
        return inputView
    }()

    override var canBecomeFirstResponder: Bool {
        get {
            if let groupID = feedPost?.groupId {
                // don't allow commenting if user is no longer part of this feed post's group
                let viewContext = MainAppContext.shared.chatData.viewContext
                if let _ = MainAppContext.shared.chatData.chatGroupMember(groupId: groupID, memberUserId: MainAppContext.shared.userData.userId, in: viewContext) {
                    return true
                } else {
                    return false
                }
            }
            
            return true
        }
    }

    private var showInputView = true {
        didSet { reloadInputViews() }
    }

    override var inputAccessoryView: ContentInputView? {
        return showInputView ? self.messageInputView : nil
    }

    // MARK: Draft Comments

    private func saveCommentDraft() {
        guard !messageInputView.textView.mentionText.collapsedText.isEmpty else {
            FeedData.deletePostCommentDrafts { existingDraft in
                existingDraft.postID == feedPostId
            }
            return
        }
        let draft = CommentDraft(postID: feedPostId, text: messageInputView.textView.mentionText, parentComment: parentCommentID)
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

        messageInputView.set(draft: draft.text)
    }

    @objc private func dismissAnimated() {
        dismiss(animated: true)
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
        guard let media = MainAppContext.shared.feedData.media(postID: feedPostId, in: MainAppContext.shared.feedData.viewContext) else { return }

        var canSavePost = false

        if let post = MainAppContext.shared.feedData.feedPost(with: feedPostId, in: MainAppContext.shared.feedData.viewContext) {
            canSavePost = post.canSaveMedia
        }

        let controller = MediaExplorerController(media: media, index: index, canSaveMedia: canSavePost, source: .post)
        controller.animatorDelegate = view
        present(controller, animated: true)
    }
}

extension FlatCommentsViewController: MessageViewCommentDelegate {
    func messageView(_ view: MediaListAnimatorDelegate, forComment feedPostCommentID: FeedPostCommentID, didTapMediaAtIndex index: Int) {
        messageInputView.textView.resignFirstResponder()
        var canSavePost = false
        if let post = MainAppContext.shared.feedData.feedPost(with: feedPostId, in: MainAppContext.shared.feedData.viewContext) {
            canSavePost = post.canSaveMedia
        }
        guard let media = MainAppContext.shared.feedData.media(commentID: feedPostCommentID, in: MainAppContext.shared.feedData.viewContext) else { return }
        let controller = MediaExplorerController(media: media, index: index, canSaveMedia: canSavePost, source: .comment)
        controller.animatorDelegate = view
        present(controller, animated: true)
    }

    func messageView(_ messageViewCell: MessageCellViewBase, replyTo feedPostCommentID: FeedPostCommentID) {
        guard
            let feedPostComment = messageViewCell.feedPostComment,
            let comment = fetchedResultsController?.fetchedObjects?.first(where: {$0.id == feedPostComment.id }),
            !comment.isRetracted
        else {
            return
        }

        let userColorAssignment = self.getUserColorAssignment(userId: comment.userId)
        let panel = QuotedCommentPanel(comment: comment, color: userColorAssignment)
        parentCommentID = comment.id
        messageInputView.display(context: panel)

        messageInputView.textView.becomeFirstResponder()
    }

    func messageView(_ messageViewCell: MessageCellViewBase, didTapUserId userId: UserID) {
        showUserFeed(for: userId)
    }
    
    func messageView(_ messageViewCell: MessageCellViewBase, jumpTo feedPostCommentID: FeedPostCommentID) {
        scrollToComment(id: feedPostCommentID, animated: true, highlightAfterScroll: true)
    }
}

extension FeedPostComment {
  @objc var headerTime: String {
      get {
          return timestamp.chatMsgGroupingTimestamp(Date())
      }
  }
}

extension FlatCommentsViewController: ExpandableTextViewDelegate, UserMenuHandler {
    func textView(_ textView: ExpandableTextView, didRequestHandleMention userID: UserID) {
        showUserFeed(for: userID)
    }
    
    func textViewDidRequestToExpand(_ textView: ExpandableTextView) {
        textView.numberOfLines = 0
        collectionView.collectionViewLayout.invalidateLayout()
    }
    
    func textView(_ textView: ExpandableTextView, didSelectAction action: UserMenuAction) {
        handle(action: action)
    }
    
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        
        return !URLRouter.shared.handle(url: URL)
    }
}

extension FlatCommentsViewController: TextLabelDelegate {
    func textLabel(_ label: TextLabel, didRequestHandle link: AttributedTextLink) {
        switch link.linkType {
        case .link, .phoneNumber:
            if let url = link.result?.url {
                URLRouter.shared.handleOrOpen(url: url)
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

extension FlatCommentsViewController: ContentInputDelegate {

    func inputView(_ inputView: ContentInputView, didChangeHeightTo height: CGFloat) {
        if let coordinator = transitionCoordinator, coordinator.isInteractive {
            return
        }

        let bottomInset = height
        let adjustedBottomInset = bottomInset - collectionView.safeAreaInsets.bottom
        let previousBottomInset = collectionView.contentInset.bottom

        if initiallyScrolledCommentID == nil {
            UIView.animate(withDuration: 0.4, delay: 0.0, options: []) { [collectionView] in
                collectionView.contentInset.bottom = adjustedBottomInset
                collectionView.verticalScrollIndicatorInsets.bottom = adjustedBottomInset

                if previousBottomInset < adjustedBottomInset {
                    // ensure scroll offsets keep us in bounds
                    let maxOffset = max(collectionView.contentSize.height - collectionView.bounds.height + bottomInset,
                                        -collectionView.adjustedContentInset.top)
                    collectionView.contentOffset.y = min(collectionView.contentOffset.y + adjustedBottomInset - previousBottomInset,
                                                         maxOffset)
                }
            }
        } else {
            collectionView.contentInset.bottom = adjustedBottomInset
            collectionView.verticalScrollIndicatorInsets.bottom = adjustedBottomInset
        }
    }

    func inputView(_ inputView: ContentInputView, didPost content: ContentInputView.InputContent) {
        postComment(text: content.mentionText,
                    media: content.media.first,
         linkPreviewData: content.linkPreview?.data,
        linkPreviewMedia: content.linkPreview?.media)
    }

    func inputView(_ inputView: ContentInputView, possibleMentionsFor input: String) -> [MentionableUser] {
        return mentionableUsers.filter { Mentions.isPotentialMatch(fullName: $0.fullName, input: input) }
    }

    func inputViewDidSelectCamera(_ inputView: ContentInputView) {
        presentCameraViewController()
    }
    
    func inputViewContentOptionsMenu(_ inputView: ContentInputView) -> HAMenu.Content {
        let cameraImage = UIImage(systemName: "camera.fill")?.withRenderingMode(.alwaysOriginal)
                                                             .withTintColor(.primaryBlue)
        let pickerImage = UIImage(systemName: "photo.fill.on.rectangle.fill")?.withRenderingMode(.alwaysOriginal)
                                                                              .withTintColor(.primaryBlue)
        
        HAMenuButton(title: Localizations.fabAccessibilityCamera, image: cameraImage) { [weak self] in
            self?.presentCameraViewController()
        }
        
        HAMenuButton(title: Localizations.photoAndVideoLibrary, image: pickerImage) { [weak self] in
            self?.presentMediaPicker()
        }
    }

    private func presentCameraViewController() {
        let tookImage: ((UIImage) -> Void) = { [weak self] image in
            self?.dismiss(animated: true)
            self?.didTake(photo: image)
        }
        let tookVideo: ((URL) -> Void) = { [weak self] url in
            self?.dismiss(animated: true)
            self?.didTake(video: url)
        }

        let vc = CameraViewController(configuration: .init(showCancelButton: true, format: .normal),
                                          didFinish: { [weak self] in self?.dismiss(animated: true)},
                                       didPickImage: tookImage,
                                       didPickVideo: tookVideo)
        present(UINavigationController(rootViewController: vc), animated: true)
    }

    private func didTake(photo: UIImage) {
        let media = PendingMedia(type: .image)
        media.image = photo

        addMediaWhenAvailable(media)
    }

    private func didTake(video url: URL) {
        let media = PendingMedia(type: .video)
        media.originalVideoURL = url
        media.fileURL = url

        addMediaWhenAvailable(media)
    }

    func inputView(_ inputView: ContentInputView, didTap selectedMedia: PendingMedia) {
        let editController = MediaEditViewController(mediaToEdit: [selectedMedia], selected: nil) { [weak self] controller, media, selected, cancel in
            self?.dismiss(animated: true)
            self?.addMediaWhenAvailable(media[selected])
        }.withNavigationController()
        present(editController, animated: true)
    }

    func inputView(_ inputView: ContentInputView, didClose panel: InputContextPanel) {
        if panel.isKind(of: QuotedCommentPanel.self) {
            parentCommentID = nil
        }
    }

    func inputViewMicrophoneAccessDenied(_ inputView: ContentInputView) {
        let alert = UIAlertController(title: Localizations.micAccessDeniedTitle, message: Localizations.micAccessDeniedMessage, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        alert.addAction(UIAlertAction(title: Localizations.settingsAppName, style: .default, handler: { _ in
            guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(settingsUrl)
        }))
        present(alert, animated: true)
    }

    func inputViewMicrophoneAccessDeniedDuringCall(_ inputView: ContentInputView) {
        let alert = UIAlertController(title: Localizations.failedActionDuringCallTitle, message: Localizations.failedActionDuringCallNoticeText, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: { _ in }))
        present(alert, animated: true)
    }

    func inputView(_ inputView: ContentInputView, didInterrupt recorder: AudioRecorder) {
        guard let url = recorder.saveVoiceComment(for: feedPostId) else { return }
        DispatchQueue.main.async {
            self.messageInputView.show(voiceNote: url)
        }
    }
    
    func inputView(_ inputView: ContentInputView, didPaste image: PendingMedia) {
        addMediaWhenAvailable(image)
    }

    func presentMediaPicker() {
        guard  mediaPickerController == nil else {
            return
        }
        mediaPickerController = MediaPickerViewController(config: .comments) { [weak self] controller, _, _, media, cancel in
            guard let self = self else { return }
            guard let media = media.first, !cancel else {
                DDLogInfo("FlatCommentsViewController/media comment cancelled")
                self.dismissMediaPicker(animated: true)
                return
            }

            self.addMediaWhenAvailable(media)
            self.dismissMediaPicker(animated: true)
            self.messageInputView.textView.becomeFirstResponder()
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
        MainAppContext.shared.feedData.post(comment: text,
                                              media: sendMedia,
                                    linkPreviewData: linkPreviewData,
                                   linkPreviewMedia: linkPreviewMedia,
                                                 to: feedPostId,
                                         replyingTo: parentCommentID)
        scrollToLastCommentOnNextUpdate = true
        parentCommentID = nil
    }

    private func addMediaWhenAvailable(_ media: PendingMedia) {
        guard !media.ready.value else {
            messageInputView.add(media: media)
            return
        }

        media.ready.sink { [weak self] ready in
            if ready {
                self?.messageInputView.add(media: media)
            }
        }.store(in: &cancellableSet)
    }
}

extension FlatCommentsViewController {
    private class NavigationTitleView: UIView {
        let headerView: MessageCommentViewHeaderPreview = {
            let navigationHeaderView = MessageCommentViewHeaderPreview()
            navigationHeaderView.translatesAutoresizingMaskIntoConstraints = false
            return navigationHeaderView
        }()

        let titleLabel: UILabel = {
            let commentsTitleLabel = UILabel()
            commentsTitleLabel.translatesAutoresizingMaskIntoConstraints = false
            commentsTitleLabel.text = Localizations.titleComments
            commentsTitleLabel.font = UIFont.gothamFont(ofFixedSize: 15, weight: .medium)
            commentsTitleLabel.textColor = UIColor.label.withAlphaComponent(0.9)
            commentsTitleLabel.numberOfLines = 1
            commentsTitleLabel.textAlignment = .center
            return commentsTitleLabel
        }()
        
        var titleLabelFallbackCenterXConstraint: NSLayoutConstraint? = nil
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            commonInit()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            commonInit()
        }

        private func commonInit() {
            translatesAutoresizingMaskIntoConstraints = false

            let widthConstraint = widthAnchor.constraint(equalToConstant: .greatestFiniteMagnitude)
            widthConstraint.priority = .defaultLow
            widthConstraint.isActive = true
            
            let heightConstraint = heightAnchor.constraint(equalToConstant: .greatestFiniteMagnitude)
            heightConstraint.priority = .defaultLow
            heightConstraint.isActive = true
            
            addSubview(titleLabel)
            addSubview(headerView)
            
            titleLabelFallbackCenterXConstraint = titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor)
            titleLabelFallbackCenterXConstraint?.isActive = true
            
            NSLayoutConstraint.activate([
                titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
                headerView.centerYAnchor.constraint(equalTo: centerYAnchor),
                headerView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            ])
        }
        
        override func didMoveToWindow() {
            if let bar = sequence(first: self, next: { $0.superview }).lazy.compactMap({ $0 as? UINavigationBar }).first {
                titleLabelFallbackCenterXConstraint?.isActive = false
                titleLabel.centerXAnchor.constraint(equalTo: bar.centerXAnchor).isActive = true
            }
        }
    }
}
