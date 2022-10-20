//
//  InstagramStoriesShareProvider.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 10/11/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit

class InstagramStoriesShareProvider: ShareProvider {

    private static let appID = "5856403147724250"

    static var title: String {
        return NSLocalizedString("shareprovider.instagramstories.title", value: "Instagram Stories", comment: "Title for sharing to instagram stories")
    }

    static var appIcon: UIImage? {
        return UIImage(named: "")
    }

    static var canShare: Bool {
        guard let url = URL(string: "instagram-stories://") else {
            return false
        }
        return UIApplication.shared.canOpenURL(url)
    }

    static func share(text: String?, image: UIImage?, completion: ((ShareProviderResult) -> Void)?) {
        guard let url = URL(string: "instagram-stories://share?source_application=\(Self.appID)") else {
            completion?(.failed)
            return
        }

        if let image = image {
            UIPasteboard.general.setItems([["com.instagram.sharedSticker.backgroundImage": image]],
                                          options: [.expirationDate: Date(timeIntervalSinceNow: 5 * 60)])
        }

        UIApplication.shared.open(url) { completed in
            completion?(completed ? .success : .failed)
        }
    }
}
