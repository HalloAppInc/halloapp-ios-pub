//
//  FeedTableView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/30/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import CoreData
import UIKit

fileprivate enum FeedTableSection {
    case main
}

class FeedTableViewController: UIViewController, NSFetchedResultsControllerDelegate, UITableViewDelegate, UITableViewDataSource, UIScrollViewDelegate, FeedTableViewCellDelegate {

    private struct Constants {
        static let activePostCellReuseIdentifier = "active-post"
        static let deletedPostCellReuseIdentifier = "deleted-post"
    }

    let tableView = UITableView()
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
        
        DDLogInfo("FeedTableViewController/viewDidLoad")

        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.constrain(to: view)

        tableView.separatorStyle = .none
        tableView.allowsSelection = false
        tableView.showsVerticalScrollIndicator = false
        tableView.register(FeedPostTableViewCell.self, forCellReuseIdentifier: Constants.activePostCellReuseIdentifier)
        tableView.register(DeletedPostTableViewCell.self, forCellReuseIdentifier: Constants.deletedPostCellReuseIdentifier)
        tableView.backgroundColor = .feedBackground
        tableView.delegate = self
        tableView.dataSource = self

        setupFetchedResultsController()

        cancellableSet.insert(MainAppContext.shared.feedData.willDestroyStore.sink { [weak self] in
            guard let self = self else { return }
            self.fetchedResultsController = nil
            self.tableView.reloadData()
            self.view.isUserInteractionEnabled = false
        })

        cancellableSet.insert(
            MainAppContext.shared.feedData.didReloadStore.sink { [weak self] in
                guard let self = self else { return }
                self.view.isUserInteractionEnabled = true
                self.setupFetchedResultsController()
                self.tableView.reloadData()
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
                guard let indexPaths = self.tableView.indexPathsForVisibleRows else { return }
                indexPaths.forEach { (indexPath) in
                    self.didShowPost(atIndexPath: indexPath)
                }
        })
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == tableView {
            updateNavigationBarStyleUsing(scrollView: tableView)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        updateNavigationBarStyleUsing(scrollView: tableView)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        stopAllVideoPlayback()
    }

