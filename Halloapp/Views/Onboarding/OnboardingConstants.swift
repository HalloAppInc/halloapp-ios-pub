//
//  OnboardingConstants.swift
//  HalloApp
//
//  Created by Tanveer on 8/15/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit

/// UI constants for the various onboarding view controllers.
struct OnboardingConstants {

    /// Distance of the advancing button from the bottom of the safe area when there is no keyboard displayed.
    static var bottomButtonBottomDistance: CGFloat {
        50
    }

    /// Distance of the advancing button from the top of the displayed keyboard.
    static var advanceButtonKeyboardBottomPadding: CGFloat {
        10
    }

    static var bottomButtonInsets: UIEdgeInsets {
        UIEdgeInsets(top: 12, left: 80, bottom: 12, right: 80)
    }

    static var bottomButtonPadding: CGFloat {
        10
    }
}

// MARK: - AdvanceButton

extension OnboardingConstants {

    class AdvanceButton: RoundedRectChevronButton {

        override init(frame: CGRect) {
            super.init(frame: frame)

            backgroundTintColor = .lavaOrange
            tintColor = .white
            contentEdgeInsets = .init(top: 12, left: 80, bottom: 12, right: 80)
        }

        required init(coder: NSCoder) {
            fatalError("AdvanceButton coder init not implemented...")
        }
    }
}

// MARK: - TextFieldContainerView

extension OnboardingConstants {

    class TextFieldContainerView: UIView {

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .feedPostBackground

            layoutMargins = .init(top: 10, left: 12, bottom: 10, right: 12)

            layer.cornerRadius = 10
            layer.shadowColor = UIColor.black.withAlphaComponent(0.15).cgColor
            layer.shadowOffset = CGSize(width: 0, height: 1)
            layer.shadowRadius = 0.75
            layer.shadowOpacity = 1
        }

        required init(coder: NSCoder) {
            fatalError("TextFieldShadowView coder init not implemented...")
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
        }
    }
}
