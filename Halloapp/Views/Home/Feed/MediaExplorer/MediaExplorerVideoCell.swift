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

    private lazy var video: VideoView = {
        let view = VideoView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    var isSystemUIHidden = false

    override func prepareForReuse() {
        super.prepareForReuse()
        url = nil
    }

    var url: URL! {
        didSet {
            if url != nil {
                video.player = AVPlayer(url: url)
            } else {
                video.player?.pause()
                video.player = nil
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(video)

        NSLayoutConstraint.activate([
            video.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: spaceBetweenPages),
            video.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -spaceBetweenPages),
            video.topAnchor.constraint(equalTo: self.topAnchor),
            video.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func play(time: CMTime = .zero) {
        video.player?.seek(to: time)
        video.player?.play()
    }

    func pause() {
        video.player?.pause()
    }

    func currentTime() -> CMTime {
        guard let player = video.player else { return .zero }
        return player.currentTime()
    }

    func isPlaying() -> Bool {
        guard let player = video.player else { return false }
        return player.rate > 0
    }
}
