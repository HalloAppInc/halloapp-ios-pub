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
import CoreData
import UIKit

protocol FeedCollectionViewControllerDelegate: AnyObject {
    func feedCollectionViewController(_ feedCollectionViewController: FeedCollectionViewController, userActioned: Bool)
}

class FeedCollectionViewController: UIViewController, NSFetchedResultsControllerDelegate {

    weak var delegate: FeedCollectionViewControllerDelegate?

    // TODO: Remove this implicitly unwrapped optional
    private(set) var collectionView: UICollectionView!
    private(set) var dataSource: FeedDataSource?
    private let feedLayout = FeedLayout()

    private var cancellableSet: Set<AnyCancellable> = []

    private var cachedCellHeights = [FeedDisplayItem: CGFloat]()
    private var expandedPostIDs = Set<FeedPostID>()

    private var isVisible: Bool = true
    private var isCheckForOnscreenCellsScheduled: Bool = false

    var firstActionHappened: Bool = false

    init(title: String?, fetchRequest: NSFetchRequest<FeedPost>) {
        self.feedDataSource = FeedDataSource(fetchRequest: fetchRequest)
        super.init(nibName: nil, bundle: nil)
        self.title = title
        self.feedDataSource.itemsDidChange = { [weak self] items in
            DispatchQueue.main.async {
                self?.update(with: items)
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        DDLogInfo("FeedCollectionView/viewDidLoad")

        view.backgroundColor = .feedBackground

        feedLayout.estimatedItemSize.width = view.frame.width
        feedLayout.estimatedItemSize.height = view.frame.width

        feedLayout.minimumInteritemSpacing = 0
        feedLayout.minimumLineSpacing = 0

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
        })

        cancellableSet.insert(
            NotificationCenter.default.publisher(for: UIContentSizeCategory.didChangeNotification).sink { [weak self] (_) in
                guard let self = self else { return }
                self.cachedCellHeights.removeAll()
                // TextLabel in FeedItemContentView uses NSAttributedText and therefore doesn't support automatic font adjustment.
                self.collectionView.reloadData()
        })

        cancellableSet.insert(
            MainAppContext.shared.chatData.didGetAGroupEvent.sink { [weak self] (groupID) in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    for indexPath in self.collectionView.indexPathsForVisibleItems {
                        guard let feedCell = self.collectionView.cellForItem(at: indexPath) as? FeedPostCollectionViewCell else { continue }
                        guard let feedPost = self.feedDataSource.item(at: indexPath.item)?.post else { continue }
                        guard feedPost.groupId != nil, feedPost.groupId == groupID else { continue }
                        feedCell.configureGroupLabel(with: groupID)
                    }
                }
            }
        )

