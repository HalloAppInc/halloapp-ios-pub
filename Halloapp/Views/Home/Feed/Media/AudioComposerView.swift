//
//  AudioComposerView.swift
//  HalloApp
//
//  Created by Stefan Fidanov on 25.07.22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Combine
import Core
import CoreCommon
import Foundation
import UIKit

protocol AudioComposerDelegate: PostAudioViewDelegate {
    func audioComposerDidToggleRecording(_ audioComposerView: AudioComposerView)
}

class AudioComposerView: UIView {
    weak var delegate: AudioComposerDelegate? {
        didSet {
            playerView.delegate = delegate
        }
    }

    private var meterCancellables: Set<AnyCancellable> = []

    private lazy var title: UILabel = {
        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .systemFont(ofSize: 16)
        title.textColor = .audioComposerTitleText
        title.text = Localizations.newAudioPost

        return title
    }()

    private lazy var helper: UILabel = {
        let helper = UILabel()
        helper.translatesAutoresizingMaskIntoConstraints = false
        helper.font = .preferredFont(forTextStyle: .footnote)
        helper.textColor = .audioComposerHelperText
        helper.text = Localizations.tapToRecord

        return helper
    }()

    private lazy var recordImage: UIImage? = {
        UIImage(named: "icon_mic")?.withTintColor(.audioComposerRecordButtonBackground, renderingMode: .alwaysOriginal)
    }()

    private lazy var stopImage: UIImage? = {
        UIImage(named: "icon_stop")?.withTintColor(.audioComposerRecordButtonForeground, renderingMode: .alwaysOriginal)
    }()

    private lazy var recordButton: UIButton = {
        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(recordImage, for: .normal)
        button.backgroundColor = .audioComposerRecordButtonForeground
        button.layer.borderWidth = 2
        button.layer.borderColor = UIColor.audioComposerRecordButtonForeground.cgColor
        button.layer.cornerRadius = 38
        button.layer.shadowOpacity = 1
        button.layer.shadowColor = UIColor.black.withAlphaComponent(0.15).cgColor
        button.layer.shadowRadius = 4
        button.layer.shadowOffset = CGSize(width: 0, height: 4)
        button.layer.masksToBounds = false
        button.addTarget(self, action: #selector(toggleRecordingAction), for: .touchUpInside)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 76),
            button.heightAnchor.constraint(equalToConstant: 76),
        ])

        return button
    }()

    private lazy var timeLabel: UILabel = {
        let label = AudioRecorderTimeView()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .clear
        label.isHidden = true

        return label
    }()

    private lazy var playerView: PostAudioView = {
        let view = PostAudioView(configuration: .composer)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isSeen = true
        view.isHidden = true

        return view
    }()

    private lazy var meterLarge: UIImageView = {
        let view = UIImageView(image: UIImage(named: "AudioRecorderLevelsLarge"))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit

        return view
    }()

    private lazy var meterSmall: UIImageView = {
        let view = UIImageView(image: UIImage(named: "AudioRecorderLevelsSmall"))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit

        return view
    }()

    private lazy var meterView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(meterLarge)
        view.addSubview(meterSmall)

        meterLarge.constrain(to: view)
        meterSmall.constrain(to: view)

        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 76),
            view.heightAnchor.constraint(equalToConstant: 76),
        ])

        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = ComposerConstants.backgroundRadius
        layer.shadowOpacity = 1
        layer.shadowColor = UIColor.black.withAlphaComponent(0.08).cgColor
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 5)

        addSubview(title)
        addSubview(meterView)
        addSubview(recordButton)
        addSubview(helper)
        addSubview(timeLabel)
        addSubview(playerView)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: 26),
            title.centerXAnchor.constraint(equalTo: centerXAnchor),
            recordButton.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 75),
            recordButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            helper.topAnchor.constraint(equalTo: recordButton.bottomAnchor, constant: 11),
            helper.centerXAnchor.constraint(equalTo: centerXAnchor),
            helper.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -67),
            timeLabel.centerXAnchor.constraint(equalTo: title.centerXAnchor),
            timeLabel.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            playerView.centerYAnchor.constraint(equalTo: centerYAnchor),
            meterView.centerXAnchor.constraint(equalTo: recordButton.centerXAnchor),
            meterView.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
        ])
    }

    public func update(with recorder: AudioRecorder, voiceNote: PendingMedia?) {
        if recorder.isRecording {
            timeLabel.isHidden = false
            timeLabel.text = recorder.duration?.formatted ?? 0.formatted
            title.alpha = 0
            recordButton.backgroundColor = .audioComposerRecordButtonBackground
            recordButton.setImage(stopImage, for: .normal)
            helper.text = Localizations.buttonStop
            helper.textColor = .audioComposerRecordButtonForeground
            playerView.isHidden = true
            meterView.isHidden = false

            if meterCancellables.count == 0 {
                recorder.meter.receive(on: RunLoop.main).sink { [weak self] (averagePower: Float, _) in
                    guard let self = self else { return }
                    let scale = self.convertMeterToScale(dbm: CGFloat(averagePower))
                    self.meterLarge.transform = CGAffineTransform(scaleX: scale, y: scale)
                }.store(in: &meterCancellables)

                recorder.meter.delay(for: .seconds(0.2), scheduler: RunLoop.main).sink { [weak self] (averagePower: Float, _) in
                    guard let self = self else { return }
                    let scale = self.convertMeterToScale(dbm: CGFloat(averagePower))
                    self.meterSmall.transform = CGAffineTransform(scaleX: scale, y: scale)
                }.store(in: &meterCancellables)
            }
        } else {
            timeLabel.isHidden = true
            title.alpha = 1
            recordButton.backgroundColor = .audioComposerRecordButtonForeground
            recordButton.setImage(recordImage, for: .normal)
            recordButton.isHidden = voiceNote != nil
            helper.text = Localizations.tapToRecord
            helper.textColor = .audioComposerHelperText
            helper.isHidden = voiceNote != nil
            meterView.isHidden = true

            playerView.isHidden = voiceNote == nil

            if let voiceNote = voiceNote, playerView.url != voiceNote.fileURL {
                playerView.url = voiceNote.fileURL
            }
        }
    }

    private func convertMeterToScale(dbm: CGFloat) -> CGFloat {
        return 1.0 + 0.4 * min(1.0, max(0.0, 8 * CGFloat(pow(10.0, (0.05 * dbm)))))
    }

    @objc private func toggleRecordingAction() {
        delegate?.audioComposerDidToggleRecording(self)
    }
}

private extension Localizations {
    static let newAudioPost = NSLocalizedString("composer.audio.title",
                                                value: "New Audio",
                                                comment: "Title for audio post composer")

    static let tapToRecord = NSLocalizedString("composer.audio.instructions",
                                               value: "Tap to record",
                                               comment: "Instructions for audio post composer")
}
