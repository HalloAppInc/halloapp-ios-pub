//
//  SystemShareProvider.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 10/11/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import UIKit

class SystemShareProvider: ShareProvider {

    static var analyticsShareDestination: String {
        return "system"
    }

    static var title: String {
        return NSLocalizedString("shareprovider.system.title", value: "Share via", comment: "Title for button launching system share dialog")
    }

    static var canShare: Bool {
        return true
    }

    static func share(text: String?, image: UIImage?, completion: ShareProviderCompletion?) {
        guard let currentViewController = UIViewController.currentViewController else {
            DDLogError("SystemShareProvider/unable to find view controller to present on")
            completion?(.failed)
            return
        }

        var activityItems: [Any] = []

        if let text = text {
            activityItems.append(text)
        }

        if let image = image {
            activityItems.append(image)
        }

        let activityViewController = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        activityViewController.completionWithItemsHandler = { activityType, completed, returnedItems, activityError in
            if completed {
                completion?(.success)
            } else {
                if activityError != nil {
                    completion?(.failed)
                } else {
                    completion?(.cancelled)
                }
            }

        }
        currentViewController.present(activityViewController, animated: true, completion: nil)
    }
}
