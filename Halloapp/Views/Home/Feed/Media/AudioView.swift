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
        let playedControlColor: UIColor
        let thumbDiameter: CGFloat

        static let post = Configuration(playIcon: UIImage(systemName: "play.fill",
                                                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 20))!,
                                        pauseIcon: UIImage(systemName: "pause.fill",
                                                           withConfiguration: UIImage.SymbolConfiguration(pointSize: 20))!,
                                        playPauseButtonSize: CGSize(width: 32, height: 32),
                                        playedControlColor: UIColor.feedPostAudioPlayerControl,
                                        thumbDiameter: 12)

        static let comment = Configuration(playIcon: UIImage(systemName: "play.fill",
                                                             withConfiguration: UIImage.SymbolConfiguration(pointSize: 16))!,
                                           pauseIcon: UIImage(systemName: "pause.fill",
                                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 16))!,
                                           playPauseButtonSize: CGSize(width: 20, height: 20),
                                           playedControlColor: UIColor.audioViewControlsPlayed,
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
            player = url.flatMap { try? AVAudioPlayer(contentsOf: $0) }
        }
    }

    var isPlaying: Bool {
        return player?.isPlaying ?? false
    }

    private let configuration: Configuration

    private var mediaPlaybackCancellable: AnyCancellable?
    private var isSeeking = false
    private var wasPlayingBeforeSeek = false
    private var audioSession: AudioSession?
    private var displayLink: CADisplayLink? {
        willSet {
            displayLink?.invalidate()
        }
    }

    private var player: AVAudioPlayer? {
        didSet {
            player?.delegate = self
            updateProgress(currentTime: 0)
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
        slider.addTarget(self, action: #selector(onSliderTouchDown), for: .touchDown)
        slider.addTarget(self, action: #selector(onSliderValueChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(onSliderTouchUp), for: .touchUpInside)
        slider.addTarget(self, action: #selector(onSliderTouchUp), for: .touchUpOutside)
        slider.addTarget(self, action: #selector(onSliderTouchUp), for: .touchCancel)
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return slider
    } ()

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            indicator.widthAnchor.constraint(equalToConstant: 20),
            indicator.heightAnchor.constraint(equalToConstant: 20),
        ])
        return indicator
    } ()

    private var isPlayerAtTheEnd: Bool {
        guard let player = player else {
            return false
        }
        return abs(player.duration - player.currentTime) < 0.03
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
        invalidatePlayerAndDisplayLink()
    }

    private func invalidatePlayerAndDisplayLink() {
        player = nil
        displayLink?.invalidate()
    }

    func play() {
        guard let player = player else {
            return
        }

        if isPlayerAtTheEnd {
            player.currentTime = 0
        }

        audioSession = AudioSession(category: .play)
        AudioSessionManager.beginSession(audioSession)

        MainAppContext.shared.mediaDidStartPlaying.send(url)

        let displayLink = CADisplayLink(weakTarget: self, selector: #selector(onTimeUpdate))
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink

        player.play()
        updateIsPlaying()
        delegate?.audioViewDidStartPlaying(self)
    }

    func pause() {
        player?.pause()
        updateIsPlaying()
        displayLink = nil
        AudioSessionManager.endSession(audioSession)
        delegate?.audioViewDidEndPlaying(self, completed: false)
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
            controlColor = configuration.playedControlColor
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

    private func updateProgress(currentTime: TimeInterval) {
        guard let player = player else {
            return
        }

        let duration = player.duration

        if !isSeeking {
            slider.value = duration > 0 ? Float(currentTime / duration) : 0
        }

        delegate?.audioView(self, at: TimeInterval(duration - currentTime).formatted)
    }


// MARK: - Event Handling

    @objc private func onSliderTouchDown() {
        isSeeking = true

        if isPlaying {
            wasPlayingBeforeSeek = true
            // directly call play / pause while seeking to avoid cancelling audio session
            player?.pause()
            updateIsPlaying()
        }
    }

    @objc private func onSliderValueChanged() {
        guard let player = player else {
            return
        }

        let current = player.duration * TimeInterval(slider.value)
        player.currentTime = current
        updateProgress(currentTime: current)

    }

    @objc private func onSliderTouchUp() {
        isSeeking = false

        if wasPlayingBeforeSeek {
            wasPlayingBeforeSeek = false
            player?.play()
            updateIsPlaying()
        }
    }

    @objc private func onPlayButtonTap() {
        isPlaying ? pause() : play()
    }

    @objc private func onTimeUpdate() {
        updateProgress(currentTime: player?.currentTime ?? 0)
    }
}

extension AudioView: AVAudioPlayerDelegate {

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        updateIsPlaying()
        player.currentTime = 0
        AudioSessionManager.endSession(audioSession)
        delegate?.audioViewDidEndPlaying(self, completed: flag)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard let error = error else {
            return
        }
        DDLogError("AudioView/audioPlayerDecodeErrorDidOccur: \(error)")
    }
}
