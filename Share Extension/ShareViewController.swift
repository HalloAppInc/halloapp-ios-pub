//
//  ShareViewController.swift
//  Share Extension
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import Foundation
import UIKit

enum ShareError: Error {
    case cancel
    case invalidData
    case notLoggedIn
    case mediaUploadFailed
}

enum ShareDestination {
    case feed
    case group(GroupListItem)
    case contact(ABContact)
}

extension Localizations {
    static var notLoggedInTitle: String {
        NSLocalizedString("share.notlogged.title", value: "You are not logged in", comment: "Title of alert when user is not logged in")
    }

    static var notLoggedInMessage: String {
        NSLocalizedString("share.notlogged.message", value: "Please open HalloApp and sign in.", comment: "Message of alert when user is not logged in")
    }
}

@objc(ShareViewController)
class ShareViewController: UINavigationController {

    private let serviceBuilder: ServiceBuilder = {
        return ProtoServiceCore(userData: $0, passiveMode: true, automaticallyReconnect: false)
    }
    // TODO: We should automatically reconnect here in-case of connection loss.
    // Otherwise, user could end up in a state where the share extension does not have an active connection.
    // This should be fine for now, enable this after server allows multiple passive connections.

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)

        initAppContext(ShareExtensionContext.self, serviceBuilder: serviceBuilder, contactStoreClass: ContactStore.self, appTarget: AppTarget.shareExtension)
        ShareExtensionContext.shared.coreService.startConnectingIfNecessary()

        // Reconnect when a user switches between HalloApp and extension
        NotificationCenter.default.addObserver(forName: .NSExtensionHostWillEnterForeground, object: nil, queue: nil) { _ in
            ShareExtensionContext.shared.coreService.startConnectingIfNecessary()
        }

        guard ShareExtensionContext.shared.userData.isLoggedIn else {
            DDLogError("ShareViewController/init/error  user is not logged in")

            let alert = UIAlertController(title: Localizations.notLoggedInTitle, message: Localizations.notLoggedInMessage, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default) { _ in
                self.extensionContext?.cancelRequest(withError: ShareError.notLoggedIn)
            })

            DispatchQueue.main.async {
                self.present(alert, animated: true)
            }

            return
        }

        setViewControllers([ShareDestinationViewController()], animated: false)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
