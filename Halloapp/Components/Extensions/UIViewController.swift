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
        let makeNavigationBarOpaque = scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top
        let isNavigationBarOpaque = self.navigationItem.standardAppearance?.backgroundEffect == nil
        guard makeNavigationBarOpaque != isNavigationBarOpaque else { return }
        if makeNavigationBarOpaque {
            self.navigationItem.standardAppearance = .opaqueAppearance
        } else {
            self.navigationItem.standardAppearance = .translucentAppearance
        }
    }

}
