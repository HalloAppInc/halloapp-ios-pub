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
import CoreCommon
import CoreData
import Intents
import SwiftUI
import UIKit


class FeedViewController: FeedCollectionViewController, FloatingMenuPresenter {

    private var cancellables: Set<AnyCancellable> = []
    private var notificationButton: BadgedButton?
    private var notificationCount: Int = 0 {
        didSet {
            updateNotificationCount(notificationCount)
        }
    }
    private lazy var canInvite = {
        return isWhatsAppAvailable || isIMessageAvailable
    }()

    private var showContactsPermissionDialogIfNecessary = true

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
            MainAppContext.shared.didTapNotification.sink { [weak self] (metadata) in
                guard let self = self else { return }
                self.processNotification(metadata: metadata)
        })

        cancellables.insert(MainAppContext.shared.callManager.isAnyCallOngoing.sink(receiveValue: { [weak self] activeCall in
            let hasActiveCall = activeCall != nil
            let isVideoCallOngoing = activeCall?.isVideoCall ?? false
            self?.composeVoiceNoteButton?.button.isEnabled = !hasActiveCall
            self?.composeCamPostButton?.button.isEnabled = !isVideoCallOngoing
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
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        let bottomInset = view.bounds.maxX - floatingMenu.triggerButton.frame.minX
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
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
        DispatchQueue.main.async { [weak self] in
            self?.floatingMenu.setAccessoryState(fabAccessoryState, animated: true)
        }
    }

    // MARK: FeedCollectionViewController

    override func willUpdate(with items: [FeedDisplayItem]) {
        super.willUpdate(with: items)

        updateEmptyView(items.isEmpty)
    }

    // MARK: Datasource
    
    override func modifyItems(_ items: [FeedDisplayItem]) -> [FeedDisplayItem] {
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
                }
            } else {
                sharedNUX.recordWelcomePost(id: userID, type: .mainFeed)
                result.append(FeedDisplayItem.welcome)
            }
        }

        // Check original items array to ignore any other nux / promos
        if canInvite, !items.isEmpty, !inviteContactsManager.randomSelection.isEmpty, !isZeroZone {
            result.insert(.inviteCarousel, at: min(4, result.count))
        }

        return result
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
            targetRect: floatingMenu.anchorButton.bounds,
            targetSpace: floatingMenu.anchorButton.coordinateSpace,
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
    private var composeCamPostButton: FloatingMenuButton?

    private(set) lazy var floatingMenu: FloatingMenu = {
        let camButton = FloatingMenuButton.standardActionButton(
            iconTemplate: UIImage(named: "icon_fab_compose_camera")?.withRenderingMode(.alwaysTemplate),
            accessibilityLabel: Localizations.fabAccessibilityCamera,
            action: { [weak self] in self?.presentNewPostViewController(source: .camera) })
        composeCamPostButton = camButton

        var expandedButtons: [FloatingMenuButton] = [
            .standardActionButton(
                iconTemplate: UIImage(named: "icon_fab_compose_image")?.withRenderingMode(.alwaysTemplate),
                accessibilityLabel: Localizations.fabAccessibilityPhotoLibrary,
                action: { [weak self] in self?.presentNewPostViewController(source: .library) }),
            .standardActionButton(
                iconTemplate: UIImage(named: "icon_fab_compose_text")?.withRenderingMode(.alwaysTemplate),
                accessibilityLabel: Localizations.fabAccessibilityTextPost,
                action: { [weak self] in self?.presentNewPostViewController(source: .noMedia) }),
            camButton
        ]

        if ServerProperties.isVoicePostsEnabled {
            let button = FloatingMenuButton.standardActionButton(
                iconTemplate: UIImage(named: "icon_fab_compose_voice")?.withRenderingMode(.alwaysTemplate),
                accessibilityLabel: Localizations.fabAccessibilityVoiceNote,
                action: { [weak self] in self?.presentNewPostViewController(source: .voiceNote) })
            composeVoiceNoteButton = button
            expandedButtons.insert(button, at: 1)
        }
        
        return FloatingMenu(presenter: self, expandedButtons: expandedButtons)
    }()
    
    func makeTriggerButton() -> FloatingMenuButton {
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        let plusImage = UIImage(systemName: "plus", withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
        let accessory = UIImageView(image: UIImage(named: "fab_hallo"))
        
        return .rotatingToggleButton(collapsedIconTemplate: plusImage,
                                             accessoryView: accessory,
                                          expandedRotation: 45)
    }
    
    private func installFloatingActionMenu() {
        let trigger = floatingMenu.triggerButton
        
        trigger.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(trigger)
        
        NSLayoutConstraint.activate([
            trigger.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            trigger.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor, constant: -20),
        ])
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
        let fabActionType: FabActionType
        switch source {
        case .library:
            fabActionType = .gallery
        case .camera:
            fabActionType = .camera
        case .noMedia:
            fabActionType = .text
        case .voiceNote:
            fabActionType = .audio
        }
        AppContext.shared.observeAndSave(event: .fabAction(type: fabActionType))
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
                MainAppContext.shared.privacySettings.activeType = .all
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
                let result = scrollTo(postId: feedPost.id)
                DDLogDebug("FeedViewController/scroll-to-post/immediate \(feedPostId)/result: \(result)")
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
            DDLogDebug("FeedViewController/processNotification/groupFeedPost, groupId: \(metadata.groupId ?? "")")
            if let vc = GroupFeedViewController(metadata: metadata) {
                navigationController?.pushViewController(vc, animated: false)
            }
        default:
            break
        }
    }
}
