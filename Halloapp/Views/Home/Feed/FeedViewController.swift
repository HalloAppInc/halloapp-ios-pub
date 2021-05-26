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

class FeedViewController: FeedCollectionViewController {

    private var cancellables: Set<AnyCancellable> = []
    private var notificationButton: BadgedButton?
    private var notificationCount: Int = 0 {
        didSet {
            updateNotificationCount(notificationCount)
        }
    }

    private var feedPostIdToScrollTo: FeedPostID?
    private var showContactsPermissionDialogIfNecessary = true

    // MARK: UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        installLargeTitleUsingGothamFont()
        installEmptyView()
        installFloatingActionMenu()

        let notificationButton = BadgedButton(type: .system)
        notificationButton.centerYConstant = 5
        notificationButton.setImage(UIImage(named: "FeedNavbarNotifications")?.withTintColor(UIColor.primaryBlue, renderingMode: .alwaysOriginal), for: .normal)
        notificationButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        notificationButton.addTarget(self, action: #selector(presentNotificationsView), for: .touchUpInside)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: notificationButton)
        self.notificationButton = notificationButton

        if let feedNotifications = MainAppContext.shared.feedData.feedNotifications {
            notificationCount = feedNotifications.unreadCount
            self.cancellables.insert(feedNotifications.unreadCountDidChange.sink { [weak self] (unreadCount) in
                self?.notificationCount = unreadCount
            })
        }

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
            MainAppContext.shared.feedData.didMergeFeedPost.sink { [weak self] (feedPostId) in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if self.feedPostIdToScrollTo == feedPostId {
                        DDLogDebug("FeedViewController/scroll-to-post/merged \(feedPostId)")
                        self.scrollToPostId(postId: feedPostId)
                        self.feedPostIdToScrollTo = nil
                    }
                }
        })

        cancellables.insert(
            MainAppContext.shared.didTapNotification.sink { [weak self] (metadata) in
                guard let self = self else { return }
                self.processNotification(metadata: metadata)
        })

        // When the user was not on this view, and HomeView sends user to here
        if let metadata = NotificationMetadata.fromUserDefaults()  {
            // dispatch_async is needed because collection view isn't ready to scroll to a given item at this point.
            DispatchQueue.main.async {
                self.processNotification(metadata: metadata)
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateContactPermissionsAlert()
        showNUXIfNecessary()
    }

    deinit {
        self.cancellables.forEach { $0.cancel() }
    }

    // MARK: FeedCollectionViewController

    override func willUpdate(with items: [FeedDisplayItem]) {
        super.willUpdate(with: items)

        updateEmptyView(items.isEmpty)
    }

    // MARK: UI Actions

    @objc private func presentNotificationsView() {
        self.present(UINavigationController(rootViewController: NotificationsViewController(style: .plain)), animated: true)
    }

    // MARK: NUX

    private lazy var overlayContainer: OverlayContainer = {
        let overlayContainer = OverlayContainer()
        overlayContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayContainer)
        overlayContainer.constrain(to: view)
        return overlayContainer
    }()

    private lazy var emptyView: UIView = {
        let image = UIImage(named: "FeedEmpty")?.withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: image)
        imageView.tintColor = UIColor.label.withAlphaComponent(0.2)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.text = Localizations.nuxHomeFeedEmpty
        label.textAlignment = .center
        label.textColor = .secondaryLabel

        let stackView = UIStackView(arrangedSubviews: [imageView, label])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 12

        return stackView
    }()

    private weak var overlay: Overlay?

    private func showNUXIfNecessary() {
        guard view.window != nil else {
            return
        }
        if overlay != nil {
            // only show one NUX item at a time
            return
        } else if MainAppContext.shared.nux.isIncomplete(.activityCenterIcon) && notificationCount > 0 {
            showActivityCenterNUX()
        } else if MainAppContext.shared.nux.isIncomplete(.newPostButton) {
            showFloatingMenuNUX()
        }
    }

    private func installEmptyView() {
        view.addSubview(emptyView)

        // Put empty view behind collection view in case it contains NUX header
        view.sendSubviewToBack(emptyView)

        emptyView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.6).isActive = true
        emptyView.constrain([.centerX, .centerY], to: view)
    }

    private func updateEmptyView(_ isEmpty: Bool) {
        emptyView.alpha = isEmpty ? 1 : 0
    }

    private func showFloatingMenuNUX() {
        let popover = NUXPopover(
            Localizations.nuxNewPostButtonContent,
            targetRect: floatingMenu.permanentButton.bounds,
            targetSpace: floatingMenu.permanentButton.coordinateSpace,
            showButton: false) { [weak self] in
            MainAppContext.shared.nux.didComplete(.newPostButton)
            self?.overlay = nil
        }

        overlay = popover
        overlayContainer.display(popover)
    }

    private func showActivityCenterNUX() {
        guard let notificationButton = notificationButton else {
            return
        }
        let popover = NUXPopover(
            Localizations.nuxActivityCenterIconContent,
            targetRect: notificationButton.bounds,
            targetSpace: notificationButton.coordinateSpace,
            showButton: false) { [weak self] in
            MainAppContext.shared.nux.didComplete(.activityCenterIcon)
            self?.overlay = nil
        }

        overlay = popover
        overlayContainer.display(popover)
    }

    @objc
    private func dismissOverlay() {
        if let currentOverlay = overlay {
            overlayContainer.dismiss(currentOverlay)
        }
        overlay = nil
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
                    accessibilityLabel: Localizations.fabAccessibilityPhotoLibrary,
                    action: { [weak self] in self?.presentNewPostViewController(source: .library) }),
                .standardActionButton(
                    iconTemplate: UIImage(named: "icon_fab_compose_camera")?.withRenderingMode(.alwaysTemplate),
                    accessibilityLabel: Localizations.fabAccessibilityCamera,
                    action: { [weak self] in self?.presentNewPostViewController(source: .camera) }),
                .standardActionButton(
                    iconTemplate: UIImage(named: "icon_fab_compose_text")?.withRenderingMode(.alwaysTemplate),
                    accessibilityLabel: Localizations.fabAccessibilityTextPost,
                    action: { [weak self] in self?.presentNewPostViewController(source: .noMedia) }),
            ]
        )
    }()

    private func installFloatingActionMenu() {
        floatingMenu.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatingMenu)
        floatingMenu.constrain(to: view)

        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: floatingMenu.suggestedContentInsetHeight, right: 0)
    }

    private func updateContactPermissionsAlert() {
        let overlayID = "feed.contact.permissions.alert"

        guard showContactsPermissionDialogIfNecessary && ContactStore.contactsAccessDenied else {
            overlayContainer.dismissOverlay(with: overlayID)
            return
        }
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            DDLogError("FeedViewController/showPermissionsDialog/error settings-url-unavailable")
            return
        }
        let alert = FeedPermissionAlert(
            message: Localizations.contactsPermissionExplanation,
            acceptAction: .init(title: Localizations.buttonContinue) { [weak self] _ in
                UIApplication.shared.open(url)
                self?.dismissOverlay()
            },
            dismissAction: .init(title: Localizations.buttonNotNow) { [weak self] _ in
                self?.showContactsPermissionDialogIfNecessary = false
                self?.dismissOverlay()
            })
        alert.overlayID = overlayID

        overlay = alert
        overlayContainer.display(alert)
    }

    private func presentNewPostViewController(source: NewPostMediaSource) {
        let newPostViewController = NewPostViewController(source: source, destination: .userFeed) {
            self.dismiss(animated: true)
        }
        newPostViewController.modalPresentationStyle = .fullScreen
        present(newPostViewController, animated: true)
    }

    // MARK: Notification Handling

    private func updateNotificationCount(_ unreadCount: Int) {
        notificationButton?.isBadgeHidden = unreadCount == 0
        showNUXIfNecessary()
    }

    private func scrollTo(post feedPost: FeedPost) {
        scrollToPostId(postId: feedPost.id)
    }

    private func scrollToPostId(postId feedPostId: FeedPostID) {
        if let index = feedDataSource.index(of: feedPostId) {
            collectionView.scrollToItem(at: IndexPath(item: index, section: 0), at: .top, animated: false)
        }
    }

    private func processNotification(metadata: NotificationMetadata) {
        guard metadata.isFeedNotification else {
            return
        }

        metadata.removeFromUserDefaults()

        DDLogInfo("FeedViewController/notification/process type=\(metadata.contentType) contentId=\(metadata.contentId)")

        guard let protoContainer = metadata.protoContainer, protoContainer.hasComment || protoContainer.hasPost else {
            DDLogError("FeedViewController/notification/process/error Invalid protobuf")
            return
        }
        guard let feedPostId = protoContainer.hasComment ? protoContainer.comment.feedPostID : metadata.feedPostId else {
            DDLogError("FeedViewController/notification/process/error Can't find postId")
            return
        }

        let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId)
        if feedPost == nil {
            DDLogWarn("FeedViewController/notification/process/warning Missing post with id=[\(feedPostId)]")
        }

        navigationController?.popToRootViewController(animated: false)

        switch metadata.contentType {
        case .feedComment, .groupFeedComment:
            if let commentId = metadata.feedPostCommentId {
                showCommentsView(for: feedPostId, highlighting: commentId)
            }

        case .feedPost:
            if let feedPost = feedPost {
                DDLogDebug("FeedViewController/scroll-to-post/immediate \(feedPostId)")
                // Scroll to feed post now.
                scrollTo(post: feedPost)
            } else {
                DDLogDebug("FeedViewController/scroll-to-post/postpone \(feedPostId)")
                // Scroll to the top now and wait for post to be received.
                ///TODO: some kind of indicator?
                feedPostIdToScrollTo = feedPostId
                if !feedDataSource.displayItems.isEmpty {
                    collectionView.scrollToItem(at: IndexPath(item: 0, section: 0), at: .top, animated: false)
                }
            }

        case .groupFeedPost:
            if let groupId = metadata.groupId, let _ = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
                let vc = GroupFeedViewController(groupId: groupId)
                navigationController?.pushViewController(vc, animated: false)
            }
            break

        default:
            break
        }
    }

    // MARK: Collection View

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        let layout = collectionViewLayout as! UICollectionViewFlowLayout
        var inset = layout.sectionInset
        if section == 0 {
            inset.top = 0
        }
        return inset
    }

}
