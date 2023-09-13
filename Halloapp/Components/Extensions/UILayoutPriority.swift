//
//  UILayoutPriority.swift
//  HalloApp
//
//  Created by Tanveer on 8/29/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit

extension UILayoutPriority {

    static var breakable: Self {
        UILayoutPriority(999)
    }

    static var minimal: Self {
        UILayoutPriority(1)
    }
}
