//
//  MediaExplorerImageCell.swift
//  HalloApp
//
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import AVKit
import Core
import Combine
import Foundation
import UIKit

class MediaExplorerImageCell: UICollectionViewCell, UIGestureRecognizerDelegate {
    static var reuseIdentifier: String {
        return String(describing: MediaExplorerImageCell.self)
    }

    private let spaceBetweenPages: CGFloat = 20

    public weak var scrollView: UIScrollView?

    private var originalOffset = CGPoint.zero
    private var imageConstraints: [NSLayoutConstraint] = []
    private var imageViewWidth: CGFloat = .zero
    private var imageViewHeight: CGFloat = .zero
    private var scale: CGFloat = 1
    private var animator: UIDynamicAnimator?

    private var width: CGFloat {
        imageViewWidth * scale
    }
    private var height: CGFloat {
        imageViewHeight * scale
    }
    private var minX: CGFloat {
        imageView.center.x - width / 2
    }
    private var maxX: CGFloat {
        imageView.center.x + width / 2
    }
    private var minY: CGFloat {
        imageView.center.y - height / 2
    }
    private var maxY: CGFloat {
        imageView.center.y + height / 2
    }

    private var readyCancellable: AnyCancellable?
    private var progressCancellable: AnyCancellable?

    private lazy var imageView: UIImageView = {
        let imageView = UIImageView(frame: .zero)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isUserInteractionEnabled = true
        imageView.contentMode = .scaleAspectFit

        return imageView
    }()

    private lazy var placeHolderView: UIImageView = {
        let placeHolderImageView = UIImageView(image: UIImage(systemName: "photo"))
        placeHolderImageView.contentMode = .center
        placeHolderImageView.translatesAutoresizingMaskIntoConstraints = false
        placeHolderImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .largeTitle)
        placeHolderImageView.tintColor = .white
        placeHolderImageView.isHidden = true

