//
//  FeedCollectionViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 11/12/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import CoreData
import SwiftUI
import UIKit
import Intents
import Photos
import SafariServices

protocol FeedCollectionViewControllerDelegate: AnyObject {
    func feedCollectionViewController(_ feedCollectionViewController: FeedCollectionViewController, userActioned: Bool)
}

class FeedCollectionViewController: UIViewController, FeedDataSourceDelegate, ShareMenuPresenter, UIViewControllerMediaSaving, UserActionHandler {

    weak var delegate: FeedCollectionViewControllerDelegate?

    // TODO: Remove this implicitly unwrapped optional
    private(set) var collectionView: UICollectionView!
    let feedDataSource: FeedDataSource
    var collectionViewDataSource: UICollectionViewDiffableDataSource<FeedDisplaySection, FeedDisplayItem>?
    
    private lazy var feedLayout: FeedLayout = {

        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                             heightDimension: .estimated(64))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                              heightDimension: .estimated(64))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.boundarySupplementaryItems = collectionViewSupplementaryItems
        section.contentInsets = Self.collectionViewSectionInsets

        return FeedLayout(section: section)
    }()

    var collectionViewSupplementaryItems: [NSCollectionLayoutBoundarySupplementaryItem] {
        return []
    }

    class var collectionViewSectionInsets: NSDirectionalEdgeInsets {
        return .zero
    }

    private var cancellableSet: Set<AnyCancellable> = []

    private var postDisplayData = [FeedPostID: FeedPostDisplayData]()

    private var isVisible: Bool = true
    private var isCheckForOnscreenCellsScheduled: Bool = false

    private var invitedContacts: Set<InviteContact> = Set()

    lazy var inviteContactsManager: InviteContactsManager = {
        let inviteContactsManager = InviteContactsManager(hideInvitedAndHidden: true, sort: .numPotentialContacts)
        inviteContactsManager.contactsChanged = suggestedContactsDidChange
        return inviteContactsManager
    }()

    lazy var suggestionsManager: FriendSuggestionsManager = {
        let suggestionsManager = FriendSuggestionsManager()
        suggestionsManager.suggestionsDidChange = { [weak self] animate in
            self?.friendSuggestionsDidChange(animateChanges: animate)
        }
        return suggestionsManager
    }()

    var isThemed: Bool {
        return false
    }

    var feedPostIdToScrollTo: FeedPostID?
    var shouldScrollToOwnMoment = false
    
    var firstActionHappened: Bool = false

    init(title: String?, fetchRequest: NSFetchRequest<FeedPost>) {
        self.feedDataSource = FeedDataSource(fetchRequest: fetchRequest)
        super.init(nibName: nil, bundle: nil)
        self.title = title
        
        feedDataSource.delegate = self
        feedDataSource.setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        DDLogInfo("FeedCollectionView/viewDidLoad")

        view.backgroundColor = .feedBackground

        setupCollectionView()

        setupNoConnectionBanner()

        cancellableSet.insert(MainAppContext.shared.mainDataStore.willClearStore.sink { [weak self] in
            guard let self = self else { return }
            self.view.isUserInteractionEnabled = false
            self.feedDataSource.clear()
            self.collectionView.reloadData()
        })

        cancellableSet.insert(
            MainAppContext.shared.mainDataStore.didClearStore.sink { [weak self] in
                guard let self = self else { return }
                self.feedDataSource.setup()
                self.collectionView.reloadData()
                self.view.isUserInteractionEnabled = true
        })

        cancellableSet.insert(
            MainAppContext.shared.feedData.shouldReloadView.sink { [weak self] in
                guard let self = self else { return }
                self.feedDataSource.refresh()
        })

        CountPublisher<FeedPost>(context: MainAppContext.shared.mainDataStore.viewContext, predicate: FeedPost.unreadPostsPredicate)
            .filter { $0 == 0 }
            .sink { [weak self] _ in self?.removeNewPostsIndicator() }
            .store(in: &cancellableSet)

        cancellableSet.insert(
            MainAppContext.shared.service.didDisconnect.sink { [weak self] in
                DispatchQueue.main.async { self?.updateNoConnectionBanner(animated: true) }
            }
        )

        cancellableSet.insert(
            MainAppContext.shared.service.didConnect.sink { [weak self] in
                DispatchQueue.main.async { self?.updateNoConnectionBanner(animated: true) }
            }
        )

        cancellableSet.insert(
            NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification).sink { [weak self] (_) in
                guard let self = self else { return }
                self.stopAllVideoPlayback()
        })

        cancellableSet.insert(
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification).sink { [weak self] (_) in
                guard let self = self else { return }
                self.refreshTimestamps()
        })

        cancellableSet.insert(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification).sink { [weak self] (_) in
                guard let self = self else { return }
                self.checkForOnscreenCells()
                self.updateNoConnectionBanner(animated: true)
        })

        cancellableSet.insert(
            MainAppContext.shared.chatData.didGetAGroupEvent.sink { [weak self] (groupID) in
                guard let self = self else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    let visibleCellNeedsUpdate = self.collectionView.indexPathsForVisibleItems.contains { indexPath in
                        guard let cellGroupID = self.feedDataSource.item(at: indexPath.item)?.post?.groupId else  {
                            return false
                        }
                        return cellGroupID == groupID
                    }
                    if visibleCellNeedsUpdate {
                        self.collectionView.reloadData()
                    }
                }
            }
        )

        update(with: feedDataSource.displayItems, animated: false)
    }

    func setupCollectionView() {
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: feedLayout)
        collectionViewDataSource = makeCollectionViewDataSource()

        collectionView.delegate = self
        collectionView.dataSource = collectionViewDataSource
        collectionView.allowsSelection = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.backgroundColor = .clear
        collectionView.preservesSuperviewLayoutMargins = true
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(FeedPostCollectionViewCell.self, forCellWithReuseIdentifier: FeedPostCollectionViewCell.reuseIdentifier)
        collectionView.register(FeedEventCollectionViewCell.self, forCellWithReuseIdentifier: FeedEventCollectionViewCell.reuseIdentifier)
        collectionView.register(FeedWelcomeCell.self, forCellWithReuseIdentifier: FeedWelcomeCell.reuseIdentifier)
        collectionView.register(GroupFeedWelcomeCell.self, forCellWithReuseIdentifier: GroupFeedWelcomeCell.reuseIdentifier)
        collectionView.register(FeedInviteCarouselCell.self, forCellWithReuseIdentifier: FeedInviteCarouselCell.reuseIdentifier)
        collectionView.register(FeedSuggestionsCarouselCell.self, forCellWithReuseIdentifier: FeedSuggestionsCarouselCell.reuseIdentifier)
        collectionView.register(MomentCollectionViewCell.self, forCellWithReuseIdentifier: MomentCollectionViewCell.reuseIdentifier)
        collectionView.register(StackedMomentCollectionViewCell.self, forCellWithReuseIdentifier: StackedMomentCollectionViewCell.reuseIdentifier)
        collectionView.register(FeedShareCarouselCell.self, forCellWithReuseIdentifier: FeedShareCarouselCell.reuseIdentifier)
        collectionView.register(OwnProfileHeaderCollectionViewCell.self, forCellWithReuseIdentifier: OwnProfileHeaderCollectionViewCell.reuseIdentifier)
        collectionView.register(ProfileHeaderCollectionViewCell.self, forCellWithReuseIdentifier: ProfileHeaderCollectionViewCell.reuseIdentifier)
        collectionView.register(ProfileLinksCollectionViewCell.self, forCellWithReuseIdentifier: ProfileLinksCollectionViewCell.reuseIdentifier)

        view.addSubview(collectionView)
        collectionView.constrain(to: view)
    }

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("FeedCollectionViewController/viewWillAppear")
        super.viewWillAppear(animated)

        isVisible = true
        checkForOnscreenCells()
        scheduleNewPostsIndicatorRemoval()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        updateNoConnectionBanner(animated: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        DDLogInfo("FeedCollectionViewController/viewWillDisappear")
        super.viewWillDisappear(animated)

        stopAllVideoPlayback()

        isVisible = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        if let postID = feedPostIdToScrollTo, scrollTo(postId: postID) {
            feedPostIdToScrollTo = nil
        }

        if shouldScrollToOwnMoment, let id = MainAppContext.shared.feedData.validMoment.value?.id, scrollTo(postId: id) {
            shouldScrollToOwnMoment = false
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView == collectionView else { return }
        if isNearTop(100) {
            removeNewPostsIndicator()
        }

        checkForOnscreenCells()
    }
    
    /**
     Scrolls to a specific post.
     
     - Returns: `true` if the post associated with `id` exists in the data source.
     */
    @discardableResult
    func scrollTo(postId: FeedPostID, animated: Bool = false) -> Bool {
        guard let post = feedDataSource.posts.first(where: { $0.id == postId }) else {
            return false
        }

        var isMomentStackItem = false
        let indexPath: IndexPath?
        if post.isMoment, post.userId != MainAppContext.shared.userData.userId {
            isMomentStackItem = true
            indexPath = collectionViewDataSource?.indexPath(for: .momentStack(feedDataSource.momentItems))
        } else {
            indexPath = collectionViewDataSource?.indexPath(for: post.isMoment ? .moment(post) : .post(post))
        }

        guard let indexPath = indexPath else {
            return false
        }

        collectionView.scrollToItem(at: indexPath, at: .top, animated: animated)
        // attempt a more accurate scroll
        if !animated {
            collectionView.layoutIfNeeded()
            collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
        }

        if isMomentStackItem, let stackCell = collectionView.cellForItem(at: indexPath) as? StackedMomentCollectionViewCell {
            stackCell.stackedView.scroll(to: postId)
        }

        return true
    }

    // MARK: FeedCollectionViewController Customization

    public func shouldOpenFeed(for userId: UserID) -> Bool {
        return true
    }

    public func showGroupName() -> Bool {
        return true
    }
    
    // MARK: - FeedDataSourceDelegate methods
    
    func itemsDidChange(_ items: [FeedDisplayItem]) {
        update(with: items)
    }
    
    func itemDidChange(_ item: FeedDisplayItem, change type: FeedDataSource.FeedDataSourceChangeType) {
        
    }
    
    func modifyItems(_ items: [FeedDisplayItem]) -> [FeedDisplayItem] {
        return items
    }

    public func willUpdate(with items: [FeedDisplayItem]) {
        // Subclasses can implement
    }

    public func didUpdateItems() {
        // Update footers (currently the only part of cell that may change after an update)
        refreshFooters()
    }

    // MARK: Update

    private var loadedPostIDs = Set<FeedPostID>()

    // This works around an NSDiffableDataSource issue.
    // Cells for deleted posts need to be reloaded (but only when they're first deleted)
    private var deletedPostIDs = Set<FeedPostID>()

    private var waitingPostIds = Set<FeedPostID>()
    
    private func update(with items: [FeedDisplayItem], animated: Bool = true) {
        willUpdate(with: items)

        let updatedPostIDs = Set(items.compactMap { $0.post?.id })

        let newPostIDs = updatedPostIDs.subtracting(loadedPostIDs)
        let newWaitingPosts = items.filter {
            guard let post = $0.post else { return false }
            return post.isWaiting
        }
        waitingPostIds.formUnion(newWaitingPosts.compactMap { $0.post?.id })

        if !isNearTop(100) && !newPostIDs.isEmpty {
            let userOwnItems = items.filter { $0.post?.userId == MainAppContext.shared.userData.userId }
            let userOwnItemsIDs = Set(userOwnItems.compactMap { $0.post?.id })
            let newPostIDsWithoutUserOwnItems = newPostIDs.subtracting(userOwnItemsIDs)

            if !newPostIDsWithoutUserOwnItems.isEmpty {
                showNewPostsIndicator()
                feedLayout.maintainVisualPosition = true
            }
        }

        let newlyDeletedPosts = items.filter {
            guard let post = $0.post else { return false }
            return post.isPostRetracted && !deletedPostIDs.contains(post.id)
        }

        let newlyDecryptedPosts = items.filter {
            guard let post = $0.post else { return false }
            return !post.isWaiting && waitingPostIds.contains(post.id)
        }

        var snapshot = NSDiffableDataSourceSnapshot<FeedDisplaySection, FeedDisplayItem>()
        snapshot.appendSections([.posts])
        snapshot.appendItems(items)

        // TODO: See if we can improve this animation
        // Ensure no duplicates, which will crash the app
        var itemsToReload: [FeedDisplayItem] = newlyDeletedPosts
        newlyDecryptedPosts.forEach {
            if !itemsToReload.contains($0) {
                itemsToReload.append($0)
            }
        }
        snapshot.reloadItems(itemsToReload)
        deletedPostIDs.formUnion(newlyDeletedPosts.compactMap { $0.post?.id })
        waitingPostIds = waitingPostIds.subtracting(newlyDecryptedPosts.compactMap { $0.post?.id })

        collectionViewDataSource?.apply(snapshot, animatingDifferences: animated) { [weak self] in
            guard let self = self else { return }

            self.loadedPostIDs = updatedPostIDs
            self.feedLayout.maintainVisualPosition = false
            self.didUpdateItems()

            if self.feedPostIdToScrollTo != nil {
                self.view.setNeedsLayout()
            }
        }
    }
    
    func presentAppropriateMomentViewController(for moment: FeedPost, using momentView: MomentView) {
        let ownValidMoment = MainAppContext.shared.feedData.fetchLatestMoment(using: MainAppContext.shared.feedData.viewContext)

        switch (ownValidMoment, moment.status) {
        case (.some(let unlocker), _) where unlocker.status == .sent:
            presentMomentViewController(moment: moment, unlockingMoment: nil, momentView: momentView)

        case (.some(let unlocker), _):
            // user's moment hasn't been confirmed as `.sent` yet; open in full-screen with the unlocking post
            presentMomentViewController(moment: moment, unlockingMoment: unlocker, momentView: momentView)

        default:
            presentNewMomentViewController(context: .unlock(moment))
        }
    }

    private func presentMomentViewController(moment: FeedPost, unlockingMoment: FeedPost?, momentView: MomentView) {
        let vc = MomentViewController(post: moment, unlockingPost: unlockingMoment)
        vc.transitionStartView = momentView
        vc.delegate = self

        present(vc, animated: true)
    }

    @objc
    func createNewMoment() {
        presentNewMomentViewController(context: .normal)
    }

    func presentNewMomentViewController(context: MomentContext) {
        let vc = NewMomentViewController(context: context)
        vc.delegate = self
        present(vc, animated: true)
    }

    func presentNewMomentViewController(notificationMetadata: NotificationMetadata) {
        guard case .dailyMoment = notificationMetadata.contentType else {
            return
        }

        let vc = NewMomentViewController(notificationMetadata: notificationMetadata)
        vc.delegate = self
        present(vc, animated: true)
    }

    // MARK: Post Actions

    func showCommentsView(for postId: FeedPostID, highlighting commentId: FeedPostCommentID? = nil) {
        DDLogDebug("FeedCollectionViewController/showCommentsView/post: \(postId), comment: \(commentId ?? "")")

        let commentsViewController = FlatCommentsViewController(feedPostId: postId)
        commentsViewController.initiallyHighlightedCommentID = commentId
        navigationController?.pushViewController(commentsViewController, animated: true)

        if !firstActionHappened {
            delegate?.feedCollectionViewController(self, userActioned: true)
            firstActionHappened = true
        }
    }

    private func showMessageView(for userID: UserID, with postID: FeedPostID) {
        let vc = ChatViewControllerNew(for: userID, with: postID, at: Int32(postDisplayData[postID]?.currentMediaIndex ?? 0))
        self.navigationController?.pushViewController(vc, animated: true)

        if !firstActionHappened {
            delegate?.feedCollectionViewController(self, userActioned: true)
            firstActionHappened = true
        }
    }

    func showSeenByView(for post: FeedPost) {
        if post.userID == MainAppContext.shared.userData.userId {
            let viewController = PostDashboardViewController(feedPost: post)
            viewController.delegate = self
            present(UINavigationController(rootViewController: viewController), animated: true)
        } else {
            let viewController = ReactionListViewController(feedPost: post)
            viewController.delegate = self
            present(UINavigationController(rootViewController: viewController), animated: true)
        }
    }

    private func showUserFeed(for userID: UserID) {
        guard shouldOpenFeed(for: userID) else { return }
        let userViewController = UserFeedViewController(userId: userID)
        navigationController?.pushViewController(userViewController, animated: true)
    }

    private func showGroupFeed(for groupID: GroupID) {
        guard let group = MainAppContext.shared.chatData.chatGroup(groupId: groupID, in: MainAppContext.shared.chatData.viewContext) else { return }
        let vc = GroupFeedViewController(group: group)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func showInviteScreen(opensInSearch: Bool = false) {
        guard ContactStore.contactsAccessAuthorized else {
            let inviteVC = InvitePermissionDeniedViewController()
            present(UINavigationController(rootViewController: inviteVC), animated: true)
            return
        }
        InviteManager.shared.requestInvitesIfNecessary()
        let inviteVC = InviteViewController(manager: InviteManager.shared, opensInSearch: opensInSearch, dismissAction: { [weak self] in self?.dismiss(animated: true, completion: nil) })
        let navController = UINavigationController(rootViewController: inviteVC)
        present(navController, animated: true)
    }

    private func shareGroupInviteLink(_ link: String) {
        if let urlStr = NSURL(string: link) {
            let shareText = "\(Localizations.groupInviteShareLinkMessage) \(urlStr)"
            let objectsToShare = [shareText]
            let activityVC = UIActivityViewController(activityItems: objectsToShare, applicationActivities: nil)

            present(activityVC, animated: true, completion: nil)
        }
    }

    private func cancelSending(postId: FeedPostID) {
        MainAppContext.shared.feedData.cancelMediaUpload(postId: postId)
    }

    private func retrySending(postId: FeedPostID) {
        MainAppContext.shared.feedData.retryPosting(postId: postId)
    }

    private func deleteUnsentPost(postID: FeedPostID) {
        MainAppContext.shared.feedData.deleteUnsentPost(postID: postID)
    }

    // MARK: No Connection Banner

    private let noConnectionBanner = ConnectionBanner()

    private func setupNoConnectionBanner() {
        noConnectionBanner.translatesAutoresizingMaskIntoConstraints = false
        noConnectionBanner.isHidden = true
        view.addSubview(noConnectionBanner)
        noConnectionBanner.constrainMargin(anchor: .leading, to: view, constant: -4)
        noConnectionBanner.constrainMargin(anchor: .bottom, to: view, constant: -12)

        // TODO: Avoid hardcoding this size
        let spaceForFloatingMenu: CGFloat = 80
        noConnectionBanner.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -spaceForFloatingMenu).isActive = true
    }

    /// Hides banner immediately if connected, otherwise waits for timeout to decide whether to show banner
    private func updateNoConnectionBanner(animated: Bool, timeout: TimeInterval = 8) {
        if MainAppContext.shared.service.isConnected {
            hideNoConnectionBanner(animated: animated)
        } else if UIApplication.shared.applicationState == .active {
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                if MainAppContext.shared.service.isConnected {
                    self.hideNoConnectionBanner(animated: animated)
                } else if UIApplication.shared.applicationState == .active {
                    self.showNoConnectionBanner(animated: animated)
                }
            }
        }
    }

    private func showNoConnectionBanner(animated: Bool) {
        guard noConnectionBanner.isHidden else { return }
        noConnectionBanner.isHidden = false
        noConnectionBanner.alpha = 0
        noConnectionBanner.transform = .init(translationX: 0, y: self.noConnectionBanner.frame.height)
        UIView.animate(withDuration: animated ? 0.3: 0) {
            self.noConnectionBanner.superview?.bringSubviewToFront(self.noConnectionBanner)
            self.noConnectionBanner.transform = .identity
            self.noConnectionBanner.alpha = 1
        }
    }

    private func hideNoConnectionBanner(animated: Bool) {
        guard !noConnectionBanner.isHidden else { return }
        UIView.animate(
            withDuration: animated ? 0.3: 0,
            animations: {
                self.noConnectionBanner.transform = .init(translationX: 0, y: self.noConnectionBanner.frame.height)
                self.noConnectionBanner.alpha = 0
            },
            completion: { _ in self.noConnectionBanner.isHidden = true })
    }

    // MARK: New Posts Indicator

    private let newPostsIndicator = NewPostsIndicator()
    /// Allows us to delay and cancel the removal of the indicator.
    private var removeNewPostsIndicatorItem: DispatchWorkItem?

    func showNewPostsIndicator() {
        guard newPostsIndicator.superview !== view else {
            return
        }
        
        newPostsIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(newPostsIndicator)
        NSLayoutConstraint.activate([
            newPostsIndicator.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            newPostsIndicator.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            newPostsIndicator.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(newPostsIndicatorTapped))
        newPostsIndicator.isUserInteractionEnabled = true
        newPostsIndicator.addGestureRecognizer(tapGesture)
        
        newPostsIndicator.alpha = 0
        UIView.animate(withDuration: 0.2) { () -> Void in
            self.newPostsIndicator.alpha = 1.0
        }
        
        scheduleNewPostsIndicatorRemoval()
    }

    /**
     Schedules the removal of the "New Posts" indicator for 5 seconds from the time of calling this method.
     */
    func scheduleNewPostsIndicatorRemoval() {
        guard
            isVisible,
            newPostsIndicator.superview === view,
            removeNewPostsIndicatorItem == nil
        else {
            return
        }
        
        let operation = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            self.removeNewPostsIndicatorItem = nil
            self.removeNewPostsIndicator()
        }
        
        removeNewPostsIndicatorItem = operation
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: operation)
    }
    
    /**
     Cancels the removal of the "New Posts" indicator. Does nothing if the removal is not already scheduled.
     */
    func cancelNewPostsIndicatorRemoval() {
        removeNewPostsIndicatorItem?.cancel()
        removeNewPostsIndicatorItem = nil
    }

    private func removeNewPostsIndicator(animated: Bool = true) {
        guard animated else {
            newPostsIndicator.removeFromSuperview()
            return
        }
        
        UIView.animate(withDuration: 0.2) {
            self.newPostsIndicator.alpha = 0
        } completion: { _ in
            self.newPostsIndicator.removeFromSuperview()
        }
    }

    @objc
    func newPostsIndicatorTapped() {
        removeNewPostsIndicator(animated: false)
        scrollToTop(animated: true)
    }

    // MARK: Misc

    private func stopAllVideoPlayback() {
        guard isViewLoaded else {
            // Turns out viewWillDisappear might be called even if view isn't loaded.
            return
        }
        for cell in collectionView.visibleCells {
            if let feedPostCell = cell as? FeedPostCollectionViewCell {
                feedPostCell.stopPlayback()
            }
        }
    }

    private func refreshTimestamps() {
        for indexPath in collectionView.indexPathsForVisibleItems {
            if let feedCell = collectionView.cellForItem(at: indexPath) as? FeedPostCollectionViewCell,
               let feedPost = feedDataSource.item(at: indexPath.item)?.post
            {
                feedCell.refreshTimestamp(using: feedPost)
            } else if let momentCell = collectionView.cellForItem(at: indexPath) as? MomentCollectionViewCell {
                momentCell.refreshTimestamp()
            }
        }
    }

    private func willShowCell(atIndexPath indexPath: IndexPath) {
        guard let feedPost = feedDataSource.item(at: indexPath.item)?.post else {
            // This is the stacked moments cell.
            switch collectionViewDataSource?.itemIdentifier(for: indexPath) {
            case .momentStack, .moment:
                MainAppContext.shared.feedData.downloadMediaInMoments()
            default:
                break
            }
            return
        }
        // Load downloaded images into memory.
        MainAppContext.shared.feedData.loadImages(postID: feedPost.id)

        // Initiate download for images that were not yet downloaded.
        MainAppContext.shared.feedData.downloadMedia(in: [feedPost])
    }

    private func didShowCell(atIndexPath indexPath: IndexPath) {
        guard
            let feedPost = feedDataSource.item(at: indexPath.item)?.post,
            let cell = self.collectionView.cellForItem(at: indexPath),
            isOnscreen(cell: cell)
        else {
            // This is the stacked moments cell.
            switch collectionViewDataSource?.itemIdentifier(for: indexPath) {
            case .momentStack, .moment:
                UNUserNotificationCenter.current().removeDeliveredMomentNotifications()
            default:
                break
            }
            return
        }

        if feedPost.isMoment {
            UNUserNotificationCenter.current().removeDeliveredMomentNotifications()
        }
        UNUserNotificationCenter.current().removeDeliveredPostNotifications(postId: feedPost.id)
        UNUserNotificationCenter.current().removeDeliveredGroupAddNotification(groupId: feedPost.groupID)
        if !feedPost.isMoment {
            AppContext.shared.coreFeedData.sendSeenReceiptIfNecessary(for: feedPost)
        }
    }
    
    private func isOnscreen(cell: UICollectionViewCell) -> Bool {
        var rectSize = collectionView.bounds.size
        var rectOrigin = collectionView.contentOffset

        rectSize.height -= 220 // rough estimate for top/bottom bars and cell paddings
        rectOrigin.y += 120 // rough estimate for top bar and cell padding
        let visibleOnscreenRect = CGRect(origin: rectOrigin, size: rectSize)
        let result = cell.frame.intersects(visibleOnscreenRect)
        return result
    }

    // checks for cells that's actually visible on the screen
    // using dispatch instead of timer for throttling as scrolling will keep pushing back timers
    private func checkForOnscreenCells() {
        guard isVisible && UIApplication.shared.applicationState == .active else { return }
        guard !isCheckForOnscreenCellsScheduled else { return }
        isCheckForOnscreenCellsScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            self.collectionView.indexPathsForVisibleItems.forEach { (indexPath) in
                self.didShowCell(atIndexPath: indexPath)
            }
            self.isCheckForOnscreenCellsScheduled = false
        }
    }

    func isNearTop(_ fromTop: CGFloat) -> Bool {
        guard let collectionView = collectionView else { return true }
        return collectionView.contentOffset.y < fromTop
    }
}

