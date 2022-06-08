//
//  UIViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import UIKit

protocol UIViewControllerScrollsToTop {

    func scrollToTop(animated: Bool)
}

extension UIViewController {

    func installAvatarBarButton() {
        let diameter: CGFloat = 30
        let avatar = AvatarViewButton()
        avatar.configure(userId: MainAppContext.shared.userData.userId, using: MainAppContext.shared.avatarStore)
        avatar.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            avatar.heightAnchor.constraint(equalToConstant: diameter),
            avatar.widthAnchor.constraint(equalToConstant: diameter),
        ])

        avatar.addTarget(self, action: #selector(presentProfile), for: .touchUpInside)
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: avatar)
    }

    @objc
    private func presentProfile(_ sender: AnyObject) {
        let profile = ProfileViewController(nibName: nil, bundle: nil)
        let nav = UINavigationController(rootViewController: profile)
        present(nav, animated: true)
    }
    
    func proceedIfConnected() -> Bool {
        guard MainAppContext.shared.service.isConnected else {
            let alert = UIAlertController(title: Localizations.alertNoInternetTitle, message: Localizations.alertNoInternetTryAgain, preferredStyle: .alert)
            alert.addAction(.init(title: Localizations.buttonOK, style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
            return false
        }
        return true
    }
    
    func getFailedCallAlert() -> UIAlertController {
        let alert = UIAlertController(title: Localizations.failedCallTitle,
                                    message: Localizations.failedCallNoticeText,
                             preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default) { action in
            self.dismiss(animated: true, completion: nil)
        })
        
        return alert
    }

    // returns the topmost view controller in the app
    class var currentViewController: UIViewController? {
        var keyWindow: UIWindow?
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            if [.foregroundInactive, .foregroundActive].contains(scene.activationState) {
                for window in scene.windows {
                    if window.isKeyWindow {
                        keyWindow = window
                        break
                    }
                }
            }
        }

        var viewController = keyWindow?.rootViewController
        while let presentedViewController = viewController?.presentedViewController {
            viewController = presentedViewController
        }

        return viewController
    }
}


protocol UIViewControllerHandleTapNotification {
    func processNotification(metadata: NotificationMetadata)
}
