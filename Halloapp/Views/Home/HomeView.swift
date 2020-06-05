//
//  HomeViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/20/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI
import UIKit
import Combine

struct HomeView: UIViewControllerRepresentable {
    typealias UIViewControllerType = HomeViewController

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIViewControllerType {
        return HomeViewController()
    }

    func updateUIViewController(_ viewController: UIViewControllerType, context: Context) { }

    static func dismantleUIViewController(_ uiViewController: Self.UIViewControllerType, coordinator: Self.Coordinator) { }

    class Coordinator: NSObject {
        var parent: HomeView

        init(_ homeView: HomeView) {
            self.parent = homeView
        }
    }
}

class HomeViewController: UITabBarController, UITabBarControllerDelegate {

    private var cancellableSet: Set<AnyCancellable> = []
    
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
        
        let appearance = UITabBarAppearance()
        appearance.shadowColor = nil
        appearance.stackedLayoutAppearance.normal.badgeBackgroundColor = .lavaOrange
        appearance.stackedLayoutAppearance.normal.badgePositionAdjustment = UIOffset(horizontal: 0, vertical: 10 + Self.tabBarItemImageInsets.top)
        self.tabBar.standardAppearance = appearance
        self.updateTabBarBackgroundEffect()

        self.viewControllers = [
            feedNavigationController(),
            chatNavigationController(),
            profileNavigationController()
        ]

        if let tintColor = UIColor(named: "Tint") {
            self.view.tintColor = tintColor
            UIView.appearance().tintColor = tintColor
        }

        self.cancellableSet.insert(
            MainAppContext.shared.chatData.didChangeUnreadCount.sink { [weak self] (count) in
                guard let self = self else { return }
                self.updateChatNavigationControllerBadge(count)
            })
        MainAppContext.shared.chatData.updateUnreadMessageCount()
        
        // When the app was in the background
        self.cancellableSet.insert(
            MainAppContext.shared.didTapNotification.sink { [weak self] (status) in
                if !status { return }
                guard let self = self else { return }

                self.onTapNotification()
            }
        )
        
        // When the app just started (had been force-quit before)
        self.onTapNotification()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if self.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            self.updateTabBarBackgroundEffect()
        }
    }

    private func updateTabBarBackgroundEffect() {
        let blurStyle: UIBlurEffect.Style = self.traitCollection.userInterfaceStyle == .light ? .systemUltraThinMaterial : .systemChromeMaterial
        self.tabBar.standardAppearance.backgroundEffect = UIBlurEffect(style: blurStyle)
    }

    static let tabBarItemImageInsets: UIEdgeInsets = {
        let vInset: CGFloat = UIDevice.current.hasNotch ? 2 : 0
        return UIEdgeInsets(top: vInset, left: 0, bottom: -vInset, right: 0)
    }()

    private func feedNavigationController() -> UINavigationController {
        let navigationController = UINavigationController(rootViewController: FeedViewController(title: "Home"))
        navigationController.tabBarItem.image = UIImage(named: "TabBarHome")
        navigationController.tabBarItem.imageInsets = HomeViewController.tabBarItemImageInsets
        return navigationController
    }

    private func chatNavigationController() -> UINavigationController {
        let navigationController = UINavigationController(rootViewController: ChatListViewController(title: "Messages"))
        navigationController.tabBarItem.image = UIImage(named: "TabBarMessages")
        navigationController.tabBarItem.imageInsets = HomeViewController.tabBarItemImageInsets
        return navigationController
    }
    
    private func profileNavigationController() -> UINavigationController {
        let navigationController = UINavigationController(rootViewController: ProfileViewController(title: "Profile"))
        navigationController.tabBarItem.image = UIImage(named: "TabBarProfile")
        navigationController.tabBarItem.imageInsets = HomeViewController.tabBarItemImageInsets
        return navigationController
    }

    private func updateChatNavigationControllerBadge(_ count: Int) {
        DispatchQueue.main.async {
            if let controller = self.viewControllers?[1] {
                controller.tabBarItem.badgeValue = count == 0 ? nil : String(count)
            }
        }
    }
    
    private func onTapNotification() {
        // If the user tapped on a notification, switch to feed or chat tab
        if let metadata = UserDefaults.standard.object(forKey: NotificationKey.keys.userDefaults) as? [String: String] {
            if (metadata[NotificationKey.keys.contentType] == NotificationKey.contentType.chat) {
                self.selectedIndex = 1
            }
        }
    }
    
    // MARK: UITabBarControllerDelegate

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        // Tap on selected tab again to make it scroll to the top.
        if tabBarController.selectedViewController == viewController {
            if let navigationController = viewController as? UINavigationController {
                if let visibleViewController = navigationController.topViewController as? FeedTableViewController {
                    visibleViewController.scrollToTop(animated: true)
                }
            }
        }
        return true
    }
}
