//
//  MediaPickerPreview.swift
//  HalloApp
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation
import PhotosUI

class MediaPickerPreview {
    private let asset: PHAsset
    private let parent: UIView
    private var content: UIView?

    init(asset: PHAsset, parent: UIView) {
        self.asset = asset
        self.parent = parent
    }

    private func makeImagePreview(_ image: UIImage) {
        guard content == nil else { return }

        let content = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.backgroundColor = UIColor.init(red: 0, green: 0, blue: 0, alpha: 0.6)
        parent.addSubview(content)

        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.layer.cornerRadius = 15
        imageView.clipsToBounds = true
        imageView.image = image
        content.addSubview(imageView)

        let spacing = CGFloat(20)
        let widthRatio = (parent.bounds.width - 2 * spacing) / image.size.width
        let heightRatio = (parent.bounds.height - 2 * spacing) / image.size.height
        let scale = min(widthRatio, heightRatio, 1)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: parent.topAnchor),
            content.leftAnchor.constraint(equalTo: parent.leftAnchor),
            content.rightAnchor.constraint(equalTo: parent.rightAnchor),
            content.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            imageView.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: image.size.width * scale),
            imageView.heightAnchor.constraint(equalToConstant: image.size.height * scale),
        ])

        self.content = content
    }

    private func makeVideoPreview(_ item: AVPlayerItem) {
        guard content == nil else { return }

        let content = UIView()
        content.backgroundColor = UIColor.init(red: 0, green: 0, blue: 0, alpha: 0.4)
        content.frame = parent.bounds
        parent.addSubview(content)

        let player = AVPlayer(playerItem: item)
        let playerView = PlayerPreviewView()
        playerView.player = player
        playerView.frame = parent.bounds.insetBy(dx: 40, dy: 40)
        content.addSubview(playerView)

        player.play()

        self.content = content
    }

    public func show() {
        guard content == nil else { return }
        let manager = PHImageManager.default()

        if asset.mediaType == .image {
            let options = PHImageRequestOptions()
            options.isSynchronous = true
            options.isNetworkAccessAllowed = true

            manager.requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: options) {[weak self] image, _ in
                guard let self = self else { return }
                guard let image = image else { return }
                guard self.content == nil else { return }

                self.makeImagePreview(image)
                self.present()
            }
        } else if asset.mediaType == .video {
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true

            manager.requestPlayerItem(forVideo: asset, options: options) {[weak self] playerItem, _ in
                guard let self = self else { return }
                guard let playerItem = playerItem else { return }
                guard self.content == nil else { return }

                self.makeVideoPreview(playerItem)
                self.present()
            }
        }
    }

    private func present() {
        guard let content = content else { return }

        content.alpha = 0
        UIView.animate(withDuration: 0.3) {
            content.alpha = 1
        }
    }

    public func hide() {
        guard let content = content else { return }
        self.content = nil

        UIView.animate(withDuration: 0.3, animations: {
            content.alpha = 0
        }, completion: { finished in
            content.removeFromSuperview()
        })
    }
}

fileprivate class PlayerPreviewView: UIView {
    var player: AVPlayer? {
        get {
            return playerLayer.player
        }
        set {
            playerLayer.player = newValue
            playerLayer.player?.currentItem?.addObserver(self, forKeyPath: "status", options: [], context: nil)
        }
    }

    var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }

    // Override UIView property
    override static var layerClass: AnyClass {
        return AVPlayerLayer.self
    }

    private func makeVideoRounded() {
        let maskLayer = CAShapeLayer()
        maskLayer.path = UIBezierPath(roundedRect: playerLayer.videoRect, cornerRadius: 15).cgPath
        playerLayer.mask = maskLayer
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status" {
            guard let status = playerLayer.player?.currentItem?.status, status == .readyToPlay else { return }
            makeVideoRounded()
            return
        }

        super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
    }
}
