//
//  FeedCollectionViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 11/12/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import CoreData
import UIKit

class FeedCollectionViewController: UIViewController, NSFetchedResultsControllerDelegate {

    private(set) var collectionView: UICollectionView!
    private(set) var fetchedResultsController: NSFetchedResultsController<FeedPost>?
    private var cancellableSet: Set<AnyCancellable> = []

    init(title: String?) {
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        DDLogInfo("FeedCollectionView/viewDidLoad")

        view.backgroundColor = .feedBackground

        let layout = UICollectionViewFlowLayout()
        layout.estimatedItemSize.width = view.frame.width
        layout.estimatedItemSize.height = view.frame.width
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.allowsSelection = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.backgroundColor = .clear
        collectionView.preservesSuperviewLayoutMargins = true
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(FeedPostCollectionViewCell.self, forCellWithReuseIdentifier: FeedPostCollectionViewCell.reuseIdentifier)
        collectionView.register(DeletedPostCollectionViewCell.self, forCellWithReuseIdentifier: DeletedPostCollectionViewCell.reuseIdentifier)

        view.addSubview(collectionView)
        collectionView.constrain(to: view)

        setupFetchedResultsController()
        setupNoConnectionBanner()

        cancellableSet.insert(MainAppContext.shared.feedData.willDestroyStore.sink { [weak self] in
            guard let self = self else { return }
            self.fetchedResultsController = nil
            self.collectionView.reloadData()
            self.view.isUserInteractionEnabled = false
        })

        cancellableSet.insert(
            MainAppContext.shared.feedData.didReloadStore.sink { [weak self] in
                guard let self = self else { return }
                self.view.isUserInteractionEnabled = true
                self.setupFetchedResultsController()
                self.collectionView.reloadData()
        })

        cancellableSet.insert(
            MainAppContext.shared.service.didDisconnect.sink { [weak self] in
                self?.updateNoConnectionBanner(animated: true)
            }
        )

        cancellableSet.insert(
            MainAppContext.shared.service.didConnect.sink { [weak self] in
                self?.updateNoConnectionBanner(animated: true)
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
                self.collectionView.indexPathsForVisibleItems.forEach { (indexPath) in
                    self.didShowPost(atIndexPath: indexPath)
                }
        })

        cancellableSet.insert(
            NotificationCenter.default.publisher(for: UIContentSizeCategory.didChangeNotification).sink { [weak self] (_) in
                guard let self = self else { return }
                // TextLabel in FeedItemContentView uses NSAttributedText and therefore doesn't support automatic font adjustment.
                self.collectionView.reloadData()
        })
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        updateNavigationBarStyleUsing(scrollView: collectionView)
        updateNoConnectionBanner(animated: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        stopAllVideoPlayback()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == collectionView {
            updateNavigationBarStyleUsing(scrollView: collectionView)
        }
    }

    // MARK: FeedCollectionViewController Customization

    public var fetchRequest: NSFetchRequest<FeedPost> {
        fatalError("Must be implemented in a subclass.")
    }

    public func shouldOpenFeed(for userId: UserID) -> Bool {
        return true
    }
    
    public func showGroupName() -> Bool {
        return true
    }

    // MARK: Fetched Results Controller

    private var trackPerRowFRCChanges = false

    private var collectionViewUpdates: [BlockOperation] = []

    @Published var isFeedEmpty = true

    func reloadTableView() {
        guard fetchedResultsController != nil else { return }
        fetchedResultsController?.delegate = nil
        setupFetchedResultsController()
        if isViewLoaded {
            collectionView.reloadData()
        }
    }

    private func setupFetchedResultsController() {
        fetchedResultsController = newFetchedResultsController()
        do {
            try fetchedResultsController?.performFetch()
            isFeedEmpty = (fetchedResultsController?.sections?.first?.numberOfObjects ?? 0) == 0
        } catch {
            fatalError("Failed to fetch feed items \(error)")
        }
    }

    private func newFetchedResultsController() -> NSFetchedResultsController<FeedPost> {
        // Setup fetched results controller the old way because it allows granular control over UI update operations.
        let fetchedResultsController = NSFetchedResultsController<FeedPost>(fetchRequest: fetchRequest,
                                                                            managedObjectContext: MainAppContext.shared.feedData.viewContext,
                                                                            sectionNameKeyPath: nil,
                                                                            cacheName: nil)
        fetchedResultsController.delegate = self
        return fetchedResultsController
    }

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        trackPerRowFRCChanges = view.window != nil && UIApplication.shared.applicationState == .active
        DDLogDebug("FeedCollectionView/frc/will-change perRowChanges=[\(trackPerRowFRCChanges)]")
        if trackPerRowFRCChanges {
            collectionViewUpdates.removeAll()
            collectionViewUpdates.append(BlockOperation {
                DDLogDebug("FeedCollectionView/frc/batch-updates Start")
            })
        }
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            guard let indexPath = newIndexPath, let feedPost = anObject as? FeedPost else { break }
            DDLogDebug("FeedCollectionView/frc/insert [\(feedPost)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                collectionViewUpdates.append(BlockOperation {
                    DDLogDebug("FeedCollectionView/frc/batch-updates/insert at [\(indexPath)]")
                    self.collectionView.insertItems(at: [ indexPath ])
                })
            }

        case .delete:
            guard let indexPath = indexPath, let feedPost = anObject as? FeedPost else { break }
            DDLogDebug("FeedCollectionView/frc/delete [\(feedPost)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                collectionViewUpdates.append(BlockOperation {
                    DDLogDebug("FeedCollectionView/frc/batch-updates/delete at [\(indexPath)]")
                    self.collectionView.deleteItems(at: [ indexPath ])
                })
            }

        case .move:
            guard let fromIndexPath = indexPath, let toIndexPath = newIndexPath, let feedPost = anObject as? FeedPost else { break }
            DDLogDebug("FeedCollectionView/frc/move [\(feedPost)] from [\(fromIndexPath)] to [\(toIndexPath)]")
            if trackPerRowFRCChanges {
                collectionViewUpdates.append(BlockOperation {
                    DDLogDebug("FeedCollectionView/frc/batch-updates/move from [\(fromIndexPath)] to [\(toIndexPath)]")
                    self.collectionView.moveItem(at: fromIndexPath, to: toIndexPath)
                })
            }

        case .update:
            guard let indexPath = indexPath, let feedPost = anObject as? FeedPost else { return }
            DDLogDebug("FeedCollectionView/frc/update [\(feedPost)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                collectionViewUpdates.append(BlockOperation {
                    DDLogDebug("FeedCollectionView/frc/batch-updates/reload at [\(indexPath)]")
                    self.collectionView.reloadItems(at: [ indexPath ])
                })
            }

        default:
            break
        }

        isFeedEmpty = (controller.sections?.first?.numberOfObjects ?? 0) == 0
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DDLogDebug("FeedCollectionView/frc/did-change perRowChanges=[\(trackPerRowFRCChanges)]")
        if trackPerRowFRCChanges {
            collectionViewUpdates.append(BlockOperation {
                DDLogDebug("FeedCollectionView/frc/batch-updates Finish")
            })
            collectionView.performBatchUpdates {
                collectionViewUpdates.forEach({ $0.start() })
            }
            collectionViewUpdates.removeAll()
        } else {
            collectionView.reloadData()
        }

        isFeedEmpty = (controller.sections?.first?.numberOfObjects ?? 0) == 0
    }

    // MARK: Post Actions

    func showCommentsView(for postId: FeedPostID, highlighting commentId: FeedPostCommentID? = nil) {
        let commentsViewController = CommentsViewController(feedPostId: postId)
        commentsViewController.highlightedCommentId = commentId
        navigationController?.pushViewController(commentsViewController, animated: true)
    }

    private func showMessageView(for postId: FeedPostID) {
        if let feedDataItem = MainAppContext.shared.feedData.feedDataItem(with: postId) {
            navigationController?.pushViewController(ChatViewController(for: feedDataItem.userId, with: postId, at: Int32(feedDataItem.currentMediaIndex ?? 0)), animated: true)
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
        navigationController?.pushViewController(GroupFeedViewController(groupId: groupID), animated: true)
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
               let feedPost = fetchedResultsController?.object(at: indexPath)
            {
                feedCell.refreshTimestamp(using: feedPost)
            }
        }
    }

    private func didShowPost(atIndexPath indexPath: IndexPath) {
        if let feedPost = fetchedResultsController?.object(at: indexPath) {
            // Load downloaded images into memory.
            MainAppContext.shared.feedData.feedDataItem(with: feedPost.id)?.loadImages()

            // Initiate download for images that were not yet downloaded.
            MainAppContext.shared.feedData.downloadMedia(in: [ feedPost ])

            // If app is in foreground and is currently active:
            // • send "seen" receipt for the post
            // • remove notifications for the post
            if UIApplication.shared.applicationState == .active {
                MainAppContext.shared.feedData.sendSeenReceiptIfNecessary(for: feedPost)
                UNUserNotificationCenter.current().removeDeliveredFeedNotifications(postId: feedPost.id)
            }
        }
    }
}