extension FeedCollectionViewController: UIViewControllerScrollsToTop {

    func scrollToTop(animated: Bool) {
        guard collectionView.numberOfItems(inSection: 0) > 0 else {
            return
        }
        
        let path = IndexPath(item: 0, section: 0)
        collectionView.scrollToItem(at: path, at: .top, animated: animated)
    }
}

extension FeedCollectionViewController {

    func makeCollectionViewDataSource() -> UICollectionViewDiffableDataSource<FeedDisplaySection, FeedDisplayItem> {
        return UICollectionViewDiffableDataSource<FeedDisplaySection, FeedDisplayItem>(collectionView: collectionView) { [weak self] collectionView, indexPath, item in
            switch item {
            case .event(let event):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FeedEventCollectionViewCell.reuseIdentifier, for: indexPath)
                (cell as? FeedEventCollectionViewCell)?.configure(with: event, isThemed: self?.isThemed ?? false, onTap: { [weak self] in
                    self?.feedDataSource.toggleExpansion(feedEvent: event)
                })
                return cell
            case .moment(let feedPost):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MomentCollectionViewCell.reuseIdentifier, for: indexPath)
                if let postCell = cell as? MomentCollectionViewCell {
                    self?.configure(cell: postCell, withSecretFeedPost: feedPost)
                }
                return cell
            case .momentStack(let stackItems):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: StackedMomentCollectionViewCell.reuseIdentifier, for: indexPath)
                if let stackCell = cell as? StackedMomentCollectionViewCell {
                    self?.configure(cell: stackCell, with: stackItems)
                }
                return cell
            case .post(let feedPost):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FeedPostCollectionViewCell.reuseIdentifier, for: indexPath)
                if let postCell = cell as? FeedPostCollectionViewCell {
                    self?.configure(cell: postCell, withActiveFeedPost: feedPost)
                }
                return cell
            case .welcome:
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FeedWelcomeCell.reuseIdentifier, for: indexPath)
                if let welcomeCell = cell as? FeedWelcomeCell {
                    if indexPath.row > 5 {
                        welcomeCell.configure(showCloseButton: true)
                    }
                    
                    welcomeCell.openNetwork = { [weak self] in
                        guard let self else {
                            return
                        }

                        let viewController = SegmentedFriendsViewController(initialState: .friends)
                        let navigationController = UINavigationController(rootViewController: viewController)
                        self.present(navigationController, animated: true)
                    }
                    
                    welcomeCell.closeWelcomePost = {
                        MainAppContext.shared.nux.stopShowingWelcomePost(id: MainAppContext.shared.userData.userId)
                        UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseOut, animations: {
                            welcomeCell.alpha = 0.0
                        }, completion: { _ in
                            welcomeCell.isHidden = true
                        })
                    }
                }
                return cell
            case .groupWelcome(let groupID):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: GroupFeedWelcomeCell.reuseIdentifier, for: indexPath)
                if let groupFeedWelcomeCell = cell as? GroupFeedWelcomeCell {
                    
                    let showCloseButton = indexPath.row > 5
                    groupFeedWelcomeCell.configure(groupID: groupID, showCloseButton: showCloseButton)
                    
                    groupFeedWelcomeCell.openShareLink = { [weak self] link in
                        guard let self = self else { return }
                        self.shareGroupInviteLink(link)
                    }
                    
                    groupFeedWelcomeCell.closeWelcomePost = {
                        MainAppContext.shared.nux.stopShowingWelcomePost(id: groupID)
                        UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseOut, animations: {
                            groupFeedWelcomeCell.alpha = 0.0
                        }, completion: { _ in
                            groupFeedWelcomeCell.isHidden = true
                        })
                    }
                }
                return cell
            case .inviteCarousel:
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FeedInviteCarouselCell.reuseIdentifier, for: indexPath)
                if let self = self, let cell = cell as? FeedInviteCarouselCell {
                    cell.configure(with: self.inviteContactsManager.randomSelection, invitedContacts: self.invitedContacts)
                    cell.openInviteViewController = { [weak self] in
                        self?.showInviteScreen(opensInSearch: true)
                    }
                    cell.inviteContact = { [weak self] contact in
                        self?.showInviteContactActionSheet(for: contact)
                    }
                    cell.hideContact = { contact in
                        AppContext.shared.contactStore.hideContactFromSuggestedInvites(identifier: contact.identifier)
                    }
                }
                return cell
            case .suggestionsCarousel:
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FeedSuggestionsCarouselCell.reuseIdentifier, for: indexPath)
                
                if let self, let cell = cell as? FeedSuggestionsCarouselCell {
                    cell.configure(with: self.suggestionsManager.suggestions, animateChanges: false)
                    cell.onAdd = { [weak self] suggestion in
                        self?.suggestionsManager.add(suggestion)
                    }
                    cell.onCancel = { [weak self] suggestion in
                        self?.suggestionsManager.cancelRequest(for: suggestion)
                    }
                    cell.onHide = { [weak self] suggestion in
                        self?.suggestionsManager.hide(suggestion)
                    }
                    cell.onOpen = { [weak self] suggestion in
                        guard let self else {
                            return
                        }
                        let viewController = UserFeedViewController(profile: suggestion)
                        let navigationController = UINavigationController(rootViewController: viewController)
                        self.present(navigationController, animated: true)
                    }
                }

                return cell
            case .shareCarousel(let feedPostID):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FeedShareCarouselCell.reuseIdentifier, for: indexPath)
                if let cell = cell as? FeedShareCarouselCell {
                    cell.shareAction = { [weak self] shareProvider in
                        guard let self = self else {
                            return
                        }
                        self.share(postID: feedPostID, mediaIndex: self.postDisplayData[feedPostID]?.currentMediaIndex, with: shareProvider)
                    }
                }
                return cell
            case .ownProfile(let info):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: OwnProfileHeaderCollectionViewCell.reuseIdentifier, for: indexPath)
                if let self, let cell = cell as? OwnProfileHeaderCollectionViewCell {
                    cell.profileHeader.configure(with: info, mutualFriends: [], mutualGroups: [])
                    cell.profileHeader.willMove(toParent: self)
                    self.addChild(cell.profileHeader)
                    cell.profileHeader.didMove(toParent: self)
                }
                return cell
            case .profile(let info, let friends, let groups):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ProfileHeaderCollectionViewCell.reuseIdentifier, for: indexPath)
                if let self, let cell = cell as? ProfileHeaderCollectionViewCell {
                    cell.profileHeader.configure(with: info, mutualFriends: friends, mutualGroups: groups)
                    cell.profileHeader.willMove(toParent: self)
                    self.addChild(cell.profileHeader)
                    cell.profileHeader.didMove(toParent: self)
                }
                return cell
            case .profileLinks(let name, let links):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ProfileLinksCollectionViewCell.reuseIdentifier, for: indexPath)
                if let cell = cell as? ProfileLinksCollectionViewCell {
                    cell.configure(with: name, links: links)
                }
                return cell
            }
        }
    }

    private var cellContentWidth: CGFloat {
        collectionView.frame.size.width - collectionView.layoutMargins.left - collectionView.layoutMargins.right
    }

    private var gutterWidth: CGFloat {
        (1 - FeedPostCollectionViewCell.LayoutConstants.backgroundPanelHMarginRatio) * collectionView.layoutMargins.left
    }

    func refreshFooters() {
        for indexPath in collectionView.indexPathsForVisibleItems {
            if let feedCell = collectionView.cellForItem(at: indexPath) as? FeedPostCollectionViewCell,
               let feedPost = feedDataSource.item(at: indexPath.item)?.post
            {
                feedCell.refreshFooter(using: feedPost, contentWidth: cellContentWidth)
            } else if let momentCell = collectionView.cellForItem(at: indexPath) as? MomentCollectionViewCell {
                momentCell.refreshFooter()
            }
        }
    }
    
    func configure(cell: MomentCollectionViewCell, withSecretFeedPost feedPost: FeedPost) {
        cell.configure(with: feedPost, contentWidth: cellContentWidth)

        cell.showUserAction = { [weak self, feedPost] in
            self?.showUserFeed(for: feedPost.userId)
        }

        cell.moreMenuContent = { [weak self] in
            self?.moreMenu(for: feedPost) ?? []
        }

        cell.showSeenByAction = { [weak self, feedPost] in
            self?.showSeenByView(for: feedPost)
        }

        cell.openAction = { [weak self, feedPost] in
            self?.presentAppropriateMomentViewController(for: feedPost, using: cell.momentView)
        }

        cell.uploadProgressControl.onRetry = { [weak self] in
            self?.retrySending(postId: feedPost.id)
        }
    }

    func configure(cell: StackedMomentCollectionViewCell, with items: [MomentStackItem]) {
        cell.configure(with: items)

        cell.stackedView.actionCallback = { [weak self] momentView, action in
            switch action {
            case .open(moment: let moment):
                self?.presentMomentViewController(moment: moment, unlockingMoment: nil, momentView: momentView)
            case .camera:
                self?.createNewMoment()
            case .view(profile: let userID):
                self?.showUserFeed(for: userID)
            case .seenBy(moment: let moment):
                self?.showSeenByView(for: moment)
            }
        }
    }

    func configure(cell: FeedPostCollectionViewCell, withActiveFeedPost feedPost: FeedPost) {
        let postId = feedPost.id

        cell.configure(
            with: feedPost,
            contentWidth: cellContentWidth,
            gutterWidth: gutterWidth,
            showGroupName: showGroupName(),
            displayData: postDisplayData[postId])

        cell.commentAction = { [weak self] in
            guard let self = self else { return }
            self.showCommentsView(for: postId)
        }
        cell.messageAction = { [weak self] in
            guard let self = self else { return }
            self.showMessageView(for: feedPost.userId, with: postId)
        }
        cell.showSeenByAction = { [weak self] in
            guard let self = self else { return }
            self.showSeenByView(for: feedPost)
        }
        cell.showUserAction = { [weak self] userID in
            guard let self = self else { return }
            self.showUserFeed(for: userID)
        }
        cell.showGroupFeedAction = { [weak self] groupID in
            guard let self = self else { return }
            self.showGroupFeed(for: groupID)
        }
        cell.moreMenuContent = { [weak self] in
            self?.moreMenu(for: feedPost) ?? []
        }
        cell.showPrivacyAction = { [weak self] in
            guard let self = self else { return }
            let description: String
            if feedPost.userId == MainAppContext.shared.userData.userId {
                description = Localizations.favoritesDescriptionOwn
            } else {
                let format = Localizations.favoritesDescriptionNotOwn
                let name = feedPost.user.displayName
                description = String(format: format, name)
            }
           let alert = UIAlertController(title: Localizations.favoritesTitle, message: description, preferredStyle: .alert)
            alert.view.tintColor = .primaryBlue
            if feedPost.userId != MainAppContext.shared.userData.userId {
                alert.addAction(.init(title: Localizations.titleEditFavorites, style: .default, handler: { [weak self] _ in
                    guard let self = self else { return }
                    let privacyVC = ContactSelectionViewController.forPrivacyList(MainAppContext.shared.privacySettings.whitelist, in: MainAppContext.shared.privacySettings, setActiveType: false, doneAction: { [weak self] in
                        self?.dismiss(animated: false)
                    }, dismissAction: nil)
                    self.present(UINavigationController(rootViewController: privacyVC), animated: true)
                }))
            }
           alert.addAction(.init(title: Localizations.buttonOK, style: .default, handler: nil))
           self.present(alert, animated: true, completion: nil)
        }
        cell.cancelSendingAction = { [weak self] in
            guard let self = self else { return }
            self.cancelSending(postId: postId)
        }
        cell.retrySendingAction = { [weak self] in
            guard let self = self else { return }
            self.retrySending(postId: postId)
        }
        cell.contextAction = { [weak self] action, userID in
            Task { try await self?.handle(action, for: userID) }
        }
        cell.shareAction = { [weak self] in
            guard let self = self else {
                return
            }
            self.presentShareMenu(for: feedPost, mediaIndex: self.postDisplayData[feedPost.id]?.currentMediaIndex)
        }
        cell.reactAction = { reaction in
            if let reaction = reaction, !reaction.isEmpty {
                Analytics.log(event: .sendPostReaction)
            }
            MainAppContext.shared.feedData.updatePostReaction(reaction, for: postId)
        }
        cell.deleteAction = {
            MainAppContext.shared.feedData.deleteUnsentPost(postID: postId)
        }
        cell.delegate = self
    }

    @HAMenuContentBuilder
    private func moreMenu(for feedPost: FeedPost) -> HAMenu.Content {
        HAMenu {
            if ServerProperties.enableMomentExternalShare, feedPost.isMoment, feedPost.userID == MainAppContext.shared.userData.userId {
                HAMenuButton(title: Localizations.buttonShare, image: UIImage(systemName: "square.and.arrow.up")) { [weak self] in
                    guard let self = self else {
                        return
                    }
                    self.presentShareMenu(for: feedPost, mediaIndex: self.postDisplayData[feedPost.id]?.currentMediaIndex)
                }
            }

            if feedPost.hasSaveablePostMedia, feedPost.canSaveMedia {
                let title = (feedPost.media?.count ?? 0) > 1 ? Localizations.saveAllButton : Localizations.saveAllButtonSingular
                HAMenuButton(title: title, image: UIImage(systemName: "photo.on.rectangle.angled")) { [weak self] in
                    self?.savePostMedia(feedPost: feedPost)
                }
            }

            if feedPost.canDeletePost {
                let title = feedPost.isMoment ? Localizations.deleteMomentButtonTitle : Localizations.deletePostButtonTitle
                HAMenuButton(title: title, image: UIImage(systemName: "trash")) { [weak self] in
                    self?.handleDeletePostTapped(post: feedPost)
                }.destructive()
            }
        }
        .displayInline()

        if feedPost.userID != MainAppContext.shared.userData.userId {
            HAMenu {
                HAMenuButton(title: Localizations.reportPost, image: UIImage(systemName: "flag")) { [weak self] in
                    self?.handleReportPost(feedPost)
                }
                .destructive()
            }
            .displayInline()
        }
    }

    private func savePostMedia(feedPost: FeedPost) {
        Task {
            await self.saveMedia(source: .post(feedPost.id)) {
                guard let expectedMedia = feedPost.media else { return [] } // Get the media data to determine how many should be downloaded
                let media = self.getMedia(feedPost: feedPost) // Get the media from memory
                guard expectedMedia.count == media.count else {
                    DDLogError("FeedCollectionViewController/saveAllButton/error: Downloaded media not same size as expected")
                    return []
                }
                return media
            }
        }
    }
    
    private func getMedia(feedPost: FeedPost) -> [(type: CommonMediaType, url: URL)] {
        let feedMedia = MainAppContext.shared.feedData.media(for: feedPost)

        var mediaItems: [(type: CommonMediaType, url: URL)] = []
        
        for media in feedMedia {
            if media.isMediaAvailable, let url = media.fileURL {
                mediaItems.append((type: media.type, url: url))
            }
        }
        
        return mediaItems
    }
    
    private func handleDeletePostTapped(post: FeedPost) {
        let title = post.isMoment ? Localizations.deleteMomentButtonTitle : Localizations.deletePostButtonTitle
        let message = post.isMoment ? Localizations.deleteMomentConfirmationPrompt : Localizations.deletePostConfirmationPrompt

        let actionSheet = UIAlertController(title: nil, message: message, preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: title, style: .destructive) { _ in
            self.reallyRetractPost(postId: post.id)
        })
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        actionSheet.view.tintColor = .systemBlue
        self.present(actionSheet, animated: true)
    }

    private func reallyRetractPost(postId: FeedPostID) {
        guard let feedPost = MainAppContext.shared.feedData.feedPost(with: postId, in: MainAppContext.shared.feedData.viewContext) else {
            dismiss(animated: true)
            return
        }
        
        MainAppContext.shared.feedData.retract(post: feedPost) { [weak self] result in
            switch result {
            case .failure(_):
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: Localizations.deletePostError, message: nil, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: nil))
                    self?.present(alert, animated: true, completion: nil)
                }
            default:
                break
            }
        }
        dismiss(animated: true)
    }

    private func handleReportPost(_ post: FeedPost) {
        let name = post.user.displayName
        let title = Localizations.reportPost
        let message = String(format: Localizations.reportPostMessage, name)
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)

        let report: (Bool) -> Void = { removePost in
            MainAppContext.shared.feedData.report(post: post, delete: removePost) {
                switch $0 {
                case .success(_):
                    Toast(type: .icon(.init(systemName: "checkmark")), text: Localizations.reportPostSuccess).show()
                case .failure(_):
                    Toast(type: .icon(.init(systemName: "xmark")), text: Localizations.reportPostFailure).show()
                }
            }
        }

        alert.addAction(.init(title: Localizations.reportAndRemovePost, style: .destructive) { _ in
            report(true)
        })

        alert.addAction(.init(title: Localizations.reportTitle, style: .destructive) { _ in
            report(false)
        })

        alert.addAction(.init(title: Localizations.buttonCancel, style: .cancel) { _ in })

        present(alert, animated: true)
    }
}

