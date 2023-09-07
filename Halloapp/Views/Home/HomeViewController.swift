//
//  HomeViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/20/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Contacts
import ContactsUI
import Core
import CoreCommon
import Foundation
import Intents
import UIKit

class HomeViewController: UITabBarController {

    private var cancellableSet: Set<AnyCancellable> = []
    private var tabBarViewControllers: [UIViewController] = []
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        self.commonSetup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.commonSetup()
    }

    private var feedController: UIViewController?
    private var groupsController: UIViewController?
    private var cameraController: UIViewController?
    private var chatsController: UIViewController?
    private var activityController: UIViewController?

    private func commonSetup() {
        self.delegate = self

        // Set background color for navigation bar and search bar system-wide.
        UINavigationBar.appearance().standardAppearance = .opaqueAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = .opaqueAppearance
        UINavigationBar.appearance().compactAppearance = .opaqueAppearance
        UISearchBar.appearance().backgroundColor = .primaryBg

        // need to set UITabBarItem in addition to appearance as the very first load does not respect appearance (for font)
        let fontAttributes = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 9.5, weight: .semibold),
                              NSAttributedString.Key.kern: 0.01,
                              NSAttributedString.Key.paragraphStyle: NSParagraphStyle.default,
                              NSAttributedString.Key.foregroundColor: UIColor.tabBar] as [NSAttributedString.Key: Any]
        UITabBarItem.appearance().setTitleTextAttributes(fontAttributes, for: .normal)
        
        let appearance = UITabBarAppearance()
        appearance.shadowColor = nil
        appearance.stackedLayoutAppearance.normal.badgeBackgroundColor = .lavaOrange
        appearance.stackedLayoutAppearance.normal.badgePositionAdjustment = UIOffset(horizontal: 2, vertical: 0 + Self.tabBarItemImageInsets.top)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = fontAttributes
        tabBar.standardAppearance = appearance

        tabBar.tintColor = .primaryBlue

        updateTabBarBackgroundEffect()

        let feedNavController = feedNavigationController()
        feedController = feedNavController
        let groupsNavController = groupsNavigationController()
        groupsController = groupsNavController
        let cameraNavController = cameraNavigationController()
        cameraController = cameraNavigationController()
        let chatsNavController = chatsNavigationController()
        chatsController = chatsNavController
        let activityNavController = activityNavigationController()
        activityController = activityNavController

        tabBarViewControllers = [
            feedNavController,
            groupsNavController,
            cameraNavController,
            chatsNavController,
            activityNavController,
        ]

        setViewControllers(tabBarViewControllers, animated: false)

        /*
         The home tab indicator starts hidden on each new app open (does not count background/foreground)
         It shows when a new post (not shared) comes in if the user is not actively viewing the top of the main feed
         It's removed when the user scrolls to the top of the main feed or when the total unseen posts is 0
         (ie. user scrolls to middle of feed, goes to groups tab, views all unread, indicator should go away)
         */
        cancellableSet.insert(MainAppContext.shared.feedData.didGetNewFeedPost.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.showHomeTabIndicatorIfNeeded()
        })
        // Can ignore shared (old) merged feed posts as they will not be sent when connection is passive
        cancellableSet.insert(MainAppContext.shared.feedData.didMergeFeedPost.receive(on: DispatchQueue.main).sink { [weak self] feedPostID in
            let viewContext = MainAppContext.shared.feedData.viewContext
            guard let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostID, in: viewContext) else { return }
            let isInbound = feedPost.userId != MainAppContext.shared.userData.userId
            if isInbound {
                self?.showHomeTabIndicatorIfNeeded()
            }
        })
        cancellableSet.insert(MainAppContext.shared.feedData.didGetRemoveHomeTabIndicator.receive(on: DispatchQueue.main).sink { [weak self] in
            self?.removeHomeTabIndicator()
        })
        cancellableSet.insert(AppContext.shared.coreFeedData.didGetUnreadFeedCount.receive(on: DispatchQueue.main).sink { [weak self] (count) in
            guard count == 0 else { return }
            self?.removeHomeTabIndicator()
        })

        MainAppContext.shared.chatData.unreadGroupThreadCountController.count
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in self?.updateGroupsNavigationControllerBadge(count) }
            .store(in: &cancellableSet)

        cancellableSet.insert(
            MainAppContext.shared.chatData.didChangeUnreadThreadCount.receive(on: DispatchQueue.main).sink { [weak self] (count) in
                self?.updateChatNavigationControllerBadge(count)
        })
        MainAppContext.shared.chatData.updateUnreadChatsThreadCount()

        let feedActivity = MainAppContext.shared.feedData.activityObserver
        let currentNotificationCount = feedActivity?.unreadCount ?? 0
        updateActivityNavigationControllerBadge(currentNotificationCount)

        feedActivity?.unreadCountDidChange.receive(on: DispatchQueue.main).sink { [weak self] count in
            self?.updateActivityNavigationControllerBadge(count)
        }.store(in: &cancellableSet)

        // When the app was in the background
        cancellableSet.insert(
            MainAppContext.shared.didTapNotification.sink { [weak self] (metadata) in
                guard let self = self else { return }
                self.processNotification(metadata: metadata)
        })

        // Present UIActivityViewController from the tabbar view controller.
        cancellableSet.insert(
            MainAppContext.shared.activityViewControllerPresentRequest.sink { [weak self] (items) in
                guard let self = self else { return }
                self.presentActivityViewController(forItems: items)
        })

        // navigate to group feed from the tabbar
        cancellableSet.insert(
            MainAppContext.shared.groupFeedFromGroupTabPresentRequest.sink { [weak self] (groupID) in
                guard let self = self else { return }
                guard groupID != nil else { return }
                self.switchTo(tab: .group)
        })

        cancellableSet.insert(
            MainAppContext.shared.openChatThreadRequest.sink { [weak self] (threadID) in
                guard let self = self else { return }
                self.switchTo(tab: .chat)
        })

        cancellableSet.insert(
            MainAppContext.shared.service.didConnect.sink { [weak self] in
                guard let self = self else { return }
                
                // for registration case where we want to present the group preview
                // after user registers and connect, and also when user have slow connectivity
                // when opening the app
                self.presentGroupPreviewIfNeeded()
            }
        )

        cancellableSet.insert(
            MainAppContext.shared.didGetGroupInviteToken.sink { [weak self] in
                guard let self = self else { return }
                self.presentGroupPreviewIfNeeded()
            }
        )

        cancellableSet.insert(
            MainAppContext.shared.didTapIntent.sink(receiveValue: { [weak self] intent in
                if (intent as? INSendMessageIntent) != nil {
                    guard let self = self else { return }
                    DDLogInfo("HomeViewController/cancellableSet/didTapIntentNotification chat opened from intent donation")
                    
                    self.switchTo(tab: .chat)
                }
            })
        )

        cancellableSet.insert(MainAppContext.shared.openPostInFeed.sink(receiveValue: { [weak self] postID in
            guard let self = self else {
                return
            }
            self.dismiss(animated: false)
            self.switchTo(tab: .home)

            guard let feedNavigationController = self.selectedViewController as? UINavigationController else {
                DDLogError("HomeViewController/openPostInFeed/unexpected view controller hierarchy")
                return
            }

            feedNavigationController.popToRootViewController(animated: false)

            guard let feedViewController = feedNavigationController.topViewController as? FeedCollectionViewController else {
                DDLogError("HomeViewController/openPostInFeed/unexpected view controller hierarchy")
                return
            }

            feedViewController.scrollTo(postId: postID)
        }))

        // When the app just started (had been force-quit before)
        if let metadata = NotificationMetadata.fromUserDefaults() {
            processNotification(metadata: metadata)
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateTabBarBackgroundEffect()
        }
    }

    private func updateTabBarBackgroundEffect() {
        let blurStyle: UIBlurEffect.Style = traitCollection.userInterfaceStyle == .light ? .systemMaterial : .systemChromeMaterial
        tabBar.standardAppearance.backgroundEffect = UIBlurEffect(style: blurStyle)
    }

    static let tabBarItemImageInsets: UIEdgeInsets = {
        let vInset: CGFloat = UIDevice.current.hasNotch ? 3 : 3 // currently same but can be used to adjust in the future
        let sizeAdjust: CGFloat = -2
        let topInset = vInset + sizeAdjust
        let bottomInset = -vInset + sizeAdjust

        return UIEdgeInsets(top: topInset, left: sizeAdjust, bottom: bottomInset, right: sizeAdjust)
    }()

    private func feedNavigationController() -> UINavigationController {
        let feedViewController = getFeedViewController()
        let navigationController = UINavigationController(rootViewController: feedViewController)
        navigationController.tabBarItem.image = UIImage(named: "TabBarHome")?.withTintColor(.tabBar, renderingMode: .alwaysOriginal)
        navigationController.tabBarItem.selectedImage = UIImage(named: "TabBarHomeActive")
        navigationController.tabBarItem.imageInsets = HomeViewController.tabBarItemImageInsets
        return navigationController
    }
    
    private func getFeedViewController() -> UIViewController {
        DDLogInfo("HomeViewController/getFeedViewController/loading FeedViewController")
        return FeedViewController(
            title: Localizations.titleHome,
            fetchRequest: FeedDataSource.homeFeedRequest())
    }

    private func groupsNavigationController() -> UINavigationController {
        let groupsViewController = GroupGridViewController()
        groupsViewController.title = Localizations.titleGroups

        let navigationController = UINavigationController(rootViewController: groupsViewController)
        navigationController.tabBarItem.image = UIImage(named: "TabBarGroups")?.withTintColor(.tabBar, renderingMode: .alwaysOriginal)
        navigationController.tabBarItem.selectedImage = UIImage(named: "TabBarGroupsActive")
        navigationController.tabBarItem.imageInsets = HomeViewController.tabBarItemImageInsets
        return navigationController
    }

    private func cameraNavigationController() -> UIViewController {
        if DeveloperSetting.showPhotoSuggestions {
            let controller = SharedAlbumViewController()
            controller.title = Localizations.titleSuggestions

            let navigationController = UINavigationController(rootViewController: controller)
            navigationController.tabBarItem.image = UIImage(systemName: "wand.and.stars.inverse")
            navigationController.tabBarItem.selectedImage = UIImage(systemName: "wand.and.stars")
            navigationController.tabBarItem.imageInsets = HomeViewController.tabBarItemImageInsets
            return navigationController
        } else {

            let controller = CameraTabPlaceholderViewController()

            controller.title = Localizations.fabAccessibilityCamera
            controller.tabBarItem.image = UIImage(named: "TabBarCamera")?.withTintColor(.tabBar, renderingMode: .alwaysOriginal)
            controller.tabBarItem.selectedImage = UIImage(named: "TabBarCameraActive")?.withRenderingMode(.alwaysTemplate)
            controller.tabBarItem.imageInsets = HomeViewController.tabBarItemImageInsets

            return controller
        }
    }

    private func chatsNavigationController() -> UINavigationController {
        let navigationController = UINavigationController(rootViewController: ChatListViewController(title: Localizations.titleChats))
        navigationController.tabBarItem.image = UIImage(named: "TabBarChats")?.withTintColor(.tabBar, renderingMode: .alwaysOriginal)
        navigationController.tabBarItem.selectedImage = UIImage(named: "TabBarChatsActive")
        navigationController.tabBarItem.imageInsets = HomeViewController.tabBarItemImageInsets
        return navigationController
    }

    private func activityNavigationController() -> UINavigationController {
        let vc = NotificationsViewController()
        let navigationController = UINavigationController(rootViewController: vc)

        vc.title = Localizations.titleActivity
        navigationController.tabBarItem.image = UIImage(named: "TabBarActivity")?.withTintColor(.tabBar, renderingMode: .alwaysOriginal)
        navigationController.tabBarItem.selectedImage = UIImage(named: "TabBarActivityActive")
        navigationController.tabBarItem.imageInsets = HomeViewController.tabBarItemImageInsets

        return navigationController
    }

    private func updateGroupsNavigationControllerBadge(_ count: Int) {
        guard let controller = viewControllers?[1] else { return }

        var unseenSampleGroupWelcomePost = 0
        let sharedNUX = MainAppContext.shared.nux
        if let seen = sharedNUX.sampleGroupWelcomePostSeen(), !seen {
            unseenSampleGroupWelcomePost = 1
        }
        let badge = count + unseenSampleGroupWelcomePost

        controller.tabBarItem.badgeValue = badge == 0 ? nil : String(badge)
    }

    private func updateChatNavigationControllerBadge(_ count: Int) {
        if let controller = chatsController {
            controller.tabBarItem.badgeValue = count == 0 ? nil : String(count)
        }
    }

    private func updateActivityNavigationControllerBadge(_ count: Int) {
        if let activityController = activityController {
            // we don't want a number on the badge, just the red dot with a smaller white dot inside
            activityController.tabBarItem.badgeValue = count == 0 ? nil : "⦁"
        }
    }

    private func processNotification(metadata: NotificationMetadata) {
        let oldSelectedIndex = selectedIndex
        if let selected = selectedViewController, selected.presentedViewController != nil {
            selected.dismiss(animated: false) {
                self.processNotification(metadata: metadata)
            }
            return
        }

        if metadata.isFeedNotification {
            selectedIndex = TabBarSelection.home.index
        } else if metadata.isFeedGroupAddNotification {
            selectedIndex = TabBarSelection.group.index
        } else if metadata.isChatGroupAddNotification {
            selectedIndex = TabBarSelection.chat.index
        } else if metadata.isChatNotification || metadata.isContactNotification {
            // we need to show the chatscreen when the notification tapped is chat/friend/inviter notification.
            selectedIndex = TabBarSelection.chat.index
        } else if metadata.isMissedCallNotification {
            metadata.removeFromUserDefaults()
            // Default to audio call.
            var callType: CallType = .audio
            if metadata.contentType == .missedAudioCall {
                callType = .audio
            } else if metadata.contentType == .missedVideoCall {
                callType = .video
            }
            MainAppContext.shared.callManager.startCall(to: metadata.fromId, type: callType) { [weak self] result in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        DDLogInfo("HomeViewController/startCall/success")
                    case .failure:
                        DDLogInfo("HomeViewController/startCall/failure")
                        let alert = self.getFailedCallAlert()
                        self.present(alert, animated: true)
                    }
                }
            }
        }
        DDLogDebug("HomeViewController/processNotification/selectedIndex: \(selectedIndex)/oldSelectedIndex: \(oldSelectedIndex)")
        ((selectedViewController as? UINavigationController)?.children.first as? UIViewControllerHandleTapNotification)?.processNotification(metadata: metadata)
    }
    
    private func presentGroupPreviewIfNeeded() {
        guard let inviteToken = MainAppContext.shared.userData.groupInviteToken else { return }
        DDLogInfo("HomeViewController/presentGroupPreviewIfNeeded/inviteToken/\(inviteToken)")
        guard MainAppContext.shared.userData.isLoggedIn else {
            DDLogVerbose("HomeViewController/presentGroupPreviewIfNeeded/inviteToken/\(inviteToken)/not logged in")
            return
        }
        guard MainAppContext.shared.service.isConnected else {
            DDLogVerbose("HomeViewController/presentGroupPreviewIfNeeded/inviteToken/\(inviteToken)/not connected")
            return
        }

        MainAppContext.shared.chatData.getGroupPreviewWithLink(inviteLink: inviteToken) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let groupInviteLink):
                let groupID = groupInviteLink.group.gid

                let pushNames = groupInviteLink.group.members.reduce(into: [UserID: String]()) { (dict, member) in
                    let userID = String(member.uid)
                    let pushName = member.name
                    guard !userID.isEmpty && !pushName.isEmpty else { return }
                    dict[userID] = pushName
                }
                if !pushNames.isEmpty {
                    MainAppContext.shared.contactStore.addPushNames(pushNames)
                }

                let viewContext = MainAppContext.shared.chatData.viewContext
                if MainAppContext.shared.chatData.chatGroupMember(groupId: groupID, memberUserId: MainAppContext.shared.userData.userId, in: viewContext) != nil {
                    DDLogVerbose("HomeViewController/presentGroupPreviewIfNeeded/inviteToken/\(inviteToken)/already member")
                    MainAppContext.shared.groupFeedFromGroupTabPresentRequest.send(groupID)
                } else {
                    DDLogVerbose("HomeViewController/presentGroupPreviewIfNeeded/inviteToken/\(inviteToken)/present")

                    // dismiss any presented views including compose and activity center
                    self.dismiss(animated: false)

                    let vc = GroupInvitePreviewViewController(inviteToken: inviteToken, groupInviteLink: groupInviteLink)
                    self.present(vc, animated: true)
                }
                DDLogVerbose("HomeViewController/presentGroupPreviewIfNeeded/inviteToken/\(inviteToken)/remove inviteToken")
                MainAppContext.shared.userData.groupInviteToken = nil
            case .failure(let error):
                DDLogInfo("HomeViewController/getGroupPreviewWithLink/error \(error)")

                let alert = UIAlertController( title: nil, message: Localizations.groupPreviewGetInfoErrorInvalidLink, preferredStyle: .alert)
                alert.addAction(.init(title: Localizations.buttonOK, style: .default, handler: { _ in
                    self.dismiss(animated: true)
                }))
                self.present(alert, animated: true, completion: nil)
                DDLogVerbose("HomeViewController/presentGroupPreviewIfNeeded/inviteToken/\(inviteToken)/remove inviteToken")
                MainAppContext.shared.userData.groupInviteToken = nil
            }
        }
    }

    private func showHomeTabIndicatorIfNeeded() {
        if selectedIndex == TabBarSelection.home.index { // user is on the main feed
            guard let nc = self.viewControllers?[0] as? UINavigationController else { return }
            guard let vc = nc.topViewController as? FeedViewController else { return }
            guard !vc.isNearTop(100) else { return } // exit if user is at the top of the main feed
        }

        setTabBarDot(index: 0, count: 1)
    }

    private func removeHomeTabIndicator() {
        setTabBarDot(index: 0, count: 0)
    }

    private func setTabBarDot(index: Int, count: Int) {
        guard let barItems = tabBar.items else {
            return
        }

        let tag = 1000

        var tabBarButtons = [UIView]()

        for subview in tabBar.subviews {
            let className = String(describing: type(of: subview))
            guard className == "UITabBarButton" else { continue }
            tabBarButtons.append(subview)
        }

        guard index > -1 && index < tabBarButtons.count - 1 else { return }

        let tabBarItemView = tabBarButtons[index]

        for subview in tabBarItemView.subviews {
            if subview.tag == tag {
                subview.removeFromSuperview()
            }
        }

        guard count > 0 else { return }

        let barItemWidth = tabBarItemView.bounds.width

        let selectedItemWidth: CGFloat = barItems[index].selectedImage?.size.width ?? barItemWidth
        let x: CGFloat = (barItemWidth + selectedItemWidth) * 0.5 - 5
        let y: CGFloat = 8
        let size: CGFloat = 6

        let dot = UIView(frame: CGRect(x: x, y: y, width: size, height: size))
        dot.tag = tag
        dot.backgroundColor = .primaryBlue
        dot.layer.cornerRadius = size/2

        tabBarItemView.addSubview(dot)
    }
    
    /// Describes the status of which tab is selected
    enum TabBarSelection {
        case home
        case group
        case camera
        case chat
        case activity

        var index: Int {
            switch self {
            case .home:
                return 0
            case .group:
                return 1
            case .camera:
                return 2
            case .chat:
                return 3
            case .activity:
                return 4
            }
        }
    }
    
    /// Switches the view to be for whichever tab is selected
    /// - Parameter tab: Tab to display as a `TabBarSelection`
    private func switchTo(tab: TabBarSelection) {
        self.selectedIndex = tab.index
    }
}

