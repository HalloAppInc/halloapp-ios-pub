//
//  SwipeToExitGestureRecognizer.swift
//  HalloApp
//
//  Created by Stefan Fidanov on 24.06.22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import UIKit

enum SwipeToExitDirection {
    case vertical, horizontal
}

class SwipeToExitGestureRecognizer: UIPanGestureRecognizer {
    private let translationBeginThreshold: CGFloat = 20
    private let translationFinishThreshold: CGFloat = 100
    private let veleocityFinishThreshold: CGFloat = 600

    weak var animator: MediaListAnimator?
    var inProgress = false
    private(set) var start: CGPoint = .zero

    private let direction: SwipeToExitDirection
    private let action: () -> Void

    init(direction: SwipeToExitDirection, action: @escaping () -> Void) {
        self.direction = direction
        self.action = action

        super.init(target: nil, action: nil)

        addTarget(self, action: #selector(onSwipeExitAction(sender:)))
        maximumNumberOfTouches = 1
    }

    @objc private func onSwipeExitAction(sender: UIPanGestureRecognizer) {
        let translation = sender.translation(in: sender.view)
        let velocity = sender.velocity(in: sender.view)

        switch sender.state {
        case .changed:
            if inProgress {
                animator?.move(translation)
            } else if shouldBegin(translation: translation, velocity: velocity) {
                sender.setTranslation(.zero, in: sender.view)
                inProgress = true
                start = sender.location(in: sender.view)

                action()
            }
        case .cancelled:
            guard inProgress else { return }
            inProgress = false

            animator?.cancelInteractiveTransition()
        case .ended:
            guard inProgress else { return }
            inProgress = false

            if shouldFinish(translation: translation, velocity: velocity) {
                animator?.finishInteractiveTransition()
            } else {
                animator?.cancelInteractiveTransition()
            }
        default:
            break
        }
    }

    private func shouldBegin(translation: CGPoint, velocity: CGPoint) -> Bool {
        switch direction {
        case .vertical:
            return abs(translation.y) > translationBeginThreshold && abs(translation.y) > abs(translation.x)
        case .horizontal:
            return abs(translation.x) > translationBeginThreshold && abs(translation.x) > abs(translation.y)
        }
    }

    private func shouldFinish(translation: CGPoint, velocity: CGPoint) -> Bool {
        return (pow(translation.x, 2) + pow(translation.y, 2) > pow(translationFinishThreshold, 2)) ||
               (pow(velocity.x, 2) + pow(velocity.y, 2) > pow(veleocityFinishThreshold, 2))
    }
}
