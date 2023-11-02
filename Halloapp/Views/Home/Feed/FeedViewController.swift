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

    private var recentSelfPostIDs = Set<FeedPostID>()
    private var recentSelfPostShareCarouselDisplayTimes = Dictionary<FeedPostID, Date>()

    private lazy var canInvite = {
        return isWhatsAppAvailable || isIMessageAvailable
    }()

    // MARK: UIViewController

    override func viewDidLoad() {
        DDLogDebug("FeedViewController/viewDidLoad/begin")
        super.viewDidLoad()

        installAvatarBarButton()
        installEmptyView()
        installFloatingActionMenu()

        let friendsButton = UIBarButtonItem(title: Localizations.friendsTitle, primaryAction: UIAction { [weak self] _ in
            guard let self else {
                return
            }

            let viewController = SegmentedFriendsViewController()
            let navigationController = UINavigationController(rootViewController: viewController)
            self.present(navigationController, animated: true)
        })

        friendsButton.tintColor = .primaryBlue
        navigationItem.rightBarButtonItem = friendsButton

        cancellables.insert(MainAppContext.shared.callManager.isAnyCallOngoing.sink(receiveValue: { [weak self] activeCall in
            let hasActiveCall = activeCall != nil
            let isVideoCallOngoing = activeCall?.isVideoCall ?? false
            self?.composeVoiceNoteButton?.button.isEnabled = !hasActiveCall
            self?.composeCamPostButton?.button.isEnabled = !isVideoCallOngoing
        }))
        
        // needed for presenting the FAB while the call bar is active
        navigationController?.definesPresentationContext = false
        tabBarController?.definesPresentationContext = true

        MainAppContext.shared.feedData.validMoment
            .dropFirst() // no need to reload for initial values
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // in this case we want to refresh since we want the prompt cell to be
                // inserted again
                self?.feedDataSource.refresh()
            }
            .store(in: &cancellables)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showNUXIfNecessary()
        Analytics.openScreen(.homeFeed)

        if isNearTop(100) {
            MainAppContext.shared.feedData.didGetRemoveHomeTabIndicator.send()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DDLogInfo("FeedViewController/viewWillAppear")

        if suggestionsManager.suggestions.count < 10 {
            Task(priority: .userInitiated) { @MainActor in
                await suggestionsManager.refresh()
                feedDataSource.refresh()
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let bottomInset = view.bounds.maxY - floatingMenu.triggerButton.frame.minY - collectionView.safeAreaInsets.bottom
        if bottomInset != collectionView.contentInset.bottom {
            collectionView.contentInset.bottom = bottomInset
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
        
        guard scrollView.contentSize.height > scrollView.bounds.inset(by: scrollView.adjustedContentInset).height else {
            DispatchQueue.main.async { [weak self] in self?.floatingMenu.setAccessoryState(.accessorized, animated: true) }
            return
        }
        
        let fabAccessoryState: FloatingMenu.AccessoryState = scrollView.contentOffset.y <= 0 ? .accessorized : .plain
        // if we didn't use a DispatchQueue here, we'd get some issues when restoring scroll position
        DispatchQueue.main.async { [weak self] in self?.floatingMenu.setAccessoryState(fabAccessoryState, animated: true) }
    }

    override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        super.collectionView(collectionView, willDisplay: cell, forItemAt: indexPath)

        if let feedItem = feedDataSource.item(at: indexPath.item), case .shareCarousel(let feedPostID) = feedItem {
            recentSelfPostShareCarouselDisplayTimes[feedPostID] = Date()
        }
    }

    override func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        super.collectionView(collectionView, didEndDisplaying: cell, forItemAt: indexPath)

        if let feedItem = feedDataSource.item(at: indexPath.item), case .shareCarousel(let feedPostID) = feedItem {
            if let displayStart = recentSelfPostShareCarouselDisplayTimes[feedPostID], -displayStart.timeIntervalSinceNow > 2 {
                // Dispatch_async to prevent data source updates while applying snapshot
                DispatchQueue.main.async {
                    self.recentSelfPostIDs.remove(feedPostID)
                    self.feedDataSource.removeItem(feedItem)
                }
            }
            recentSelfPostShareCarouselDisplayTimes[feedPostID] = nil
        }
    }

    // MARK: FeedCollectionViewController

    override func willUpdate(with items: [FeedDisplayItem]) {
        super.willUpdate(with: items)

        updateEmptyView(items.isEmpty)
    }

    // MARK: Datasource

    override func itemDidChange(_ item: FeedDisplayItem, change type: FeedDataSource.FeedDataSourceChangeType) {
        super.itemDidChange(item, change: type)

        if type == .insert, case .post(let feedPost) = item, feedPost.userID == MainAppContext.shared.userData.userId, -feedPost.timestamp.timeIntervalSinceNow < 5 * 60 {
            recentSelfPostIDs.insert(feedPost.id)
        }
    }
    
    override func modifyItems(_ items: [FeedDisplayItem]) -> [FeedDisplayItem] {
        var result = items

        let sharedNUX = MainAppContext.shared.nux
        let userID = MainAppContext.shared.userData.userId

        let isDemoMode = sharedNUX.isDemoMode
        let isZeroZone = sharedNUX.state == .zeroZone
        let welcomePostExist = sharedNUX.welcomePostExist(id: userID)
        let isEmptyItemsList = items.count == 0
        let showWelcomePostIfNeeded = welcomePostExist || isZeroZone || isEmptyItemsList
        let showFriendSuggestions = suggestionsManager.suggestions.count >= 5

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
        if !items.isEmpty, !isZeroZone {
            if showFriendSuggestions {
                result.insert(.suggestionsCarousel, at: min(4, result.count))
            } else if canInvite, !inviteContactsManager.randomSelection.isEmpty {
                result.insert(.inviteCarousel, at: min(4, result.count))
            }
        }

        if MainAppContext.shared.feedData.validMoment.value == nil {
            switch result.first {
            case .momentStack(_):
                break
            default:
                result.insert(.momentStack([.prompt]), at: 0)
            }
        }

        // Insert share carousels last, so any other operations will not interfere with positioning
        var idx = 0
        while idx < result.count {
            if case .post(let feedPost) = result[idx], recentSelfPostIDs.contains(feedPost.id) {
                result.insert(.shareCarousel(feedPost.id), at: idx + 1)
            }
            idx += 1
        }

        return result
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
            iconTemplate: UIImage(named: "icon_fab_moment")?.withRenderingMode(.alwaysTemplate),
            accessibilityLabel: Localizations.fabMoment,
            action: { [weak self] in
                Analytics.log(event: .fabSelect, properties: [.fabSelection: "moment"])
                self?.createNewMoment()
            })
        composeCamPostButton = camButton

        let voiceNoteButton = FloatingMenuButton.standardActionButton(
            iconTemplate: UIImage(named: "icon_fab_compose_voice")?.withRenderingMode(.alwaysTemplate),
            accessibilityLabel: Localizations.fabAccessibilityVoiceNote,
            action: { [weak self] in
                Analytics.log(event: .fabSelect, properties: [.fabSelection: "audio"])
                self?.presentNewPostViewController(source: .voiceNote)
            })
        composeVoiceNoteButton = voiceNoteButton

        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold, scale: .medium)
        let textIconName = view.effectiveUserInterfaceLayoutDirection == .leftToRight ? "text.alignleft" : "text.alignright"
        let textIcon = UIImage(systemName: textIconName)?.withConfiguration(symbolConfiguration)

        var expandedButtons: [FloatingMenuButton] = [
            .standardActionButton(
                iconTemplate: UIImage(systemName: "photo.fill")?.withConfiguration(symbolConfiguration),
                accessibilityLabel: Localizations.fabAccessibilityPhotoLibrary,
                action: { [weak self] in
                    Analytics.log(event: .fabSelect, properties: [.fabSelection: "photo_video"])
                    self?.presentNewPostViewController(source: .library)
                }),
            voiceNoteButton,
            .standardActionButton(
                iconTemplate: textIcon,
                accessibilityLabel: Localizations.fabAccessibilityTextPost,
                action: { [weak self] in
                    Analytics.log(event: .fabSelect, properties: [.fabSelection: "text"])
                    self?.presentNewPostViewController(source: .noMedia)
                }),
            camButton
        ]

        return FloatingMenu(presenter: self, expandedButtons: expandedButtons)
    }()

    func makeTriggerButton() -> FloatingMenuButton {
        let postLabel = UILabel()
        postLabel.translatesAutoresizingMaskIntoConstraints = false
        postLabel.font = .quicksandFont(ofFixedSize: 21, weight: .bold)
        postLabel.text = Localizations.fabPostButton
        postLabel.textColor = .white

        let labelContainer = UIView()
        labelContainer.translatesAutoresizingMaskIntoConstraints = false
        labelContainer.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 1, right: 0)
        labelContainer.addSubview(postLabel)
        postLabel.constrainMargins(to: labelContainer)

        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        let plusImage = UIImage(systemName: "plus", withConfiguration: config)?.withRenderingMode(.alwaysTemplate)

        return .rotatingToggleButton(collapsedIconTemplate: plusImage,
                                             accessoryView: labelContainer,
                                          expandedRotation: 45)
    }
    
    func floatingMenuExpansionStateWillChange(to state: FloatingMenu.ExpansionState) {
        if case .expanded = state {
            // keep the indicator visible while the menu is expanded
            cancelNewPostsIndicatorRemoval()
        } else {
            // remove the indicator x seconds after we dismiss the menu
            scheduleNewPostsIndicatorRemoval()
        }
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
    
    override func showNewPostsIndicator() {
        super.showNewPostsIndicator()
        
        if presentedViewController === floatingMenu {
            // case where the FAB was already displayed when the indicator appeared
            cancelNewPostsIndicatorRemoval()
        }
    }

    private func presentNewPostViewController(source: NewPostMediaSource) {
        let fabActionType: FabActionType?
        switch source {
        case .library:
            fabActionType = .gallery
        case .camera:
            fabActionType = .camera
        case .noMedia:
            fabActionType = .text
        case .voiceNote:
            fabActionType = .audio
        case .unified:
            fabActionType = nil
        }

        if let fabActionType = fabActionType {
            AppContext.shared.observeAndSave(event: .fabAction(type: fabActionType))
        }

        let state = NewPostState(mediaSource: source)

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
            let newPostViewController = NewPostViewController(state: state, destination: .feed(.all), showDestinationPicker: true) { didPost, _ in
                // Reset back to all
                MainAppContext.shared.privacySettings.activeType = .all
                self.dismiss(animated: true)
                if didPost { self.scrollToTop(animated: true) }
            }
            newPostViewController.modalPresentationStyle = .fullScreen
            present(newPostViewController, animated: true)
        }
    }
}

