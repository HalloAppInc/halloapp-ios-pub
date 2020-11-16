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

    private struct Constants {
        static let activePostCellReuseIdentifier = "active-post"
        static let deletedPostCellReuseIdentifier = "deleted-post"
    }

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

        DDLogInfo("FeedCollectionViewController/viewDidLoad")

        let layoutSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(100))
        let item = NSCollectionLayoutItem(layoutSize: layoutSize)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: layoutSize, subitem: item, count: 1)
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 25, trailing: 0)
        section.interGroupSpacing = 50
        let layout = UICollectionViewCompositionalLayout(section: section)

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isPrefetchingEnabled = false
        collectionView.allowsSelection = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.backgroundColor = .feedBackground
        collectionView.preservesSuperviewLayoutMargins = true
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(FeedPostCollectionViewCell.self, forCellWithReuseIdentifier: Constants.activePostCellReuseIdentifier)
        collectionView.register(DeletedPostCollectionViewCell.self, forCellWithReuseIdentifier: Constants.deletedPostCellReuseIdentifier)

        view.addSubview(collectionView)
        collectionView.constrain(to: view)

        setupFetchedResultsController()

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
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        updateNavigationBarStyleUsing(scrollView: collectionView)
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

    // MARK: Fetched Results Controller

    private var trackPerRowFRCChanges = false

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
//        if trackPerRowFRCChanges {
//            tableView.beginUpdates()
//            CATransaction.begin()
//            CATransaction.setCompletionBlock {
//                self.tableView.setNeedsLayout()
//                self.tableView.layoutIfNeeded()
//            }
//        }
        DDLogDebug("FeedCollectionView/frc/will-change perRowChanges=[\(trackPerRowFRCChanges)]")
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            guard let indexPath = newIndexPath, let feedPost = anObject as? FeedPost else { break }
            DDLogDebug("FeedCollectionView/frc/insert [\(feedPost)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                collectionView.insertItems(at: [ indexPath ])
            }

        case .delete:
            guard let indexPath = indexPath, let feedPost = anObject as? FeedPost else { break }
            DDLogDebug("FeedCollectionView/frc/delete [\(feedPost)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                collectionView.deleteItems(at: [ indexPath ])
            }

        case .move:
            guard let fromIndexPath = indexPath, let toIndexPath = newIndexPath, let feedPost = anObject as? FeedPost else { break }
            DDLogDebug("FeedCollectionView/frc/move [\(feedPost)] from [\(fromIndexPath)] to [\(toIndexPath)]")
            if trackPerRowFRCChanges {
                collectionView.moveItem(at: fromIndexPath, to: toIndexPath)
            }

        case .update:
            guard let indexPath = indexPath, let feedPost = anObject as? FeedPost else { return }
            DDLogDebug("FeedCollectionView/frc/update [\(feedPost)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                collectionView.reloadItems(at: [ indexPath ])
            }

        default:
            break
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DDLogDebug("FeedCollectionView/frc/did-change perRowChanges=[\(trackPerRowFRCChanges)]")
        if trackPerRowFRCChanges {
//            tableView.endUpdates()
//            CATransaction.commit()
        } else {
            collectionView.reloadData()
        }
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

    private func cancelSending(postId: FeedPostID) {
        MainAppContext.shared.feedData.cancelMediaUpload(postId: postId)
    }

    private func retrySending(postId: FeedPostID) {
        MainAppContext.shared.feedData.retryPosting(postId: postId)
    }

    // MARK: Misc

    private func stopAllVideoPlayback() {
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
//        if tableView.tableHeaderView != nil {
//            tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: animated)
//            return
//        }
        guard let firstSection = fetchedResultsController?.sections?.first else { return }
        if firstSection.numberOfObjects > 0 {
            collectionView.scrollToItem(at: IndexPath(item: 0, section: 0), at: .top, animated: animated)
        }
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
        let cellReuseIdentifier = feedPost.isPostRetracted ? Constants.deletedPostCellReuseIdentifier : Constants.activePostCellReuseIdentifier
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellReuseIdentifier, for: indexPath) as! FeedPostCollectionViewCellBase

        let postId = feedPost.id
        let isGroupPost = feedPost.groupId != nil
        let contentWidth = collectionView.frame.size.width - collectionView.layoutMargins.left - collectionView.layoutMargins.right
        let gutterWidth = (1 - FeedPostTableViewCell.LayoutConstants.backgroundPanelHMarginRatio) * collectionView.layoutMargins.left

        cell.configure(with: feedPost, contentWidth: contentWidth, gutterWidth: gutterWidth)

        if let activePostCell = cell as? FeedPostCollectionViewCell {
            activePostCell.commentAction = { [weak self] in
                guard let self = self else { return }
                self.showCommentsView(for: postId)
            }
            activePostCell.messageAction = { [weak self] in
                guard let self = self else { return }
                self.showMessageView(for: postId)
            }
            activePostCell.showSeenByAction = { [weak self] in
                guard let self = self else { return }
                self.showSeenByView(for: postId, isGroupPost: isGroupPost)
            }
            activePostCell.showUserAction = { [weak self] userID in
                guard let self = self else { return }
                self.showUserFeed(for: userID)
            }
            activePostCell.cancelSendingAction = { [weak self] in
                guard let self = self else { return }
                self.cancelSending(postId: postId)
            }
            activePostCell.retrySendingAction = { [weak self] in
                guard let self = self else { return }
                self.retrySending(postId: postId)
            }
            activePostCell.delegate = self
        }
        if let deletedPostCell = cell as? DeletedPostCollectionViewCell {
            deletedPostCell.showUserAction = { [weak self] userID in
                guard let self = self else { return }
                self.showUserFeed(for: userID)
            }
        }
        return cell
    }
}

extension FeedCollectionViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        didShowPost(atIndexPath: indexPath)

        cell.backgroundColor = UIColor(red: CGFloat.random(in: 0...1), green: CGFloat.random(in: 0...1), blue: CGFloat.random(in: 0...1), alpha: 1)
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let feedCell = cell as? FeedPostCollectionViewCell {
            feedCell.stopPlayback()
        }
    }
}

extension FeedCollectionViewController: FeedPostCollectionViewCellDelegate {

    func feedPostCollectionViewCell(_ cell: FeedPostCollectionViewCell, didRequestOpen url: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            UIApplication.shared.open(url, options: [:])
        }
    }

    func feedPostCollectionViewCellDidRequestReloadHeight(_ cell: FeedPostCollectionViewCell, animations animationBlock: () -> Void) {
//        collectionView.beginUpdates()
        animationBlock()
//        tableView.endUpdates()

        if let postId = cell.postId, let feedDataItem = MainAppContext.shared.feedData.feedDataItem(with: postId) {
            feedDataItem.textExpanded = true
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
