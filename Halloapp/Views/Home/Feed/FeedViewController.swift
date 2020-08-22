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
        installFloatingActionMenu()

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

        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: notificationButton)

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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Floating menu is hidden while our view is obscured
        floatingMenu.isHidden = false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Floating menu is in the navigation controller's view so we have to hide it
        floatingMenu.setState(.collapsed, animated: true)
        floatingMenu.isHidden = true
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

    @objc private func presentNotificationsView() {
        self.present(UINavigationController(rootViewController: NotificationsViewController(style: .plain)), animated: true)
    }

    // MARK: New post

    private lazy var floatingMenu: FloatingMenu = {
        FloatingMenu(
            permanentButton: .rotatingToggleButton(
                collapsedIconTemplate: UIImage(named: "icon_fab_compose_post")?.withRenderingMode(.alwaysTemplate),
                expandedRotation: 45),
            expandedButtons: [
                .standardActionButton(
                    iconTemplate: UIImage(named: "icon_fab_compose_image")?.withRenderingMode(.alwaysTemplate),
                    accessibilityLabel: "Photo",
                    action: { [weak self] in self?.presentNewPostViewController(source: .library) }),
                .standardActionButton(
                    iconTemplate: UIImage(named: "icon_fab_compose_camera")?.withRenderingMode(.alwaysTemplate),
                    accessibilityLabel: "Camera",
                    action: { [weak self] in self?.presentNewPostViewController(source: .camera) }),
                .standardActionButton(
                    iconTemplate: UIImage(named: "icon_fab_compose_text")?.withRenderingMode(.alwaysTemplate),
                    accessibilityLabel: "Text",
                    action: { [weak self] in self?.presentNewPostViewController(source: .noMedia) }),
            ]
        )
    }()

    private func installFloatingActionMenu() {
        // Install in NavigationController's view because our own view is a table view (complicates position and z-ordering)
        guard let container = navigationController?.view else {
            DDLogError("Cannot install FAB on feed without navigation controller")
            return
        }

        floatingMenu.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(floatingMenu)
        floatingMenu.constrain(to: container)
    }

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
