//
//  UIButtonConfiguration+HalloApp.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 9/26/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit

extension UIButton.Configuration {

    static func filledCapsule(backgroundColor: UIColor = .lavaOrange, contentInsets: NSDirectionalEdgeInsets? = nil) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.filled()
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = backgroundColor
        configuration.cornerStyle = .capsule

        if let contentInsets {
            configuration.contentInsets = contentInsets
        }

        return configuration
    }

}
