//
//  RoundedRectChevronButton.swift
//  HalloApp
//
//  Created by Tanveer on 8/20/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit

/// Similar to `RoundedRectButton` but with a chevron symbol that localizes.
class RoundedRectChevronButton: RoundedRectButton {

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        let font = UIFont.systemFont(forTextStyle: .body, weight: .medium, maximumPointSize: 22)
        let config = UIImage.SymbolConfiguration(font: font)
        let image = UIImage(systemName: "chevron.forward", withConfiguration: config)

        titleLabel?.font = font
        setImage(image, for: .normal)
        imageView?.contentMode = .center

        let imageInset: CGFloat = 10
        switch effectiveUserInterfaceLayoutDirection {
        case .rightToLeft:
            semanticContentAttribute = .forceLeftToRight
            imageView?.semanticContentAttribute = .forceRightToLeft
            imageEdgeInsets = UIEdgeInsets(top: 0, left: -imageInset, bottom: 0, right: imageInset)
        case .leftToRight:
            semanticContentAttribute = .forceRightToLeft
            imageView?.semanticContentAttribute = .forceLeftToRight
            imageEdgeInsets = UIEdgeInsets(top: 0, left: imageInset, bottom: 0, right: -imageInset)
        @unknown default:
            break
        }
    }
}
