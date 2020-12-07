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

class MediaExplorerAnimator: NSObject, UIViewControllerTransitioningDelegate, UIViewControllerAnimatedTransitioning {
    weak var delegate: MediaExplorerTransitionDelegate?

    private var media: MediaExplorerMedia
    private let index: Int
    private let presenting: Bool

    init(media: MediaExplorerMedia, atPosition index: Int, presenting: Bool) {
        self.media = media
        self.index = index
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
        return 0.7
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
        guard let delegate = delegate,
              let toController = transitionContext.viewController(forKey: .to),
              let fromController = transitionContext.viewController(forKey: .from)
        else {
            transitionContext.completeTransition(true)
            return
        }

        let toView = transitionContext.view(forKey: .to)
        if let view = toView {
            transitionContext.containerView.addSubview(view)
        }

        let fromView = transitionContext.view(forKey: .from)
        if let view = fromView, !presenting {
            transitionContext.containerView.addSubview(view)
        }

        // Ensurees that the toView and fromView have rendered their transition views
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                transitionContext.completeTransition(true)
                return
            }

            guard let transitionView = self.getTransitionView(),
                  let originView = delegate.getTransitionView(atPostion: self.index),
                  let originFrame = originView.superview?.convert(originView.frame, to: transitionContext.containerView)
            else {
                transitionContext.completeTransition(true)
                return
            }

            let fromViewStartFrame = transitionContext.initialFrame(for: fromController)
            let toViewFinalFrame = transitionContext.finalFrame(for: toController)
            let originMediaSize = self.computeSize(containerSize: originFrame.size, contentSize: self.media.size)

            var transitionViewFinalCenter = CGPoint.zero
            var transitionViewFinalTransform = CGAffineTransform.identity
            if self.presenting {
                let scale = self.computeScaleAspectFit(containerSize: toViewFinalFrame.size, contentSize: self.media.size, transitionSize: originMediaSize)
                transitionViewFinalTransform = CGAffineTransform(scaleX: scale, y: scale)

                transitionView.frame.size = originMediaSize
                transitionView.center = CGPoint(x: originFrame.midX, y: originFrame.midY)
                toView?.alpha = 0.0
                transitionViewFinalCenter = CGPoint(x: toViewFinalFrame.midX, y: toViewFinalFrame.midY)
            } else {
                let scale = self.computeScaleAspectFit(containerSize: fromViewStartFrame.size, contentSize: self.media.size, transitionSize: originMediaSize)
                transitionViewFinalTransform = CGAffineTransform(scaleX: 1 / scale, y: 1 / scale)

                transitionView.frame.size = originMediaSize.applying(CGAffineTransform(scaleX: scale, y: scale))
                transitionView.center = CGPoint(x: fromViewStartFrame.midX, y: fromViewStartFrame.midY)
                transitionViewFinalCenter = CGPoint(x: originFrame.midX, y: originFrame.midY)
            }

            transitionContext.containerView.addSubview(transitionView)

            UIView.animateKeyframes(withDuration: self.transitionDuration(using: nil), delay: 0, options: [], animations: {
                if self.presenting {
                    UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.4) {
                        transitionView.center = transitionViewFinalCenter
                        transitionView.transform = transitionViewFinalTransform
                    }

                    UIView.addKeyframe(withRelativeStartTime: 0.4, relativeDuration: 0.6) {
                        toView?.alpha = 1.0
                    }
                } else {
                    UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.6) {
                        fromView?.alpha = 0.0
                    }

                    UIView.addKeyframe(withRelativeStartTime: 0.6, relativeDuration: 0.4) {
                        transitionView.center = transitionViewFinalCenter
                        transitionView.transform = transitionViewFinalTransform
                    }
                }
            }) { [weak self] finished in
                guard let self = self else { return }
                let success = !transitionContext.transitionWasCancelled

                if self.presenting && !success {
                    toView?.removeFromSuperview()
                }

                transitionView.removeFromSuperview()

                transitionContext.completeTransition(success)
            }
        }
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
