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

    private var media: MediaExplorerMedia
    private let originIndex: Int?
    private let explorerIndex: Int
    private let presenting: Bool
    private var context: UIViewControllerContextTransitioning?
    private var interactiveTransitionView: UIView?

    init(media: MediaExplorerMedia, between originIndex: Int?, and explorerIndex: Int, presenting: Bool) {
        self.media = media
        self.originIndex = originIndex
        self.explorerIndex = explorerIndex
        self.presenting = presenting

        self.media.computeSize()
    }

    private func computeSize(containerSize: CGSize, contentSize: CGSize) -> CGSize {
        var scale = CGFloat(1.0)
        if contentSize.width > contentSize.height {
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

    private func computeScaleAspectFit(containerSize: CGSize, contentSize: CGSize, transitionSize: CGSize) -> CGFloat {
        let contentFitScale = min(containerSize.width / contentSize.width, containerSize.height / contentSize.height)
        let transitionFitScale = min(contentSize.width / transitionSize.width, contentSize.height / transitionSize.height)

        return contentFitScale * transitionFitScale
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.4
    }

    func getTransitionView() -> UIView? {
        if media.type == .image {
            guard let image = media.image else { return nil }

            let imageView = UIImageView(image: image)
            imageView.contentMode = media.size.width > media.size.height ? .scaleAspectFit : .scaleAspectFill
            imageView.clipsToBounds = true

            return imageView
        } else if media.type == .video {
            guard let url = media.url else { return nil }

            let videoView = VideoTransitionView()
            videoView.player = AVPlayer(url: url)
            videoView.playerLayer.videoGravity = media.size.width > media.size.height ? .resizeAspect : .resizeAspectFill

            return videoView
        }

        return nil
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
        let originMediaSize = computeSize(containerSize: originFrame.size, contentSize: media.size)

        var transitionViewFinalCenter = CGPoint.zero
        var transitionViewFinalTransform = CGAffineTransform.identity

        if presenting {
            let scale = computeScaleAspectFit(containerSize: toViewFinalFrame.size, contentSize: media.size, transitionSize: originMediaSize)
            transitionViewFinalTransform = CGAffineTransform(scaleX: scale, y: scale)

            transitionView.frame.size = originMediaSize
            transitionView.center = CGPoint(x: originFrame.midX, y: originFrame.midY)
            toView?.alpha = 0.0
            transitionViewFinalCenter = CGPoint(x: toViewFinalFrame.midX, y: toViewFinalFrame.midY)
        } else {
            if let interactiveTransitionView = interactiveTransitionView {
                let scale = computeScaleAspectFit(containerSize: interactiveTransitionView.frame.size, contentSize: media.size, transitionSize: originMediaSize)
                transitionViewFinalTransform = CGAffineTransform(scaleX: 1 / scale, y: 1 / scale)

                transitionView.frame.size = originMediaSize.applying(CGAffineTransform(scaleX: scale, y: scale))
                transitionView.center = interactiveTransitionView.center
                interactiveTransitionView.removeFromSuperview()
            } else {
                let scale = computeScaleAspectFit(containerSize: fromViewStartFrame.size, contentSize: media.size, transitionSize: originMediaSize)
                transitionViewFinalTransform = CGAffineTransform(scaleX: 1 / scale, y: 1 / scale)

                transitionView.frame.size = originMediaSize.applying(CGAffineTransform(scaleX: scale, y: scale))
                transitionView.center = CGPoint(x: fromViewStartFrame.midX, y: fromViewStartFrame.midY)
            }

            transitionViewFinalCenter = CGPoint(x: originFrame.midX, y: originFrame.midY)
        }

        transitionContext.containerView.addSubview(transitionView)
        explorer.hideCollectionView()

        UIView.animate(withDuration: transitionDuration(using: nil), animations: { [weak self] in
            guard let self = self else { return }

            if self.presenting {
                transitionView.center = transitionViewFinalCenter
                transitionView.transform = transitionViewFinalTransform
                toView?.alpha = 1.0
            } else {
                transitionView.center = transitionViewFinalCenter
                transitionView.transform = transitionViewFinalTransform
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

fileprivate class VideoTransitionView: UIView {
    var player: AVPlayer? {
        get {
            return playerLayer.player
        }
        set {
            playerLayer.player = newValue
        }
    }

    var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }

    override static var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
}
