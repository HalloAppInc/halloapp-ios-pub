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

class FeedCollectionViewController: UIViewController, FeedDataSourceDelegate, UserMenuHandler {

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
        section.boundarySupplementaryItems = Self.collectionViewSupplementaryItems
        section.contentInsets = Self.collectionViewSectionInsets

        return FeedLayout(section: section)
    }()

    class var collectionViewSupplementaryItems: [NSCollectionLayoutBoundarySupplementaryItem] {
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

    var feedPostIdToScrollTo: FeedPostID?
    
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

        view.addSubview(collectionView)
        collectionView.constrain(to: view)

        setupNoConnectionBanner()

        cancellableSet.insert(MainAppContext.shared.feedData.willDestroyStore.sink { [weak self] in
            guard let self = self else { return }
            self.view.isUserInteractionEnabled = false
            self.feedDataSource.clear()
            self.collectionView.reloadData()
        })

        cancellableSet.insert(
            MainAppContext.shared.feedData.didReloadStore.sink { [weak self] in
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

        // feed view needs to know when unread count changes when user is not on view
        cancellableSet.insert(
            MainAppContext.shared.feedData.didGetUnreadFeedCount.sink { [weak self] (count) in
                guard let self = self else { return }
                guard count == 0 else { return }
                DispatchQueue.main.async {
                    self.removeNewPostsIndicator()
                }
        })

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

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("FeedCollectionViewController/viewWillAppear")
        super.viewWillAppear(animated)

        isVisible = true
        checkForOnscreenCells()
        removeNewPostsIndicatorAfterSeen()
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
        guard let index = feedDataSource.index(of: postId) else {
            return false
        }
        
        let path = IndexPath(item: index, section: 0)
        collectionView.scrollToItem(at: path, at: .top, animated: animated)
        
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
        DispatchQueue.main.async {
            self.update(with: items)
        }
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
        snapshot.reloadItems(newlyDeletedPosts + newlyDecryptedPosts)
        deletedPostIDs.formUnion(newlyDeletedPosts.compactMap { $0.post?.id })
        waitingPostIds = waitingPostIds.subtracting(newlyDecryptedPosts.compactMap { $0.post?.id })

        collectionViewDataSource?.apply(snapshot, animatingDifferences: animated) { [weak self] in
            guard let self = self else { return }
            
            self.loadedPostIDs = updatedPostIDs
            self.feedLayout.maintainVisualPosition = false
            self.didUpdateItems()
            
            if let id = self.feedPostIdToScrollTo {
                DDLogInfo("FeedCollectionViewController/scroll-to/postId: \(id)")
                for item in items {
                    if id == item.post?.id {
                        self.feedPostIdToScrollTo = nil
                        let result = self.scrollTo(postId: id)
                        DDLogInfo("FeedCollectionViewController/scroll-to/postId: \(id)/result: \(result)")
                        break
                    }
                }
            }
        }
    }

    // MARK: Post Actions

    func showCommentsView(for postId: FeedPostID, highlighting commentId: FeedPostCommentID? = nil) {
        DDLogDebug("FeedCollectionViewController/showCommentsView/post: \(postId), comment: \(commentId ?? "")")

        if ServerProperties.isFlatCommentsEnabled {
            let commentsViewController = FlatCommentsViewController(feedPostId: postId)
            commentsViewController.highlightedCommentId = commentId
            navigationController?.pushViewController(commentsViewController, animated: true)
        } else {
            let commentsViewController = CommentsViewController(feedPostId: postId)
            commentsViewController.highlightedCommentId = commentId
            navigationController?.pushViewController(commentsViewController, animated: true)
        }

        if !firstActionHappened {
            delegate?.feedCollectionViewController(self, userActioned: true)
            firstActionHappened = true
        }
    }

    private func showMessageView(for userID: UserID, with postID: FeedPostID) {
        navigationController?.pushViewController(ChatViewController(for: userID, with: postID, at: Int32(postDisplayData[postID]?.currentMediaIndex ?? 0)), animated: true)

        if !firstActionHappened {
            delegate?.feedCollectionViewController(self, userActioned: true)
            firstActionHappened = true
        }
    }

    private func showSeenByView(for postId: FeedPostID, isGroupPost: Bool) {
        let viewController = PostDashboardViewController(feedPostId: postId, isGroupPost: isGroupPost)
        viewController.delegate = self
        present(UINavigationController(rootViewController: viewController), animated: true)
    }

    private func showUserFeed(for userID: UserID) {
        guard shouldOpenFeed(for: userID) else { return }
        let userViewController = UserFeedViewController(userId: userID)
        navigationController?.pushViewController(userViewController, animated: true)
    }

    private func showGroupFeed(for groupID: GroupID) {
        guard MainAppContext.shared.chatData.chatGroup(groupId: groupID) != nil else { return }
        let vc = GroupFeedViewController(groupId: groupID)
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

    func showNewPostsIndicator() {
        guard !view.subviews.contains(newPostsIndicator) else { return }
        newPostsIndicator.translatesAutoresizingMaskIntoConstraints = false

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(newPostsIndicatorTapped))
        newPostsIndicator.isUserInteractionEnabled = true
        newPostsIndicator.addGestureRecognizer(tapGesture)

        view.addSubview(newPostsIndicator)
        newPostsIndicator.alpha = 0
        newPostsIndicator.constrain([.leading, .trailing, .top], to: view.safeAreaLayoutGuide)

        UIView.animate(withDuration: 0.35) { () -> Void in
            self.newPostsIndicator.alpha = 1.0
        }
        
        removeNewPostsIndicatorAfterSeen()
    }

    private func removeNewPostsIndicatorAfterSeen() {
        guard isVisible, view.subviews.contains(newPostsIndicator) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.removeNewPostsIndicator()
        }
    }

    private func removeNewPostsIndicator() {
        guard view.subviews.contains(newPostsIndicator) else { return }
        newPostsIndicator.removeFromSuperview()
    }

    @objc func newPostsIndicatorTapped() {
        removeNewPostsIndicator()
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
            }
        }
    }

    private func willShowCell(atIndexPath indexPath: IndexPath) {
        guard let feedPost = feedDataSource.item(at: indexPath.item)?.post else { return }
        // Load downloaded images into memory.
        MainAppContext.shared.feedData.loadImages(postID: feedPost.id)

        // Initiate download for images that were not yet downloaded.
        MainAppContext.shared.feedData.downloadMedia(in: [feedPost])
    }

    private func didShowCell(atIndexPath indexPath: IndexPath) {
        guard let feedPost = feedDataSource.item(at: indexPath.item)?.post else { return }
        guard let cell = self.collectionView.cellForItem(at: indexPath) else { return }
        guard self.isOnscreen(cell: cell) else { return }
        MainAppContext.shared.feedData.sendSeenReceiptIfNecessary(for: feedPost)
        UNUserNotificationCenter.current().removeDeliveredFeedNotifications(postId: feedPost.id)
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
                if let _ = event.containingItems {
                    (cell as? FeedEventCollectionViewCell)?.configure(with: event.description, type: .deletedPostsMerge, isThemed: event.isThemed, tapFunction: self?.tapFunction, thisEvent: item)
                } else {
                    (cell as? FeedEventCollectionViewCell)?.configure(with: event.description, type: .event, isThemed: event.isThemed, tapFunction: nil, thisEvent: item)
                }
                return cell
            case .post(let feedPost):
                guard !feedPost.isPostRetracted else {
                    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FeedEventCollectionViewCell.reuseIdentifier, for: indexPath)
                    (cell as? FeedEventCollectionViewCell)?.configure(with: Localizations.deletedPost(from: feedPost.userId), type: .deletedPost, tapFunction: nil, thisEvent: item)
                    return cell
                }
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FeedPostCollectionViewCell.reuseIdentifier, for: indexPath)
                if let postCell = cell as? FeedPostCollectionViewCell {
                    self?.configure(cell: postCell, withActiveFeedPost: feedPost)
                } else {
                    DDLogError("FeedCollectionViewController/error FeedPostCollectionViewCell reuse identifier not registered correctly")
                }
                return cell
            case .welcome:
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FeedWelcomeCell.reuseIdentifier, for: indexPath)
                if let welcomeCell = cell as? FeedWelcomeCell {
                    if indexPath.row > 5 {
                        welcomeCell.configure(showCloseButton: true)
                    }

                    welcomeCell.openInvite = { [weak self] in
                        guard let self = self else { return }
                        self.showInviteScreen()
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
                        AppContext.shared.contactStore.hideContactFromSuggestedInvites(normalizedPhoneNumber: contact.normalizedPhoneNumber)
                    }
                }
                return cell
            }
        }
    }
    
    func tapFunction(expandEvent: FeedDisplayItem) {
        feedDataSource.expand(expandItem: expandEvent)
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
            }
        }
    }

    func configure(cell: FeedPostCollectionViewCell, withActiveFeedPost feedPost: FeedPost) {
        let postId = feedPost.id
        let isGroupPost = feedPost.groupId != nil

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
            self.showSeenByView(for: postId, isGroupPost: isGroupPost)
        }
        cell.showUserAction = { [weak self] userID in
            guard let self = self else { return }
            self.showUserFeed(for: userID)
        }
        cell.showGroupFeedAction = { [weak self] groupID in
            guard let self = self else { return }
            self.showGroupFeed(for: groupID)
        }
        cell.showMoreAction = { [weak self] userID in
            self?.showMoreMenu(for: feedPost)
        }
        cell.showPrivacyAction = { [weak self] in
            guard let self = self else { return }
            let description: String
            if feedPost.userId == MainAppContext.shared.userData.userId {
                description = Localizations.favoritesDescriptionOwn
            } else {
                description = Localizations.favoritesDescriptionNotOwn
            }
           let alert = UIAlertController(title: Localizations.favoritesTitle, message: description, preferredStyle: .alert)
           alert.addAction(.init(title: Localizations.titlePrivacy, style: .default, handler: { [weak self] _ in
               guard let self = self else { return }
               let privacyVC = UIHostingController(rootView: FeedPrivacyView(privacySettings: MainAppContext.shared.privacySettings))
               self.navigationController?.pushViewController(privacyVC, animated: true)
           }))
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
        cell.deleteAction = { [weak self] in
            guard let self = self else { return }
            self.handleDeletePostTapped(postId: postId)
        }
        cell.contextAction = { [weak self] action in
            self?.handle(action: action)
        }
        
        cell.delegate = self
    }

    private func showMoreMenu(for feedPost: FeedPost) {
        let isOwnPost = feedPost.userId == MainAppContext.shared.userData.userId
        let isGroupPost = feedPost.groupId != nil
        let menu = FeedPostMenuViewController.Menu {
            // Disable external share if not enabled or this is a group post
            if isOwnPost && !isGroupPost && ServerProperties.externalSharingEnabled {
                FeedPostMenuViewController.Section(description: Localizations.externalShareDescription)
                FeedPostMenuViewController.Section {
                    FeedPostMenuViewController.Item(style: .standard,
                                                    icon: UIImage(systemName: "square.and.arrow.up"),
                                                    title: Localizations.externalShareButton) { [weak self] _ in
                        self?.generateExternalShareLink(postID: feedPost.id, success: { [weak self] url in
                            let shareText = "\(Localizations.externalShareText) \(url)"
                            let activityViewController = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
                            self?.present(activityViewController, animated: true)
                        })
                    }
                    FeedPostMenuViewController.Item(style: .standard,
                                                    icon: UIImage(systemName: "link"),
                                                    title: Localizations.externalShareCopyLink) { [weak self] _ in
                        self?.generateExternalShareLink(postID: feedPost.id, success: { url in
                            UIPasteboard.general.url = url
                            Toast.show(icon: UIImage(systemName: "checkmark"), text: Localizations.externalShareLinkCopied)
                        })
                    }
                }
            }

            if feedPost.hasSaveablePostMedia, feedPost.canSaveMedia {
                FeedPostMenuViewController.Section {
                    FeedPostMenuViewController.Item(style: .standard,
                                                    icon: UIImage(systemName: "photo.on.rectangle.angled"),
                                                    title: feedPost.media?.count ?? 0 > 1 ?
                                                        Localizations.saveAllButton :
                                                        Localizations.saveAllButtonSingular) { [weak self] _ in
                        self?.savePostMedia(feedPost: feedPost)
                    }
                }
            }

            if isOwnPost {
                FeedPostMenuViewController.Section {
                    FeedPostMenuViewController.Item(style: .destructive,
                                                    icon: UIImage(systemName: "trash"),
                                                    title: Localizations.deletePostButtonTitle) { [weak self] _ in
                        self?.handleDeletePostTapped(postId: feedPost.id)
                    }
                }
            }
        }

        present(FeedPostMenuViewController(menu: menu), animated: true)
    }

    private func savePostMedia(feedPost: FeedPost) {
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            // `.limited` was introduced in iOS 14, and only gives us partial access to the photo album. In this case we can still save to the camera roll
            if #available(iOS 14, *) {
                guard status == .authorized || status == .limited else {
                    DispatchQueue.main.async {
                        self?.handleMediaAuthorizationFailure()
                    }
                    return
                }
            } else {
                guard status == .authorized else {
                    DispatchQueue.main.async {
                        self?.handleMediaAuthorizationFailure()
                    }
                    return
                }
            }

            guard let expectedMedia = feedPost.media, let self = self else { return } // Get the media data to determine how many should be downloaded
            let media = self.getMedia(feedPost: feedPost) // Get the media from memory

            // Make sure the media in memory is the correct number or items
            guard expectedMedia.count == media.count else {
                DDLogError("FeedCollectionViewController/saveAllButton/error: Downloaded media not same size as expected")
                return
            }

            self.saveMedia(media: media)
        }
    }
    
    private func handleMediaAuthorizationFailure() {
        let alert = UIAlertController(title: Localizations.mediaPermissionsError, message: Localizations.mediaPermissionsErrorDescription, preferredStyle: .alert)
        
        DDLogInfo("FeedCollectionViewController/shareAllButtonPressed: User denied photos permissions")
        
        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: nil))
        
        present(alert, animated: true)
    }
    
    private func getMedia(feedPost: FeedPost) -> [(type: FeedMediaType, url: URL)] {
        let feedMedia = MainAppContext.shared.feedData.media(for: feedPost)

        var mediaItems: [(type: FeedMediaType, url: URL)] = []
        
        for media in feedMedia {
            if media.isMediaAvailable, let url = media.fileURL {
                mediaItems.append((type: media.type, url: url))
            }
        }
        
        return mediaItems
    }
    
    private func saveMedia(media: [(type: FeedMediaType, url: URL)]) {
        PHPhotoLibrary.shared().performChanges({ [weak self] in
            for media in media {
                if media.type == .image {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: media.url)
                } else if media.type == .video {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: media.url)
                }
            }
            
            DispatchQueue.main.async {
                self?.mediaSaved()
            }
        }, completionHandler: { [weak self] success, error in
            DispatchQueue.main.async {
                if !success {
                    self?.handleMediaSaveError(error: error)
                }
            }
        })
    }
    
    private func mediaSaved() {
        let savedLabel = UILabel()
        
        let imageAttachment = NSTextAttachment()
        imageAttachment.image = UIImage(named: "CheckmarkLong")?.withTintColor(.white)

        let fullString = NSMutableAttributedString()
        fullString.append(NSAttributedString(attachment: imageAttachment))
        fullString.append(NSAttributedString(string: " ")) // Space between localized string for saved and checkmark
        fullString.append(NSAttributedString(string: Localizations.saveSuccessfulLabel))
        savedLabel.attributedText = fullString
        
        savedLabel.layer.cornerRadius = 13
        savedLabel.clipsToBounds = true
        savedLabel.textColor = .white
        savedLabel.backgroundColor = .primaryBlue
        savedLabel.textAlignment = .center
        
        self.view.addSubview(savedLabel)
        
        savedLabel.translatesAutoresizingMaskIntoConstraints = false
        savedLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        savedLabel.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 22.5).isActive = true
        savedLabel.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -22.5).isActive = true
        savedLabel.bottomAnchor.constraint(equalTo: self.view.bottomAnchor, constant: -100).isActive = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            savedLabel.removeFromSuperview()
        }
    }
    
    private func handleMediaSaveError(error: Error?) {
        let alert = UIAlertController(title: Localizations.mediaSaveError, message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
    
    private func handleDeletePostTapped(postId: FeedPostID) {
        let actionSheet = UIAlertController(title: nil, message: Localizations.deletePostConfirmationPrompt, preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: Localizations.deletePostButtonTitle, style: .destructive) { _ in
            self.reallyRetractPost(postId: postId)
        })
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        actionSheet.view.tintColor = .systemBlue
        self.present(actionSheet, animated: true)
    }

    private func reallyRetractPost(postId: FeedPostID) {
        guard let feedPost = MainAppContext.shared.feedData.feedPost(with: postId) else {
            dismiss(animated: true)
            return
        }
        
        MainAppContext.shared.feedData.retract(post: feedPost)
        dismiss(animated: true)
    }

    private func generateExternalShareLink(postID: FeedPostID, success: @escaping (URL) -> Void) {
        guard proceedIfConnected() else {
            return
        }
        MainAppContext.shared.feedData.externalShareUrl(for: postID) { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                switch result {
                case .success(let url):
                    success(url)
                case .failure(_):
                    let actionSheet = UIAlertController(title: nil, message: Localizations.externalShareFailed, preferredStyle: .alert)
                    actionSheet.addAction(UIAlertAction(title: Localizations.buttonOK, style: .cancel))
                    self?.present(actionSheet, animated: true)
                }
            }
        }
    }
}

