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

    private func commonSetup() {
        self.delegate = self

        // Set background color for navigation bar and search bar system-wide.
        UINavigationBar.appearance().standardAppearance = .opaqueAppearance
        // Setting background color through appearance proxy seems to be the only way
        // to modify navigation bar in SwiftUI's NavigationView.
        UINavigationBar.appearance().backgroundColor = .primaryBg
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
        
        tabBarViewControllers = [
            feedNavigationController(),
            groupsNavigationController(),
            chatsNavigationController(),
            profileNavigationController()
        ]
        
        setViewControllers(tabBarViewControllers, animated: false)

        /*
         The home tab indicator starts hidden on each new app open (does not count background/foreground)
         It shows when a new post (not shared) comes in if the user is not actively viewing the top of the main feed
         It's removed when the user scrolls to the top of the main feed or when the total unseen posts is 0
         (ie. user scrolls to middle of feed, goes to groups tab, views all unread, indicator should go away)
         */
        cancellableSet.insert(MainAppContext.shared.feedData.didGetNewFeedPost.sink { [weak self] _ in
            self?.showHomeTabIndicatorIfNeeded()
        })
        // Can ignore shared (old) merged feed posts as they will not be sent when connection is passive
        cancellableSet.insert(MainAppContext.shared.feedData.didMergeFeedPost.sink { [weak self] feedPostID in
            guard let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostID) else { return }
            let isInbound = feedPost.userId != MainAppContext.shared.userData.userId
            if isInbound {
                self?.showHomeTabIndicatorIfNeeded()
            }
        })
        cancellableSet.insert(MainAppContext.shared.feedData.didGetRemoveHomeTabIndicator.sink { [weak self] in
            self?.removeHomeTabIndicator()
        })
        cancellableSet.insert(MainAppContext.shared.feedData.didGetUnreadFeedCount.sink { [weak self] (count) in
            guard count == 0 else { return }
            self?.removeHomeTabIndicator()
        })

        cancellableSet.insert(
            MainAppContext.shared.chatData.didChangeUnreadThreadGroupsCount.sink { [weak self] (count) in
                guard let self = self else { return }
                self.updateGroupsNavigationControllerBadge(count)
        })
        MainAppContext.shared.chatData.updateUnreadThreadGroupsCount()

        cancellableSet.insert(
            MainAppContext.shared.chatData.didChangeUnreadThreadCount.sink { [weak self] (count) in
                guard let self = self else { return }
                self.updateChatNavigationControllerBadge(count)
        })
        MainAppContext.shared.chatData.updateUnreadChatsThreadCount()

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
        guard ContactStore.contactsAccessAuthorized else {
            DDLogInfo("HomeViewController/getFeedViewController/loading FeedPermissionDeniedController")
            let feedPermissionDeniedViewController = FeedPermissionDeniedController(title: Localizations.titleHome)
            return feedPermissionDeniedViewController
        }
        DDLogInfo("HomeViewController/getFeedViewController/loading FeedViewController")
        return FeedViewController(
            title: Localizations.titleHome,
            fetchRequest: FeedDataSource.homeFeedRequest())
    }

    private func groupsNavigationController() -> UINavigationController {
        let navigationController = UINavigationController(rootViewController: GroupsListViewController(title: Localizations.titleGroups))
        navigationController.tabBarItem.image = UIImage(named: "TabBarGroups")?.withTintColor(.tabBar, renderingMode: .alwaysOriginal)
        navigationController.tabBarItem.selectedImage = UIImage(named: "TabBarGroupsActive")
        navigationController.tabBarItem.imageInsets = HomeViewController.tabBarItemImageInsets
        return navigationController
    }

    private func chatsNavigationController() -> UINavigationController {
        let navigationController = UINavigationController(rootViewController: ChatListViewController(title: Localizations.titleChats))
        navigationController.tabBarItem.image = UIImage(named: "TabBarChats")?.withTintColor(.tabBar, renderingMode: .alwaysOriginal)
        navigationController.tabBarItem.selectedImage = UIImage(named: "TabBarChatsActive")
        navigationController.tabBarItem.imageInsets = HomeViewController.tabBarItemImageInsets
        return navigationController
    }

    private func profileNavigationController() -> UINavigationController {
        let navigationController = UINavigationController(rootViewController: SettingsViewController(title: Localizations.titleSettings))
        navigationController.tabBarItem.image = UIImage(named: "TabBarSettings")?.withTintColor(.tabBar, renderingMode: .alwaysOriginal)
        navigationController.tabBarItem.selectedImage = UIImage(named: "TabBarSettingsActive")
        navigationController.tabBarItem.imageInsets = HomeViewController.tabBarItemImageInsets
        return navigationController
    }

    private func updateGroupsNavigationControllerBadge(_ count: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let controller = self.viewControllers?[1] else { return }

            var unseenSampleGroupWelcomePost = 0
            let sharedNUX = MainAppContext.shared.nux
            if let seen = sharedNUX.sampleGroupWelcomePostSeen(), !seen {
                unseenSampleGroupWelcomePost = 1
            }
            let badge = count + unseenSampleGroupWelcomePost

            controller.tabBarItem.badgeValue = badge == 0 ? nil : String(badge)
        }
    }

    private func updateChatNavigationControllerBadge(_ count: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let controller = self.viewControllers?[2] {
                controller.tabBarItem.badgeValue = count == 0 ? nil : String(count)
            }
        }
    }

    private func processNotification(metadata: NotificationMetadata) {
        view.window?.rootViewController?.dismiss(animated: false, completion: nil)

        if metadata.isFeedNotification {
            selectedIndex = 0
        } else if metadata.isGroupAddNotification {
            selectedIndex = 1
        } else if metadata.isChatNotification || metadata.isContactNotification {
            // we need to show the chatscreen when the notification tapped is chat/friend/inviter notification.
            selectedIndex = 2
        } else if metadata.isMissedCallNotification {
            metadata.removeFromUserDefaults()
            MainAppContext.shared.callManager.startCall(to: metadata.fromId) { [weak self] result in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        DDLogInfo("HomeViewController/startCall/success")
                    case .failure:
                        DDLogInfo("HomeViewController/startCall/failure")
                        let alert = self.getFailedCallAlertController()
                        self.present(alert, animated: true)
                    }
                }
            }
        }
        DDLogDebug("HomeViewController/processNotification/selectedIndex: \(selectedIndex)")
    }

    private func getFailedCallAlertController() -> UIAlertController {
        let alert = UIAlertController(
            title: Localizations.failedCallTitle,
            message: Localizations.failedCallNoticeText,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: { action in
            self.dismiss(animated: true, completion: nil)
        }))
        return alert
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

                if MainAppContext.shared.chatData.chatGroupMember(groupId: groupID, memberUserId: MainAppContext.shared.userData.userId) != nil {
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.currentlyOn() == .home { // user is on the main feed
                guard let nc = self.viewControllers?[0] as? UINavigationController else { return }
                guard let vc = nc.topViewController as? FeedViewController else { return }
                guard !vc.isNearTop(100) else { return } // exit if user is at the top of the main feed
            }
            self.setTabBarDot(index: 0, count: 1)
        }
    }

    private func removeHomeTabIndicator() {
        DispatchQueue.main.async { [weak self] in
            self?.setTabBarDot(index: 0, count: 0)
        }
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
    enum TabBarSelection: Int {
        case home = 0
        case group = 1
        case chat = 2
        case settings = 3
    }
    
    /// Switches the view to be for whichever tab is selected
    /// - Parameter tab: Tab to display as a `TabBarSelection`
    private func switchTo(tab: TabBarSelection) {
        self.selectedIndex = tab.rawValue
    }
    
    /// Gets the current tab that the `HomeViewController` is displaying
    /// - Returns: The `TabBarSelection` representing the currently displayed view
    private func currentlyOn() -> TabBarSelection {
        return TabBarSelection(rawValue: self.selectedIndex) ?? .home
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
        return true
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        guard let navigationController = (viewController as? UINavigationController) else {
            return
        }
        if(navigationController.topViewController != navigationController.viewControllers.first) {
            navigationController.popToRootViewController(animated: false)
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
