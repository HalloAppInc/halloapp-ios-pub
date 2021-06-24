//
//  MediaExplorerVideoCell.swift
//  HalloApp
//
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import AVKit
import Core
import Combine
import Foundation
import UIKit

class MediaExplorerVideoCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: MediaExplorerVideoCell.self)
    }

    private let spaceBetweenPages: CGFloat = 20
    private var readyCancellable: AnyCancellable?
    private var progressCancellable: AnyCancellable?

    private lazy var video: VideoView = {
        let view = VideoView(playbackControls: .advanced)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var placeHolderView: UIImageView = {
        let placeHolderImageView = UIImageView(image: UIImage(systemName: "video"))
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
    private var looper: AVPlayerLooper?

    var isSystemUIHidden = false

    override func prepareForReuse() {
        super.prepareForReuse()

        video.player?.pause()
        video.player = nil
        media = nil
        readyCancellable?.cancel()
        progressCancellable?.cancel()
        readyCancellable = nil
        progressCancellable = nil
    }

    var media: MediaExplorerMedia? {
        didSet {
            guard let media = media else { return }

            if let url = media.url {
                show(url: url)
            } else {
                show(progress: media.progress.value)

                readyCancellable = media.ready.sink { [weak self] ready in
                    guard let self = self else { return }
                    guard ready else { return }
                    guard let url = self.media?.url else { return }
                    self.show(url: url)
                }

                progressCancellable = media.progress.sink { [weak self] value in
                    guard let self = self else { return }
                    self.progressView.setProgress(value, animated: true)
                }
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(placeHolderView)
        contentView.addSubview(progressView)
        contentView.addSubview(video)

        NSLayoutConstraint.activate([
            placeHolderView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            placeHolderView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            progressView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            progressView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            progressView.widthAnchor.constraint(equalToConstant: 80),
            progressView.heightAnchor.constraint(equalToConstant: 80),
            video.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: spaceBetweenPages),
            video.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -spaceBetweenPages),
            video.topAnchor.constraint(equalTo: contentView.topAnchor),
            video.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        video.player?.pause()
        video.player = nil
    }

    func show(url: URL) {
        placeHolderView.isHidden = true
        progressView.isHidden = true
        video.isHidden = false

        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        looper = AVPlayerLooper(player: player, templateItem: item)
        video.player = player
    }

    func show(progress: Float) {
        placeHolderView.isHidden = false
        progressView.isHidden = false
        progressView.setProgress(progress, animated: false)
        video.isHidden = true
        video.player?.pause()
        video.player = nil
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
