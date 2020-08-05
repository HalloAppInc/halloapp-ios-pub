//
//  FeedViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/20/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import CoreData
import SwiftUI
import UIKit

class FeedViewController: FeedTableViewController {

    private var cancellables: Set<AnyCancellable> = []

    private var feedPostIdToScrollTo: FeedPostID?

    // MARK: UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        installLargeTitleUsingGothamFont()

        let notificationButton = BadgedButton(type: .system)
        notificationButton.setImage(UIImage(named: "FeedNavbarNotifications"), for: .normal)
        notificationButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        notificationButton.addTarget(self, action: #selector(presentNotificationsView), for: .touchUpInside)
        if let feedNotifications = MainAppContext.shared.feedData.feedNotifications {
            notificationButton.isBadgeHidden = feedNotifications.unreadCount == 0
            self.cancellables.insert(feedNotifications.unreadCountDidChange.sink { (unreadCount) in
                notificationButton.isBadgeHidden = unreadCount == 0
            })
        }

        let composeButton = UIButton(type: .system)
        composeButton.setImage(UIImage(named: "FeedCompose"), for: .normal)
        composeButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        composeButton.tintColor = .lavaOrange
        composeButton.addTarget(self, action: #selector(composePost), for: .touchUpInside)

        self.navigationItem.rightBarButtonItems = [
            UIBarButtonItem(customView: composeButton),
            UIBarButtonItem(customView: notificationButton) ]

        let privacySettings = MainAppContext.shared.xmppController.privacySettings!
        cancellables.insert(
            privacySettings.mutedContactsChanged.sink { [weak self] in
                guard let self = self else { return }
                self.reloadTableView()
        })

        cancellables.insert(
            MainAppContext.shared.feedData.didReceiveFeedPost.sink { [weak self] (feedPost) in
                guard let self = self else { return }
                if self.feedPostIdToScrollTo == feedPost.id {
                    DDLogDebug("FeedViewController/scroll-to-post/postponed \(feedPost.id)")
                    self.scrollTo(post: feedPost)
                    self.feedPostIdToScrollTo = nil
                }
        })

        cancellables.insert(
            MainAppContext.shared.didTapNotification.sink { [weak self] (metadata) in
                guard let self = self else { return }
                self.processNotification(metadata: metadata)
        })

        // When the user was not on this view, and HomeView sends user to here
        if let metadata = NotificationUtility.Metadata.fromUserDefaults()  {
            self.processNotification(metadata: metadata)
        }
    }

    deinit {
        self.cancellables.forEach { $0.cancel() }
    }

    // MARK: FeedTableViewController

    override var fetchRequest: NSFetchRequest<FeedPost> {
        get {
            let mutedUserIds = MainAppContext.shared.xmppController.privacySettings.mutedContactIds
            let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
            if !mutedUserIds.isEmpty {
                fetchRequest.predicate = NSPredicate(format: "NOT (userId IN %@)", mutedUserIds)
            }
            fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
            return fetchRequest
        }
    }

    // MARK: UI Actions

    @objc(composePost)
    private func composePost() {
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: "Photo Library", style: .default) { _ in
            self.presentNewPostViewController(source: .library)
        })
        actionSheet.addAction(UIAlertAction(title: "Camera", style: .default) { _ in
            self.presentNewPostViewController(source: .camera)
        })
        actionSheet.addAction(UIAlertAction(title: "Text", style: .default) { _ in
            self.presentNewPostViewController(source: .noMedia)
        })
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        self.present(actionSheet, animated: true, completion: nil)
    }

    @objc(showNotifications)
    private func presentNotificationsView() {
        self.present(UINavigationController(rootViewController: NotificationsViewController(style: .plain)), animated: true)
    }

    // MARK: New post

    private func presentNewPostViewController(source: NewPostMediaSource) {
        let newPostViewController = NewPostViewController(source: source) {
            self.dismiss(animated: true)
        }
        newPostViewController.modalPresentationStyle = .fullScreen
        present(newPostViewController, animated: true)
    }

    // MARK: Notification Handling

    private func scrollTo(post feedPost: FeedPost) {
        if let indexPath = fetchedResultsController?.indexPath(forObject: feedPost) {
            tableView.scrollToRow(at: indexPath, at: .top, animated: false)
        }
    }

    private func processNotification(metadata: NotificationUtility.Metadata) {
        guard metadata.contentType == .comment || metadata.contentType == .feedpost else {
            return
        }

        metadata.removeFromUserDefaults()

        DDLogInfo("FeedViewController/notification/process type=\(metadata.contentType) contentId=\(metadata.contentId)")

        guard let protoContainer = metadata.protoContainer, protoContainer.hasComment || protoContainer.hasPost else {
            DDLogError("FeedViewController/notification/process/error Invalid protobuf")
            return
        }

        let feedPostId = protoContainer.hasPost ? metadata.contentId : protoContainer.comment.feedPostID

        let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId)
        if feedPost == nil {
            DDLogWarn("FeedViewController/notification/process/warning Missing post with id=[\(feedPostId)]")
        }

        self.navigationController?.popToRootViewController(animated: false)

        switch metadata.contentType {
        case .comment:
            self.showCommentsView(for: feedPostId, highlighting: metadata.contentId)

        case .feedpost:
            if let feedPost = feedPost {
                DDLogDebug("FeedViewController/scroll-to-post/immediate \(feedPostId)")
                // Scroll to feed post now.
                scrollTo(post: feedPost)
            } else {
                DDLogDebug("FeedViewController/scroll-to-post/postpone \(feedPostId)")
                // Scroll to the top now and wait for post to be received.
                ///TODO: some kind of indicator?
                feedPostIdToScrollTo = feedPostId
                if !(fetchedResultsController?.fetchedObjects?.isEmpty ?? true) {
                    tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: false)
                }
            }

        default:
            break
        }
    }

}
