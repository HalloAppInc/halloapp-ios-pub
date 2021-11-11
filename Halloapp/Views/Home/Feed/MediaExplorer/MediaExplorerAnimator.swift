//
//  MediaExplorerAnimator.swift
//  HalloApp
//
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import AVKit
import Core
import Foundation
import UIKit

class MediaExplorerAnimator: NSObject, UIViewControllerTransitioningDelegate, UIViewControllerAnimatedTransitioning, UIViewControllerInteractiveTransitioning {
    weak var delegate: MediaExplorerTransitionDelegate?
    weak var delegateExplorer: MediaExplorerController?

    private weak var media: MediaExplorerMedia?
    private let originIndex: Int?
    private let explorerIndex: Int
    private let presenting: Bool
    private weak var context: UIViewControllerContextTransitioning?
    private weak var interactiveTransitionView: UIView?

    init(media: MediaExplorerMedia, between originIndex: Int?, and explorerIndex: Int, presenting: Bool) {
        self.media = media
        self.originIndex = originIndex
        self.explorerIndex = explorerIndex
        self.presenting = presenting

        self.media?.computeSize()
    }

    private func shouldScaleToFit() -> Bool {
        return delegate?.shouldTransitionScaleToFit() ?? true
    }

    private func computeSize(scaleToFit: Bool = true, containerSize: CGSize, contentSize: CGSize) -> CGSize {
        var scale: CGFloat

        if scaleToFit {
            // .scaleAspectFit
            scale = min(containerSize.width / contentSize.width, containerSize.height / contentSize.height)
        } else {
            // .scaleAspectFill
            scale = max(containerSize.width / contentSize.width, containerSize.height / contentSize.height)
        }

        let width = min(containerSize.width, contentSize.width * scale)
        let height = min(containerSize.height, contentSize.height * scale)

        return CGSize(width: width, height: height)
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.4
    }

    func getTransitionView() -> UIView? {
        guard let media = media else { return nil}

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true

        switch media.type {
        case .image:
            guard let image = media.image else { return nil }
            imageView.image = image
        case .video:
            guard let url = media.url else { return nil }
            guard let image = VideoUtils.videoPreviewImage(url: url) else { return nil }
            imageView.image = image
        }

        return imageView
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let toView = transitionContext.view(forKey: .to)
        if let view = toView, interactiveTransitionView == nil {
            transitionContext.containerView.addSubview(view)
        }

        let fromView = transitionContext.view(forKey: .from)
        if let view = fromView, !presenting && interactiveTransitionView == nil {
            transitionContext.containerView.addSubview(view)
        }

        runTransition(using: transitionContext)
    }

    func runTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let index = originIndex,
              let media = media,
              let transitionView = getTransitionView(),
              let explorer = delegateExplorer,
              let originView = delegate?.getTransitionView(atPostion: index),
              let originFrame = originView.superview?.convert(originView.frame, to: transitionContext.containerView),
              let toController = transitionContext.viewController(forKey: .to),
              let fromController = transitionContext.viewController(forKey: .from)
        else {
            transitionContext.completeTransition(true)
            return
        }

        let toView = transitionContext.view(forKey: .to)
        let fromView = transitionContext.view(forKey: .from)
        let fromViewStartFrame = transitionContext.initialFrame(for: fromController)
        let toViewFinalFrame = transitionContext.finalFrame(for: toController)
        let originMediaSize = computeSize(scaleToFit: shouldScaleToFit(), containerSize: originFrame.size, contentSize: media.size)

        var transitionViewFinalCenter: CGPoint
        var transitionViewFinalSize: CGSize

        if presenting {
            transitionView.frame.size = originMediaSize
            transitionView.center = CGPoint(x: originFrame.midX, y: originFrame.midY)
            toView?.alpha = 0.0
            transitionViewFinalCenter = CGPoint(x: toViewFinalFrame.midX, y: toViewFinalFrame.midY)
            transitionViewFinalSize = computeSize(containerSize: toViewFinalFrame.size, contentSize: media.size)
        } else {
            if let interactiveTransitionView = interactiveTransitionView {
                transitionView.frame.size = computeSize(containerSize: interactiveTransitionView.frame.size, contentSize: media.size)
                transitionView.center = interactiveTransitionView.center
                interactiveTransitionView.removeFromSuperview()
            } else {
                transitionView.frame.size = computeSize(containerSize: fromViewStartFrame.size, contentSize: media.size)
                transitionView.center = CGPoint(x: fromViewStartFrame.midX, y: fromViewStartFrame.midY)
            }

            transitionViewFinalSize = originMediaSize
            transitionViewFinalCenter = CGPoint(x: originFrame.midX, y: originFrame.midY)
        }

