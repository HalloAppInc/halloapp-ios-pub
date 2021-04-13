//
//  HomeViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/20/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Contacts
import ContactsUI
import Core
import UIKit

class HomeViewController: UITabBarController {

    private var cancellableSet: Set<AnyCancellable> = []
    
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
        let fontAttributes = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 10.0, weight: .semibold),
                              NSAttributedString.Key.foregroundColor: UIColor.tabBar]
        UITabBarItem.appearance().setTitleTextAttributes(fontAttributes, for: .normal)
        
        let appearance = UITabBarAppearance()
        appearance.shadowColor = nil
        appearance.stackedLayoutAppearance.normal.badgeBackgroundColor = .lavaOrange
        appearance.stackedLayoutAppearance.normal.badgePositionAdjustment = UIOffset(horizontal: 2, vertical: 0 + Self.tabBarItemImageInsets.top)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = fontAttributes
        tabBar.standardAppearance = appearance

        tabBar.tintColor = .primaryBlue
        
        updateTabBarBackgroundEffect()

        viewControllers = [
            feedNavigationController(),
            groupsNavigationController(),
            chatsNavigationController(),
            profileNavigationController()
        ]

        cancellableSet.insert(
            MainAppContext.shared.feedData.didFindUnreadFeed.sink { [weak self] (count) in
                guard let self = self else { return }
                self.updateFeedNavigationControllerBadge(count)
        })
        MainAppContext.shared.feedData.checkForUnreadFeed()
        
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
                self.selectedIndex = 1
        })
        
        // Temporary listener for adding/removing the groups tab
        cancellableSet.insert(
            MainAppContext.shared.service.didConnect.sink { [weak self] in
                guard let self = self else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {                    
                    if ServerProperties.isGroupFeedEnabled {
                        if self.viewControllers?.count == 3 {
                            self.viewControllers = [
                                self.feedNavigationController(),
                                self.groupsNavigationController(),
                                self.chatsNavigationController(),
                                self.profileNavigationController()
                            ]
                        }
                    } else {
                        if self.viewControllers?.count == 4 {
                            self.viewControllers = [
                                self.feedNavigationController(),
                                self.chatsNavigationController(),
                                self.profileNavigationController()
                            ]
                        }
                    }
                }
        })
        
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
        let sizeAdjust: CGFloat = -1
        let topInset = vInset + sizeAdjust
        let bottomInset = -vInset + sizeAdjust
        
        return UIEdgeInsets(top: topInset, left: sizeAdjust, bottom: bottomInset, right: sizeAdjust)
    }()

    private func feedNavigationController() -> UINavigationController {
        let navigationController = UINavigationController(
            rootViewController: FeedViewController(
                title: Localizations.titleHome,
                fetchRequest: FeedDataSource.homeFeedRequest(combinedFeed: ServerProperties.isCombineFeedEnabled)))
        navigationController.tabBarItem.image = UIImage(named: "TabBarHome")?.withTintColor(.tabBar, renderingMode: .alwaysOriginal)
        navigationController.tabBarItem.selectedImage = UIImage(named: "TabBarHomeActive")
        navigationController.tabBarItem.imageInsets = HomeViewController.tabBarItemImageInsets
        return navigationController
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
    
    private func updateFeedNavigationControllerBadge(_ count: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.setTabBarDot(index: 0, count: count)
        }
    }
    
    private func updateGroupsNavigationControllerBadge(_ count: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard ServerProperties.isGroupFeedEnabled else { return }
            if let controller = self.viewControllers?[1] {
                controller.tabBarItem.badgeValue = count == 0 ? nil : String(count)
            }
        }
    }
    
    private func updateChatNavigationControllerBadge(_ count: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let controller = self.viewControllers?[ServerProperties.isGroupFeedEnabled ? 2 : 1] {
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
        
        let x = (barItemWidth * 0.5 + (barItems[index].selectedImage?.size.width ?? barItemWidth) / 2) - 5
        let y: CGFloat = 8
        let size: CGFloat = 6

        let dot = UIView(frame: CGRect(x: x, y: y, width: size, height: size))
        dot.tag = tag
        dot.backgroundColor = .primaryBlue
        dot.layer.cornerRadius = size/2

        tabBarItemView.addSubview(dot)
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
