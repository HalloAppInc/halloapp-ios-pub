//
//  ContentInputView.swift
//  HalloApp
//
//  Created by Tanveer on 3/5/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Core
import CoreCommon
import AVKit
import Combine

protocol ContentInputDelegate: AnyObject {
    func inputView(_ inputView: ContentInputView, isTyping: Bool)
    func inputView(_ inputView: ContentInputView, possibleMentionsFor input: String) -> [MentionableUser]
    func inputView(_ inputView: ContentInputView, didPost content: ContentInputView.InputContent)
    func inputView(_ inputView: ContentInputView, didChangeHeightTo height: CGFloat)
    func inputView(_ inputView: ContentInputView, didClose panel: InputContextPanel)
    func inputViewDidSelectCamera(_ inputView: ContentInputView)
    func inputViewDidSelectContentOptions(_ inputView: ContentInputView)
    func inputView(_ inputView: ContentInputView, didPaste image: PendingMedia)
    
    func inputView(_ inputView: ContentInputView, didInterrupt recorder: AudioRecorder)
    func inputViewMicrophoneAccessDenied(_ inputView: ContentInputView)
    func inputViewMicrophoneAccessDeniedDuringCall(_ inputView: ContentInputView)
}

protocol InputContextPanel: UIView {
    var closeButton: UIButton { get }
}

// MARK: - constants

extension ContentInputView {
    struct Options: OptionSet {
        let rawValue: Int
        fileprivate static let mentions = Options(rawValue: 1 << 0)
        fileprivate static let typingIndication = Options(rawValue: 1 << 1)
        
        static let chat: Options = [typingIndication]
        static let comments: Options = [mentions]
    }
    
    private enum ContentState {
        /// No content; shows the placeholder.
        case none
        /// There is text, but it consists only of whitespaces and/or newlines.
        case invalidText
        /// There is input text.
        case text
        /// User is holding down on `voiceNoteControl`.
        case audioRecording
        /// `voiceNoteControl` is locked.
        case audioRecordingLocked
        /// User pushed `stopVoiceRecordingButton` and can now playback.
        case audioPlayback
    }
    
    struct InputContent {
        let mentionText: MentionText
        let media: [PendingMedia]
        let linkPreview: (data: LinkPreviewData, media: PendingMedia?)?
    }
    
    /// The padding between `textView` and the top and bottom edges of `textPanel`.
    private static let textViewPadding: CGFloat = 9.0
    /// The corner radius of `textView` when it's in the expanded state.
    private static let textViewCornerRadius: CGFloat = 17.0
    private static let textViewInsets = UIEdgeInsets(top: 10, left: 5, bottom: 10, right: 5)
    
    fileprivate static var borderColor: UIColor {
        return UIColor { traits in
            switch traits.userInterfaceStyle {
            case .dark:
                return .lightGray.withAlphaComponent(0.3)
            default:
                return .black.withAlphaComponent(0.2)
            }
        }
    }
    
    static let voiceNoteDurationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.zeroFormattingBehavior = .pad
        formatter.allowedUnits = [.second, .minute]

        return formatter
    }()
}

class ContentInputView: UIView {
    let options: Options
    private var contentState: ContentState = .none {
        didSet {
            if oldValue != contentState { refreshButtons() }
        }
    }
    
    weak var delegate: ContentInputDelegate?
    private var cancellables: Set<AnyCancellable> = []
    
    // MARK: - views
    
    /// - note: Everything goes in here.
    private lazy var vStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        
        stack.addArrangedSubview(linkPreviewPanel)
        stack.addArrangedSubview(mentionPicker)
        stack.addArrangedSubview(functionPanel)
        stack.addSubview(voiceNoteTimeLabel)
        stack.addSubview(stopVoiceRecordingButton)
        
