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

        self.tabBar.tintColor = .systemBlue

        // Set background color for navigation bar and search bar system-wide.
        UINavigationBar.appearance().standardAppearance = .opaqueAppearance
        // Settings background color throguh appearance proxy seems to be the only way
        // to modify navigation bar in SwiftUI's NavigationView.
        UINavigationBar.appearance().backgroundColor = .feedBackground
        UISearchBar.appearance().backgroundColor = .feedBackground

        self.cancellableSet.insert(
            MainAppContext.shared.service.didConnect.sink {
                if (UIApplication.shared.applicationState == .active) {
                    self.checkClientVersionExpiration()
                }
            }
        )
        
        self.cancellableSet.insert(
            MainAppContext.shared.chatData.didChangeUnreadThreadCount.sink { [weak self] (count) in
                guard let self = self else { return }
                self.updateChatNavigationControllerBadge(count)
        })
        MainAppContext.shared.chatData.updateUnreadThreadCount()
        
        // When the app was in the background
        self.cancellableSet.insert(
            MainAppContext.shared.didTapNotification.sink { [weak self] (metadata) in
                guard let self = self else { return }
                self.processNotification(metadata: metadata)
        })

        // Present UIActivityViewController from the tabbar view controller.
        self.cancellableSet.insert(
            MainAppContext.shared.activityViewControllerPresentRequest.sink { [weak self] (items) in
                guard let self = self else { return }
                self.presentActivityViewController(forItems: items)
        })
        
        // When the app just started (had been force-quit before)
        if let metadata = NotificationMetadata.fromUserDefaults() {
            self.processNotification(metadata: metadata)
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
        let vInset: CGFloat = UIDevice.current.hasNotch ? 4 : 2
        return UIEdgeInsets(top: vInset, left: 0, bottom: -vInset, right: 0)
    }()

    private func feedNavigationController() -> UINavigationController {
        let navigationController = UINavigationController(rootViewController: FeedViewController(title: Localizations.titleHome))
        navigationController.tabBarItem.image = UIImage(named: "TabBarHome")
        navigationController.tabBarItem.imageInsets = HomeViewController.tabBarItemImageInsets
        return navigationController
    }

    private func chatNavigationController() -> UINavigationController {
        let navigationController = UINavigationController(rootViewController: ChatListViewController(title: Localizations.titleMessages))
        navigationController.tabBarItem.image = UIImage(named: "TabBarMessages")
        navigationController.tabBarItem.imageInsets = HomeViewController.tabBarItemImageInsets
        return navigationController
    }
    
    private func profileNavigationController() -> UINavigationController {
        let navigationController = UINavigationController(rootViewController: ProfileViewController())
        navigationController.tabBarItem.image = UIImage(named: "TabBarProfile")
        navigationController.tabBarItem.imageInsets = HomeViewController.tabBarItemImageInsets
        return navigationController
    }

    private func checkClientVersionExpiration() {
        MainAppContext.shared.service.checkVersionExpiration { result in
            guard case .success(let numSecondsLeft) = result else {
                DDLogError("Client version check did not return expiration")
                return
            }
            
            let numDaysLeft = numSecondsLeft/86400
            if numDaysLeft < 10 {
                DDLogInfo("HomeViewController/updateNotice/days left: \(numDaysLeft)")
                let isExpired = numDaysLeft <= 0
                let alert = UIAlertController(title: Localizations.homeUpdateNoticeTitle, message: Localizations.homeUpdateNoticeText, preferredStyle: UIAlertController.Style.alert)
                let updateAction = UIAlertAction(title: Localizations.buttonUpdate, style: .default, handler: { action in
                    DDLogInfo("HomeViewController/updateNotice/update clicked")
                    if let customAppURL = URL(string: "itms-apps://apple.com/app/1501583052"){
                        if UIApplication.shared.canOpenURL(customAppURL) {
                            UIApplication.shared.open(customAppURL, options: [:], completionHandler: nil)
                        }
                    }
                })
                let dismissAction = UIAlertAction(title: isExpired ? Localizations.homeUpdateNoticeButtonExit : Localizations.buttonDismiss, style: .default, handler: { action in
                    DDLogInfo("HomeViewController/updateNotice/dismiss clicked")
                    if isExpired {
                        exit(0)
                    }
                })
                alert.addAction(updateAction)
                alert.addAction(dismissAction)
                self.present(alert, animated: true, completion: nil)
            }
        }
    }
    
    private func updateChatNavigationControllerBadge(_ count: Int) {
        DispatchQueue.main.async {
            if let controller = self.viewControllers?[1] {
                controller.tabBarItem.badgeValue = count == 0 ? nil : String(count)
            }
        }
    }
    
    private func processNotification(metadata: NotificationMetadata) {
        view.window?.rootViewController?.dismiss(animated: false, completion: nil)
        
        if metadata.isFeedNotification {
            selectedIndex = 0
        } else if metadata.isChatNotification {
            selectedIndex = 1
        }
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

private extension Localizations {

    static var homeUpdateNoticeTitle: String {
        NSLocalizedString("home.update.notice.title", value: "This version is out of date", comment: "Title of update notice shown to users who have old versions of the app")
    }
    
    static var homeUpdateNoticeText: String {
        NSLocalizedString("home.update.notice.text", value: "Please update to the latest version of HalloApp", comment: "Text shown to users who have old versions of the app")
    }
    
    static var homeUpdateNoticeButtonExit: String {
        NSLocalizedString("home.update.notice.button.exit", value: "Exit", comment: "Title for exit button that closes the app")
    }
    
}
