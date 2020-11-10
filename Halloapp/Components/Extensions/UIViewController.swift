//
//  UIViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import UIKit

extension UIViewController {

    func installLargeTitleUsingGothamFont() {
        guard let title = title else { return }
        let fontDescriptor = UIFontDescriptor
            .preferredFontDescriptor(withTextStyle: .largeTitle)
            .addingAttributes([ .traits: [ UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold ] ])
        let attributes: [ NSAttributedString.Key : Any ] =
            [ .font: UIFont(descriptor: fontDescriptor, size: fontDescriptor.pointSize - 10), // 24 for default text size
              .foregroundColor: UIColor.label.withAlphaComponent(0.75),
              .kern: -0.01 ]
        let titleLabel = UILabel()
        titleLabel.attributedText = NSAttributedString(string: title, attributes: attributes)
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: titleLabel)
        navigationItem.title = nil
    }

    func updateNavigationBarStyleUsing(scrollView: UIScrollView) {
//        let makeNavigationBarOpaque = scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top
//        let isNavigationBarOpaque = self.navigationItem.standardAppearance?.backgroundEffect == nil
//        guard makeNavigationBarOpaque != isNavigationBarOpaque else { return }
//        if makeNavigationBarOpaque {
//            self.navigationItem.standardAppearance = .opaqueAppearance
//        } else {
//            self.navigationItem.standardAppearance = .translucentAppearance
//        }
    }

}
