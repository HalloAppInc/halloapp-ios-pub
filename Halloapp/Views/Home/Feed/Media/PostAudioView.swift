//
//  PostAudioView.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 11/22/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Combine
import UIKit

// MARK: PostAudioViewDelegate

protocol PostAudioViewDelegate: AnyObject {
    func postAudioViewDidRequestDeletion(_ postAudioView: PostAudioView)
    func postAudioView(_ postAudioView: PostAudioView, didUpdateIsPlayingTo isPlaying: Bool)
}

// Add default implementations to make all methods optional
extension PostAudioViewDelegate {

    func postAudioViewDidRequestDeletion(_ postAudioView: PostAudioView) { }

    func postAudioView(_ postAudioView: PostAudioView, didUpdateIsPlayingTo isPlaying: Bool) { }
}

// MARK: PostAudioViewConfiguration

struct PostAudioViewConfiguration {
    fileprivate let showDeleteButton: Bool
    fileprivate let backgroundColor: UIColor

    static let composer = PostAudioViewConfiguration(showDeleteButton: true,
                                                     backgroundColor: .feedPostAudioPlayerBackground)

    static let composerWithMedia = PostAudioViewConfiguration(showDeleteButton: true,
                                                              backgroundColor: .feedPostAudioPlayerCommentsBackground)

    static let feed = PostAudioViewConfiguration(showDeleteButton: false,
                                                 backgroundColor: .feedPostAudioPlayerBackground)

    static let comments = PostAudioViewConfiguration(showDeleteButton: false,
                                                     backgroundColor: .feedPostAudioPlayerCommentsBackground)
}

// MARK: PostAudioView

class PostAudioView: UIView {

    private var mediaReadyPromise: AnyCancellable?

    private let deleteButtonSize = CGSize(width: 32, height: 32)

    private let backgroundView: UIView = {
        let backgroundView = UIView()
        backgroundView.layer.shadowColor = UIColor.black.withAlphaComponent(0.07).cgColor
        backgroundView.layer.shadowOffset = CGSize(width: 0, height: 1)
        backgroundView.layer.shadowOpacity = 1
        backgroundView.layer.shadowRadius = 0
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        return backgroundView
    }()

    private lazy var deleteButton: UIButton = {
        let deleteButton = UIButton(type: .system)
        deleteButton.addTarget(self, action: #selector(didTapDelete), for: .touchUpInside)
        deleteButton.imageView?.contentMode = .center
        deleteButton.layer.cornerRadius = min(deleteButtonSize.width, deleteButtonSize.height) / 2
        deleteButton.layer.masksToBounds = true
        deleteButton.setBackgroundColor(.audioComposerDeleteButtonBackground, for: .normal)
        let image = UIImage(systemName: "trash.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14))
        deleteButton.setImage(image, for: .normal)
        deleteButton.tintColor = .audioComposerDeleteButtonForeground
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        return deleteButton
    }()

    private let audioView: AudioView = {
        let audioView = AudioView(configuration: .post)
        audioView.translatesAutoresizingMaskIntoConstraints = false
        return audioView
    }()

    private let timerLabel: UILabel = {
        let timerLabel = UILabel()
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        timerLabel.textColor = .feedPostAudioPlayerDurationText
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        return timerLabel
    }()

    override var directionalLayoutMargins: NSDirectionalEdgeInsets {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

    var isSeen = false {
        didSet {
            updateState()
        }
    }

    private(set) var isLoading = false {
        didSet {
            updateState()
        }
    }

    var feedMedia: FeedMedia? {
        didSet {
            guard let feedMedia = feedMedia, feedMedia.type == .audio else {
                return
            }

            mediaReadyPromise?.cancel()

            if feedMedia.isMediaAvailable, let fileURL = feedMedia.fileURL {
                url = fileURL
            } else {
                // Wait for fileURL
                isLoading = true
                mediaReadyPromise = feedMedia.$isMediaAvailable.sink { [weak self] isMediaAvailable in
                    if isMediaAvailable, let self = self {
                        self.url = feedMedia.fileURL
                        self.isLoading = false
                    }
                }
            }
        }
    }

    var url: URL? {
        get {
            return audioView.url
        }
        set {
            mediaReadyPromise?.cancel()

            if newValue != url {
                audioView.url = newValue
            }
        }
    }

    weak var delegate: PostAudioViewDelegate?

    init(configuration: PostAudioViewConfiguration) {
        super.init(frame: .zero)

        directionalLayoutMargins = .zero

        backgroundView.backgroundColor = configuration.backgroundColor
        addSubview(backgroundView)

        if configuration.showDeleteButton {
            deleteButton.addTarget(self, action: #selector(didTapDelete), for: .touchUpInside)
            backgroundView.addSubview(deleteButton)
        }

        audioView.delegate = self
        backgroundView.addSubview(audioView)

        backgroundView.addSubview(timerLabel)

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),

            audioView.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),

            timerLabel.leadingAnchor.constraint(equalTo: audioView.trailingAnchor, constant: 10),
            timerLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -20),
            timerLabel.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
        ])

        if configuration.showDeleteButton {
            NSLayoutConstraint.activate([
                deleteButton.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 14),
                deleteButton.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
                deleteButton.heightAnchor.constraint(equalToConstant: deleteButtonSize.width),
                deleteButton.widthAnchor.constraint(equalToConstant: deleteButtonSize.height),

                audioView.leadingAnchor.constraint(equalTo: deleteButton.trailingAnchor, constant: 14),
            ])
        } else {
            NSLayoutConstraint.activate([
                audioView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 20),
            ])
        }

        resetTimerText()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let cornerRadius = min(backgroundView.bounds.width, backgroundView.bounds.height) / 2
        backgroundView.layer.cornerRadius = cornerRadius
        backgroundView.layer.shadowPath = UIBezierPath(roundedRect: backgroundView.bounds,
                                                       cornerRadius: cornerRadius).cgPath
    }

    private func resetTimerText() {
        timerLabel.text = TimeInterval(0).formatted
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric,
                      height: 60 + directionalLayoutMargins.top + directionalLayoutMargins.bottom)
    }

    private func updateState() {
        if isLoading {
            audioView.state = .loading
        } else {
            audioView.state = isSeen ? .played : .normal
        }
    }

    @objc func didTapDelete() {
        delegate?.postAudioViewDidRequestDeletion(self)
    }
}

extension PostAudioView: AudioViewDelegate {

    func audioView(_ view: AudioView, at time: String) {
        timerLabel.text = time
    }

    func audioViewDidStartPlaying(_ view: AudioView) {
        delegate?.postAudioView(self, didUpdateIsPlayingTo: true)
    }

    func audioViewDidEndPlaying(_ view: AudioView, completed: Bool) {
        delegate?.postAudioView(self, didUpdateIsPlayingTo: false)
    }
}
