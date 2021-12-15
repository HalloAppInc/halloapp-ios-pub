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
import UIKit

protocol AudioViewDelegate: AnyObject {
    func audioView(_ view: AudioView, at time: String)
    func audioViewDidStartPlaying(_ view: AudioView)
    func audioViewDidEndPlaying(_ view: AudioView, completed: Bool)
}

enum AudioViewState {
    case normal, played, loading
}

class AudioView : UIStackView {

    struct Configuration {
        let playIcon: UIImage
        let pauseIcon: UIImage
        let playPauseButtonSize: CGSize
        let thumbDiameter: CGFloat

        static let post = Configuration(playIcon: UIImage(systemName: "play.fill",
                                                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 20))!,
                                        pauseIcon: UIImage(systemName: "pause.fill",
                                                           withConfiguration: UIImage.SymbolConfiguration(pointSize: 20))!,
                                        playPauseButtonSize: CGSize(width: 32, height: 32),
                                        thumbDiameter: 12)

        static let comment = Configuration(playIcon: UIImage(systemName: "play.fill",
                                                             withConfiguration: UIImage.SymbolConfiguration(pointSize: 24))!,
                                           pauseIcon: UIImage(systemName: "pause.fill",
                                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 20))!,
                                           playPauseButtonSize: CGSize(width: 20, height: 20),
                                           thumbDiameter: 10)

    }

    weak var delegate: AudioViewDelegate?

    var state: AudioViewState = .normal {
        didSet {
            updateState()
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

    var isPlaying: Bool {
        return player?.rate ?? 0 > 0
    }

    private let configuration: Configuration

    private var rateObservation: NSKeyValueObservation?
    private var timeObservation: Any?
    private var mediaPlaybackCancellable: AnyCancellable?
    private var sessionManager = AudioSessionManager()

    private var player: AVPlayer? {
        didSet {
            rateObservation = nil
            timeObservation = nil

            guard let player = player else { return }
            player.seek(to: .zero)

            rateObservation = player.observe(\.rate, options: [.old, .new]) { [weak self] (player, change) in
                guard let self = self else { return }
                self.updateIsPlaying()
                self.updateProgress()

                if change.oldValue == 1 && change.newValue == 0 {
                    self.delegate?.audioViewDidEndPlaying(self, completed: self.isPlayerAtTheEnd)
                    self.pause()
                }
            }

            let interval = CMTime(value: 1, timescale: 60)
            timeObservation = player.addPeriodicTimeObserver(forInterval: interval, queue: DispatchQueue.main) { [weak self] time in
                guard let self = self else { return }
                guard player.rate > 0 else { return }
                self.updateProgress()
            }

            updateIsPlaying()
            updateProgress()
        }
    }

    private var thumbIcon: UIImage {
        let diameter = configuration.thumbDiameter
        let bounds = CGRect(x: 0, y: diameter / 2, width: diameter, height: diameter)
        return UIGraphicsImageRenderer(bounds: bounds).image { context in
            UIBezierPath(ovalIn: context.format.bounds).fill()
        }.withRenderingMode(.alwaysTemplate)
    }

    // The play button is small. This one has bigger hit area to make it easier for tapping.
    private class PlayButton: UIButton {
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            return bounds.insetBy(dx: min(0, bounds.width - 44),
                                  dy: min(0, bounds.height - 44)).contains(point)
        }
    }

    // improves hit rate
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return super.point(inside: point, with: event) || playPauseButton.point(inside: convert(point, to: playPauseButton),
                                                                                with: event)
    }

    private lazy var playPauseButton: UIButton = {
        let btn = PlayButton(type: .system)
        btn.imageView?.contentMode = .center
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setImage(configuration.playIcon, for: .normal)
        btn.addTarget(self, action: #selector(onPlayButtonTap), for: .touchUpInside)
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: configuration.playPauseButtonSize.width),
            btn.heightAnchor.constraint(equalToConstant: configuration.playPauseButtonSize.height),
        ])
        return btn
    } ()

    private lazy var slider: UISlider = {
        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.setThumbImage(thumbIcon, for: .normal)
        slider.addTarget(self, action: #selector(onSliderValueUpdate), for: .valueChanged)
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return slider
    } ()

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.widthAnchor.constraint(equalToConstant: 20).isActive = true
        indicator.heightAnchor.constraint(equalToConstant: 20).isActive = true

        return indicator
    } ()

    private var isPlayerAtTheEnd: Bool {
        guard let player = player else { return false }
        guard let duration = player.currentItem?.asset.duration else { return false }
        guard duration.isNumeric else { return false }

        // When a voice note ends 'player.currentTime()' should be equal to the duration
        // but sometimes it is a little bit less and sometimes a little bit more.
        // By observation it is usually within 30 milliseconds.
        let playerEndThreshold = 0.03
        return duration.seconds - player.currentTime().seconds < playerEndThreshold
    }

    init(configuration: Configuration) {
        self.configuration = configuration
        super.init(frame: .zero)

        axis = .horizontal
        alignment = .center
        spacing = 12
        isLayoutMarginsRelativeArrangement = true

        addArrangedSubview(loadingIndicator)
        addArrangedSubview(playPauseButton)
        addArrangedSubview(slider)

        mediaPlaybackCancellable = MainAppContext.shared.mediaDidStartPlaying.sink { [weak self] playingUrl in
            guard let self = self else { return }
            guard self.url != playingUrl else { return }
            self.pause()
        }

        let nc = NotificationCenter.default
        nc.addObserver(self,
                       selector: #selector(proximityChanged),
                       name: UIDevice.proximityStateDidChangeNotification,
                       object: nil)

        updateState()
    }

    convenience init() {
        self.init(configuration: .comment)
    }

    convenience init(url: URL) {
        self.init()
        self.url = url
    }

    @available(*, unavailable)
    init(arrangedSubviews: [UIView]) {
        fatalError("init(arrangedSubviews:) has not been implemented")
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        pause()
        player = nil
    }

    @objc func proximityChanged() {
        do {
            if UIDevice.current.proximityState {
                try AVAudioSession.sharedInstance().overrideOutputAudioPort(.none)
            } else {
                try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
            }
        } catch {
            return DDLogError("AudioView/proximityChanged: output port [\(error)]")
        }
    }

    func play() {
        guard let player = player else { return }
        guard let duration = player.currentItem?.duration else { return }
        guard duration.isNumeric else { return }

        if isPlayerAtTheEnd {
            player.seek(to: .zero)
        }

        MainAppContext.shared.mediaDidStartPlaying.send(url)
        UIApplication.shared.isIdleTimerDisabled = true
        UIDevice.current.isProximityMonitoringEnabled = true

        sessionManager.save()

        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord)
            if !UIDevice.current.proximityState {
                try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
            }
        } catch {
            return DDLogError("AudioView/play: audio session [\(error)]")
        }

        player.play()
        delegate?.audioViewDidStartPlaying(self)
    }

    func pause() {
        player?.pause()
        sessionManager.restore()
        UIDevice.current.isProximityMonitoringEnabled = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func updateIsPlaying() {
        playPauseButton.setImage(isPlaying ? configuration.pauseIcon : configuration.playIcon, for: .normal)
    }

    private func updateState() {
        let controlColor: UIColor
        switch state {
        case .normal:
            controlColor = .primaryBlue
        case .played, .loading:
            controlColor = .audioViewControlsPlayed
        }
        playPauseButton.tintColor = controlColor
        slider.minimumTrackTintColor = controlColor
        slider.tintColor = controlColor

        if state == .loading {
            loadingIndicator.startAnimating()
            playPauseButton.isHidden = true
        } else {
            loadingIndicator.stopAnimating()
            playPauseButton.isHidden = false
        }
    }

    private func updateProgress() {
        guard let player = player else { return }
        guard let duration = player.currentItem?.asset.duration else { return }
        guard duration.isNumeric else { return }

        let current = player.currentTime()
        slider.setValue(isPlayerAtTheEnd && player.rate == 0 ? 0 : Float(current.seconds / duration.seconds), animated: false)

        let formatted = TimeInterval(player.rate > 0 ? (duration.seconds - current.seconds) : duration.seconds).formatted
        delegate?.audioView(self, at: formatted)
    }

    @objc private func onSliderValueUpdate() {
        guard let player = player else { return }
        guard let duration = player.currentItem?.duration else { return }
        guard duration.isNumeric else { return }

        if player.rate > 0 {
            pause()
        }

        player.seek(to: CMTime(seconds: duration.seconds * Double(slider.value), preferredTimescale: duration.timescale))
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
