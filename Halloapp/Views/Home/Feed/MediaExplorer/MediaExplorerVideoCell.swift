//
//  MediaExplorerVideoCell.swift
//  HalloApp
//
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import AVKit
import Core
import Foundation
import UIKit

class MediaExplorerVideoCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: MediaExplorerVideoCell.self)
    }

    private let spaceBetweenPages: CGFloat = 20

    private var statusObservation: NSKeyValueObservation?
    private var videoBoundsObservation: NSKeyValueObservation?

    private lazy var playerController: AVPlayerViewController = {
        let controller = AVPlayerViewController()
        controller.view.backgroundColor = .clear
        controller.allowsPictureInPicturePlayback = false

        return controller
    }()

    var isSystemUIHidden = false {
        didSet {
            playerController.showsPlaybackControls = !isSystemUIHidden
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        statusObservation = nil
        videoBoundsObservation = nil
        url = nil
        playerController.view.frame = bounds.insetBy(dx: spaceBetweenPages, dy: 0)
    }

    var url: URL! {
        didSet {
            if url != nil {
                let player = AVPlayer(url: url)

                statusObservation = player.observe(\.status) { [weak self] player, change in
                    guard let self = self else { return }
                    guard player.status == .readyToPlay else { return }
                    self.playerController.player = player
                }
            } else {
                playerController.player?.pause()
                statusObservation = nil
                playerController.player = nil
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        playerController.view.frame = bounds.insetBy(dx: spaceBetweenPages, dy: 0)
        contentView.addSubview(playerController.view)
        videoBoundsObservation = playerController.observe(\.videoBounds) { controller, change in
            guard controller.videoBounds.size != .zero else { return }

            let bounds = controller.videoBounds
            let x = controller.view.frame.midX - bounds.width / 2
            let y = controller.view.frame.midY - bounds.height / 2

            controller.view.frame = CGRect(x: x, y: y, width: bounds.width, height: bounds.height)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func resetVideoSize() {
        playerController.view.frame = bounds.insetBy(dx: spaceBetweenPages, dy: 0)
    }

    func play(time: CMTime = .zero) {
        playerController.player?.seek(to: time)
        playerController.player?.play()
    }

    func pause() {
        playerController.player?.pause()
    }

    func currentTime() -> CMTime {
        guard let player = playerController.player else { return .zero }
        return player.currentTime()
    }

    func isPlaying() -> Bool {
        guard let player = playerController.player else { return false }
        return player.rate > 0
    }
}