    func scrollToTop(animated: Bool) {
        if tableView.tableHeaderView != nil {
            tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: animated)
            return
        }
        guard let firstSection = fetchedResultsController?.sections?.first else { return }
        if firstSection.numberOfObjects > 0 {
            tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: animated)
        }
    }

    // MARK: FeedTableViewController Customization

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
            tableView.reloadData()
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
        if trackPerRowFRCChanges {
            tableView.beginUpdates()
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                self.tableView.setNeedsLayout()
                self.tableView.layoutIfNeeded()
            }
        }
        DDLogDebug("FeedTableView/frc/will-change perRowChanges=[\(trackPerRowFRCChanges)]")
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            guard let indexPath = newIndexPath, let feedPost = anObject as? FeedPost else { break }
            DDLogDebug("FeedTableView/frc/insert [\(feedPost)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                tableView.insertRows(at: [ indexPath ], with: .fade)
            }

        case .delete:
            guard let indexPath = indexPath, let feedPost = anObject as? FeedPost else { break }
            DDLogDebug("FeedTableView/frc/delete [\(feedPost)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                tableView.deleteRows(at: [ indexPath ], with: .none)
            }

        case .move:
            guard let fromIndexPath = indexPath, let toIndexPath = newIndexPath, let feedPost = anObject as? FeedPost else { break }
            DDLogDebug("FeedTableView/frc/move [\(feedPost)] from [\(fromIndexPath)] to [\(toIndexPath)]")
            if trackPerRowFRCChanges {
                tableView.moveRow(at: fromIndexPath, to: toIndexPath)
            }

        case .update:
            guard let indexPath = indexPath, let feedPost = anObject as? FeedPost else { return }
            DDLogDebug("FeedTableView/frc/update [\(feedPost)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                var reloadRow = feedPost.isPostRetracted
                if !reloadRow {
                    // Update UI without doing full cell reuse-reload if possible to avoid flickering.
                    if let cell = tableView.cellForRow(at: indexPath) as? FeedPostTableViewCellBase, cell.postId == feedPost.id {
                        let contentWidth = tableView.frame.size.width - tableView.layoutMargins.left - tableView.layoutMargins.right
                        let gutterWidth = (1 - FeedPostTableViewCell.LayoutConstants.backgroundPanelHMarginRatio) * tableView.layoutMargins.left
                        cell.configure(with: feedPost, contentWidth: contentWidth, gutterWidth: gutterWidth)
                        DDLogDebug("FeedTableView/frc/update/soft [\(feedPost)] at [\(indexPath)]")
                    } else {
                        reloadRow = true
                    }
                }
                if reloadRow {
                    DDLogDebug("FeedTableView/frc/update/full [\(feedPost)] at [\(indexPath)]")
                    tableView.reloadRows(at: [ indexPath ], with: .none)
                }
            }

        default:
            break
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DDLogDebug("FeedTableView/frc/did-change perRowChanges=[\(trackPerRowFRCChanges)]")
        if trackPerRowFRCChanges {
            tableView.endUpdates()
            CATransaction.commit()
        } else {
            tableView.reloadData()
        }
    }

    // MARK: UITableView

    func numberOfSections(in tableView: UITableView) -> Int {
        return fetchedResultsController?.sections?.count ?? 0
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sections = fetchedResultsController?.sections else {
            return 0
        }
        return sections[section].numberOfObjects
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let feedPost = fetchedResultsController?.object(at: indexPath) else {
            return UITableViewCell(style: .default, reuseIdentifier: nil)
        }
        let cellReuseIdentifier = feedPost.isPostRetracted ? Constants.deletedPostCellReuseIdentifier : Constants.activePostCellReuseIdentifier
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier, for: indexPath) as! FeedPostTableViewCellBase

        let postId = feedPost.id
        let isGroupPost = feedPost.groupId != nil
        let contentWidth = tableView.frame.size.width - tableView.layoutMargins.left - tableView.layoutMargins.right
        let gutterWidth = (1 - FeedPostTableViewCell.LayoutConstants.backgroundPanelHMarginRatio) * tableView.layoutMargins.left
        cell.configure(with: feedPost, contentWidth: contentWidth, gutterWidth: gutterWidth)

        if let activePostCell = cell as? FeedPostTableViewCell {
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
        if let deletedPostCell = cell as? DeletedPostTableViewCell {
            deletedPostCell.showUserAction = { [weak self] userID in
                guard let self = self else { return }
                self.showUserFeed(for: userID)
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        didShowPost(atIndexPath: indexPath)
    }

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if let feedCell = cell as? FeedPostTableViewCell {
            feedCell.stopPlayback()
        }
    }

    // MARK: FeedTableViewCellDelegate

    func feedTableViewCell(_ cell: FeedPostTableViewCell, didRequestOpen url: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            UIApplication.shared.open(url, options: [:])
        }
    }

    func feedTableViewCellDidRequestReloadHeight(_ cell: FeedPostTableViewCell, animations animationBlock: () -> Void) {
        tableView.beginUpdates()
        animationBlock()
        tableView.endUpdates()

        if let postId = cell.postId, let feedDataItem = MainAppContext.shared.feedData.feedDataItem(with: postId) {
            feedDataItem.textExpanded = true
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
        for cell in tableView.visibleCells {
            if let feedTableViewCell = cell as? FeedPostTableViewCell {
                feedTableViewCell.stopPlayback()
            }
        }
    }

    private func refreshTimestamps() {
        guard let indexPaths = tableView.indexPathsForVisibleRows else { return }
        for indexPath in indexPaths {
            if let feedTableViewCell = tableView.cellForRow(at: indexPath) as? FeedPostTableViewCell,
                let feedPost = fetchedResultsController?.object(at: indexPath) {
                feedTableViewCell.refreshTimestamp(using: feedPost)
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

extension FeedTableViewController: PostDashboardViewControllerDelegate {

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