extension FeedCollectionViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        willShowCell(atIndexPath: indexPath)
        checkForOnscreenCells()
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if case .suggestionsCarousel = collectionViewDataSource?.itemIdentifier(for: indexPath) {
            suggestionsManager.clearAddedSuggestions()
        }

        (cell as? FeedPostCollectionViewCell)?.stopPlayback()
    }
}

extension FeedCollectionViewController: FeedPostCollectionViewCellDelegate {

    func feedPostCollectionViewCell(_ cell: FeedPostCollectionViewCell, didRequestOpen url: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            UIApplication.shared.open(url, options: [:])
        }
    }

    func feedPostCollectionViewCell(_ cell: FeedPostCollectionViewCell, didChangeMediaIndex index: Int) {
        guard let postID = cell.postId else { return }
        var displayData = postDisplayData[postID] ?? FeedPostDisplayData()
        displayData.currentMediaIndex = index
        postDisplayData[postID] = displayData
    }

    func feedPostCollectionViewCellDidRequestTextExpansion(_ cell: FeedPostCollectionViewCell, for textView: ExpandableTextView) {
        guard let indexPath = collectionView.indexPath(for: cell),
              let postID = cell.postId else
        {
            return
        }

        let numberOfLines = textView.numberOfLines + 10

        var displayData = postDisplayData[postID] ?? FeedPostDisplayData()
        displayData.textNumberOfLines = numberOfLines
        postDisplayData[postID] = displayData

        textView.numberOfLines = numberOfLines

        if let collectionViewDataSource = collectionViewDataSource, let displayItem = feedDataSource.item(at: indexPath.item) {
            var snapshot = collectionViewDataSource.snapshot()
            snapshot.reconfigureItems([displayItem])
            collectionViewDataSource.apply(snapshot)
        } else {
            DDLogWarn("FeedPostViewController/feedPostCollectionViewCellDidRequestTextExpansion/unable to resize via dataSource")
            let context = UICollectionViewLayoutInvalidationContext()
            context.invalidateItems(at: [indexPath])
            self.collectionView.collectionViewLayout.invalidateLayout(with: context)
        }
    }
}

