//
//  VideoView.swift
//  HalloApp
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import AVFoundation
import Foundation
import UIKit

class VideoView: UIView {
    private var rateObservation: NSKeyValueObservation?

    var player: AVPlayer? {
        get {
            return playerLayer.player
        }
        set {
            playerLayer.player = newValue

            if let player = newValue {
                rateObservation = player.observe(\.rate, options: [ ], changeHandler: { [weak self] (player, change) in
                    guard let self = self else { return }
                    self.playButton.isHidden = player.rate > 0
                })
            } else {
                rateObservation = nil
            }
        }
    }

    var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }

    // Override UIView property
    override static var layerClass: AnyClass {
        return AVPlayerLayer.self
    }

    private lazy var playButton: UIView = {
        let size: CGFloat = 100
        let config = UIImage.SymbolConfiguration(pointSize: 36)
        let iconColor = UIColor(red: 0.54, green: 0.53, blue: 0.48, alpha: 1.00)
        let icon = UIImage(systemName: "play.fill", withConfiguration: config)!.withTintColor(iconColor, renderingMode: .alwaysOriginal)

        let buttonIcon = UIImageView(image: icon)
        buttonIcon.translatesAutoresizingMaskIntoConstraints = false

        let button = UIView()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.cornerRadius = size / 2
        button.clipsToBounds = true
        button.backgroundColor = UIColor(red: 0.92, green: 0.91, blue: 0.89, alpha: 0.9)

        button.addSubview(buttonIcon)

        NSLayoutConstraint.activate([
            buttonIcon.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            buttonIcon.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: size),
            button.heightAnchor.constraint(equalToConstant: size),
        ])

        return button
    }()

    init() {
        super.init(frame: .zero)

        addSubview(playButton)

        NSLayoutConstraint.activate([
            playButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(sender:)))
        addGestureRecognizer(tapRecognizer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleTap(sender: UITapGestureRecognizer) {
        if sender.state == .ended {
            if let rate = player?.rate, rate > 0 {
                player?.pause()
            } else {
                if player?.currentTime() == player?.currentItem?.duration {
                    player?.seek(to: .zero)
                }

                player?.play()
            }
        }
    }
}
