//
//  AudioView.swift
//  HalloApp
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import AVFoundation
import CocoaLumberjackSwift
import Foundation

class AudioView : UIStackView {

    var textColor: UIColor {
        get { timeLabel.textColor }
        set { timeLabel.textColor = newValue }
    }

    var url: URL? {
        didSet {
            if let url = self.url {
                player = AVPlayer(url: url)
            } else {
                player = nil
            }
        }
    }

    private var rateObservation: NSKeyValueObservation?
    private var timeObservation: Any?

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

    private lazy var playIcon: UIImage = {
        let config = UIImage.SymbolConfiguration(pointSize: 24)
        let icon = UIImage(systemName: "play.fill", withConfiguration: config)!.withTintColor(.primaryBlackWhite, renderingMode: .alwaysOriginal)

        return icon
    } ()

    private lazy var pauseIcon: UIImage = {
        let config = UIImage.SymbolConfiguration(pointSize: 20)
        let icon = UIImage(systemName: "pause.fill", withConfiguration: config)!.withTintColor(.primaryBlackWhite, renderingMode: .alwaysOriginal)

        return icon
    } ()

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

    private lazy var timeLabel: UILabel = {
        let time = UILabel()
        time.translatesAutoresizingMaskIntoConstraints = false
        time.textColor = .white
        time.font = .gothamFont(ofFixedSize: 13)
        time.widthAnchor.constraint(equalToConstant: 48).isActive = true
        time.textAlignment = .center

        return time
    } ()

    init() {
        super.init(frame: .zero)

        axis = .horizontal
        alignment = .center
        spacing = 4
        isLayoutMarginsRelativeArrangement = true

        addArrangedSubview(playButton)
        addArrangedSubview(timeLabel)
        addArrangedSubview(slider)
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

        player.play()
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

        let current = player.currentTime().seconds / duration.seconds
        slider.setValue(Float(current), animated: false)
        playButton.setImage(player.rate > 0 ? pauseIcon : playIcon, for: .normal)
        timeLabel.text = timeFormatter.string(from: player.rate > 0 ? (duration.seconds * current) : duration.seconds)
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
