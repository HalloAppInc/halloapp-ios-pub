//
//  VideoView.swift
//  HalloApp
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import AVFoundation
import Combine
import Foundation
import UIKit

class VideoView: UIView {
    enum PlaybackControls { case simple, advanced, custom }

    public var videoRectDidChange = PassthroughSubject<CGRect, Never>()

    private var rateObservation: NSKeyValueObservation?
    private var videoRectObservation: NSKeyValueObservation?

    var player: AVPlayer? {
        get {
            return playerLayer.player
        }
        set {
            playerLayer.mask = nil
            playerLayer.player = newValue
            timeSeekView.player = newValue

            if let player = newValue {
                rateObservation = player.observe(\.rate, options: [ ], changeHandler: { [weak self] (player, change) in
                    guard let self = self else { return }
                    self.playButton.isHidden = player.rate > 0 || self.playbackControls == .advanced
                })
            } else {
                rateObservation = nil
            }
        }
    }

    var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }

    var videoRect: CGRect {
        return playerLayer.videoRect
    }

    // Override UIView property
    override static var layerClass: AnyClass {
        return AVPlayerLayer.self
    }

    private var playbackControls: PlaybackControls = .simple

    private(set) lazy var playButton: UIView = {
        let size: CGFloat = 100
        let config = UIImage.SymbolConfiguration(pointSize: 36)
        let icon = UIImage(systemName: "play.fill", withConfiguration: config)!.withTintColor(.white, renderingMode: .alwaysOriginal)

        let buttonIcon = UIImageView(image: icon)
        buttonIcon.translatesAutoresizingMaskIntoConstraints = false

        let button = UIView()
        button.isUserInteractionEnabled = false
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.cornerRadius = size / 2
        button.clipsToBounds = true

        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        let blurredEffectView = BlurView(effect: blurEffect, intensity: 0.5)
        blurredEffectView.translatesAutoresizingMaskIntoConstraints = false

        button.insertSubview(blurredEffectView, at: 0)
        blurredEffectView.constrain(to: button)

        button.addSubview(buttonIcon)

        NSLayoutConstraint.activate([
            buttonIcon.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            buttonIcon.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: size),
            button.heightAnchor.constraint(equalToConstant: size),
        ])

        return button
    }()

    private(set) lazy var timeSeekView: TimeSeekView = {
        let timeSeekView = TimeSeekView()
        timeSeekView.translatesAutoresizingMaskIntoConstraints = false

        return timeSeekView
    } ()

    init(playbackControls: PlaybackControls = .simple) {
        super.init(frame: .zero)

        addSubview(playButton)
        addSubview(timeSeekView)

        NSLayoutConstraint.activate([
            timeSeekView.heightAnchor.constraint(equalToConstant: 44),
        ])

        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(sender:)))
        addGestureRecognizer(tapRecognizer)

        self.playbackControls = playbackControls

        switch playbackControls {
        case .simple:
            timeSeekView.isHidden = true
        case .advanced:
            timeSeekView.isHidden = false
            timeSeekView.alpha = 1

            NSLayoutConstraint.activate([
                playButton.centerXAnchor.constraint(equalTo: centerXAnchor),
                playButton.centerYAnchor.constraint(equalTo: centerYAnchor),
                timeSeekView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
                timeSeekView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
                timeSeekView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            ])
        case .custom:
            timeSeekView.isHidden = false
            timeSeekView.alpha = 1
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func roundCorner(_ radius: CGFloat) {
        clipsToBounds = true

        videoRectObservation = playerLayer.observe(\.videoRect) { [weak self] _, _ in
            guard let self = self else { return }
            guard self.playerLayer.videoRect.size != .zero else { return }

            let mask = CAShapeLayer()
            mask.path = UIBezierPath(roundedRect: self.playerLayer.videoRect, cornerRadius: radius).cgPath
            self.playerLayer.mask = mask

            self.videoRectDidChange.send(self.playerLayer.videoRect)
        }
    }

    public func togglePlay() {
        guard let player = player else { return }
        guard let duration = player.currentItem?.duration else { return }
        guard duration.isNumeric else { return }

        if player.rate > 0 {
            player.pause()
        } else {
            if player.currentTime() == duration {
                player.seek(to: .zero)
            }

            player.play()
        }
    }

    @objc private func handleTap(sender: UITapGestureRecognizer) {
        if sender.state == .ended {
            switch playbackControls {
            case .simple:
                togglePlay()
            case .advanced, .custom:
                if !playButton.isHidden {
                    togglePlay()
                }

                let targetAlpha: CGFloat = timeSeekView.alpha > 0 ? 0 : 1
                UIView.animate(withDuration: 0.3) { [weak self] in
                    self?.timeSeekView.alpha = targetAlpha
                }
            }
        }
    }
}

