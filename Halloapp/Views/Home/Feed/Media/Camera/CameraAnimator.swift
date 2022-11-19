//
//  CameraAnimator.swift
//  HalloApp
//
//  Created by Tanveer on 11/9/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import UIKit

fileprivate typealias MaskPaths = (small: UIBezierPath, large: UIBezierPath)

fileprivate protocol CameraAnimator: UIViewControllerAnimatedTransitioning, CAAnimationDelegate {
    var startPoint: CGPoint { get }
    var transitionContext: UIViewControllerContextTransitioning? { get }
}

extension CameraAnimator {

    var maskPaths: MaskPaths? {
        guard let height = transitionContext?.viewController(forKey: .to)?.view.bounds.height else {
            return nil
        }

        let smallFrame = CGRect(origin: startPoint, size: .zero)
        let largeFrame: CGRect

        let offscreen = CGPoint(x: smallFrame.minX, y: smallFrame.minY + height)
        let radius = sqrt(offscreen.x * offscreen.x + offscreen.y * offscreen.y)
        largeFrame = smallFrame.insetBy(dx: -radius, dy: -radius)

        let smallMaskPath = UIBezierPath(ovalIn: smallFrame)
        let largeMaskPath = UIBezierPath(ovalIn: largeFrame)

        return (smallMaskPath, largeMaskPath)
    }

    func performAnimation(startPath: CGPath, endPath: CGPath, viewController: UIViewController) {
        let mask = CAShapeLayer()
        let animation = CABasicAnimation(keyPath: "path")

        mask.path = startPath
        viewController.view.layer.mask = mask

        animation.fromValue = startPath
        animation.toValue = endPath
        animation.duration = transitionDuration(using: nil)
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.delegate = self

        mask.add(animation, forKey: nil)
        mask.path = endPath
    }
}

// MARK: - CameraTabPresenter implementation

class CameraTabPresenter: NSObject, CameraAnimator {

    let startPoint: CGPoint
    private var backgroundView: UIView?
    fileprivate var transitionContext: UIViewControllerContextTransitioning?

    init(startPoint: CGPoint) {
        self.startPoint = startPoint
        super.init()
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.5
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        self.transitionContext = transitionContext

        guard let to = transitionContext.viewController(forKey: .to), let maskPaths else {
            return transitionContext.completeTransition(false)
        }

        let background = UIView()
        background.frame = transitionContext.containerView.bounds
        background.backgroundColor = .black.withAlphaComponent(0.9)
        background.alpha = 0
        backgroundView = background

        transitionContext.containerView.addSubview(background)
        transitionContext.containerView.addSubview(to.view)

        performAnimation(startPath: maskPaths.small.cgPath, endPath: maskPaths.large.cgPath, viewController: to)
        UIView.animate(withDuration: 0.2) {
            background.alpha = 1
        }
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        transitionContext?.viewController(forKey: .to)?.view.layer.mask = nil
        backgroundView?.removeFromSuperview()
        transitionContext?.completeTransition(true)
    }
}

// MARK: - CameraTabDismisser implementation

class CameraTabDismisser: NSObject, CameraAnimator {

    let startPoint: CGPoint
    private var backgroundView: UIView?
    fileprivate var transitionContext: UIViewControllerContextTransitioning?

    init(startPoint: CGPoint) {
        self.startPoint = startPoint
        super.init()
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.35
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        self.transitionContext = transitionContext

        guard let from = transitionContext.viewController(forKey: .from), let maskPaths else {
            return transitionContext.completeTransition(false)
        }

        let background = UIView()
        background.frame = transitionContext.containerView.bounds
        background.backgroundColor = .black.withAlphaComponent(0.9)
        background.alpha = 0
        backgroundView = background

        transitionContext.containerView.insertSubview(background, belowSubview: from.view)
        performAnimation(startPath: maskPaths.large.cgPath, endPath: maskPaths.small.cgPath, viewController: from)
        UIView.animate(withDuration: 0.7) {
            background.alpha = 0
        }

        UIView.animate(withDuration: 0.1, delay: 0.325, animations: {
            from.view.alpha = 0
        })
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        transitionContext?.viewController(forKey: .to)?.view.layer.mask = nil
        backgroundView?.removeFromSuperview()
        transitionContext?.completeTransition(true)
    }
}
