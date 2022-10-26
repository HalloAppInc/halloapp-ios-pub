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
        let font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        let configuration = UIImage.SymbolConfiguration(font: font)
        let image = UIImage(systemName: "chevron.right", withConfiguration: configuration)

        titleLabel?.font = font
        imageView?.contentMode = .center

        let imageInset: CGFloat = 10
        switch effectiveUserInterfaceLayoutDirection {
        case .rightToLeft:
            setImage(image?.imageFlippedForRightToLeftLayoutDirection(), for: .normal)
            semanticContentAttribute = .forceLeftToRight
            imageView?.semanticContentAttribute = .forceRightToLeft
            imageEdgeInsets = UIEdgeInsets(top: 0, left: -imageInset, bottom: 0, right: imageInset)

        case .leftToRight:
            setImage(image?.imageFlippedForRightToLeftLayoutDirection(), for: .normal)
            semanticContentAttribute = .forceRightToLeft
            imageView?.semanticContentAttribute = .forceLeftToRight
            imageEdgeInsets = UIEdgeInsets(top: 0, left: imageInset, bottom: 0, right: -imageInset)
        @unknown default:
            break
        }
    }
}
