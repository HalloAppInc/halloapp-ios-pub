//
//  UINavigationBar.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/8/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit

extension UINavigationBarAppearance {

    func configureTitleTextAttributes() {
        titleTextAttributes = [
            .font: UIFont.gothamFont(ofSize: 15, weight: .medium),
            .foregroundColor: UIColor.label.withAlphaComponent(0.9)
        ]
    }

    class var opaqueAppearance: UINavigationBarAppearance {
        get {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.configureTitleTextAttributes()
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
            appearance.configureTitleTextAttributes()
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
            appearance.configureTitleTextAttributes()
             //TODO: proper mask image.
            appearance.setBackIndicatorImage(UIImage(named: "NavbarBack"), transitionMaskImage: UIImage(named: "NavbarBack"))
            return appearance
        }
    }

}