extension FeedCollectionViewController: UIViewControllerScrollsToTop {
    
    func scrollToTop(animated: Bool) {
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: animated)
    }
}

extension FeedCollectionViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return fetchedResultsController?.sections?.count ?? 0
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let sections = fetchedResultsController?.sections else {
            return 0
        }
        return sections[section].numberOfObjects
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let feedPost = fetchedResultsController?.object(at: indexPath) else {
            return UICollectionViewCell(frame: .zero)
        }
        guard !feedPost.isPostRetracted else {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DeletedPostCollectionViewCell.reuseIdentifier, for: indexPath)
            (cell as? DeletedPostCollectionViewCell)?.configure(with: feedPost)
            return cell
        }
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FeedPostCollectionViewCell.reuseIdentifier, for: indexPath) as? FeedPostCollectionViewCell else {
            DDLogError("FeedCollectionViewController/error FeedPostCollectionViewCell reuse identifier not registered correctly")
            return UICollectionViewCell(frame: .zero)
        }

        let postId = feedPost.id
        let isGroupPost = feedPost.groupId != nil
        let contentWidth = collectionView.frame.size.width - collectionView.layoutMargins.left - collectionView.layoutMargins.right
        let gutterWidth = (1 - FeedPostCollectionViewCellBase.LayoutConstants.backgroundPanelHMarginRatio) * collectionView.layoutMargins.left

        cell.maxWidth = collectionView.frame.width
        cell.configure(with: feedPost, contentWidth: contentWidth, gutterWidth: gutterWidth, showGroupName: showGroupName())

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
        return cell
    }
}