extension FeedCollectionViewController: ReactionListViewControllerDelegate {
    func removeReaction(reaction: CommonReaction) {
        MainAppContext.shared.feedData.retract(reaction: reaction)
    }
}

// MARK: - NewMomentViewControllerDelegate methods

extension FeedCollectionViewController: NewMomentViewControllerDelegate {

    func momentView(_ momentView: MomentView, didSelect action: MomentView.Action) {
        switch action {
        case .view(profile: let id):
            dismiss(animated: true) { [weak self] in
                self?.showUserFeed(for: id)
            }
        default:
            break
        }
    }

    func newMomentViewControllerDidPost(_ viewController: NewMomentViewController) {
        shouldScrollToOwnMoment = true
    }
}

extension FeedCollectionViewController: PostDashboardViewControllerDelegate {

    func postDashboardViewController(didRequestPerformAction action: PostDashboardViewController.UserAction) {
        let actionToPerformOnDashboardDismiss: () -> ()
        switch action {
        case .profile(let userId):
            actionToPerformOnDashboardDismiss = {
                self.showUserFeed(for: userId)
            }

        case .message(let userId, let postId):
            actionToPerformOnDashboardDismiss = {
                let vc = ChatViewControllerNew(for: userId, with: postId)
                self.navigationController?.pushViewController(vc, animated: true)
            }

        case .blacklist(let userId):
            actionToPerformOnDashboardDismiss = {
                MainAppContext.shared.privacySettings.hidePostsFrom(userId: userId)
            }
        }

        dismiss(animated: true, completion: actionToPerformOnDashboardDismiss)
    }
}


