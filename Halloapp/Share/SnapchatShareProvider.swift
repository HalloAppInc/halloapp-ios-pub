//
//  SnapchatShareProvider.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 11/10/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import SCSDKCoreKit
import SCSDKCreativeKit
import UIKit

class SnapchatShareProvider: ShareProvider {

    // Must hold a reference to snapAPI
    private static var snapAPI: SCSDKSnapAPI?

    static var analyticsShareDestination: String {
        return "snapchat"
    }

    static var title: String {
        return "Snapchat"
    }

    static var canShare: Bool {
        // Disable until we get prod API keys
        return false//URL(string: "snapchat://").flatMap { UIApplication.shared.canOpenURL($0) } ?? false
    }

    static func share(text: String?, image: UIImage?, completion: ((ShareProviderResult) -> Void)?) {
        SCSDKSnapKit.initSDK()

        let content: SCSDKSnapContent
        if let image = image {
            let photo = SCSDKSnapPhoto(image: image)
            content = SCSDKPhotoSnapContent(snapPhoto: photo)
        } else {
            content = SCSDKNoSnapContent()
        }
        content.caption = text

        let snapAPI = SCSDKSnapAPI()
        self.snapAPI = snapAPI
        snapAPI.startSending(content) { error in
            self.snapAPI = nil
            SCSDKSnapKit.deinitialize()
            completion?(error == nil ? .success : .failed)
        }
    }
}
