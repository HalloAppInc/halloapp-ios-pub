//
//  UnifiedComposerView.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 9/12/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import UIKit

protocol UnifiedComposerViewDelegate: ContentTextViewDelegate, PostAudioViewDelegate, AudioRecorderControlViewDelegate {
    func unifiedComposer(_ unifiedComposerView: UnifiedComposerView, didUpdate data: LinkPreviewData?, andImage image: UIImage?)
    func unifiedComposer(_ unifiedComposerView: UnifiedComposerView, didSelect mention: MentionableUser)
    func unifiedComposerDidTapPreviewLink(_ unifiedComposerView: UnifiedComposerView)
    func unifiedComposerOpenMediaPicker(_ unifiedComposerView: UnifiedComposerView)
    func unifiedComposerStopRecording(_ unifiedComposerView: UnifiedComposerView)
}

class UnifiedComposerView: UIStackView {

    weak var delegate: UnifiedComposerViewDelegate? {
        didSet {
            textView.delegate = delegate
            audioRecorderControlView.delegate = delegate
            audioPlayerView.delegate = delegate
        }
    }

    private lazy var audioRecorderControlView: AudioRecorderControlView = {
        let controlView = AudioRecorderControlView(configuration: .unifiedPost)
        controlView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            controlView.widthAnchor.constraint(equalToConstant: 28),
            controlView.heightAnchor.constraint(equalToConstant: 28),
        ])

        return controlView
    }()

    private lazy var audioPlayerView: PostAudioView = {
        let view = PostAudioView(configuration: .unifiedComposer)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isSeen = true
        view.isHidden = true
        view.setContentHuggingPriority(.defaultHigh, for: .vertical)

        return view
    }()

    private lazy var stopVoiceRecordingButton: UIButton = {
        let stopVoiceRecordingButton = UIButton(type: .system)
        stopVoiceRecordingButton.tintColor = .primaryBlue
        stopVoiceRecordingButton.setTitle(Localizations.buttonStop, for: .normal)
        stopVoiceRecordingButton.titleLabel?.font = .scaledSystemFont(ofSize: 17, weight: .semibold)
        stopVoiceRecordingButton.addTarget(self, action: #selector(stopVoiceRecordingAction), for: .touchUpInside)
        stopVoiceRecordingButton.isHidden = true

        return stopVoiceRecordingButton
    }()

    private lazy var voiceNoteTimeLabel: AudioRecorderTimeView = {
        let label = AudioRecorderTimeView()
        label.backgroundColor = .clear
        label.isHidden = true
        return label
    }()

    private lazy var inlineMediaPickerButton: UIButton = {
        let inlineMediaPickerButton = UIButton(type: .system)
        inlineMediaPickerButton.addTarget(self, action: #selector(openMediaPickerAction), for: .touchUpInside)
        inlineMediaPickerButton.setBackgroundImage(UIImage(named: "icon_add_photo"), for: .normal)
        inlineMediaPickerButton.tintColor = .primaryBlue
        return inlineMediaPickerButton
    }()

    private lazy var mediaPickerButtonView: UIView = {
        let mediaPickerButtonView = UIView()

        var mediaPickerButtonConfiguration: UIButton.Configuration = .plain()
        mediaPickerButtonConfiguration.baseForegroundColor = .primaryBlue
        mediaPickerButtonConfiguration.image = UIImage(named: "icon_add_photo")
        mediaPickerButtonConfiguration.title = Localizations.addMedia
        mediaPickerButtonConfiguration.imagePadding = 4
        mediaPickerButtonConfiguration.imagePlacement = .top

        let mediaPickerButton = UIButton(type: .system)
        mediaPickerButton.configuration = mediaPickerButtonConfiguration
        mediaPickerButton.addTarget(self, action: #selector(openMediaPickerAction), for: .touchUpInside)
        mediaPickerButton.setContentHuggingPriority(.defaultHigh, for: .vertical)

        let imageSize = mediaPickerButton.imageView?.intrinsicContentSize ?? .zero
        let titleSize = mediaPickerButton.titleLabel?.intrinsicContentSize ?? .zero

        mediaPickerButton.translatesAutoresizingMaskIntoConstraints = false
        mediaPickerButtonView.addSubview(mediaPickerButton)

        NSLayoutConstraint.activate([
            mediaPickerButton.centerXAnchor.constraint(equalTo: mediaPickerButtonView.centerXAnchor),
            mediaPickerButton.topAnchor.constraint(equalTo: mediaPickerButtonView.topAnchor, constant: 100),
            mediaPickerButton.bottomAnchor.constraint(equalTo: mediaPickerButtonView.bottomAnchor, constant: -40),
        ])

        return mediaPickerButtonView
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
            self.delegate?.unifiedComposer(self, didSelect: item)
        }

        return picker
    }()

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()

        scrollableContentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(scrollableContentView)

        NSLayoutConstraint.activate([
            scrollableContentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            scrollableContentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            scrollableContentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            scrollableContentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            scrollableContentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            scrollableContentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        return scrollView
    }()

    private lazy var scrollableContentView: UIStackView = {
        let scrollableContentView = UIStackView(arrangedSubviews: [textView, linkPreviewView])
        scrollableContentView.axis = .vertical
        scrollableContentView.spacing = 8
        return scrollableContentView
    }()

    private lazy var cardView: UIView = {
        let stackView = UIStackView(arrangedSubviews: [scrollView, mediaPickerButtonView, audioPlayerView, mediaFooter])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)

        let cardView = UIView()
        cardView.backgroundColor = .secondarySystemGroupedBackground
        cardView.layer.cornerRadius = ComposerConstants.backgroundRadius
        cardView.layer.shadowOpacity = 1
        cardView.layer.shadowColor = UIColor.black.withAlphaComponent(0.08).cgColor
        cardView.layer.shadowRadius = 8
        cardView.layer.shadowOffset = CGSize(width: 0, height: 5)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        stackView.insertSubview(cardView, at: 0)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: stackView.leadingAnchor, constant: 12),
            cardView.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: -12),
            cardView.topAnchor.constraint(equalTo: stackView.topAnchor),
            cardView.bottomAnchor.constraint(equalTo: stackView.bottomAnchor),
        ])

        return stackView
    }()

    private lazy var textView: ContentTextView = {
        let textView = ContentTextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isScrollEnabled = false
        textView.isEditable = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.font = ComposerConstants.getFontSize(textSize: 0, isPostWithMedia: false)
        textView.tintColor = .systemBlue
        textView.textColor = ComposerConstants.textViewTextColor
        textView.backgroundColor = .secondarySystemGroupedBackground
        textView.placeholder = Localizations.writePost
        textView.placeholderColor = .label.withAlphaComponent(0.4)

        NSLayoutConstraint.activate([
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 86),
        ])

        return textView
    }()

    private lazy var linkPreviewView: PostComposerLinkPreviewView = {
        let linkPreviewView = PostComposerLinkPreviewView() { [weak self] resetLink, linkPreviewData, linkPreviewImage in
            guard let self = self else { return }

            self.linkPreviewView.isHidden = resetLink
            self.delegate?.unifiedComposer(self, didUpdate: linkPreviewData, andImage: linkPreviewImage)
        }

        linkPreviewView.translatesAutoresizingMaskIntoConstraints = false
        linkPreviewView.isHidden = true
        linkPreviewView.setContentHuggingPriority(.defaultHigh, for: .vertical)

        linkPreviewView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(previewTappedAction(sender:))))

        return linkPreviewView
    }()

    private lazy var mediaFooter: UIView = {
        let mediaFooter = UIView()

        inlineMediaPickerButton.translatesAutoresizingMaskIntoConstraints = false
        mediaFooter.addSubview(inlineMediaPickerButton)

        voiceNoteTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        mediaFooter.addSubview(voiceNoteTimeLabel)

        stopVoiceRecordingButton.translatesAutoresizingMaskIntoConstraints = false
        mediaFooter.addSubview(stopVoiceRecordingButton)

        audioRecorderControlView.translatesAutoresizingMaskIntoConstraints = false
        mediaFooter.addSubview(audioRecorderControlView)

        let minimizeHeightConstraint = mediaFooter.heightAnchor.constraint(equalToConstant: 0)
        minimizeHeightConstraint.priority = UILayoutPriority(1)

        NSLayoutConstraint.activate([
            inlineMediaPickerButton.leadingAnchor.constraint(equalTo: mediaFooter.leadingAnchor, constant: 8),
            inlineMediaPickerButton.bottomAnchor.constraint(equalTo: mediaFooter.bottomAnchor, constant: -8),
            inlineMediaPickerButton.topAnchor.constraint(greaterThanOrEqualTo: mediaFooter.topAnchor),

            voiceNoteTimeLabel.leadingAnchor.constraint(equalTo: mediaFooter.leadingAnchor, constant: 16),
            voiceNoteTimeLabel.bottomAnchor.constraint(equalTo: mediaFooter.bottomAnchor, constant: -8),
            voiceNoteTimeLabel.topAnchor.constraint(greaterThanOrEqualTo: mediaFooter.topAnchor),

            audioRecorderControlView.trailingAnchor.constraint(equalTo: mediaFooter.trailingAnchor, constant: -8),
            audioRecorderControlView.bottomAnchor.constraint(equalTo: mediaFooter.bottomAnchor, constant: -8),
            audioRecorderControlView.topAnchor.constraint(greaterThanOrEqualTo: mediaFooter.topAnchor),

            stopVoiceRecordingButton.centerXAnchor.constraint(equalTo: mediaFooter.centerXAnchor),
            stopVoiceRecordingButton.bottomAnchor.constraint(equalTo: mediaFooter.bottomAnchor, constant: -8),
            stopVoiceRecordingButton.topAnchor.constraint(greaterThanOrEqualTo: mediaFooter.topAnchor),

            minimizeHeightConstraint,
        ])

        return mediaFooter
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        textView.becomeFirstResponder()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        axis = .vertical
        spacing = 10

        addArrangedSubview(mentionPickerView)
        addArrangedSubview(cardView)
    }

    public func update(with input: MentionInput, mentionables: [MentionableUser], recorder: AudioRecorder, voiceNote: PendingMedia?, locked: Bool) {
        textView.text = input.text
        textView.mentions = input.mentions
        textView.font = ComposerConstants.getFontSize(textSize: input.text.count, isPostWithMedia: false)
        scrollView.isHidden = voiceNote != nil

        updateLinkPreviewViewIfNecessary(with: input)
        updateMentionPicker(with: mentionables)

        audioRecorderControlView.isEnabled = input.text.isEmpty && !recorder.isRecording
        audioRecorderControlView.isHidden = voiceNote != nil

        voiceNoteTimeLabel.isHidden = !recorder.isRecording
        voiceNoteTimeLabel.text = recorder.duration?.formatted ?? 0.formatted

        stopVoiceRecordingButton.isHidden = !recorder.isRecording || !locked

        audioPlayerView.isHidden = recorder.isRecording || voiceNote == nil

        inlineMediaPickerButton.isHidden = recorder.isRecording || voiceNote != nil
        mediaPickerButtonView.isHidden = voiceNote == nil

        mediaFooter.isHidden = voiceNote != nil

        if let voiceNote = voiceNote, audioPlayerView.url != voiceNote.fileURL {
            audioPlayerView.url = voiceNote.fileURL
        }
    }

    @objc func stopVoiceRecordingAction() {
        delegate?.unifiedComposerStopRecording(self)
    }

    @objc func openMediaPickerAction() {
        delegate?.unifiedComposerOpenMediaPicker(self)
    }
}

// MARK: Link Preview
extension UnifiedComposerView {
    private func updateLinkPreviewViewIfNecessary(with input: MentionInput) {
        if let url = detectLink(text: input.text) {
            linkPreviewView.updateLink(url: url)
            linkPreviewView.isHidden = false
        } else {
            linkPreviewView.isHidden = true
        }
    }

    private func detectLink(text: String) -> URL? {
        let linkDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = linkDetector.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))

        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let url = text[range]
            if let url = URL(string: String(url)) {
                // We only care about the first link
                return url
            }
        }

        return nil
    }

    @objc func previewTappedAction(sender: UITapGestureRecognizer) {
        if sender.state == .ended {
            delegate?.unifiedComposerDidTapPreviewLink(self)
        }
    }
}

// MARK: Mentions
extension UnifiedComposerView {
    private func updateMentionPicker(with mentionables: [MentionableUser]) {
        // don't animate the initial load
        let shouldShow = !mentionables.isEmpty
        let shouldAnimate = mentionPickerView.isHidden != shouldShow
        mentionPickerView.updateItems(mentionables, animated: shouldAnimate)

        mentionPickerView.isHidden = !shouldShow
    }
}