extension FeedCollectionViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        willShowCell(atIndexPath: indexPath)
        checkForOnscreenCells()
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let feedCell = cell as? FeedPostCollectionViewCell else {
            return
        }

        feedCell.stopPlayback()
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
            if #available(iOS 15.0, *) {
                snapshot.reconfigureItems([displayItem])
            } else {
                snapshot.reloadItems([displayItem])
            }
            collectionViewDataSource.apply(snapshot)
        } else {
            DDLogWarn("FeedPostViewController/feedPostCollectionViewCellDidRequestTextExpansion/unable to resize via dataSource")
            let context = UICollectionViewLayoutInvalidationContext()
            context.invalidateItems(at: [indexPath])
            self.collectionView.collectionViewLayout.invalidateLayout(with: context)
        }
    }
}

extension FeedCollectionViewController: PostDashboardViewControllerDelegate {

    func postDashboardViewController(_ controller: PostDashboardViewController, didRequestPerformAction action: PostDashboardViewController.UserAction) {
        let actionToPerformOnDashboardDismiss: () -> ()
        switch action {
        case .profile(let userId):
            actionToPerformOnDashboardDismiss = {
                self.showUserFeed(for: userId)
            }

        case .message(let userId):
            actionToPerformOnDashboardDismiss = {
                self.navigationController?.pushViewController(ChatViewController(for: userId, with: controller.feedPostId), animated: true)
            }

        case .blacklist(let userId):
            actionToPerformOnDashboardDismiss = {
                MainAppContext.shared.privacySettings.hidePostsFrom(userId: userId)
            }
        }
        controller.dismiss(animated: true, completion: actionToPerformOnDashboardDismiss)
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
        if inviteContactsManager.randomSelection.isEmpty {
            snapshot.deleteItems([.inviteCarousel])
        } else {
            // If the cell is visible, update directly.
            if let indexPath = collectionViewDataSource.indexPath(for: .inviteCarousel),
               let cell = collectionView.cellForItem(at: indexPath) as? FeedInviteCarouselCell {
                cell.configure(with: inviteContactsManager.randomSelection, invitedContacts: invitedContacts, animated: true)
            } else {
                if #available(iOS 15.0, *) {
                    snapshot.reconfigureItems([.inviteCarousel])
                } else {
                    snapshot.reloadItems([.inviteCarousel])
                }
            }
        }
        collectionViewDataSource.apply(snapshot)
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
        return NSLocalizedString("media.save.all", value: "Save All To Camera Roll", comment: "Button that, when pressed, saves all the post's media to the user's camera roll")
    }()
    
    static var saveAllButtonSingular: String = {
        return NSLocalizedString("media.save.all.singular", value: "Save Media To Camera Roll", comment: "Button that, when pressed, saves the post's media to the user's camera roll. Singular version for media.save.all")
    }()
    
    static var deletePostConfirmationPrompt: String = {
        NSLocalizedString("your.post.deletepost.confirmation", value: "Delete this post? This action cannot be undone.", comment: "Post deletion confirmation. Displayed as action sheet title.")
    }()
    static var deletePostButtonTitle: String = {
        NSLocalizedString("your.post.deletepost.button", value: "Delete Post", comment: "Title for the button that confirms intent to delete your own post.")
    }()

    static var externalShareCopyLink: String = {
        NSLocalizedString("your.post.externalshare.copylink",
                          value: "Copy Link to Share",
                          comment: "Title for button in action sheet prompting user to share post to external sites")
    }()

    static var externalShareLinkCopied: String {
        NSLocalizedString("your.post.externalshare.copylink.success",
                          value: "Copied to Clipboard",
                          comment: "Success toast when external share link is copied")
    }

    static var externalShareText: String {
        NSLocalizedString("your.post.externalshare.title",
                          value: "Check out my post on HalloApp:",
                          comment: "Text introducing external share link, part of what is shared")
    }

    static var externalShareFailed: String = {
        NSLocalizedString("your.post.externalshare.error",
                          value: "Failed to upload post for external share",
                          comment: "Message that external share failed.")
    }()

    static var externalShareDescription: String = {
        NSLocalizedString("your.post.externalshare.description",
                          value: "Anyone with this link can see your post. Links expire when your post expires on HalloApp.",
                          comment: "Message on header of post menu explaining external share")
    }()

    static var externalShareButton: String = {
        NSLocalizedString("your.post.externalshare.button",
                          value: "Share Externally",
                          comment: "Button to open the system share sheet with an external post link")
    }()
}
