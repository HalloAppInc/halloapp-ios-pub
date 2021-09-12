//
//  AudioView.swift
//  HalloApp
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import AVFoundation
import CocoaLumberjackSwift
import Combine
import Foundation

protocol AudioViewDelegate: AnyObject {
    func audioView(_ view: AudioView, at time: String)
    func audioViewDidStartPlaying(_ view: AudioView)
}

enum AudioViewState {
    case normal, played
}

class AudioView : UIStackView {

    weak var delegate: AudioViewDelegate?

    var state: AudioViewState = .normal {
        didSet {
            update()
        }
    }

    var url: URL? {
        didSet {
            pause()

            if let url = self.url {
                player = AVPlayer(url: url)
            } else {
                player = nil
            }
        }
    }

    private var rateObservation: NSKeyValueObservation?
    private var timeObservation: Any?
    private var mediaPlaybackCancellable: AnyCancellable?

    private var player: AVPlayer? {
        didSet {
            rateObservation = nil
            timeObservation = nil

            guard let player = player else { return }

            rateObservation = player.observe(\.rate) { [weak self] (player, change) in
                guard let self = self else { return }
                self.update()
            }

            let interval = CMTime(seconds: 0.1, preferredTimescale: 10)
            timeObservation = player.addPeriodicTimeObserver(forInterval: interval, queue: DispatchQueue.main) { [weak self] x in
                guard let self = self else { return }
                guard player.rate > 0 else { return }

                self.update()
            }

            update()
        }
    }

    private let timeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        formatter.allowedUnits = [.second, .minute]

        return formatter
    }()

    private var playIcon: UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: 24)
        let iconColor: UIColor = state == .played ? .audioViewControlsPlayed : .primaryBlue
        let icon = UIImage(systemName: "play.fill", withConfiguration: config)!.withTintColor(iconColor, renderingMode: .alwaysOriginal)

        return icon
    }

    private var pauseIcon: UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: 20)
        let iconColor: UIColor = state == .played ? .audioViewControlsPlayed : .primaryBlue
        let icon = UIImage(systemName: "pause.fill", withConfiguration: config)!.withTintColor(iconColor, renderingMode: .alwaysOriginal)

        return icon
    }

    // The play button is small. This one has bigger hit area to make it easier for tapping.
    private class PlayButton: UIButton {
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            return bounds.insetBy(dx: -16, dy: -16).contains(point)
        }
    }

    private lazy var playButton: UIButton = {
        let btn = PlayButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setImage(playIcon, for: .normal)
        btn.addTarget(self, action: #selector(onPlayButtonTap), for: .touchUpInside)
        btn.widthAnchor.constraint(equalToConstant: 20).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 20).isActive = true

        return btn
    } ()

    private lazy var slider: UISlider = {
        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumTrackTintColor = .white
        slider.setThumbImage(thumb(radius: 16), for: .normal)
        slider.addTarget(self, action: #selector(onSliderValueUpdate), for: .valueChanged)
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.minimumTrackTintColor = .primaryBlackWhite

        return slider
    } ()

    init() {
        super.init(frame: .zero)

        axis = .horizontal
        alignment = .center
        spacing = 12
        isLayoutMarginsRelativeArrangement = true

        addArrangedSubview(playButton)
        addArrangedSubview(slider)

        mediaPlaybackCancellable = MainAppContext.shared.mediaDidStartPlaying.sink { [weak self] playingUrl in
            guard let self = self else { return }
            guard self.url != playingUrl else { return }
            self.pause()
        }
    }

    convenience init(url: URL) {
        self.init()
        self.url = url
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        player?.pause()
        player = nil
    }

    func play() {
        guard let player = player else { return }
        guard let duration = player.currentItem?.duration else { return }
        guard duration.isNumeric else { return }

        if player.currentTime() == duration {
            player.seek(to: .zero)
        }

        MainAppContext.shared.mediaDidStartPlaying.send(url)
        player.play()
        delegate?.audioViewDidStartPlaying(self)
    }

    func pause() {
        player?.pause()
    }

    private func thumb(color: UIColor = .white, radius: CGFloat) -> UIImage {
        let thumb = UIView(frame: CGRect(x: 0, y: radius / 2, width: radius, height: radius))
        thumb.backgroundColor = color
        thumb.layer.borderWidth = 0.4
        thumb.layer.borderColor = UIColor.darkGray.cgColor
        thumb.layer.cornerRadius = radius / 2

        return UIGraphicsImageRenderer(bounds: thumb.bounds).image { thumb.layer.render(in: $0.cgContext) }
    }

    private func update() {
        guard let player = player else { return }
        guard let duration = player.currentItem?.asset.duration else { return }
        guard duration.isNumeric else { return }

        let thumbColor: UIColor = state == .played ? .audioViewControlsPlayed : .primaryBlue
        let current = player.currentTime().seconds / duration.seconds
        slider.setThumbImage(thumb(color: thumbColor, radius: 16), for: .normal)
        slider.setValue(Float(current), animated: false)
        playButton.setImage(player.rate > 0 ? pauseIcon : playIcon, for: .normal)

        if let time = timeFormatter.string(from: player.rate > 0 ? (duration.seconds * current) : duration.seconds) {
            delegate?.audioView(self, at: time)
        }
    }

    @objc private func onSliderValueUpdate() {
        guard let player = player else { return }
        guard let duration = player.currentItem?.duration else { return }
        guard duration.isNumeric else { return }

        if player.rate > 0 {
            player.pause()
        }

        let time = CMTimeMultiplyByFloat64(duration, multiplier: Double(slider.value))
        player.seek(to: time)
    }

    @objc private func onPlayButtonTap() {
        guard let player = player else { return }

        if player.rate > 0 {
            pause()
        } else {
            play()
        }
    }
}