extension FeedViewController: UIViewControllerHandleTapNotification {
    func processNotification(metadata: NotificationMetadata) {
        guard metadata.isFeedNotification else {
            return
        }

        metadata.removeFromUserDefaults()
        DDLogInfo("FeedViewController/notification/process type=\(metadata.contentType) contentId=\(metadata.contentId)")

        // We still need to pop any view controllers on top of feedViewController if any.
        self.navigationController?.popToRootViewController(animated: false)

        switch metadata.contentType {
        case .feedComment, .groupFeedComment:
            guard let commentData = metadata.commentData() else {
                DDLogError("FeedViewController/notification/could not get commentData - failed to scroll \(metadata.contentId)")
                return
            }
            if let postId = metadata.postId,
               metadata.isPostReaction || metadata.isGroupPostReaction,
               let feedPost = MainAppContext.shared.feedData.feedPost(with: postId, in: MainAppContext.shared.feedData.viewContext) {
                // Scroll to feed post now.
                let result = scrollTo(postId: feedPost.id)
                // If we could not display the feedPost then try to postpone the scrolling.
                if !result {
                    feedPostIdToScrollTo = feedPost.id
                }
                DDLogDebug("FeedViewController/scroll-to-post-for-reaction/ \(feedPost.id)/result: \(result)")
                showSeenByView(for: feedPost)
            } else {
                showCommentsView(for: commentData.feedPostId, highlighting: commentData.id)
            }

        case .feedPost:
            guard let postData = metadata.postData() else {
                DDLogError("FeedViewController/notification/could not get postData - failed to scroll \(metadata.contentId)")
                return
            }
            let feedPostId = postData.id
            let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId, in: MainAppContext.shared.feedData.viewContext)
            if let feedPost = feedPost {
                DDLogDebug("FeedViewController/scroll-to-post/immediate \(feedPostId)")
                // Scroll to feed post now.
                let result = scrollTo(postId: feedPost.id)
                // If we could not display the feedPost then try to postpone the scrolling.
                if !result {
                    feedPostIdToScrollTo = feedPostId
                }
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
        case .screenshot:
            guard
                let feedData = MainAppContext.shared.feedData,
                let feedPost = feedData.feedPost(with: metadata.contentId, in: feedData.viewContext)
            else {
                // not necessarily an error since the moment could be expired / retracted
                DDLogError("FeedViewController/processNotification/screenshot unable to find post \(metadata.contentId)")
                return
            }

            DDLogDebug("FeedViewController/processNotification/screenshot for post \(feedPost.id)")
            scrollTo(postId: feedPost.id)
            let dashboard = PostDashboardViewController(feedPost: feedPost)
            dashboard.delegate = self
            present(UINavigationController(rootViewController: dashboard), animated: true)
        case .dailyMoment:
            presentNewMomentViewController(context: .normal)
        case .friendRequest:
            let viewController = SegmentedFriendsViewController(initialState: .requests)
            let navigationController = UINavigationController(rootViewController: viewController)
            present(navigationController, animated: true)
        case .friendAccept:
            let viewController = UserFeedViewController(userId: metadata.fromId)
            let navigationController = UINavigationController(rootViewController: viewController)
            present(navigationController, animated: true)
        default:
            break
        }
    }
}
