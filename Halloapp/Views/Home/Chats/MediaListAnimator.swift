//
//  MediaListAnimator.swift
//  HalloApp
//
//  Created by Stefan Fidanov on 9.06.22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import AVKit
import Core
import Foundation
import UIKit

protocol MediaListAnimatorDelegate: AnyObject {
    var transitionViewContentMode: UIView.ContentMode { get }

    func getTransitionView(at index: MediaIndex) -> UIView?
    func scrollToTransitionView(at index: MediaIndex)
    func timeForVideo(at index: MediaIndex) -> CMTime?
    func transitionDidBegin(presenting: Bool, with index: MediaIndex)
    func transitionDidEnd(presenting: Bool, with index: MediaIndex, success: Bool)
}

extension MediaListAnimatorDelegate {
    var transitionViewContentMode: UIView.ContentMode {
        .scaleAspectFill
    }

    func timeForVideo(at index: MediaIndex) -> CMTime? {
        return nil
    }

    func transitionDidBegin(presenting: Bool, with index: MediaIndex) {
    }

    func transitionDidEnd(presenting: Bool, with index: MediaIndex, success: Bool) {
    }
}

struct MediaIndex {
    var index: Int
    var chatMessageID: ChatMessageID?
}

class MediaListAnimator: NSObject, UIViewControllerAnimatedTransitioning, UIViewControllerInteractiveTransitioning {

    weak var fromDelegate: MediaListAnimatorDelegate?
    weak var toDelegate: MediaListAnimatorDelegate?

    private let media: (url: URL, type: CommonMediaType, size: CGSize)
    private let index: MediaIndex
    private let presenting: Bool

    private weak var interactiveTransitionView: UIView?
    private weak var interactiveTransitionContext: UIViewControllerContextTransitioning?

    init(presenting: Bool, media url: URL, with type: CommonMediaType, and size: CGSize, at index: MediaIndex) {
        self.presenting = presenting
        self.media = (url: url, type: type, size: size)
        self.index = index
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.45
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let toRootView = transitionContext.view(forKey: .to)

        if presenting, let toRootView = toRootView {
            transitionContext.containerView.addSubview(toRootView)
            toRootView.alpha = 0
        }

        fromDelegate?.transitionDidBegin(presenting: presenting, with: index)
        toDelegate?.transitionDidBegin(presenting: presenting, with: index)
        toDelegate?.scrollToTransitionView(at: index)

        // after 'scrollToTransitionView', 'DispatchQueue.main.async' ensures successful scrolling
        // and that every view required for the transition is at the right position
        DispatchQueue.main.async {
            self.runTransition(using: transitionContext)
        }
    }

    func startInteractiveTransition(_ transitionContext: UIViewControllerContextTransitioning) {
        guard !presenting,
              let fromView = fromDelegate?.getTransitionView(at: index),
              let fromViewFrame = fromView.superview?.convert(fromView.frame, to: transitionContext.containerView),

              let transitionView = fromView.snapshotView(afterScreenUpdates: true)
        else {
            cancelInteractiveTransition()
            return
        }

        transitionView.frame = fromViewFrame
        transitionContext.containerView.addSubview(transitionView)

        fromView.alpha = 0

        interactiveTransitionView = transitionView
        interactiveTransitionContext = transitionContext

        fromDelegate?.transitionDidBegin(presenting: presenting, with: index)
        toDelegate?.transitionDidBegin(presenting: presenting, with: index)
        toDelegate?.scrollToTransitionView(at: index)

        // after 'scrollToTransitionView', 'DispatchQueue.main.async' ensures successful scrolling
        // and that every view required for the transition is at the right position
        DispatchQueue.main.async {
            self.toDelegate?.getTransitionView(at: self.index)?.alpha = 0
        }
    }

    func move(_ translation: CGPoint) {
        guard !presenting,
              let transitionContext = interactiveTransitionContext,
              let transitionView = interactiveTransitionView,
              let fromView = fromDelegate?.getTransitionView(at: index),
              let fromViewFrame = fromView.superview?.convert(fromView.frame, to: transitionContext.containerView),
              let fromRootView = transitionContext.view(forKey: .from)
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

        transitionView.center.x = fromViewFrame.midX + translation.x
        transitionView.center.y = fromViewFrame.midY + translation.y
        transitionView.transform = CGAffineTransform(scaleX: scale, y: scale)

        fromRootView.alpha = alpha

        transitionContext.updateInteractiveTransition(progress)
    }

