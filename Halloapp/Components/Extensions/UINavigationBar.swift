//
//  UINavigationBar.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/8/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit

extension UINavigationBarAppearance {

    class var opaqueAppearance: UINavigationBarAppearance {
        get {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            //TODO: proper mask image.
            appearance.setBackIndicatorImage(UIImage(named: "NavbarBack"), transitionMaskImage: UIImage(named: "NavbarBack"))
            appearance.backgroundColor = .feedBackground
            appearance.shadowColor = nil
            return appearance
        }
    }

    class var translucentAppearance: UINavigationBarAppearance {
        get {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithDefaultBackground()
            //TODO: proper mask image.
            appearance.setBackIndicatorImage(UIImage(named: "NavbarBack"), transitionMaskImage: UIImage(named: "NavbarBack"))
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
            appearance.shadowColor = nil
            return appearance
        }
    }

    class var transparentAppearance: UINavigationBarAppearance {
        get {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            //TODO: proper mask image.
            appearance.setBackIndicatorImage(UIImage(named: "NavbarBack"), transitionMaskImage: UIImage(named: "NavbarBack"))
            return appearance
        }
    }

}