extension HomeViewController: UITabBarControllerDelegate {

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        // Tap on selected tab again to make it scroll to the top.
        if tabBarController.selectedViewController == viewController {
            if let navigationController = viewController as? UINavigationController,
               let viewController = navigationController.topViewController as? UIViewControllerScrollsToTop {
                viewController.scrollToTop(animated: true)
            }
        }

        if viewController is CameraTabPlaceholderViewController {
            let start = CGPoint(x: tabBar.frame.midX, y: tabBar.frame.midY - 20)
            let vc = CameraPostViewController(startPoint: start)
            vc.delegate = self

            present(vc, animated: true)

            return false
        }

        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        guard
            selectedIndex != TabBarSelection.camera.index,
            let navigationController = viewController as? UINavigationController,
            navigationController.topViewController !== navigationController.viewControllers.first
        else {
            return
        }

        navigationController.popToRootViewController(animated: false)
    }
}

// MARK: - CameraPostViewControllerDelegate methods

extension HomeViewController: CameraPostViewControllerDelegate {

    func cameraPostViewController(_ viewController: CameraPostViewController, didPostTo destinations: [ShareDestination]) {
        let destinations = ShareDestination.privacySort(destinations)
        guard let firstDestination = destinations.first else {
            return
        }

        let secondDestination = destinations.count > 1 ? destinations[1] : nil
        var index = TabBarSelection.home.index
        var shouldNavigateToThread = false

        switch (firstDestination, secondDestination) {
        case (.feed(_), _):
            // to go the top of home feed
            break
        case (.group(_, let firstType, _), .group(_, let secondType, _)) where firstType == .groupFeed && secondType == .groupFeed:
            // at least two group feed posts; go to groups grid
            index = TabBarSelection.group.index
        case (.group(_, let type, _), _) where type == .groupFeed:
            // only one group feed destination; go to top of the home feed
            break

        case (.group(_, let firstType, _), .group(_, let secondType, _)) where firstType == .groupChat && secondType == .groupChat:
            // at least two group chat messages; go to chat list
            index = TabBarSelection.chat.index
        case (.group(_, let type, _), .contact(_, _, _)) where type == .groupChat:
            // one group chat and at least one one-on-one chat; go to chat list
            index = TabBarSelection.chat.index
        case (.group(_, let type, _), _) where type == .groupChat:
            // only one group chat destination; go to the thread
            index = TabBarSelection.chat.index
            shouldNavigateToThread = true

        case (.contact(_, _, _), .contact(_, _, _)):
            // at least two one-on-one messages; go to chat list
            index = TabBarSelection.chat.index
        case (.contact(_, _, _), _):
            // only one one-on-one message; go to the thread
            index = TabBarSelection.chat.index
            shouldNavigateToThread = true

        default:
            break
        }

        selectedIndex = index
        ((selectedViewController as? UINavigationController)?.topViewController as? UIViewControllerScrollsToTop)?.scrollToTop(animated: false)

        if shouldNavigateToThread {
            let handler = ((selectedViewController as? UINavigationController)?.children.first as? UIViewControllerHandleShareDestination)
            handler?.route(to: firstDestination)
        }
    }
}

