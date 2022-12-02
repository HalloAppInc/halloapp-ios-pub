//
//  UIFont.swift
//  Core
//
//  Created by Garrett on 11/21/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import UIKit

public extension UIFont {
    class func scaledSystemFont(ofSize fontSize: CGFloat, weight: UIFont.Weight = .regular, scalingTextStyle: UIFont.TextStyle = .body) -> UIFont {
        return UIFontMetrics(forTextStyle: scalingTextStyle).scaledFont(for: UIFont.systemFont(ofSize: fontSize, weight: weight))
    }
}
