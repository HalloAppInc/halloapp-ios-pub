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

    weak var delegate: AudioViewDelegate?

    var state: AudioViewState = .normal {
        didSet {
            updateControls()
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
        guard let rate = player?.rate else { return false }
        return rate > 0
    }

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
                self.updateControls()
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

            updateControls()
            updateProgress()
        }
    }

    private var playIcon: UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: 24)
        let iconColor: UIColor = state == .played ? .audioViewControlsPlayed : .primaryBlue
        let icon = UIImage(systemName: "play.fill", withConfiguration: config)!.withTintColor(iconColor, renderingMode: .alwaysOriginal)

        return icon
    }

    private var pauseIcon: UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: 20)
        let icon = UIImage(systemName: "pause.fill", withConfiguration: config)!.withTintColor(.audioViewControlsPlayed, renderingMode: .alwaysOriginal)

        return icon
    }

    private var thumbIcon: UIImage {
        let iconColor: UIColor = state == .played ? .audioViewControlsPlayed : .primaryBlue
        let radius: CGFloat = 16
        let thumb = UIView(frame: CGRect(x: 0, y: radius / 2, width: radius, height: radius))
        thumb.backgroundColor = iconColor
        thumb.layer.borderWidth = 0.4
        thumb.layer.borderColor = UIColor.darkGray.cgColor
        thumb.layer.cornerRadius = radius / 2

        return UIGraphicsImageRenderer(bounds: thumb.bounds).image { thumb.layer.render(in: $0.cgContext) }
    }

    // The play button is small. This one has bigger hit area to make it easier for tapping.
    private class PlayButton: UIButton {
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            return bounds.insetBy(dx: -24, dy: -24).contains(point)
        }
    }

    // improves hit rate
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return bounds.insetBy(dx: -24, dy: -24).contains(point)
    }

    private lazy var playButton: UIButton = {
        let btn = PlayButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setImage(playIcon, for: .normal)
        btn.addTarget(self, action: #selector(onPlayButtonTap), for: [.touchUpInside, .touchUpOutside])
        btn.widthAnchor.constraint(equalToConstant: 20).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 20).isActive = true

        return btn
    } ()

    private lazy var slider: UISlider = {
        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.setThumbImage(thumbIcon, for: .normal)
        slider.addTarget(self, action: #selector(onSliderValueUpdate), for: .valueChanged)
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.minimumTrackTintColor = .audioViewControlsPlayed

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

    init() {
        super.init(frame: .zero)

        axis = .horizontal
        alignment = .center
        spacing = 12
        isLayoutMarginsRelativeArrangement = true

        addArrangedSubview(loadingIndicator)
        addArrangedSubview(playButton)
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
    }

    convenience init(url: URL) {
        self.init()
        self.url = url
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

    private func updateControls() {
        if state == .loading {
            loadingIndicator.startAnimating()
            playButton.isHidden = true
        } else {
            loadingIndicator.stopAnimating()
            playButton.isHidden = false
        }

        guard let player = player else { return }
        playButton.setImage(player.rate > 0 ? pauseIcon : playIcon, for: .normal)
        slider.setThumbImage(thumbIcon, for: .normal)
        slider.minimumTrackTintColor = state == .played ? .audioViewControlsPlayed : .primaryBlue
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