        NSLayoutConstraint.activate([
            voiceNoteTimeLabel.leadingAnchor.constraint(equalTo: functionPanel.leadingAnchor, constant: 28),
            voiceNoteTimeLabel.centerYAnchor.constraint(equalTo: placeHolder.centerYAnchor),
            stopVoiceRecordingButton.centerXAnchor.constraint(equalTo: functionPanel.centerXAnchor),
            stopVoiceRecordingButton.centerYAnchor.constraint(equalTo: placeHolder.centerYAnchor),
        ])

        return stack
    }()
    
    /// The panel that contains all of the buttons, `placeHolder`, and `textView`.
    private lazy var functionPanel: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = nil
        
        view.addSubview(textViewShadowView)
        view.addSubview(plusButton)
        view.addSubview(photoButton)
        view.addSubview(voiceNoteControl)
        view.addSubview(postButton)
        view.addSubview(textView)
        view.addSubview(placeHolder)
        view.addSubview(audioPlaybackView)
        view.addSubview(deleteAudioRecordingButton)
        
        let edgePadding: CGFloat = 13
        let padding: CGFloat = 11
        
        let placeHolderTrailing = placeHolder.trailingAnchor.constraint(equalTo: photoButton.leadingAnchor,
                                                                       constant: -padding - 4)
        placeHolderTrailing.priority = .defaultHigh
        
        textViewPostButtonConstraint = placeHolder.trailingAnchor.constraint(equalTo: postButton.leadingAnchor,
                                                                            constant: -padding - 2)
        
        NSLayoutConstraint.activate([
            postButton.heightAnchor.constraint(equalToConstant: 39),
            postButton.widthAnchor.constraint(equalToConstant: 39),
            // positioning
            plusButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: edgePadding),
            plusButton.centerYAnchor.constraint(equalTo: placeHolder.centerYAnchor),
            placeHolder.leadingAnchor.constraint(equalTo: plusButton.trailingAnchor, constant: padding),
            placeHolder.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Self.textViewPadding),
            placeHolderTrailing,
            photoButton.centerYAnchor.constraint(equalTo: placeHolder.centerYAnchor),
            voiceNoteControl.centerYAnchor.constraint(equalTo: placeHolder.centerYAnchor),
            voiceNoteControl.leadingAnchor.constraint(equalTo: photoButton.trailingAnchor, constant: padding + 2),
            voiceNoteControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -edgePadding),
            postButton.centerYAnchor.constraint(equalTo: placeHolder.centerYAnchor),
            postButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -edgePadding),
            textView.leadingAnchor.constraint(equalTo: placeHolder.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: placeHolder.trailingAnchor),
            textView.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.textViewPadding),
            textView.bottomAnchor.constraint(equalTo: placeHolder.bottomAnchor),
            textView.heightAnchor.constraint(lessThanOrEqualToConstant: textView.maxHeight),
            textViewShadowView.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            textViewShadowView.trailingAnchor.constraint(equalTo: textView.trailingAnchor),
            textViewShadowView.topAnchor.constraint(equalTo: textView.topAnchor),
            textViewShadowView.bottomAnchor.constraint(equalTo: textView.bottomAnchor),
            audioPlaybackView.leadingAnchor.constraint(equalTo: deleteAudioRecordingButton.trailingAnchor, constant: padding),
            audioPlaybackView.trailingAnchor.constraint(equalTo: postButton.leadingAnchor, constant: -padding),
            audioPlaybackView.topAnchor.constraint(equalTo: placeHolder.topAnchor),
            audioPlaybackView.bottomAnchor.constraint(equalTo: placeHolder.bottomAnchor),
            deleteAudioRecordingButton.centerXAnchor.constraint(equalTo: plusButton.centerXAnchor),
            deleteAudioRecordingButton.centerYAnchor.constraint(equalTo: plusButton.centerYAnchor)
        ])
        
        return view
    }()
    
    private lazy var textViewShadowView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        
        view.layer.shadowColor = UIColor.black.withAlphaComponent(0.2).cgColor
        view.layer.shadowRadius = 3
        view.layer.shadowOpacity = 0.2
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
        // actual path is set in `layoutSubviews()`
        view.layer.shadowPath = UIBezierPath(rect: .zero).cgPath
        view.layer.opacity = 1
        view.layer.masksToBounds = false

        return view
    }()
    
    private(set) lazy var textView: ContentTextView = {
        let textView = ContentTextView(frame: .zero)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.textContainer.maximumNumberOfLines = 0
        textView.isScrollEnabled = false
        textView.backgroundColor = .primaryWhiteBlack
        textView.enablesReturnKeyAutomatically = true
        textView.font = UIFont.preferredFont(forTextStyle: .subheadline)
        textView.textContainerInset = Self.textViewInsets
        textView.scrollIndicatorInsets = UIEdgeInsets(top: Self.textViewInsets.top,
                                                     left: 0,
                                                   bottom: Self.textViewInsets.bottom,
                                                    right: 0)
        textView.layer.cornerRadius = Self.textViewCornerRadius
        textView.layer.cornerCurve = .continuous
        textView.delegate = self

        textView.layer.borderColor = Self.borderColor.cgColor
        textView.layer.borderWidth = 1 / UIScreen.main.scale
        
        return textView
    }()
    
    private lazy var placeHolder: UITextView = {
        let textView = ContentTextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.textContainer.maximumNumberOfLines = 1
        textView.backgroundColor = nil
        textView.text = Localizations.chatInputPlaceholder
        textView.font = UIFont.preferredFont(forTextStyle: .subheadline)
        textView.textColor = .placeholderText
        textView.isScrollEnabled = false
        textView.isUserInteractionEnabled = false
        textView.textContainerInset = Self.textViewInsets

        return textView
    }()
    
    private lazy var plusButton: UIButton = {
        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 21, weight: .medium)
        let image = UIImage(systemName: "plus")?.withConfiguration(config)
        button.setImage(image, for: .normal)
        button.addTarget(self, action: #selector(tappedShareOptions), for: .touchUpInside)
        
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        return button
    }()
    
    private lazy var voiceNoteControl: AudioRecorderControlView = {
        let control = AudioRecorderControlView(configuration: .comment)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.layer.zPosition = 1
        control.delegate = self
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        return control
    }()
    
    private lazy var photoButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16)
        button.translatesAutoresizingMaskIntoConstraints = false
        let image = UIImage(systemName: "camera.fill")?.withConfiguration(config)
        button.contentMode = .scaleAspectFit
        button.setImage(image, for: .normal)
        button.imageView?.contentMode = .scaleAspectFit
        button.addTarget(self, action: #selector(tappedLibrary), for: .touchUpInside)
        
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        return button
    }()
    
    private lazy var postButton: CircleButton = {
        let button = CircleButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(named: "icon_share")?.withRenderingMode(.alwaysTemplate).withTintColor(.white), for: .normal)
        button.tintColor = .white
        button.addTarget(self, action: #selector(tappedPost), for: .touchUpInside)
        button.setBackgroundColor(.primaryBlue, for: .normal)
        button.isHidden = true
        
        return button
    }()
    
    private lazy var voiceNoteTimeLabel: AudioRecorderTimeView = {
        let label = AudioRecorderTimeView()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.backgroundColor = .primaryBg
        label.isHidden = true
        
        return label
    }()
    /// - note: Displays when the audio recorder is in the locked state.
    private lazy var stopVoiceRecordingButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .primaryBlue
        button.setTitle(Localizations.buttonStop, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 19)
        button.addTarget(self, action: #selector(tappedStopVoiceRecording), for: .touchUpInside)
        button.isHidden = true
        
        return button
    }()
    
    private lazy var audioPlaybackView: AudioPlaybackView = {
        let view = AudioPlaybackView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.audioView.state = .played
        view.audioView.delegate = self
        view.isHidden = true
        view.backgroundColor = .feedPostBackground
        
        return view
    }()
    
    private lazy var deleteAudioRecordingButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "trash"), for: .normal)
        button.addTarget(self, action: #selector(tappedDeleteVoiceNote), for: .touchUpInside)
        button.tintColor = .red
        button.isHidden = true
        
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        
        return button
    }()
    
    private lazy var mentionPicker: HorizontalMentionPickerView = {
        let picker = HorizontalMentionPickerView(avatarStore: MainAppContext.shared.avatarStore)
        picker.clipsToBounds = true
        picker.translatesAutoresizingMaskIntoConstraints = false
        // Hide until content is set
        picker.isHidden = true
        picker.didSelectItem = { [weak self] item in
            self?.textView.accept(mention: item)
            self?.updateMentionPicker()
        }
        return picker
    }()
    
    private lazy var linkPreviewPanel: LinkPreviewPanel = {
        let panel = LinkPreviewPanel()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.isHidden = true
        panel.closeButton.addTarget(self, action: #selector(closedLinkPreview), for: .touchUpInside)
        
        return panel
    }()
    
    private(set) var contextPanel: InputContextPanel?
    private var textViewPostButtonConstraint: NSLayoutConstraint?

    private lazy var voiceNoteRecorder: AudioRecorder = {
        let recorder = AudioRecorder()
        recorder.delegate = self
        
        return recorder
    }()
    
    private var typingDebounceTimer: Timer?
    private var typingThrottleTimer: Timer?
    
    override var intrinsicContentSize: CGSize {
        return textView.intrinsicContentSize
    }
    
    init(options: Options) {
        self.options = options
        super.init(frame: .zero)
        backgroundColor = nil
        
        configureBlur()
        
        addSubview(vStack)
        vStack.constrain(to: self)
        
        subscribeToKeyboardNotifications()
        
        textView.linkPreviewMetadata.sink { [weak self] fetchState in
            self?.updateLinkPreviewPanel(with: fetchState)
        }.store(in: &cancellables)
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    private func configureBlur() {
        // note that a `.prominent` blur doesn't seem to snapshot well when performing a vc transition.
        // `.regular` is better, but it's not seamless.
        let blurView = BlurView(effect: UIBlurEffect(style: .prominent), intensity: 0.9)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        
        // unused right now, but the purpose of this view is to try and get the background of the entire
        // input view to be as close as possible to that of the view behind it (the blur distorts the color).
        let backgroundView = UIView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.backgroundColor = .primaryBg
        backgroundView.alpha = 0
        
        addSubview(blurView)
        addSubview(backgroundView)
        
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    
    private func subscribeToKeyboardNotifications() {
        let nc = NotificationCenter.default
        nc.publisher(for: UIApplication.keyboardWillShowNotification, object: nil).sink { [weak self] notification in
            guard
                let self = self,
                let kbRect = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            else {
                return
            }
            
            // kbRect accounts for height of accessory view
            self.delegate?.inputView(self, didChangeHeightTo: kbRect.height)
        }.store(in: &cancellables)
        
        nc.publisher(for: UIApplication.keyboardWillHideNotification, object: nil).sink { [weak self] notification in
            if let self = self {
                self.delegate?.inputView(self, didChangeHeightTo: self.bounds.height)
            }
        }.store(in: &cancellables)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        vStack.layoutIfNeeded()

        // maybe use intrinsic content size here?
        if textView.bounds.height != placeHolder.bounds.height {
            displayExpandedShadow()
        } else {
            displayCollapsedShadow()
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            textView.layer.borderColor = Self.borderColor.resolvedColor(with: traitCollection).cgColor
        }
    }
    
    private func displayCollapsedShadow() {
        let bounds = CGRect(x: 0, y: 0, width: textView.bounds.width, height: textView.bounds.height)
        let path = UIBezierPath(roundedRect: bounds, cornerRadius: placeHolder.bounds.height / 2)

        textView.layer.cornerRadius = textView.bounds.height / 2
        textViewShadowView.layer.shadowPath = path.cgPath
    }
    
    private func displayExpandedShadow() {
        let bounds = CGRect(x: 0, y: 0, width: textView.bounds.width, height: textView.bounds.height)
        let path = UIBezierPath(roundedRect: bounds, cornerRadius: Self.textViewCornerRadius)

        textView.layer.cornerRadius = Self.textViewCornerRadius
        textViewShadowView.layer.shadowPath = path.cgPath
    }

    private func refreshButtons() {
        var hidePlaceholder = true
        var hideTextView = false
        var hidePhotoButton = true
        var hideVoiceControl = false
        var hidePostButton = true
        var hideStopVoiceRecordingButton = true
        var hideVoiceNoteTimeLabel = true
        var hidePlaybackView = true
        var hideDeleteRecordingButton = true

        switch contentState {
        case .none:
            hidePlaceholder = false
            hidePhotoButton = false
        case .invalidText:
            hidePlaceholder = true
            hidePhotoButton = false
        case .text:
            hidePostButton = false
            hideVoiceControl = true
        case .audioRecording:
            hideTextView = true
            hideVoiceNoteTimeLabel = false
            voiceNoteTimeLabel.text = "0:00"
        case .audioRecordingLocked:
            hideTextView = true
            hideVoiceControl = true
            hidePostButton = false
            hideVoiceNoteTimeLabel = false
            hideStopVoiceRecordingButton = false
        case .audioPlayback:
            hideTextView = true
            hideVoiceControl = true
            hidePostButton = false
            hideVoiceControl = true
            hideDeleteRecordingButton = false
            hidePlaybackView = false
        }

        placeHolder.isHidden = hidePlaceholder
        textView.isHidden = hideTextView
        textViewShadowView.isHidden = hideTextView

        plusButton.isHidden = hideTextView
        photoButton.isHidden = hidePhotoButton
        voiceNoteControl.isHidden = hideVoiceControl

        voiceNoteTimeLabel.isHidden = hideVoiceNoteTimeLabel
        audioPlaybackView.isHidden = hidePlaybackView
        stopVoiceRecordingButton.isHidden = hideStopVoiceRecordingButton
        deleteAudioRecordingButton.isHidden = hideDeleteRecordingButton

        postButton.isHidden = hidePostButton
        textViewPostButtonConstraint?.isActive = contentState == .text

        setNeedsLayout()
    }
    
    /**
     Displays a contextual panel at the top of the view.
     
     Use this method to visually indicate a different context——e.g. a reply to a specific chat message
     or post comment. Adding a panel will remove the current link preview, and replace the existing
     context panel if it exists. The delegate is notified when the user closes the context panel.
     */
    func display(context panel: InputContextPanel) {
        if !linkPreviewPanel.isHidden {
            textView.resetLinkDetection()
        }
        
        removeContextPanel()
        
        contextPanel = panel
        panel.closeButton.addTarget(self, action: #selector(closedPanel), for: .touchUpInside)
        vStack.insertArrangedSubview(panel, at: 0)
    }
    
    private func removeContextPanel() {
        guard let currentPanel = contextPanel else { return }
        vStack.removeArrangedSubview(currentPanel)
        currentPanel.removeFromSuperview()

        contextPanel = nil
    }
    
    func set(draft text: String) {
        guard !text.isEmpty else { return }
        
        textView.text = text
        textViewDidChange(textView)
    }
    
    func show(voiceNote url: URL) {
        audioPlaybackView.audioView.url = url
        contentState = .audioPlayback
    }
    
    private func updateLinkPreviewPanel(with fetchState: ContentTextView.LinkPreviewFetchState) {
        switch fetchState {
        case .fetching:
            linkPreviewPanel.activityIndicator.startAnimating()
            linkPreviewPanel.isHidden = false
        case .fetched(let metadata):
            linkPreviewPanel.metadata = metadata
            linkPreviewPanel.isHidden = (metadata == nil)
        }
    }
}

// MARK: - button selectors
 
extension ContentInputView {
    @objc
    private func closedPanel(_ button: UIButton) {
        guard let panel = contextPanel else {
            return
        }
        
        removeContextPanel()
        delegate?.inputView(self, didClose: panel)
        // bring up potential link preview that was closed when panel was added
        textView.checkLinkPreview()
    }
    
    @objc
    private func closedLinkPreview(_ button: UIButton) {
        textView.resetLinkDetection()
    }
    
    @objc
    private func tappedLibrary(_ button: UIButton) {
        delegate?.inputViewDidSelectCamera(self)
    }
    
    @objc
    private func tappedShareOptions(_ button: UIButton) {
        delegate?.inputViewDidSelectContentOptions(self)
    }
    
    @objc
    private func tappedPost(_ button: UIButton) {
        switch contentState {
        case .none, .audioRecording, .invalidText:
            // post button shouldn't be visible here
            return
        case .text:
            sendCurrentTextInput()
        case .audioRecordingLocked:
            stopAndSendCurrentVoiceRecording(cancel: false)
        case .audioPlayback:
            if let url = audioPlaybackView.audioView.url {
                sendVoiceRecording(url)
            }
        }
        
        resetAfterPosting()
    }
    
    @objc
    private func tappedDeleteVoiceNote(_ button: UIButton) {
        // can only be called when `contentState` is `.audioPlayback`
        audioPlaybackView.reset()
        contentState = .none
    }
}

// MARK: - text view delegate methods

extension ContentInputView: ContentTextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        if textView.intrinsicContentSize.height >= self.textView.maxHeight {
            if !textView.isScrollEnabled {
                textView.isScrollEnabled = true
                textView.flashScrollIndicators()
            }
        } else if textView.isScrollEnabled {
            textView.isScrollEnabled = false
        }
        
        textView.invalidateIntrinsicContentSize()
        
        let text = textView.text ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            contentState = text.isEmpty ? .none : .invalidText
        } else {
            contentState = .text
        }
        
        updateMentionPicker()
        self.textView.checkLinkPreview()
        sendTypingNotification()
        updateWithMarkdown()
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        let validStates: [ContentState] = [.none, .text, .invalidText]
        guard validStates.contains(contentState) else {
            // this gets called if the user dismisses the keyboard while recording an audio note
            return
        }
        
        let text = (textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            contentState = .none
        } else {
            contentState = .text
        }
        
        textView.text = text
        textView.invalidateIntrinsicContentSize()
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if options.contains(.mentions) {
            return self.textView.shouldChangeMentionText(in: range, text: text)
        }
        
        return true
    }
    
    func textView(_ textView: ContentTextView, didPaste image: UIImage) {
        let media = PendingMedia(type: .image)
        media.image = image
        
        if media.ready.value {
            delegate?.inputView(self, didPaste: media)
        } else {
            media.ready.sink { [weak self] ready in
                if let self = self, ready {
                    self.delegate?.inputView(self, didPaste: media)
                }
            }.store(in: &cancellables)
        }
    }
    
    private func sendTypingNotification() {
        guard options.contains(.typingIndication) else {
            return
        }
        
        if typingThrottleTimer == nil && !textView.text.isEmpty {
            // is typing
            delegate?.inputView(self, isTyping: true)
            typingThrottleTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
                self?.typingThrottleTimer = nil
            }
        }
        
        typingDebounceTimer?.invalidate()
        typingDebounceTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            // not typing
            self.delegate?.inputView(self, isTyping: false)
            
            self.typingThrottleTimer?.invalidate()
            self.typingThrottleTimer = nil
        }
    }
    
    private func updateWithMarkdown() {
        guard
            textView.markedTextRange == nil,
            let text = textView.text,
            let selected = textView.selectedTextRange
        else {
            return
        }
        
        let font = textView.font
        let ham = HAMarkdown(font: font ?? .systemFont(ofSize: 10), color: .label)
        textView.attributedText = ham.parseInPlace(text)
        textView.selectedTextRange = selected
    }
}

