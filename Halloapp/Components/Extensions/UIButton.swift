//
//  UIButton.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import UIKit

extension UIButton {

    func setBackgroundColor(_ color: UIColor, for state: UIControl.State) {
        setBackgroundImage(UIImage.singleColorImage(ofSize: CGSize(width: 1, height: 1), color: color), for: state)
    }

    // modified from https://stackoverflow.com/questions/4201959/label-under-image-in-uibutton/59666154#59666154
    func centerVerticallyWithPadding(padding : CGFloat) {
        guard
            let imageSize = self.imageView?.image?.size,
            let titleLabelSize = self.titleLabel?.intrinsicContentSize else {
            return
        }

        let isRTL = self.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let totalHeight = imageSize.height + titleLabelSize.height + padding

        self.imageEdgeInsets = UIEdgeInsets(
            top: max(0, -(totalHeight - imageSize.height)),
            left: 0.0,
            bottom: 0.0,
            right: -titleLabelSize.width
        ).flippedHorizontally(isRTL)

        self.titleEdgeInsets = UIEdgeInsets(
            top: (totalHeight - imageSize.height),
            left: -imageSize.width,
            bottom: -(totalHeight - titleLabelSize.height),
            right: 0.0
        ).flippedHorizontally(isRTL)

        self.contentEdgeInsets = UIEdgeInsets(
            top: 0.0,
            left: 0.0,
            bottom: titleLabelSize.height,
            right: 0.0
        ).flippedHorizontally(isRTL)
    }
}

private extension UIEdgeInsets {
    func flippedHorizontally(_ flipped: Bool) -> UIEdgeInsets {
        if flipped {
            return UIEdgeInsets(top: top, left: right, bottom: bottom, right: left)
        } else {
            return self
        }
    }
}