extension FeedCollectionViewController: InviteContactViewController {

    var inviteManager: InviteManager {
        return InviteManager.shared
    }

    func showLoadIndicator(_ isLoading: Bool) {
        // no-op
    }

    func didInviteContact(_ contact: InviteContact, with action: InviteActionType) {
        invitedContacts.insert(contact)
        suggestedContactsDidChange()
    }
}

// FeedInviteCarouselCell Callbacks

extension FeedCollectionViewController {

    private func suggestedContactsDidChange() {
        guard let collectionViewDataSource = collectionViewDataSource else {
            return
        }

        var snapshot = collectionViewDataSource.snapshot()
        var updateSnapshot = false
        if inviteContactsManager.randomSelection.isEmpty {
            if snapshot.itemIdentifiers.contains(.inviteCarousel) {
                snapshot.deleteItems([.inviteCarousel])
                updateSnapshot = true
            }
        } else {
            if let indexPath = collectionViewDataSource.indexPath(for: .inviteCarousel) {
                // If the cell is visible, update directly.
                if let cell = collectionView.cellForItem(at: indexPath) as? FeedInviteCarouselCell {
                    cell.configure(with: inviteContactsManager.randomSelection, invitedContacts: invitedContacts, animated: true)
                } else if snapshot.itemIdentifiers.contains(.inviteCarousel) {
                    snapshot.reconfigureItems([.inviteCarousel])
                    updateSnapshot = true
                }
            }
        }

        if updateSnapshot {
            collectionViewDataSource.apply(snapshot)
        }
    }
}