class TimeSeekView : UIView {
    private var rateObservation: NSKeyValueObservation?
    private var timeObservation: Any?

    private var isSeeking: Bool = false
    private var wasPlayingBeforeSeek: Bool = false
    private var isPlaying: Bool {
        guard let player = player else {
            return false
        }
        return player.rate > 0
    }

    var player: AVPlayer? {
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
        }
    }

    private let timeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        formatter.allowedUnits = [.second, .minute]

        return formatter
    }()

    private lazy var backgroundView: UIView = {
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        let blurredEffectView = BlurView(effect: blurEffect, intensity: 0.5)
        blurredEffectView.isUserInteractionEnabled = false
        blurredEffectView.translatesAutoresizingMaskIntoConstraints = false

        return blurredEffectView
    } ()

    private lazy var playIcon: UIImage = {
        let config = UIImage.SymbolConfiguration(pointSize: 24)
        let icon = UIImage(systemName: "play.fill", withConfiguration: config)!.withTintColor(.white, renderingMode: .alwaysOriginal)

        return icon
    } ()

    private lazy var pauseIcon: UIImage = {
        let config = UIImage.SymbolConfiguration(pointSize: 20)
        let icon = UIImage(systemName: "pause.fill", withConfiguration: config)!.withTintColor(.white, renderingMode: .alwaysOriginal)

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

        return btn
    } ()

    private lazy var slider: UISlider = {
        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumTrackTintColor = .white
        slider.setThumbImage(thumb(radius: 16), for: .normal)
        slider.addTarget(self, action: #selector(onSliderTouchDown), for: .touchDown)
        slider.addTarget(self, action: #selector(onSliderValueChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(onSliderTouchUp), for: .touchUpInside)
        slider.addTarget(self, action: #selector(onSliderTouchUp), for: .touchUpOutside)
        slider.addTarget(self, action: #selector(onSliderTouchUp), for: .touchCancel)
        return slider
    } ()

    private lazy var timePassed: UILabel = {
        let time = UILabel()
        time.translatesAutoresizingMaskIntoConstraints = false
        time.textColor = .white
        time.font = .gothamFont(ofFixedSize: 13)

        return time
    } ()

    private lazy var timeLeft: UILabel = {
        let time = UILabel()
        time.translatesAutoresizingMaskIntoConstraints = false
        time.textColor = .white
        time.font = .gothamFont(ofFixedSize: 13)

        return time
    } ()

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init() {
        super.init(frame: .zero)

        layer.cornerRadius = 10
        clipsToBounds = true

        addSubview(backgroundView)
        addSubview(playButton)
        addSubview(timePassed)
        addSubview(slider)
        addSubview(timeLeft)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            playButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            playButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 20),
            timePassed.centerYAnchor.constraint(equalTo: centerYAnchor),
            timePassed.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 16),
            timePassed.widthAnchor.constraint(equalToConstant: 42),
            timeLeft.centerYAnchor.constraint(equalTo: centerYAnchor),
            timeLeft.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            timeLeft.widthAnchor.constraint(equalToConstant: 48),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),
            slider.leadingAnchor.constraint(equalTo: timePassed.trailingAnchor, constant: 10),
            slider.trailingAnchor.constraint(equalTo: timeLeft.leadingAnchor, constant: -10),
        ])
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
        guard let interval = player.currentItem?.duration else { return }
        guard interval.isNumeric else { return }

        let current = player.currentTime().seconds / interval.seconds
        slider.setValue(Float(current), animated: false)

        timePassed.text = timeFormatter.string(from: interval.seconds * current)
        timeLeft.text = "-" + timeFormatter.string(from: interval.seconds * (1 - current))!

        playButton.setImage(player.rate > 0 ? pauseIcon : playIcon, for: .normal)
    }

    @objc private func onSliderTouchDown() {
        isSeeking = true
        if isPlaying {
            wasPlayingBeforeSeek = true
            player?.pause()
        }
    }

    @objc private func onSliderValueChanged() {
        guard let player = player else { return }
        guard let duration = player.currentItem?.duration else { return }
        guard duration.isNumeric else { return }

        let time = CMTimeMultiplyByFloat64(duration, multiplier: Double(slider.value))
        player.seek(to: time)
    }

    @objc private func onSliderTouchUp() {
        isSeeking = false
        if wasPlayingBeforeSeek {
            wasPlayingBeforeSeek = false
            player?.play()
        }
    }

    @objc private func onPlayButtonTap() {
        guard let player = player else { return }
        guard let duration = player.currentItem?.duration else { return }
        guard duration.isNumeric else { return }

        if player.rate > 0 {
            player.pause()
        } else {
            if player.currentTime() == duration {
                player.seek(to: .zero)
            }

            player.play()
        }
    }
}