// MARK: - audio recorder view delegate methods

extension ContentInputView: AudioRecorderControlViewDelegate {
    func audioRecorderControlViewShouldStart(_ view: AudioRecorderControlView) -> Bool {
        guard !MainAppContext.shared.callManager.isAnyCallActive else {
            delegate?.inputViewMicrophoneAccessDeniedDuringCall(self)
            return false
        }
        
        textViewDidEndEditing(self.textView)
        contentState = .audioRecording
        return true
    }
    
    func audioRecorderControlViewStarted(_ view: AudioRecorderControlView) {
        voiceNoteRecorder.start()
    }
    
    func audioRecorderControlViewFinished(_ view: AudioRecorderControlView, cancel: Bool) {
        // can only record audio when there's no text / media
        stopAndSendCurrentVoiceRecording(cancel: cancel)
        resetAfterPosting()
    }
    
    /**
     Used when `contentState` is either `.audio` or `.audioLocked`. This method either cleans up
     or sends any currently recording audio; resets `contentState` to `.none` no matter what.
     
     - Parameter cancel: `true` if audio should not be sent after stopping the recorder.
     */
    private func stopAndSendCurrentVoiceRecording(cancel: Bool) {
        guard let duration = voiceNoteRecorder.duration, duration >= 1 else {
            voiceNoteRecorder.stop(cancel: true)
            sendVoiceRecording(nil)
            return
        }
        
        voiceNoteRecorder.stop(cancel: cancel)
        guard !cancel else {
            sendVoiceRecording(nil)
            return
        }
        
        // user did not cancel; send audio
        sendVoiceRecording(voiceNoteRecorder.url)
    }
    