// MARK: - FeedSuggestionsCarouselCell callbacks

extension FeedCollectionViewController {

    private func friendSuggestionsDidChange(animateChanges: Bool) {
        guard let collectionViewDataSource else {
            return
        }

        var snapshot = collectionViewDataSource.snapshot()
        var updateSnapshot = false

        if suggestionsManager.suggestions.isEmpty {
            if snapshot.itemIdentifiers.contains(.suggestionsCarousel) {
                snapshot.deleteItems([.suggestionsCarousel])
                updateSnapshot = true
            }
        } else {
            if let indexPath = collectionViewDataSource.indexPath(for: .suggestionsCarousel) {
                if let cell = collectionView.cellForItem(at: indexPath) as? FeedSuggestionsCarouselCell {
                    cell.configure(with: suggestionsManager.suggestions, animateChanges: animateChanges)
                } else if snapshot.itemIdentifiers.contains(.suggestionsCarousel) {
                    snapshot.reconfigureItems([.suggestionsCarousel])
                    updateSnapshot = true
                }
            }
        }

        if updateSnapshot {
            collectionViewDataSource.apply(snapshot)
        }
    }
}

private class FeedLayout: UICollectionViewCompositionalLayout {

    var maintainVisualPosition: Bool = false
    var newItemsHeight: CGFloat = 0.0

