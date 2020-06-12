//
//  UIViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit

extension UIViewController {

    func installLargeTitleUsingGothamFont() {
        guard self.title != nil else { return }
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle)
        let attributes: [ NSAttributedString.Key : Any ] =
            [ .font: UIFont.gothamFont(ofSize: fontDescriptor.pointSize, weight: .medium),
              .foregroundColor: UIColor.label.withAlphaComponent(0.2),
              .kern: -1.5 ]
        let titleLabel = UILabel()
        titleLabel.attributedText = NSAttributedString(string: self.title!, attributes: attributes)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(customView: titleLabel)
        self.navigationItem.title = nil
    }

    func updateNavigationBarStyleUsing(scrollView: UIScrollView) {
        let makeNavigationBarTransparent = scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top
        let isNavigationBarTransparent = self.navigationItem.standardAppearance?.backgroundEffect == nil
        guard makeNavigationBarTransparent != isNavigationBarTransparent else { return }
        if makeNavigationBarTransparent {
            self.navigationItem.standardAppearance = .transparentAppearance
        } else {
            self.navigationItem.standardAppearance = .translucentAppearance
        }
    }
}
