//
//  UINavigationBar.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/8/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit

extension UINavigationBarAppearance {

    class var noShadowAppearance: UINavigationBarAppearance {
        get {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithDefaultBackground()
            //TODO: proper mask image.
            appearance.setBackIndicatorImage(UIImage(named: "NavbarBack"), transitionMaskImage: UIImage(named: "NavbarBack"))
            appearance.shadowColor = nil
            return appearance
        }
    }
}