// MARK: Presenting Various View Controllers

extension HomeViewController {

    private func presentActivityViewController(forItems items: [Any]) {
        let activityViewController = UIActivityViewController(activityItems: items, applicationActivities: nil)
        self.present(activityViewController, animated: true)
    }

}

fileprivate let tabBarItemTag: Int = 10090
extension UITabBar {
    public func addItemBadge(atIndex index: Int) {
        guard let itemCount = self.items?.count, itemCount > 0 else {
            return
        }
        guard index < itemCount else {
            return
        }
        removeItemBadge(atIndex: index)

        let badgeView = UIView()
        badgeView.tag = tabBarItemTag + Int(index)
        badgeView.layer.cornerRadius = 5
        badgeView.backgroundColor = UIColor.red

        let tabFrame = self.frame
        let percentX = (CGFloat(index) + 0.56) / CGFloat(itemCount)
        let x = (percentX * tabFrame.size.width).rounded(.up)
        let y = (CGFloat(0.1) * tabFrame.size.height).rounded(.up)
        badgeView.frame = CGRect(x: x, y: y, width: 10, height: 10)
        addSubview(badgeView)
    }

    //return true if removed success.
    @discardableResult
    public func removeItemBadge(atIndex index: Int) -> Bool {
        for subView in self.subviews {
            if subView.tag == (tabBarItemTag + index) {
                subView.removeFromSuperview()
                return true
            }
        }
        return false
    }
}

private extension Localizations {

    static var groupPreviewGetInfoErrorInvalidLink: String {
        NSLocalizedString("group.preview.get.info.error.invalid.link", value: "The group invite link is invalid", comment: "Text for alert box when the user clicks on an invalid group invite link")
    }
    
}