        transitionContext.containerView.addSubview(transitionView)
        explorer.hideCollectionView()

        transitionContext.containerView.setNeedsLayout()

        UIView.animate(withDuration: transitionDuration(using: nil), animations: { [weak self] in
            guard let self = self else { return }

            transitionView.frame.size = transitionViewFinalSize
            transitionView.center = transitionViewFinalCenter

            if self.presenting {
                toView?.alpha = 1.0
            } else {
                fromView?.alpha = 0.0
            }
        }) { [weak self] _ in
            guard let self = self else { return }
            let success = !transitionContext.transitionWasCancelled

            if self.presenting && !success {
                toView?.removeFromSuperview()
            }

            if self.presenting {
                explorer.showCollectionView()
            }

            transitionView.removeFromSuperview()

            transitionContext.completeTransition(success)
        }
    }

    func startInteractiveTransition(_ transitionContext: UIViewControllerContextTransitioning) {
        guard !presenting,
              let explorer = delegateExplorer,
              let fromController = transitionContext.viewController(forKey: .from),
              let transitionView = explorer.getTransitionView(atPostion: explorerIndex)?.snapshotView(afterScreenUpdates: true)
        else {
            cancelInteractiveTransition()
            return
        }

        if let view = transitionContext.view(forKey: .to) {
            transitionContext.containerView.addSubview(view)
        }

        if let view = transitionContext.view(forKey: .from) {
            transitionContext.containerView.addSubview(view)
        }

        let fromViewStartFrame = transitionContext.initialFrame(for: fromController)
        transitionView.center = CGPoint(x: fromViewStartFrame.midX, y: fromViewStartFrame.midY)
        transitionContext.containerView.addSubview(transitionView)

        explorer.hideCollectionView()

        context = transitionContext
        interactiveTransitionView = transitionView
    }

    func move(_ translation: CGPoint) {
        guard !presenting,
              let context = context,
              let fromController = context.viewController(forKey: .from),
              let fromView = context.view(forKey: .from),
              let transitionView = interactiveTransitionView
        else {
            cancelInteractiveTransition()
            return
        }

        let exitDistance: CGFloat = 100;
        let exitScale: CGFloat = 0.8;
        let exitAlpha: CGFloat = 0.3;

        let progress = min((translation.x * translation.x + translation.y * translation.y) / (exitDistance * exitDistance), 1.0)
        let scale = 1 - progress + exitScale * progress
        let alpha = 1 - progress + exitAlpha * progress

        let fromViewStartFrame = context.initialFrame(for: fromController)
        transitionView.center.x = fromViewStartFrame.midX + translation.x
        transitionView.center.y = fromViewStartFrame.midY + translation.y
        transitionView.transform = CGAffineTransform(scaleX: scale, y: scale)

        fromView.alpha = alpha

        context.updateInteractiveTransition(progress)
    }

    func cancelInteractiveTransition() {
        guard let context = context,
              let explorer = delegateExplorer,
              let fromController = context.viewController(forKey: .from),
              let fromView = context.view(forKey: .from),
              let transitionView = interactiveTransitionView
        else { return }
        context.cancelInteractiveTransition()

        let fromViewStartFrame = context.initialFrame(for: fromController)

        UIView.animate(withDuration: 0.3, animations: {
            transitionView.center = CGPoint(x: fromViewStartFrame.midX, y: fromViewStartFrame.midY)
            transitionView.transform = .identity
            fromView.alpha = 1.0
        }, completion: { _ in
            transitionView.removeFromSuperview()
            explorer.showCollectionView()
            context.completeTransition(false)
        })
    }

    func finishInteractiveTransition() {
        guard let context = context, interactiveTransitionView != nil else { return }
        context.finishInteractiveTransition()
        runTransition(using: context)
    }
}