    override func prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem]) {
        super.prepare(forCollectionViewUpdates: updateItems)
        guard maintainVisualPosition else { return }
        var totalHeight: CGFloat = 0.0
        updateItems.forEach { item in
            guard item.updateAction == .insert else { return }
            guard let index = item.indexPathAfterUpdate else { return }
            guard let attrs = layoutAttributesForItem(at: index) else { return }
            totalHeight += attrs.frame.height
        }

        newItemsHeight = totalHeight
    }

    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
        let targetContentOffset = super.targetContentOffset(forProposedContentOffset: proposedContentOffset)
        guard maintainVisualPosition else { return targetContentOffset }
        var offset = proposedContentOffset
        offset.y +=  newItemsHeight
        newItemsHeight = 0.0
        return offset
    }

    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint, withScrollingVelocity velocity: CGPoint) -> CGPoint {
        let targetContentOffset = super.targetContentOffset(forProposedContentOffset: proposedContentOffset, withScrollingVelocity: velocity)
        guard maintainVisualPosition else { return targetContentOffset }
        var offset = proposedContentOffset
        offset.y += newItemsHeight
        newItemsHeight = 0.0
        return offset
    }
}

extension Localizations {
    static var saveAllButton: String = {
        return NSLocalizedString("media.download.all", value: "Download All", comment: "Button that, when pressed, saves all the post's media to the user's camera roll")
    }()
    
