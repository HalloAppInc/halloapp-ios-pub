//
//  HomeViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/20/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI
import UIKit

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

class HomeViewController: UITabBarController {

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        self.setupViewControllers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setupViewControllers()
    }

    private func setupViewControllers() {
        let appearance = UITabBarAppearance()
        appearance.shadowColor = nil
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
        let vInset: CGFloat = UIDevice.current.hasNotch ? 10 : 4
        return UIEdgeInsets(top: vInset, left: 0, bottom: -vInset, right: 0)
    }()

    private func feedNavigationController() -> UINavigationController {
        let navigationController = UINavigationController(rootViewController: FeedViewController(title: "Home"))
        navigationController.tabBarItem.title = nil
        navigationController.tabBarItem.image = UIImage(named: "TabBarHome")
        navigationController.tabBarItem.imageInsets = HomeViewController.tabBarItemImageInsets
        return navigationController
    }

//    private func chatNavigationController() -> UINavigationController {
//        let messagesView = MessagesView().environment(\.managedObjectContext, AppContext.shared.contactStore.viewContext)
//        let chatListViewController = UIHostingController(rootView: messagesView)
//        chatListViewController.navigationItem.title = "Messages"
//        let navigationController = UINavigationController(rootViewController: chatListViewController)
//        navigationController.tabBarItem.title = nil
//        navigationController.tabBarItem.image = UIImage(named: "TabBarMessages")
//        navigationController.tabBarItem.imageInsets = HomeViewController.tabBarItemImageInsets
//        return navigationController
//    }

    private func chatNavigationController() -> UINavigationController {
        let navigationController = UINavigationController(rootViewController: ChatListViewController(title: "Messages"))
        navigationController.tabBarItem.title = nil
        navigationController.tabBarItem.image = UIImage(named: "TabBarMessages")
        navigationController.tabBarItem.imageInsets = HomeViewController.tabBarItemImageInsets
        return navigationController
    }
    
    private func profileNavigationController() -> UINavigationController {
        let navigationController = UINavigationController(rootViewController: ProfileViewController(title: "Profile"))
        navigationController.tabBarItem.title = nil
        navigationController.tabBarItem.image = UIImage(named: "TabBarProfile")
        navigationController.tabBarItem.imageInsets = HomeViewController.tabBarItemImageInsets
        return navigationController
    }

}
