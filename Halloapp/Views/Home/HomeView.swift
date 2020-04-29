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

    private static func tintColor(for traitCollection: UITraitCollection) -> UIColor {
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor(white: 0.9, alpha: 1)
        } else {
            return UIColor(white: 0.1, alpha: 1)
        }
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
        UIView.appearance().tintColor = HomeViewController.tintColor(for: self.traitCollection)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if self.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            UIView.appearance().tintColor = HomeViewController.tintColor(for: self.traitCollection)
            self.updateTabBarBackgroundEffect()
        }
    }

    private func updateTabBarBackgroundEffect() {
        let blurStyle: UIBlurEffect.Style = self.traitCollection.userInterfaceStyle == .light ? .systemUltraThinMaterial : .systemChromeMaterial
        self.tabBar.standardAppearance.backgroundEffect = UIBlurEffect(style: blurStyle)
    }

    static let tabBarItemImageInsets = UIEdgeInsets(top: 8, left: 0, bottom: -8, right: 0)

    private func feedNavigationController() -> UINavigationController {
        let navigationController = UINavigationController(rootViewController: FeedViewController(title: "Home"))
        navigationController.tabBarItem.title = nil
        navigationController.tabBarItem.image = UIImage(named: "TabBarHome")
        navigationController.tabBarItem.imageInsets = HomeViewController.tabBarItemImageInsets
        return navigationController
    }

    private func chatNavigationController() -> UINavigationController {
        let messagesView = MessagesView().environment(\.managedObjectContext, AppContext.shared.contactStore.viewContext)
        let chatListViewController = UIHostingController(rootView: messagesView)
        chatListViewController.navigationItem.title = "Messages"
        let navigationController = UINavigationController(rootViewController: chatListViewController)
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
