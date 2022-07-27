//
//  MediaComposerTextView.swift
//  HalloApp
//
//  Created by Stefan Fidanov on 26.07.22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import Foundation
import UIKit

protocol MediaComposerTextDelegate: ContentTextViewDelegate, PostAudioViewDelegate, AudioRecorderControlViewDelegate {
    func mediaComposerText(_ textView: MediaComposerTextView, didSelect mention: MentionableUser)
    func mediaComposerTextStopRecording(_ textView: MediaComposerTextView)
}

class MediaComposerTextView: UIStackView {

    weak var delegate: MediaComposerTextDelegate? {
        didSet {
            textView.delegate = delegate
            audioRecorderControlView.delegate = delegate
            audioPlayerView.delegate = delegate
        }
    }

    private lazy var placeholder: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16)
        label.textColor = .label.withAlphaComponent(0.4)

        return label
    }()

    private lazy var textViewHeightConstraint: NSLayoutConstraint = {
        textView.heightAnchor.constraint(equalToConstant: 0)
    }()

    private lazy var textView: ContentTextView = {
        let textView = ContentTextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = true
        textView.isUserInteractionEnabled = true
        textView.backgroundColor = .clear
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.font = ComposerConstants.getFontSize(textSize: 0, isPostWithMedia: true)
        textView.tintColor = .systemBlue
        textView.textColor = ComposerConstants.textViewTextColor

        textView.addSubview(placeholder)

        NSLayoutConstraint.activate([
            placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 5),
            placeholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: 9)
        ])

        return textView
    }()

    private lazy var mentionPickerView: HorizontalMentionPickerView = {
        let picker = HorizontalMentionPickerView(config: .composer, avatarStore: MainAppContext.shared.avatarStore)
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.setContentHuggingPriority(.defaultHigh, for: .vertical)
        picker.clipsToBounds = true
        picker.isHidden = true
        picker.didSelectItem = { [weak self] item in
            guard let self = self else { return }

            self.textView.accept(mention: item)
            self.delegate?.mediaComposerText(self, didSelect: item)
        }

        return picker
    }()

    private lazy var audioRecorderControlView: AudioRecorderControlView = {
        let controlView = AudioRecorderControlView(configuration: .post)
        controlView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            controlView.widthAnchor.constraint(equalToConstant: 24),
            controlView.heightAnchor.constraint(equalToConstant: 24),
        ])

        return controlView
    }()

    private lazy var audioPlayerView: PostAudioView = {
        let view = PostAudioView(configuration: .composerWithMedia)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isSeen = true
        view.isHidden = true

        return view
    }()

    private lazy var textFieldView: UIView = {
        let backgroundView = ShadowView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.backgroundColor = .secondarySystemGroupedBackground
        backgroundView.layer.cornerRadius = 20
        backgroundView.layer.masksToBounds = true
        backgroundView.layer.borderWidth = 0.5
        backgroundView.layer.borderColor = UIColor.black.withAlphaComponent(0.12).cgColor
        backgroundView.layer.shadowOpacity = 1
        backgroundView.layer.shadowRadius = 1
        backgroundView.layer.shadowOffset = CGSize(width: 0, height: 1)
        backgroundView.layer.shadowPath = UIBezierPath(roundedRect: backgroundView.bounds, cornerRadius: 20).cgPath
        backgroundView.layer.shadowColor = UIColor.black.withAlphaComponent(0.04).cgColor

        let field = UIStackView(arrangedSubviews: [])
        field.translatesAutoresizingMaskIntoConstraints = false
        field.spacing = 0
        field.axis = .horizontal
        field.alignment = .center
        field.isLayoutMarginsRelativeArrangement = true
        field.layoutMargins = UIEdgeInsets(top: 7, left: 30, bottom: 7, right: 30)
        field.addSubview(backgroundView)
        field.addArrangedSubview(textView)
        field.addArrangedSubview(audioRecorderControlView)
        field.addSubview(voiceNoteTimeLabel)
        field.addSubview(stopVoiceRecordingButton)
        field.addSubview(audioPlayerView)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: field.leadingAnchor, constant: 12),
            backgroundView.trailingAnchor.constraint(equalTo: field.trailingAnchor, constant: -12),
            backgroundView.topAnchor.constraint(equalTo: field.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: field.bottomAnchor),
            voiceNoteTimeLabel.leadingAnchor.constraint(equalTo: field.leadingAnchor, constant: 40),
            voiceNoteTimeLabel.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            stopVoiceRecordingButton.centerXAnchor.constraint(equalTo: field.centerXAnchor),
            stopVoiceRecordingButton.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            audioPlayerView.leadingAnchor.constraint(equalTo: field.leadingAnchor, constant: 12),
            audioPlayerView.trailingAnchor.constraint(equalTo: field.trailingAnchor, constant: -12),
            audioPlayerView.centerYAnchor.constraint(equalTo: field.centerYAnchor),
        ])

        return field
    }()

    private lazy var voiceNoteTimeLabel: AudioRecorderTimeView = {
        let label = AudioRecorderTimeView()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .clear
        label.isHidden = true

        return label
    }()

    // note: Displays when the audio recorder is in the locked state.
    private lazy var stopVoiceRecordingButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .primaryBlue
        button.setTitle(Localizations.buttonStop, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 19)
        button.addTarget(self, action: #selector(stopVoiceRecordingAction), for: .touchUpInside)
        button.isHidden = true

        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        axis = .vertical
        spacing = 8

        addArrangedSubview(mentionPickerView)
        addArrangedSubview(textFieldView)

        textViewHeightConstraint.isActive = true

        placeholder.text = Localizations.writeDescription
    }

    public func update(with input: MentionInput, mentionables: [MentionableUser], recorder: AudioRecorder, voiceNote: PendingMedia?, locked: Bool) {
        placeholder.isHidden = !input.text.isEmpty
        textView.alpha = recorder.isRecording || voiceNote != nil ? 0 : 1
        textView.text = input.text
        textView.mentions = input.mentions
        textView.font = ComposerConstants.getFontSize(textSize: input.text.count, isPostWithMedia: true)

        let size = textView.sizeThatFits(CGSize(width: textView.frame.size.width, height: CGFloat.greatestFiniteMagnitude))
        textViewHeightConstraint.constant = min(size.height, 86)

        updateMentionPicker(with: mentionables)

        audioRecorderControlView.isHidden = !input.text.isEmpty || voiceNote != nil

        voiceNoteTimeLabel.isHidden = !recorder.isRecording
        voiceNoteTimeLabel.text = recorder.duration?.formatted ?? 0.formatted

        stopVoiceRecordingButton.isHidden = !recorder.isRecording || !locked

        audioPlayerView.isHidden = recorder.isRecording || voiceNote == nil

        if let voiceNote = voiceNote, audioPlayerView.url != voiceNote.fileURL {
            audioPlayerView.url = voiceNote.fileURL
        }
    }

    @objc func stopVoiceRecordingAction() {
        delegate?.mediaComposerTextStopRecording(self)
    }
}

// MARK: Mentions
extension MediaComposerTextView {
    private func updateMentionPicker(with mentionables: [MentionableUser]) {
        // don't animate the initial load
        let shouldShow = !mentionables.isEmpty
        let shouldAnimate = mentionPickerView.isHidden != shouldShow
        mentionPickerView.updateItems(mentionables, animated: shouldAnimate)

        mentionPickerView.isHidden = !shouldShow
    }
}

private extension Localizations {
    static var writeDescription: String {
        NSLocalizedString("composer.placeholder.media.description", value: "Write a description", comment: "Placeholder text for media caption field in post composer.")
    }
}