        update(with: feedDataSource.displayItems)
    }

    override func viewWillAppear(_ animated: Bool) {
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
        super.viewWillDisappear(animated)

        stopAllVideoPlayback()

        isVisible = false
    }

    override func viewLayoutMarginsDidChange() {
        super.viewLayoutMarginsDidChange()
        cachedCellHeights.removeAll()
        collectionView?.reloadData()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView == collectionView else { return }
        if isNearTop(100) {
            removeNewPostsIndicator()
        }

        checkForOnscreenCells()
    }

    // MARK: FeedCollectionViewController Customization

    public func shouldOpenFeed(for userId: UserID) -> Bool {
        return true
    }

    public func showGroupName() -> Bool {
        return true
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

    private func update(with items: [FeedDisplayItem]) {
        willUpdate(with: items)

        let updatedPostIDs = Set(items.compactMap { $0.post?.id })

        let newPostIDs = updatedPostIDs.subtracting(loadedPostIDs)

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

        newlyDeletedPosts.forEach {
            self.cachedCellHeights[$0] = nil
        }

        var snapshot = NSDiffableDataSourceSnapshot<FeedDisplaySection, FeedDisplayItem>()
        snapshot.appendSections([.posts])
        snapshot.appendItems(items)

        // TODO: See if we can improve this animation
        snapshot.reloadItems(newlyDeletedPosts)
        deletedPostIDs.formUnion(newlyDeletedPosts.compactMap { $0.post?.id })

        collectionViewDataSource?.apply(snapshot, animatingDifferences: true) { [weak self] in
            self?.loadedPostIDs = updatedPostIDs
            self?.feedLayout.maintainVisualPosition = false
            self?.didUpdateItems()
        }
    }

    // MARK: Post Actions

    func showCommentsView(for postId: FeedPostID, highlighting commentId: FeedPostCommentID? = nil) {
        let commentsViewController = CommentsViewController(feedPostId: postId)
        commentsViewController.highlightedCommentId = commentId
        navigationController?.pushViewController(commentsViewController, animated: true)
        
        if !firstActionHappened {
            delegate?.feedCollectionViewController(self, userActioned: true)
            firstActionHappened = true
        }
    }

    private func showMessageView(for postId: FeedPostID) {
        if let feedDataItem = MainAppContext.shared.feedData.feedDataItem(with: postId) {
            navigationController?.pushViewController(ChatViewController(for: feedDataItem.userId, with: postId, at: Int32(feedDataItem.currentMediaIndex ?? 0)), animated: true)
        }

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
        noConnectionBanner.constrain([.leading, .trailing, .top], to: view.safeAreaLayoutGuide)
    }

    /// Hides banner immediately if connected, otherwise waits for timeout to decide whether to show banner
    private func updateNoConnectionBanner(animated: Bool, timeout: TimeInterval = 10) {
        guard UIApplication.shared.applicationState == .active else {
            return
        }
        if MainAppContext.shared.service.isConnected {
            hideNoConnectionBanner(animated: animated)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                if MainAppContext.shared.service.isConnected {
                    self.hideNoConnectionBanner(animated: animated)
                } else {
                    self.showNoConnectionBanner(animated: animated)
                }
            }
        }
    }

    private func showNoConnectionBanner(animated: Bool) {
        guard noConnectionBanner.isHidden else { return }
        noConnectionBanner.isHidden = false
        noConnectionBanner.transform = .init(translationX: 0, y: -self.noConnectionBanner.frame.height)
        UIView.animate(withDuration: animated ? 0.3: 0) {
                self.noConnectionBanner.superview?.bringSubviewToFront(self.noConnectionBanner)
                self.noConnectionBanner.transform = .identity
        }
    }

    private func hideNoConnectionBanner(animated: Bool) {
        guard !noConnectionBanner.isHidden else { return }
        UIView.animate(
            withDuration: animated ? 0.3: 0,
            animations: { self.noConnectionBanner.transform = .init(translationX: 0, y: -self.noConnectionBanner.frame.height) },
            completion: { _ in self.noConnectionBanner.isHidden = true })
    }

    // MARK: New Posts Indicator

    private let newPostsIndicator = NewPostsIndicator()

    private func showNewPostsIndicator() {
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
        guard isVisible else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.removeNewPostsIndicator()
        }
    }

    private func removeNewPostsIndicator() {
        guard view.subviews.contains(newPostsIndicator) else { return }
        newPostsIndicator.removeFromSuperview()
    }

    @objc private func newPostsIndicatorTapped() {
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
        MainAppContext.shared.feedData.feedDataItem(with: feedPost.id)?.loadImages()

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

    let feedDataSource: FeedDataSource
    var collectionViewDataSource: UICollectionViewDiffableDataSource<FeedDisplaySection, FeedDisplayItem>?
}

extension FeedCollectionViewController: UIViewControllerScrollsToTop {

    func scrollToTop(animated: Bool) {
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: animated)
    }
}

extension FeedCollectionViewController {

