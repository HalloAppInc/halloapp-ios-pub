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
            .font: UIFont.gothamFont(ofFixedSize: 26, weight: .medium),
            .foregroundColor: UIColor.label.withAlphaComponent(0.75)
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
            appearance.backButtonAppearance = .transparentAppearance
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

extension UINavigationBar {
    func showNavBarSeparator() {
        let img = UIImage.pixelImageWithColor(color: UIColor.red)
        shadowImage = img
    }
}
extension UIImage {
    class func pixelImageWithColor(color: UIColor) -> UIImage? {
        let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        UIGraphicsBeginImageContext(rect.size)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        context.setFillColor(color.cgColor)
        context.fill(rect)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return image
    }
}
