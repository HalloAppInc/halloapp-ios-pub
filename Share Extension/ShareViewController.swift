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

enum ShareDestination: Equatable {
    case feed
    case group(GroupListItem)
    case contact(ABContact)

    static func == (lhs: ShareDestination, rhs: ShareDestination) -> Bool {
        switch (lhs, rhs) {
        case (.feed, .feed):
            return true
        case (.group(let lg), .group(let rg)):
            return lg.id == rg.id
        case (.contact(let lc), .contact(let rc)):
            return lc == rc
        default:
            return false
        }
    }
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
            DDLogInfo("ShareViewController/Observer/NSExtensionHostWillEnterForeground - try connecting")
            ShareExtensionContext.shared.coreService.startConnectingIfNecessary()
        }

        // When a user switches away from the extension - we want to abort the entire action here.
        NotificationCenter.default.addObserver(forName: .NSExtensionHostWillResignActive, object: nil, queue: nil) { _ in
            DDLogInfo("ShareViewController/Observer/NSExtensionHostWillResignActive - disconnect and cancel action")
            ShareExtensionContext.shared.coreService.disconnect()
            self.extensionContext?.cancelRequest(withError: ShareError.cancel)
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