    private func sendVoiceRecording(_ url: URL?) {
        guard let url = url else {
            return
        }
        
        let media = PendingMedia(type: .audio)
        media.size = .zero
        media.order = 1
        media.fileURL = url
        
        let content = InputContent(mentionText: MentionText(expandedText: "", mentionRanges: [:]),
                                         media: [media],
                                   linkPreview: nil)
        
        delegate?.inputView(self, didPost: content)
    }
    
    private func sendCurrentTextInput() {
        guard textView.text != "" else { return }
        let mentionText = textView.mentionText.trimmed()

        guard let linkPreviewData = textView.linkPreviewData else {
            delegate?.inputView(self, didPost: InputContent(mentionText: mentionText, media: [], linkPreview: nil))
            return
        }

        guard let linkPreviewImage = linkPreviewPanel.linkPreviewMediaView.image else {
            delegate?.inputView(self, didPost: InputContent(mentionText: mentionText, media: [], linkPreview: (linkPreviewData, nil)))
            return
        }

        let linkMedia = PendingMedia(type: .image)
        linkMedia.image = linkPreviewImage
        if linkMedia.ready.value {
            delegate?.inputView(self, didPost: InputContent(mentionText: mentionText,
                                                                  media: [],
                                                            linkPreview: (linkPreviewData, linkMedia)))
        } else {
            linkMedia.ready.sink { [weak self, linkPreviewData] ready in
                guard let self = self, ready else { return }
                self.delegate?.inputView(self, didPost: InputContent(mentionText: mentionText,
                                                                           media: [],
                                                                     linkPreview: (linkPreviewData, linkMedia)))
            }.store(in: &cancellables)
        }
    }
    
