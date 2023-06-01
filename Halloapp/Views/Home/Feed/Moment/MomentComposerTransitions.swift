//
//  MomentComposerTransitions.swift
//  HalloApp
//
//  Created by Tanveer on 11/15/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import UIKit

class MomentComposerPresentTransition: NSObject, UIViewControllerAnimatedTransitioning {

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.55
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let to = transitionContext.viewController(forKey: .to)
        let composer = ((to as? UINavigationController)?.topViewController ?? to) as? MomentComposerViewController
        let presenter = composer?.delegate

        guard let to, let presenter, let composer else {
            return
        }

        to.view.alpha = 0
        transitionContext.containerView.addSubview(to.view)

        NSLayoutConstraint.activate([
            composer.background.topAnchor.constraint(equalTo: composer.view.topAnchor, constant: presenter.distanceFromTopForBackground),
            composer.background.heightAnchor.constraint(equalToConstant: presenter.heightForBackground),
        ])

        to.view.layoutIfNeeded()

        let sendButtonSnapshot = composer.sendButton.snapshotView(afterScreenUpdates: true)
        sendButtonSnapshot?.center = transitionContext.containerView.convert(composer.sendButton.center, from: composer.sendButton.superview)
        sendButtonSnapshot?.transform = .init(scaleX: 0.5, y: 0.5)
        sendButtonSnapshot?.alpha = 0

        if let sendButtonSnapshot {
            composer.sendButton.isHidden = true
            transitionContext.containerView.addSubview(sendButtonSnapshot)
        }

        UIView.animate(withDuration: transitionDuration(using: transitionContext),
                       delay: 0,
                       usingSpringWithDamping: 0.6,
                       initialSpringVelocity: 0.5, options: [.curveEaseOut]) {

            to.view.alpha = 1
            sendButtonSnapshot?.transform = .identity
            sendButtonSnapshot?.alpha = 1

        } completion: { _ in
            sendButtonSnapshot?.removeFromSuperview()
            composer.sendButton.isHidden = false
            transitionContext.completeTransition(true)
        }
    }
}

// MARK: - MomentComposerDismissTransition implementation

class MomentComposerDismissTransition: NSObject, UIViewControllerAnimatedTransitioning {

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.4
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let from = transitionContext.viewController(forKey: .from)
        let composer = ((from as? UINavigationController)?.topViewController ?? from) as? MomentComposerViewController

        guard let from, let composer else {
            return
        }

        UIView.animate(withDuration: transitionDuration(using: transitionContext),
                       delay: 0,
                       usingSpringWithDamping: 1,
                       initialSpringVelocity: 1) {

            from.view.alpha = 0
            composer.sendButton.transform = .init(scaleX: 0.5, y: 0.5)

        } completion: { _ in
            transitionContext.completeTransition(true)
        }
    }
}

// MARK: - MomentUnlockPresentTransition implementation

class MomentUnlockPresentTransition: NSObject, UIViewControllerAnimatedTransitioning {

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.4
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let to = transitionContext.viewController(forKey: .to)
        let from = transitionContext.viewController(forKey: .from)
        let moment = to as? MomentViewController
        let composer = ((from as? UINavigationController)?.topViewController ?? from) as? MomentComposerViewController

        guard let to, let moment, let composer else {
            return
        }

        to.view.alpha = 0
        transitionContext.containerView.addSubview(to.view)
        to.view.layoutIfNeeded()

        let unlockingView = moment.unlockingMomentView
        let backgroundView = composer.background

        let backgroundSnapshot = composer.background.snapshotView(afterScreenUpdates: true)
        let unlockingSnapshot = moment.unlockingMomentView.snapshotView(afterScreenUpdates: false)

        let finalSize = moment.unlockingMomentView.bounds.size
        let finalCenter = transitionContext.containerView.convert(unlockingView.center, from: unlockingView.superview)

        backgroundSnapshot?.center = transitionContext.containerView.convert(backgroundView.center, from: backgroundView.superview)
        unlockingSnapshot?.frame = backgroundSnapshot?.frame ?? .zero

        if let backgroundSnapshot, let unlockingSnapshot {
            transitionContext.containerView.addSubview(unlockingSnapshot)
            transitionContext.containerView.addSubview(backgroundSnapshot)
        }

        moment.unlockingMomentView.alpha = 0
        composer.background.isHidden = true

        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.5, options: [.curveEaseOut]) {
            backgroundSnapshot?.bounds.size = finalSize
            backgroundSnapshot?.center = finalCenter
            unlockingSnapshot?.frame = backgroundSnapshot?.frame ?? .zero

            backgroundSnapshot?.alpha = 0

        } completion: { _ in
            moment.unlockingMomentView.alpha = 1
            backgroundSnapshot?.removeFromSuperview()

            UIView.transition(with: transitionContext.containerView, duration: 0.25, options: [.transitionCrossDissolve]) {
                unlockingSnapshot?.alpha = 0
            } completion: { _ in
                transitionContext.completeTransition(true)
            }
        }

        UIView.animate(withDuration: 0.3, delay: 0.2) {
            to.view.alpha = 1
        }
    }
}
