//
//  UINavigationBar.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/8/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit

extension UIBarButtonItemAppearance {

    class var transparentAppearance: UIBarButtonItemAppearance {
        let appearance = UIBarButtonItemAppearance(style: .plain)
        appearance.normal.titleTextAttributes = [ NSAttributedString.Key.foregroundColor: UIColor.clear ]
        appearance.highlighted.titleTextAttributes = [ NSAttributedString.Key.foregroundColor: UIColor.clear ]
        appearance.disabled.titleTextAttributes = [ NSAttributedString.Key.foregroundColor: UIColor.clear ]
        appearance.focused.titleTextAttributes = [ NSAttributedString.Key.foregroundColor: UIColor.clear ]
        return appearance
    }
}

extension UINavigationBarAppearance {

    private func configureTitleTextAttributes() {
        titleTextAttributes = [
            .font: UIFont.gothamFont(ofFixedSize: 15, weight: .medium),
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
            appearance.backgroundColor = .primaryBg
            appearance.backButtonAppearance = .transparentAppearance
            appearance.buttonAppearance = UIBarButtonItemAppearance(style: .plain)
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
            appearance.backButtonAppearance = .transparentAppearance
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
            appearance.backButtonAppearance = .transparentAppearance
            return appearance
        }
    }

}