    private func resetAfterPosting() {
        textView.resetMentions()
        textView.resetLinkDetection()
        textView.text = ""
        
        audioPlaybackView.reset()
        removeContextPanel()
        
        contentState = .none
        textViewDidChange(textView)
        
        if options.contains(.typingIndication) {
            delegate?.inputView(self, isTyping: false)
        }
    }
    
    func audioRecorderControlViewLocked(_ view: AudioRecorderControlView) {
        contentState = .audioRecordingLocked
    }
    
    @objc
    private func tappedStopVoiceRecording(_ button: UIButton) {
        if voiceNoteRecorder.isRecording {
            voiceNoteRecorder.stop(cancel: false)
            audioPlaybackView.audioView.url = voiceNoteRecorder.url
            contentState = .audioPlayback
        }
    }
}

// MARK: - audio recorder delegate methods

extension ContentInputView: AudioRecorderDelegate {
    func audioRecorderMicrophoneAccessDenied(_ recorder: AudioRecorder) {
        DispatchQueue.main.async { [weak self] in
            if let self = self {
                self.contentState = .none
                self.delegate?.inputViewMicrophoneAccessDenied(self)
            }
        }
    }
    
    func audioRecorderStarted(_ recorder: AudioRecorder) {
        
    }
    
    func audioRecorderStopped(_ recorder: AudioRecorder) {
        
    }
    