        return placeHolderImageView
    }()

    private lazy var progressView: CircularProgressView = {
        let progressView = CircularProgressView()
        progressView.barWidth = 2
        progressView.progressTintColor = .lavaOrange
        progressView.trackTintColor = .white
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.isHidden = true

        return progressView
    }()

    var media: MediaExplorerMedia? {
        didSet {
            guard let media = media else { return }

            if let image = media.image {
                show(image: image)
            } else {
                show(progress: media.progress.value)

                readyCancellable = media.ready.sink { [weak self] ready in
                    guard let self = self else { return }
                    guard ready else { return }
                    guard let image = self.media?.image else { return }
                    self.show(image: image)
                }

                progressCancellable = media.progress.sink { [weak self] value in
                    guard let self = self else { return }
                    self.progressView.setProgress(value, animated: true)
                }
            }
        }
    }

    var isZoomed: Bool { scale > 1.001 }

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(placeHolderView)
        contentView.addSubview(progressView)
        contentView.addSubview(imageView)
        contentView.clipsToBounds = true

        NSLayoutConstraint.activate([
            placeHolderView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            placeHolderView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            progressView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            progressView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            progressView.widthAnchor.constraint(equalToConstant: 80),
            progressView.heightAnchor.constraint(equalToConstant: 80),
        ])

        let zoomRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(onZoom(sender:)))
        imageView.addGestureRecognizer(zoomRecognizer)

        let dragRecognizer = UIPanGestureRecognizer(target: self, action: #selector(onDrag(sender:)))
        dragRecognizer.delegate = self
        imageView.addGestureRecognizer(dragRecognizer)

        let doubleTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(onDoubleTapAction(sender:)))
        doubleTapRecognizer.numberOfTapsRequired = 2
        doubleTapRecognizer.numberOfTouchesRequired = 1
        imageView.addGestureRecognizer(doubleTapRecognizer)

        animator = UIDynamicAnimator(referenceView: contentView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        media = nil
        readyCancellable?.cancel()
        progressCancellable?.cancel()
        readyCancellable = nil
        progressCancellable = nil
    }

    func show(image: UIImage) {
        placeHolderView.isHidden = true
        progressView.isHidden = true
        imageView.isHidden = false
        imageView.image = image
        reset()
        computeConstraints()
    }

    func show(progress: Float) {
        placeHolderView.isHidden = false
        progressView.isHidden = false
        progressView.setProgress(progress, animated: false)
        imageView.isHidden = true
    }

    func computeConstraints() {
        guard let image = imageView.image else { return }

        let scale = min((contentView.frame.width - spaceBetweenPages * 2) / image.size.width, contentView.frame.height / image.size.height)
        imageViewWidth = image.size.width * scale
        imageViewHeight = image.size.height * scale

        NSLayoutConstraint.deactivate(imageConstraints)
        imageConstraints = [
            imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: imageViewWidth),
            imageView.heightAnchor.constraint(equalToConstant: imageViewHeight),
        ]
        NSLayoutConstraint.activate(imageConstraints)
    }

    func reset() {
        imageView.transform = CGAffineTransform.identity
        imageView.center = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        scale = 1
        originalOffset = CGPoint.zero
        animator?.removeAllBehaviors()
    }

    // perform zoom & drag simultaneously
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return gestureRecognizer.view == otherGestureRecognizer.view && otherGestureRecognizer is UIPinchGestureRecognizer
    }

    @objc func onZoom(sender: UIPinchGestureRecognizer) {
        guard let scrollView = scrollView else { return }

        if sender.state == .began {
            originalOffset = scrollView.contentOffset

            let temp = imageView.center
            animator?.removeAllBehaviors()
            imageView.center = temp
        }

        if sender.state == .began || sender.state == .changed {
            guard sender.numberOfTouches > 1 else { return }

            let locations = [
                sender.location(ofTouch: 0, in: contentView),
                sender.location(ofTouch: 1, in: contentView),
            ]

            let zoomCenterX = (locations[0].x + locations[1].x) / 2
            let zoomCenterY = (locations[0].y + locations[1].y) / 2

            imageView.center.x += (zoomCenterX - imageView.center.x) * (1 - sender.scale)
            imageView.center.y += (zoomCenterY - imageView.center.y) * (1 - sender.scale)

            scale *= sender.scale
            imageView.transform = CGAffineTransform(scaleX: scale, y: scale)

            sender.scale = 1
        } else if sender.state == .ended {
            if scale < 1 {
                scale = 1
                animate(scale: scale, center: CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY))
            } else {
                adjustImageView(scale: scale, center: imageView.center)
            }
        }
    }

    @objc func onDrag(sender: UIPanGestureRecognizer) {
        guard let scrollView = scrollView else { return }

        if sender.state == .began {
            originalOffset = scrollView.contentOffset

            let temp = imageView.center
            animator?.removeAllBehaviors()
            imageView.center = temp
        }

        if sender.state == .began || sender.state == .changed {
            var translation = sender.translation(in: window)

            // when scrolling horizontally, if page changing has begun it has priority
            if scrollView.contentOffset.x > originalOffset.x {
                let translate = min(scrollView.contentOffset.x - originalOffset.x, translation.x)
                scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x - translate, y: scrollView.contentOffset.y), animated: false)
                translation.x -= translate
            } else if scrollView.contentOffset.x < originalOffset.x {
                let translate = max(scrollView.contentOffset.x - originalOffset.x, translation.x)
                scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x - translate, y: scrollView.contentOffset.y), animated: false)
                translation.x -= translate
            }

            // translate horizontally up to the image border
            if translation.x > 0 && minX < spaceBetweenPages {
                imageView.center.x += min(translation.x, spaceBetweenPages - minX)
                translation.x = max(translation.x - spaceBetweenPages + minX, 0)
            } else if translation.x < 0 && maxX > contentView.bounds.maxX - spaceBetweenPages {
                imageView.center.x += max(translation.x, contentView.bounds.maxX - spaceBetweenPages - maxX)
                translation.x = min(translation.x - contentView.bounds.maxX + spaceBetweenPages + maxX, 0)
            }

            if translation.y > 0 && minY < 0 {
                imageView.center.y += min(translation.y, -minY)
            } else if translation.y < 0 && maxY > contentView.bounds.maxY {
                imageView.center.y += max(translation.y, contentView.bounds.maxY - maxY)
            }

            if translation.x != 0 {
                scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x - translation.x, y: scrollView.contentOffset.y), animated: false)
            }

            sender.setTranslation(.zero, in: window)
        } else if sender.state == .ended {
            let velocity = sender.velocity(in: window)

            if shouldScrollPage(velocity: abs(velocity.x) > abs(velocity.y) ? velocity.x : 0) {
                scale = 1
                animate(scale: scale, center: CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY))
                scrollPage(velocity: velocity.x)
            } else {
                if scale > 1 {
                    addInertialMotion(velocity: velocity)
                }

                scrollView.setContentOffset(originalOffset, animated: true)
            }
        }
    }

    @objc func onDoubleTapAction(sender: UITapGestureRecognizer) {
        let temp = imageView.center
        animator?.removeAllBehaviors()
        imageView.center = temp

        let center: CGPoint

        if imageView.transform.isIdentity {
            let location = sender.location(in: contentView)
            scale = 2.5
            center = CGPoint(x: imageView.center.x + (contentView.bounds.midX - location.x) * scale,
                             y: imageView.center.y + (contentView.bounds.midY - location.y) * scale)
        } else {
            scale = 1
            center = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        }

        adjustImageView(scale: scale, center: center)
    }

    private func adjustImageView(scale: CGFloat, center: CGPoint) {
        let width = imageViewWidth * scale
        let height = imageViewHeight * scale
        let minX = center.x - width / 2
        let maxX = center.x + width / 2
        let minY = center.y - height / 2
        let maxY = center.y + height / 2

        var x: CGFloat
        if width > bounds.width {
            x = center.x + max(contentView.bounds.maxX - spaceBetweenPages - maxX, 0) + min(contentView.bounds.minX + spaceBetweenPages - minX, 0)
        } else {
            x = contentView.bounds.midX
        }

        var y: CGFloat
        if height > bounds.height {
            y = center.y + max(contentView.bounds.maxY - maxY, 0) + min(contentView.bounds.minY - minY, 0)
        } else {
            y = contentView.bounds.midY
        }

        animate(scale: scale, center: CGPoint(x: x, y: y))
    }

    private func animate(scale: CGFloat, center: CGPoint) {
        UIView.animate(withDuration: 0.35) { [weak self] in
            guard let self = self else { return }
            self.imageView.transform = CGAffineTransform(scaleX: scale, y: scale)
            self.imageView.center = center
        }
    }

    private func shouldScrollPage(velocity: CGFloat) -> Bool {
        guard let scrollView = scrollView else { return false }

        let offset = originalOffset.x + scrollView.frame.width * (velocity > 0 ? -1 : 1)
        if offset >= 0 && offset < scrollView.contentSize.width {
            let diff = scrollView.contentOffset.x - originalOffset.x
            return (abs(diff) > scrollView.frame.width / 2) || (abs(diff) > 0 && abs(velocity) > 200)
        }

        return false
    }

    private func scrollPage(velocity: CGFloat) {
        guard let scrollView = scrollView else { return }

        let offset = originalOffset.x + scrollView.frame.width * (velocity > 0 ? -1 : 1)

        if offset >= 0 && offset < scrollView.contentSize.width {
            let distance = scrollView.contentOffset.x - offset
            let duration = min(TimeInterval(abs(distance / velocity)), 0.3)

            UIView.animate(withDuration: duration) {
                scrollView.setContentOffset(CGPoint(x: offset, y: self.originalOffset.y), animated: false)
                scrollView.layoutIfNeeded()
            }
        }
    }

    private func addInertialMotion(velocity: CGPoint) {
        var imageVelocity = CGPoint.zero
        let boundMinX: CGFloat, boundMaxX: CGFloat, boundMinY: CGFloat, boundMaxY: CGFloat

        // UICollisionBehavior doesn't take into account transform scaling
        if width > bounds.width {
            boundMinX = contentView.bounds.maxX - spaceBetweenPages - width / 2 - imageViewWidth / 2
            boundMaxX = contentView.bounds.minX + spaceBetweenPages + width / 2 + imageViewWidth / 2
            imageVelocity.x = velocity.x
        } else {
            boundMinX = contentView.bounds.midX - imageViewWidth / 2
            boundMaxX = contentView.bounds.midX + imageViewWidth / 2
        }

        // UICollisionBehavior doesn't take into account transform scaling
        if height > bounds.height {
            boundMinY = contentView.bounds.maxY - height / 2 - imageViewHeight / 2
            boundMaxY = contentView.bounds.minY + height / 2 + imageViewHeight / 2
            imageVelocity.y = velocity.y
        } else {
            boundMinY = contentView.bounds.midY - imageViewHeight / 2
            boundMaxY = contentView.bounds.midY + imageViewHeight / 2
        }

        let dynamicBehavior = UIDynamicItemBehavior(items: [imageView])
        dynamicBehavior.addLinearVelocity(imageVelocity, for: imageView)
        dynamicBehavior.resistance = 10

        // UIKit Dynamics resets the transform and ignores scale
        dynamicBehavior.action = { [weak self] in
            guard let self = self else { return }
            self.imageView.transform = CGAffineTransform(scaleX: self.scale, y: self.scale)
        }
        animator?.addBehavior(dynamicBehavior)

        let boundaries = CGRect(x: boundMinX, y: boundMinY, width: boundMaxX - boundMinX, height: boundMaxY - boundMinY)
        let collisionBehavior = UICollisionBehavior(items: [imageView])
        collisionBehavior.addBoundary(withIdentifier: NSString("boundaries"), for: UIBezierPath(rect: boundaries))
        animator?.addBehavior(collisionBehavior)
    }
}
