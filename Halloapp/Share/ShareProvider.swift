//
//  ShareProvider.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 10/7/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CoreCommon
import UIKit

enum ShareProviderResult {
    case success, cancelled, failed, unknown
}

protocol ShareProvider {

    static var title: String { get }

    static var canShare: Bool { get }

    // images or text may be dropped depending on a share provider's capabilities.
    static func share(text: String?, image: UIImage?, completion: ((ShareProviderResult) -> Void)?)
}

protocol DestinationShareProvider: ShareProvider {

    static func share(destination: ABContact.NormalizedPhoneNumber?, text: String?, image: UIImage?, completion: ((ShareProviderResult) -> Void)?)
}

extension DestinationShareProvider {

    static func share(text: String?, image: UIImage?, completion: ((ShareProviderResult) -> Void)?) {
        share(destination: nil, text: text, image: image, completion: completion)
    }
}