extension FeedCollectionViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        didShowPost(atIndexPath: indexPath)
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
        guard let feedPost = fetchedResultsController?.object(at: indexPath) else {
            DDLogError("FeedCollectionView Automatic size for index path [\(indexPath)]")
            return UICollectionViewFlowLayout.automaticSize
        }
        let cellClass: FeedPostHeightDetermining.Type = feedPost.isPostRetracted ? DeletedPostCollectionViewCell.self : FeedPostCollectionViewCell.self
        let feedItem = MainAppContext.shared.feedData.feedDataItem(with: feedPost.id)
        let cellWidth = collectionView.frame.width
        if let cachedCellHeight = feedItem?.cachedCellHeight {
            return CGSize(width: cellWidth, height: cachedCellHeight)
        }
        // NB: Retracted post cell has larger margins... for now let's pass it the entire width to simplify calculation
        let contentWidth = feedPost.isPostRetracted ? collectionView.frame.width : collectionView.frame.size.width - collectionView.layoutMargins.left - collectionView.layoutMargins.right
        let cellHeight = cellClass.height(forPost: feedPost, contentWidth: contentWidth)
        feedItem?.cachedCellHeight = cellHeight
        DDLogDebug("FeedCollectionView Calculated cell height [\(cellHeight)] for [\(feedPost.id)] at [\(indexPath)]")
        return CGSize(width: cellWidth, height: cellHeight)
    }
}

extension FeedCollectionViewController: FeedPostCollectionViewCellDelegate {

    func feedPostCollectionViewCell(_ cell: FeedPostCollectionViewCell, didRequestOpen url: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            UIApplication.shared.open(url, options: [:])
        }
    }

    func feedPostCollectionViewCellDidRequestReloadHeight(_ cell: FeedPostCollectionViewCell, animations animationBlock: @escaping () -> Void) {
        guard let indexPath = collectionView.indexPath(for: cell),
              let postId = cell.postId, let feedDataItem = MainAppContext.shared.feedData.feedDataItem(with: postId) else
        {
            return
        }
        feedDataItem.textExpanded = true
        UIView.animate(withDuration: 0.35) {
            animationBlock()
            self.collectionView.reloadItems(at: [ indexPath ])
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
