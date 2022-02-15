//
//  FeedViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/20/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreData
import Intents
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

    override init(title: String?, fetchRequest: NSFetchRequest<FeedPost>) {
        super.init(title: title, fetchRequest: fetchRequest)
        self.setupDatasourceAndRefreshIfNeeded()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: UIViewController

    override func viewDidLoad() {
        DDLogDebug("FeedViewController/viewDidLoad/begin")
        super.viewDidLoad()

        installLargeTitleUsingGothamFont()
        installEmptyView()
        installFloatingActionMenu()

        let notificationButton = BadgedButton(type: .system)
        notificationButton.centerYConstant = 5
        notificationButton.setImage(UIImage(named: "FeedNavbarNotifications")?.withTintColor(UIColor.primaryBlue, renderingMode: .alwaysOriginal), for: .normal)
        notificationButton.accessibilityLabel = Localizations.titleNotifications
        notificationButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        notificationButton.addTarget(self, action: #selector(didTapNotificationButton), for: .touchUpInside)
        self.notificationButton = notificationButton

        let inviteButton = BadgedButton(type: .system)
        inviteButton.centerYConstant = 5
        inviteButton.setImage(UIImage(named: "FeedInviteButton")?.withTintColor(UIColor.primaryBlue, renderingMode: .alwaysOriginal), for: .normal)
        inviteButton.accessibilityLabel = Localizations.inviteFriendsAndFamily
        inviteButton.isBadgeHidden = true
        inviteButton.addTarget(self, action: #selector(didTapInviteButtion), for: .touchUpInside)

        self.navigationItem.rightBarButtonItems = [UIBarButtonItem(customView: notificationButton), UIBarButtonItem(customView: inviteButton)]

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

        cancellables.insert(MainAppContext.shared.callManager.hasActiveCallPublisher.sink(receiveValue: { [weak self] hasActiveCall in
            self?.composeVoiceNoteButton?.button.isEnabled = !hasActiveCall
        }))

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

        if isNearTop(100) {
            MainAppContext.shared.feedData.didGetRemoveHomeTabIndicator.send()
        }
    }

    deinit {
        self.cancellables.forEach { $0.cancel() }
    }

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        super.scrollViewDidScroll(scrollView)
        guard scrollView == collectionView else { return }
        if isNearTop(100) {
            MainAppContext.shared.feedData.didGetRemoveHomeTabIndicator.send()
        }
        let fabAccessoryState: FloatingMenu.AccessoryState = scrollView.contentOffset.y <= 0 ? .accessorized : .plain
        floatingMenu.setAccessoryState(fabAccessoryState, animated: true)
    }

    // MARK: FeedCollectionViewController

    override func willUpdate(with items: [FeedDisplayItem]) {
        super.willUpdate(with: items)

        updateEmptyView(items.isEmpty)
    }

    // MARK: Datasource

    private func setupDatasourceAndRefreshIfNeeded() {
        var needToShowWelcomePost: Bool = false

        feedDataSource.modifyItems = { items in
            var result = items

            let sharedNUX = MainAppContext.shared.nux
            let userID = MainAppContext.shared.userData.userId

            let isDemoMode = sharedNUX.isDemoMode
            let isZeroZone = sharedNUX.state == .zeroZone
            let welcomePostExist = sharedNUX.welcomePostExist(id: userID)
            let isEmptyItemsList = items.count == 0
            let showWelcomePostIfNeeded = welcomePostExist || isZeroZone || isEmptyItemsList

            if isDemoMode {
                result.insert(FeedDisplayItem.welcome, at: 0)
                return result
            }

            if showWelcomePostIfNeeded {
                if welcomePostExist {
                    // don't show post if post was closed by user or expired
                    if sharedNUX.showWelcomePost(id: userID) {
                        result.append(FeedDisplayItem.welcome)
                        needToShowWelcomePost = true
                    }
                } else {
                    sharedNUX.recordWelcomePost(id: userID, type: .mainFeed)
                    result.append(FeedDisplayItem.welcome)
                    needToShowWelcomePost = true
                }
            }
            return result
        }

        if needToShowWelcomePost {
            DDLogInfo("FeedViewController/setupDatasourceAndRefreshIfNeeded/needToShowWelcomePost, refresh")
            feedDataSource.refresh()
        }
    }

    // MARK: UI Actions

    @objc private func didTapNotificationButton() {
        overlayContainer.dismissOverlay(with: activityCenterOverlayID)
        self.present(UINavigationController(rootViewController: NotificationsViewController()), animated: true)
    }

    @objc private func didTapInviteButtion() {
        guard ContactStore.contactsAccessAuthorized else {
            let inviteVC = InvitePermissionDeniedViewController()
            present(UINavigationController(rootViewController: inviteVC), animated: true)
            return
        }
        InviteManager.shared.requestInvitesIfNecessary()
        let inviteVC = InviteViewController(manager: InviteManager.shared, dismissAction: { [weak self] in self?.dismiss(animated: true, completion: nil) })
        let navController = UINavigationController(rootViewController: inviteVC)
        present(navController, animated: true)
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
        //
        // Disabling NUX for launch
        //

        // guard view.window != nil else {
        //     return
        // }
        // if overlay != nil {
        //     // only show one NUX item at a time
        //     return
        // } else if MainAppContext.shared.nux.isIncomplete(.activityCenterIcon) && notificationCount > 0 {
        //     showActivityCenterNUX()
        // } else if MainAppContext.shared.nux.isIncomplete(.newPostButton) {
        //     showFloatingMenuNUX()
        // }
    }

    private func installEmptyView() {
        view.addSubview(emptyView)

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

    private let activityCenterOverlayID = "activity.center.nux.id"

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
        popover.overlayID = activityCenterOverlayID

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

    private var composeVoiceNoteButton: FloatingMenuButton?

    private lazy var floatingMenu: FloatingMenu = {
        var expandedButtons: [FloatingMenuButton] = [
            .standardActionButton(
                iconTemplate: UIImage(named: "icon_fab_compose_image")?.withRenderingMode(.alwaysTemplate),
                accessibilityLabel: Localizations.fabAccessibilityPhotoLibrary,
                action: { [weak self] in self?.presentNewPostViewController(source: .library) }),
            .standardActionButton(
                iconTemplate: UIImage(named: "icon_fab_compose_text")?.withRenderingMode(.alwaysTemplate),
                accessibilityLabel: Localizations.fabAccessibilityTextPost,
                action: { [weak self] in self?.presentNewPostViewController(source: .noMedia) }),
            .standardActionButton(
                iconTemplate: UIImage(named: "icon_fab_compose_camera")?.withRenderingMode(.alwaysTemplate),
                accessibilityLabel: Localizations.fabAccessibilityCamera,
                action: { [weak self] in self?.presentNewPostViewController(source: .camera) }),
        ]

        if ServerProperties.isVoicePostsEnabled {
            let button = FloatingMenuButton.standardActionButton(
                iconTemplate: UIImage(named: "icon_fab_compose_voice")?.withRenderingMode(.alwaysTemplate),
                accessibilityLabel: Localizations.fabAccessibilityVoiceNote,
                action: { [weak self] in self?.presentNewPostViewController(source: .voiceNote) })
            composeVoiceNoteButton = button
            expandedButtons.insert(button, at: 1)
        }

        return FloatingMenu(
            permanentButton: .rotatingToggleButton(
                collapsedIconTemplate: UIImage(named: "icon_fab_compose_post")?.withRenderingMode(.alwaysTemplate),
                accessoryView: UIImageView(image: UIImage(named: "fab_hallo")),
                expandedRotation: 45),
            expandedButtons: expandedButtons,
            expandedHeader: Localizations.newPost)
    }()

    private func installFloatingActionMenu() {
        floatingMenu.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatingMenu)
        floatingMenu.constrain(to: view)

        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: floatingMenu.suggestedContentInsetHeight, right: 0)
    }

    private let settingsURL = URL(string: UIApplication.openSettingsURLString)

    private func updateContactPermissionsAlert() {
        let overlayID = "feed.contact.permissions.alert"

        guard showContactsPermissionDialogIfNecessary && ContactStore.contactsAccessDenied else {
            overlayContainer.dismissOverlay(with: overlayID)
            return
        }
        guard overlay == nil else {
            return
        }
        guard settingsURL != nil else {
            DDLogError("FeedViewController/showPermissionsDialog/error settings-url-unavailable")
            return
        }
      
        let alert = FeedPermissionAlert(
            message: Localizations.contactsPermissionExplanation,
            acceptAction: .init(title: Localizations.buttonContinue) { [weak self] _ in
                self?.dismissOverlay()
                self?.updateContactPermissionsExplanationAlert()
            },
            dismissAction: .init(title: Localizations.buttonNotNow) { [weak self] _ in
                self?.showContactsPermissionDialogIfNecessary = false
                self?.dismissOverlay()
            })
        alert.overlayID = overlayID

        overlay = alert
        overlayContainer.display(alert)
    }
    
    private func updateContactPermissionsExplanationAlert() {
        let contentView = FeedPermissionExplanationAlert(learnMoreAction: nil, notNowAction: FeedPermissionExplanationAlert.Action(title: Localizations.buttonNotNow, handler: { [weak self] _ in
            self?.dismissOverlay()
        }), continueAction: FeedPermissionExplanationAlert.Action(title: Localizations.buttonOK, handler: { [weak self] _ in
            self?.dismissOverlay()
            self?.updateContactPermissionsTutorialAlert()
        }))

        let sheet = BottomSheet(innerView: contentView, completion: {
            
        })
        
        overlay = sheet
        overlayContainer.display(sheet)
    }
    
    private func updateContactPermissionsTutorialAlert() {
        guard let settingsURL = settingsURL else {
            DDLogError("FeedViewController/showPermissionsDialog/error settings-url-unavailable")
            return
        }
        
        let contentView = FeedPermissionTutorialAlert(goToSettingsAction: FeedPermissionTutorialAlert.Action(title: Localizations.buttonGoToSettings, handler: { [weak self] _ in
            UIApplication.shared.open(settingsURL)
            self?.dismissOverlay()
        }))

        let sheet = BottomSheet(innerView: contentView, completion: {
            
        })
        
        overlay = sheet
        overlayContainer.display(sheet)
    }

    private func presentNewPostViewController(source: NewPostMediaSource) {
        if source == .voiceNote && MainAppContext.shared.callManager.isAnyCallActive {
            // When we have an active call ongoing: we should not record audio.
            // We should present an alert saying that this action is not allowed.
            let alert = UIAlertController(
                title: Localizations.failedActionDuringCallTitle,
                message: Localizations.failedActionDuringCallNoticeText,
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: { action in
                DDLogInfo("FeedViewController/presentNewPostViewController/failedActionDuringCall/dismiss")
            }))
            present(alert, animated: true)
        } else {
            let newPostViewController = NewPostViewController(source: source, destination: .userFeed) { didPost in
                self.dismiss(animated: true)
                if didPost { self.scrollToTop(animated: true) }
            }
            newPostViewController.modalPresentationStyle = .fullScreen
            present(newPostViewController, animated: true)
        }
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

        switch metadata.contentType {
        case .feedComment, .groupFeedComment:
            guard let commentData = metadata.commentData() else {
                DDLogError("FeedViewController/notification/could not get commentData - failed to scroll \(metadata.contentId)")
                return
            }
            showCommentsView(for: commentData.feedPostId, highlighting: commentData.id)
        case .feedPost:
            guard let postData = metadata.postData() else {
                DDLogError("FeedViewController/notification/could not get postData - failed to scroll \(metadata.contentId)")
                return
            }
            let feedPostId = postData.id
            let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId)
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
            // TODO: we should scroll to the specific post - separate diff.
            DDLogDebug("FeedViewController/processNotification/groupFeedPost, groupId: \(metadata.groupId ?? "")")
            if let groupId = metadata.groupId, let _ = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
                let vc = GroupFeedViewController(groupId: groupId)
                navigationController?.pushViewController(vc, animated: false)
            }
        default:
            break
        }
    }
}