    func makeCollectionViewDataSource() -> UICollectionViewDiffableDataSource<FeedDisplaySection, FeedDisplayItem> {
        return UICollectionViewDiffableDataSource<FeedDisplaySection, FeedDisplayItem>(collectionView: collectionView) { [weak self] collectionView, indexPath, item in
            switch item {
            case .event(let event):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FeedEventCollectionViewCell.reuseIdentifier, for: indexPath)
                (cell as? FeedEventCollectionViewCell)?.configure(with: event.description, type: .event, isThemed: event.isThemed)
                return cell
            case .post(let feedPost):
                guard !feedPost.isPostRetracted else {
                    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FeedEventCollectionViewCell.reuseIdentifier, for: indexPath)
                    (cell as? FeedEventCollectionViewCell)?.configure(with: Localizations.deletedPost(from: feedPost.userId), type: .deletedPost)
                    return cell
                }
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FeedPostCollectionViewCell.reuseIdentifier, for: indexPath)
                if let postCell = cell as? FeedPostCollectionViewCell {
                    self?.configure(cell: postCell, withActiveFeedPost: feedPost)
                } else {
                    DDLogError("FeedCollectionViewController/error FeedPostCollectionViewCell reuse identifier not registered correctly")
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
            }
        }
    }

    func configure(cell: FeedPostCollectionViewCell, withActiveFeedPost feedPost: FeedPost) {
        let postId = feedPost.id
        let isGroupPost = feedPost.groupId != nil

        cell.maxWidth = collectionView.frame.width
        cell.configure(
            with: feedPost,
            contentWidth: cellContentWidth,
            gutterWidth: gutterWidth,
            showGroupName: showGroupName(),
            isTextExpanded: expandedPostIDs.contains(postId))

        cell.commentAction = { [weak self] in
            guard let self = self else { return }
            self.showCommentsView(for: postId)
        }
        cell.messageAction = { [weak self] in
            guard let self = self else { return }
            self.showMessageView(for: postId)
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
            self.deleteUnsentPost(postID: postId)
        }
        cell.delegate = self
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

extension FeedCollectionViewController: UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {

        guard let displayItem = feedDataSource.item(at: indexPath.item) else {
            DDLogError("FeedCollectionView Automatic size for index path [\(indexPath)]")
            return UICollectionViewFlowLayout.automaticSize
        }

        let cellWidth = collectionView.frame.width
        if let cachedCellHeight = cachedCellHeights[displayItem] {
            return CGSize(width: cellWidth, height: cachedCellHeight)
        }

        switch displayItem {
        case .event(let event):
            let height = FeedEventCollectionViewCell.height(for: event.description, width: cellWidth)
            cachedCellHeights[displayItem] = height
            return CGSize(width: cellWidth, height: height)
        case .post(let feedPost):
            let cellHeight: CGFloat = {
                if feedPost.isPostRetracted {
                    let text = Localizations.deletedPost(from: feedPost.userId)
                    return FeedEventCollectionViewCell.height(for: text, width: cellWidth)
                } else {
                    let contentWidth = cellWidth - collectionView.layoutMargins.left - collectionView.layoutMargins.right
                    return FeedPostCollectionViewCell.height(forPost: feedPost, contentWidth: contentWidth, isTextExpanded: expandedPostIDs.contains(feedPost.id))
                }
            }()
            DDLogDebug("FeedCollectionView Calculated cell height [\(cellHeight)] for [\(feedPost.id)] at [\(indexPath)]")
            cachedCellHeights[displayItem] = cellHeight
            return CGSize(width: cellWidth, height: cellHeight)
        }
    }
}

extension FeedCollectionViewController: FeedPostCollectionViewCellDelegate {

    func feedPostCollectionViewCell(_ cell: FeedPostCollectionViewCell, didRequestOpen url: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            UIApplication.shared.open(url, options: [:])
        }
    }

    func feedPostCollectionViewCellDidRequestTextExpansion(_ cell: FeedPostCollectionViewCell, animations animationBlock: @escaping () -> Void) {
        guard let indexPath = collectionView.indexPath(for: cell),
              let postID = cell.postId else
        {
            return
        }
        expandedPostIDs.insert(postID)
        UIView.animate(withDuration: 0.35) {
            animationBlock()

            guard let collectionViewDataSource = self.collectionViewDataSource,
                  let displayItem = self.feedDataSource.item(at: indexPath.item) else
            {
                self.collectionView.reloadData()
                return
            }
            var snapshot = collectionViewDataSource.snapshot()
            snapshot.reloadItems([displayItem])
            collectionViewDataSource.apply(snapshot)
            self.collectionView.collectionViewLayout.invalidateLayout()
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

private class FeedLayout: UICollectionViewFlowLayout {

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
        guard maintainVisualPosition else { return proposedContentOffset }
        var offset = proposedContentOffset
        offset.y +=  newItemsHeight
        newItemsHeight = 0.0
        return offset
    }

    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint, withScrollingVelocity velocity: CGPoint) -> CGPoint {
        guard maintainVisualPosition else { return proposedContentOffset }
        var offset = proposedContentOffset
        offset.y += newItemsHeight
        newItemsHeight = 0.0
        return offset
    }
}
