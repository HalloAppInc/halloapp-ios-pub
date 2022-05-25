//
//  LargeHitButton.swift
//  HalloApp
//
//  Created by Tanveer on 5/25/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit

/// A button with a larger tap target.
///
/// - note: I'd like to have it so that the target increase is set at initialization, but that would prevent
///         the ability to choose the button's `buttonType`.
class LargeHitButton: UIButton {
    var targetIncrease: CGFloat = 0 {
        didSet {
            if targetIncrease < 0 { targetIncrease = 0 }
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return bounds.insetBy(dx: -targetIncrease, dy: -targetIncrease).contains(point)
    }
}
