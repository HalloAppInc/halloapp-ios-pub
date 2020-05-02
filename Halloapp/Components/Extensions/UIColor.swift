//
//  UIColor.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit

extension UIColor {

    static var feedBackgroundColor: UIColor {
        get { UIColor { (traitCollection) -> UIColor in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor.black
            } else {
                return UIColor(red: 0xF3/0xFF, green: 0xF2/0xFF, blue: 0xEF/0xFF, alpha: 1)
            } }
        }
    }
}