    static var saveAllButtonSingular: String = {
        return NSLocalizedString("media.download.singular", value: "Download", comment: "Button that, when pressed, saves the post's media to the user's camera roll. Singular version for media.save.all")
    }()
    
    static var deletePostConfirmationPrompt: String = {
        NSLocalizedString("your.post.deletepost.confirmation", value: "Delete this post? This action cannot be undone.", comment: "Post deletion confirmation. Displayed as action sheet title.")
    }()

    static var deletePostButtonTitle: String = {
        NSLocalizedString("your.post.deletepost.button", value: "Delete Post", comment: "Title for the button that confirms intent to delete your own post.")
    }()

    static var deletePostError: String {
        NSLocalizedString("your.post.deletepost.error", value: "Error deleting post", comment: "Displayed when a post fails to delete")
    }

    static var deleteMomentButtonTitle: String {
        NSLocalizedString("your.moment.delete.title",
                   value: "Delete Moment",
                 comment: "Title for the button that confirms intent to delete your own moment.")
    }

    static var deleteMomentConfirmationPrompt: String {
        NSLocalizedString("your.moment.delete.confirmation",
                   value: "Delete this moment? This action cannot be undone.",
                 comment: "Moment deletion confirmation. Displays as action sheet title.")
    }

    static var reportPost: String {
        NSLocalizedString("report.post",
                   value: "Report Post",
                 comment: "Title of the button to report a post.")
    }

    static var reportPostMessage: String {
        NSLocalizedString("report.post.message",
                   value: "Are you sure you want to report this post by %@?",
                 comment: "Message confirming if the user wants to report someone's post.")
    }

    static var reportAndRemovePost: String {
        NSLocalizedString("report.post.and.remove",
                   value: "Report and Remove Post",
                 comment: "Title of the button that both reports a post and removes it.")
    }

    static var reportPostSuccess: String {
        NSLocalizedString("report.post.success",
                   value: "Reported Post",
                 comment: "Message that's displayed after successfully reporting a post.")
    }

    static var reportPostFailure: String {
        NSLocalizedString("report.post.failure",
                   value: "Failed to Report Post",
                 comment: "Message that's displayed when reporting a post failed.")
    }

    private static let postExpirationFormatter: DateFormatter = {
        let postExpirationFormatter = DateFormatter()
        postExpirationFormatter.dateStyle = .short
        postExpirationFormatter.timeStyle = .short
        return postExpirationFormatter
    }()

    static func postExpirationMismatchMessage(postExpiration: Date?,
                                              groupExpirationType: Core.Group.ExpirationType,
                                              groupExpirationTime: Int64) -> String {
        let postExpiryString = postExpiration.flatMap { postExpirationFormatter.string(from: $0) } ?? Localizations.chatGroupExpiryOptionNever
        let groupExpiryString = Group.formattedExpirationTime(type: groupExpirationType, time: groupExpirationTime)
        let format = NSLocalizedString("post.expiration.mismatch",
                                       value: "This post will expire on %1$@, while the group's content expiration is set to %2$@.",
                                       comment: "Body of alert indicating that a post's expiration does not match that set on a group")
        return String(format: format, postExpiryString, groupExpiryString)
    }

    static func deletedPostWithNumber(from number: Int) -> String {
        let format = NSLocalizedString("n.posts.deleted", value: "%@ posts deleted", comment: "Displayed in place of deleted feed posts.")
        return String(format: format, String(number))
    }
}

extension FeedEvent {
    var description: String? {
        switch self {
        case .groupEvent(let groupEvent):
            return groupEvent.text
        case .collapsedGroupEvents(let groupEvents):
            return groupEvents.first.flatMap { GroupEvent.collapsedText(for: $0.action, memberAction: $0.memberAction, count: groupEvents.count) }
        case .deletedPost(let feedPost):
            return Localizations.deletedPost(from: feedPost.userID)
        case .collapsedDeletedPosts(let feedPosts):
            return Localizations.deletedPostWithNumber(from: feedPosts.count)
        }
    }
}
