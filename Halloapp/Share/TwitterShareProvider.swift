//
//  TwitterShareProvider.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 10/11/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Social
import UIKit

class TwitterShareProvider: ShareProvider {

    // Equivalent to SLServiceTypeTwitter, but avoids the deprecation warning
    private static let twitterServiceType = "com.apple.social.twitter"

    static var title: String {
        return NSLocalizedString("shareprovider.twitter.title", value: "Twitter", comment: "Name of Twitter app")
    }

    static var canShare: Bool {
        // SLComposeViewController.isAvailable(forServiceType: SLServiceTypeTwitter)  always returns false
        // Instead, check whether the Twitter app is installed. This will still fail if the user is not logged in,
        // but we don't have a detection mechanismfor that.
        guard let url = URL(string: "twitter://") else {
            return false
        }
        return UIApplication.shared.canOpenURL(url)
    }

    static func share(text: String?, image: UIImage?, completion: ((ShareProviderResult) -> Void)?) {
        guard let currentViewController = UIViewController.currentViewController,
              let composeViewController = SLComposeViewController(forServiceType: twitterServiceType) else {
            completion?(.failed)
            return
        }

        composeViewController.completionHandler = { result in
            switch result {
            case .done:
                completion?(.success)
            case .cancelled:
                completion?(.cancelled)
            @unknown default:
                completion?(.unknown)
            }
        }

        if let text = text {
            composeViewController.setInitialText(text)
        }

        if let image = image {
            composeViewController.add(image)
        }

        currentViewController.present(SocialComposeViewControllerHost(composeViewController: composeViewController), animated: true)
    }
}

extension TwitterShareProvider {

    // The Twitter SLComposeServiceViewController is old enough not to respect safeAreaInsets.
    // So, wrap it in another view controller that does.
    private class SocialComposeViewControllerHost: UIViewController {

        let composeViewController: SLComposeViewController

        init(composeViewController: SLComposeViewController) {
            self.composeViewController = composeViewController
            super.init(nibName: nil, bundle: nil)
            modalPresentationStyle = .pageSheet
            modalTransitionStyle = .coverVertical
        }

        required init?(coder: NSCoder) {
            fatalError()
        }

        override func viewDidLoad() {
            super.viewDidLoad()

            // Match chrome of SLComposeServiceViewController toolbars
            view.backgroundColor = UIColor {
                switch $0.userInterfaceStyle {
                case .dark:
                    return UIColor(white: 0.073, alpha: 1)
                default:
                    return UIColor(white: 0.997, alpha: 1)
                }
            }

            addChild(composeViewController)
            composeViewController.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(composeViewController.view)
            NSLayoutConstraint.activate([
                composeViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                composeViewController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                composeViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                composeViewController.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            ])
            composeViewController.didMove(toParent: self)
        }
    }
}