    func audioRecorderInterrupted(_ recorder: AudioRecorder) {
        DispatchQueue.main.async { [weak self] in
            if let self = self {
                self.delegate?.inputView(self, didInterrupt: recorder)
            }
        }
    }
    
    func audioRecorder(_ recorder: AudioRecorder, at time: String) {
        DispatchQueue.main.async { [weak self] in
            self?.voiceNoteTimeLabel.text = time
        }
    }
}

// MARK: - audio view delegate methods

extension ContentInputView: AudioViewDelegate {
    func audioView(_ view: AudioView, at time: String) {
        audioPlaybackView.timeLabel.text = time
    }
    
    func audioViewDidStartPlaying(_ view: AudioView) {
        
    }
    
    func audioViewDidEndPlaying(_ view: AudioView, completed: Bool) {
    
    }
}

// MARK: - updating the mention picker

extension ContentInputView {
    private func updateMentionPicker() {
        guard options.contains(.mentions) else {
            return
        }

        let mentionables = mentionableUsers()
        mentionPicker.items = mentionables
        mentionPicker.isHidden = mentionables.isEmpty
    }
    
    private func mentionableUsers() -> [MentionableUser] {
        let input = textView.mentionInput
        guard let candidateRange = input.rangeOfMentionCandidateAtCurrentPosition() else {
            return []
        }

        let mentionCandidate = input.text[candidateRange]
        let trimmedInput = String(mentionCandidate.dropFirst())
        
        return delegate?.inputView(self, possibleMentionsFor: trimmedInput) ?? []
    }
}