    func cancelInteractiveTransition() {
        guard let transitionContext = interactiveTransitionContext,
              let transitionView = interactiveTransitionView,
              let fromView = fromDelegate?.getTransitionView(at: index),
              let fromViewFrame = fromView.superview?.convert(fromView.frame, to: transitionContext.containerView),
              let toView = toDelegate?.getTransitionView(at: index),
              let fromRootView = transitionContext.view(forKey: .from)
        else { return }
        transitionContext.cancelInteractiveTransition()


        UIView.animate(withDuration: transitionDuration(using: transitionContext), animations: {
            transitionView.center = CGPoint(x: fromViewFrame.midX, y: fromViewFrame.midY)
            transitionView.transform = .identity
            fromRootView.alpha = 1
        }) { _ in
            fromView.alpha = 1
            toView.alpha = 1

            transitionView.removeFromSuperview()
            transitionContext.completeTransition(false)

            self.fromDelegate?.transitionDidEnd(presenting: self.presenting, with: self.index, success: false)
            self.toDelegate?.transitionDidEnd(presenting: self.presenting, with: self.index, success: false)
        }
    }

    func finishInteractiveTransition() {
        guard let transitionContext = interactiveTransitionContext, interactiveTransitionView != nil else { return }
        transitionContext.finishInteractiveTransition()
        runTransition(using: transitionContext)
    }

    private func runTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let transitionView = getTransitionView(),
              let fromView = fromDelegate?.getTransitionView(at: index),
              let fromViewFrame = fromView.superview?.convert(fromView.frame, to: transitionContext.containerView),
              let toView = toDelegate?.getTransitionView(at: index),
              let toViewFrame = toView.superview?.convert(toView.frame, to: transitionContext.containerView)
        else {
            transitionContext.view(forKey: .to)?.alpha = 1
            transitionContext.completeTransition(true)

            fromDelegate?.transitionDidEnd(presenting: presenting, with: index, success: false)
            toDelegate?.transitionDidEnd(presenting: presenting, with: index, success: false)
            return
        }

        if let interactiveTransitionView = interactiveTransitionView {
            transitionView.frame = interactiveTransitionView.frame
            interactiveTransitionView.removeFromSuperview()
        } else {
            transitionView.frame = fromViewFrame
        }

        transitionView.layer.cornerRadius = presenting ? fromView.layer.cornerRadius : toView.layer.cornerRadius
        transitionContext.containerView.addSubview(transitionView)

        fromView.alpha = 0
        toView.alpha = 0

        let toRootView = transitionContext.view(forKey: .to)
        let fromRootView = transitionContext.view(forKey: .from)

        UIView.animate(withDuration: transitionDuration(using: transitionContext), delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: .curveEaseInOut, animations: {
            transitionView.frame = toViewFrame

            if self.presenting {
                toRootView?.alpha = 1.0
            } else {
                fromRootView?.alpha = 0.0
            }
        }) { _ in
            let success = !transitionContext.transitionWasCancelled

            if self.presenting && !success {
                toRootView?.removeFromSuperview()
            }

            fromView.alpha = 1
            toView.alpha = 1
            transitionView.removeFromSuperview()

            transitionContext.completeTransition(success)

            self.fromDelegate?.transitionDidEnd(presenting: self.presenting, with: self.index, success: success)
            self.toDelegate?.transitionDidEnd(presenting: self.presenting, with: self.index, success: success)
        }
    }

    private func getTransitionView() -> UIView? {
        let imageView = UIImageView()
        imageView.clipsToBounds = true

        if presenting, let fromDelegate = fromDelegate {
            imageView.contentMode = fromDelegate.transitionViewContentMode
        } else if !presenting, let toDelegate = toDelegate {
            imageView.contentMode = toDelegate.transitionViewContentMode
        } else {
            imageView.contentMode = .scaleAspectFill
        }

        switch media.type {
        case .image:
            guard let image = UIImage(contentsOfFile: media.url.path) else { return nil }
            imageView.image = image
        case .video:
            guard let image = VideoUtils.videoPreviewImage(url: media.url) else { return nil }
            imageView.image = image
        case .audio:
            return nil // no transition for audio media
        }

        return imageView
    }
}

// convenience
extension UIImageView: MediaListAnimatorDelegate {
    func getTransitionView(at index: MediaIndex) -> UIView? {
        self
    }

    func scrollToTransitionView(at index: MediaIndex) {
    }
}
