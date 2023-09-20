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

        configuration?.image = UIImage(systemName: "chevron.forward")
        configuration?.imagePlacement = .trailing
        configuration?.imagePadding = 10
        configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributeContainer in
            var updatedAttributeContainer = attributeContainer
            updatedAttributeContainer.font = font
            return updatedAttributeContainer
        }
    }
}