// MARK: - circle button implementation

fileprivate class CircleButton: UIButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("Circle button coder init not implemented...")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

// MARK: - audio playback view implementation

fileprivate class AudioPlaybackView: UIStackView {
    let audioView = AudioView()
    let timeLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = UIColor.audioViewControlsPlayed
        
        return label
    }()
    
    let borderLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.strokeColor = ContentInputView.borderColor.withAlphaComponent(0.2).cgColor
        layer.lineWidth = 1
        layer.fillColor = UIColor.clear.cgColor
        
        return layer
    }()
    
    override init(frame: CGRect) {
        super.init(frame: .zero)
        
        axis = .horizontal
        spacing = 10
        
        addArrangedSubview(audioView)
        addArrangedSubview(timeLabel)
        layer.addSublayer(borderLayer)
        
        directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        isLayoutMarginsRelativeArrangement = true
    }
    
    required init(coder: NSCoder) {
        fatalError("AudioPlaybackView coder init not implemented...")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let path = UIBezierPath(roundedRect: bounds, byRoundingCorners: .allCorners, cornerRadii: bounds.size)
        borderLayer.path = path.cgPath
        
        let mask = CAShapeLayer()
        mask.path = path.cgPath
        layer.mask = mask
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            let color = ContentInputView.borderColor
            borderLayer.strokeColor = color.resolvedColor(with: traitCollection).cgColor
        }
    }
    
    func reset() {
        audioView.url = nil
        timeLabel.text = ""
    }
}

// MARK: - localization

extension Localizations {
    static var chatInputPlaceholder: String {
        NSLocalizedString("chat.message.placeholder",
                   value: "New Message",
                 comment: "Text shown when content input text field is empty for chat screens.")
    }
}
