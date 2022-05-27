//
//  CommentInputView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/24/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVKit
import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import UIKit
import CoreGraphics

fileprivate protocol ContainerViewDelegate: AnyObject {
    func containerView(_ containerView: CommentInputView.ContainerView, preferredHeightFor layoutWidth: CGFloat) -> CGFloat
    func containerView(_ containerView: CommentInputView.ContainerView, didChangeBottomSafeAreaHeight safeAreaHeight: CGFloat)
    func currentLayoutWidth(for containerView: CommentInputView.ContainerView) -> CGFloat
}

protocol CommentInputViewDelegate: AnyObject {
    func commentInputView(_ inputView: CommentInputView, didChangeBottomInsetWith animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve)
    func commentInputView(_ inputView: CommentInputView, wantsToSend text: MentionText, andMedia media: PendingMedia?, linkPreviewData: LinkPreviewData?, linkPreviewMedia : PendingMedia?)
    func commentInputView(_ inputView: CommentInputView, possibleMentionsForInput input: String) -> [MentionableUser]
    func commentInputViewPickMedia(_ inputView: CommentInputView)
    func commentInputViewResetReplyContext(_ inputView: CommentInputView)
    func commentInputViewResetInputMedia(_ inputView: CommentInputView)
    func commentInputViewMicrophoneAccessDenied(_ inputView: CommentInputView)
    func commentInputViewCouldNotRecordDuringCall(_ inputView: CommentInputView)
    func commentInputViewDidTapSelectedMedia(_ inputView: CommentInputView, mediaToEdit: PendingMedia)
    func commentInputView(_ inputView: CommentInputView, didInterruptRecorder recorder: AudioRecorder)
}

class CommentInputView: UIView, InputTextViewDelegate, ContainerViewDelegate {

    private var cancellableSet: Set<AnyCancellable> = []
    weak var delegate: CommentInputViewDelegate?

    // Only one of these should be active at a time
    private var mentionPickerTopConstraint: NSLayoutConstraint?
    private var vStackTopConstraint: NSLayoutConstraint?

    private var bottomConstraint: NSLayoutConstraint?

    private var textViewHeight: NSLayoutConstraint?
    private var textView1LineHeight: CGFloat = 0
    private var textView5LineHeight: CGFloat = 0

    private var previousHeight: CGFloat = 0
    let closeButtonDiameter: CGFloat = 24

    private var voiceNoteRecorder = AudioRecorder()
    private var isVoiceNoteRecordingLocked = false
    private var isShowingVoiceNote = false

    private var uploadMedia: PendingMedia?

    private var linkPreviewUrl: URL?
    private var invalidLinkPreviewUrl: URL?
    private var linkPreviewData: LinkPreviewData?
    private var linkDetectionTimer = Timer()

    private var isPostButtonEnabled: Bool {
        get {
            if !isEnabled {
                return false
            }
            return !(textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (mediaView.image != nil)
        }
    }
    var isEnabled: Bool = true {
        didSet {
            textView.isEditable = isEnabled
            postButton.isEnabled = isPostButtonEnabled
        }
    }

    class ContainerView: UIView {
        fileprivate weak var delegate: ContainerViewDelegate?

        fileprivate let windowSafeAreaInsets = UIApplication.shared.windows[0].safeAreaInsets

        override init(frame: CGRect) {
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()

            // NB: Safe area bounces around and causes an infinite loop when slowly dismissing keyboard: https://github.com/MessageKit/MessageKit/issues/349
            let isCloseToWindowSafeArea = abs(windowSafeAreaInsets.bottom - safeAreaInsets.bottom) < 2
            let safeAreaToReport = isCloseToWindowSafeArea ? windowSafeAreaInsets.bottom : 0
            delegate?.containerView(self, didChangeBottomSafeAreaHeight: safeAreaToReport)

            invalidateIntrinsicContentSize()
        }

        override var intrinsicContentSize: CGSize {
            get {
                let width = self.delegate!.currentLayoutWidth(for: self)
                let height = self.preferredHeight(for: width) + safeAreaInsets.bottom
                return CGSize(width: width, height: height)
            }
        }

        func preferredHeight(for layoutWidth: CGFloat) -> CGFloat {
            return self.delegate!.containerView(self, preferredHeightFor: layoutWidth)
        }
    }

    private lazy var containerView: ContainerView = {
        let view = ContainerView()
        view.delegate = self
        view.translatesAutoresizingMaskIntoConstraints = false
        view.preservesSuperviewLayoutMargins = true
        return view
    }()

    private lazy var contentView: UIView = {
        let view = UIView()
        view.preservesSuperviewLayoutMargins = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var vStack: UIStackView = {
        let vStack = UIStackView()
        vStack.axis = .vertical
        vStack.preservesSuperviewLayoutMargins = true
        vStack.translatesAutoresizingMaskIntoConstraints = false
        return vStack
    }()

    private lazy var textView: InputTextView = {
        let textView = InputTextView(frame: .zero)
        textView.tintColor = .systemBlue
        textView.font = UIFont.preferredFont(forTextStyle: .subheadline)
        textView.backgroundColor = .clear
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .yes
        textView.enablesReturnKeyAutomatically = true
        textView.scrollsToTop = false
        textView.textContainerInset.left = -5
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.showsVerticalScrollIndicator = false

        textView.onPasteImage = { [weak self] in
            if let image = UIPasteboard.general.image {
                let media = PendingMedia(type: .image)
                media.image = image
                if media.ready.value {
                    self?.showMediaPanel(with: media)
                } else {
                    self?.cancellableSet.insert(
                        media.ready.sink { [weak self] ready in
                            guard let self = self else { return }
                            guard ready else { return }
                            self.showMediaPanel(with: media)
                        }
                    )
                }
            }
        }

        return textView
    }()

    private lazy var textFieldPanel: UIView = {
        let textFieldPanel = UIView()
        textFieldPanel.translatesAutoresizingMaskIntoConstraints = false
        textFieldPanel.preservesSuperviewLayoutMargins = true

        textFieldPanel.addSubview(textFieldPanelContent)
        textFieldPanelContent.leadingAnchor.constraint(equalTo: textFieldPanel.layoutMarginsGuide.leadingAnchor).isActive = true
        textFieldPanelContent.topAnchor.constraint(equalTo: textFieldPanel.layoutMarginsGuide.topAnchor, constant: -3).isActive = true
        textFieldPanelContent.trailingAnchor.constraint(equalTo: textFieldPanel.layoutMarginsGuide.trailingAnchor).isActive = true
        textFieldPanelContent.bottomAnchor.constraint(equalTo: textFieldPanel.layoutMarginsGuide.bottomAnchor).isActive = true

        return textFieldPanel
    }()

    private lazy var textFieldPanelContent: UIStackView = {
        let textViewContainer = UIView()
        textViewContainer.translatesAutoresizingMaskIntoConstraints = false

        textViewContainer.addSubview(textView)
        textView.leadingAnchor.constraint(equalTo: textViewContainer.leadingAnchor).isActive = true
        textView.topAnchor.constraint(equalTo: textViewContainer.topAnchor).isActive = true
        textView.trailingAnchor.constraint(equalTo: textViewContainer.trailingAnchor).isActive = true
        textView.bottomAnchor.constraint(equalTo: textViewContainer.bottomAnchor).isActive = true

        textViewContainer.addSubview(placeholder)
        placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor).isActive = true
        placeholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: textView.textContainerInset.top + 1).isActive = true

        let buttonStack = UIStackView(arrangedSubviews: [pickMediaButton, recordVoiceNoteControl, postButton])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .horizontal
        buttonStack.alignment = .center
        buttonStack.spacing = 16

        let buttonStackHeightConstraint = buttonStack.heightAnchor.constraint(equalToConstant: 38)
        buttonStackHeightConstraint.priority = .defaultLow // avoid layout constraint issue and logs
        buttonStackHeightConstraint.isActive = true

        // as the user keeps typing, we want the text field to exand while
        // the media/post buttons stick to the bottom,
        let spacer = UIView()
        let vButtonStack = UIStackView(arrangedSubviews: [ spacer, buttonStack])
        vButtonStack.translatesAutoresizingMaskIntoConstraints = false
        vButtonStack.axis = .vertical

        let stack = UIStackView(arrangedSubviews: [textViewContainer, vButtonStack])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 8

        stack.addSubview(cancelRecordingButton)
        stack.addSubview(postVoiceNoteButton)
        stack.addSubview(voiceNoteTime)
        stack.addSubview(removeVoiceNoteButton)
        stack.addSubview(voiceNotePlayer)

        cancelRecordingButton.centerXAnchor.constraint(equalTo: stack.centerXAnchor).isActive = true
        cancelRecordingButton.centerYAnchor.constraint(equalTo: stack.centerYAnchor).isActive = true
        postVoiceNoteButton.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
        postVoiceNoteButton.centerYAnchor.constraint(equalTo: stack.centerYAnchor).isActive = true
        voiceNoteTime.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 14).isActive = true
        voiceNoteTime.centerYAnchor.constraint(equalTo: stack.centerYAnchor).isActive = true

        voiceNotePlayer.centerXAnchor.constraint(equalTo: stack.centerXAnchor).isActive = true
        voiceNotePlayer.centerYAnchor.constraint(equalTo: stack.centerYAnchor).isActive = true
        removeVoiceNoteButton.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        removeVoiceNoteButton.centerYAnchor.constraint(equalTo: stack.centerYAnchor).isActive = true

        return stack
    } ()

    private lazy var placeholder: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .placeholderText
        return label
    }()

    private lazy var pickMediaButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "Photo")?.withTintColor(.primaryBlue), for: .normal)
        button.addTarget(self, action: #selector(pickMediaButtonClicked), for: .touchUpInside)
        button.isEnabled = true
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        button.tintColor = UIColor.primaryBlue
        button.accessibilityLabel = Localizations.fabAccessibilityPhotoLibrary

        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true

        return button
    }()

    private lazy var postButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "Send"), for: .normal)
        button.accessibilityLabel = Localizations.buttonSend
        button.isEnabled = false
        button.tintColor = .systemBlue
        button.backgroundColor = UIColor.clear
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        button.addTarget(self, action: #selector(self.postButtonClicked), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false

        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        button.widthAnchor.constraint(equalToConstant: 38).isActive = true
        return button
    }()

    private lazy var postVoiceNoteButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "Send"), for: .normal)
        button.accessibilityLabel = Localizations.buttonSend
        button.addTarget(self, action: #selector(postButtonClicked), for: .touchUpInside)
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        button.tintColor = .white
        button.backgroundColor = .primaryBlue
        button.layer.cornerRadius = 19
        button.layer.masksToBounds = true

        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
        button.imageView?.layer.transform = CATransform3DMakeScale(1.1, 1.1, 1.1)

        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        button.widthAnchor.constraint(equalToConstant: 38).isActive = true
        button.heightAnchor.constraint(equalToConstant: 38).isActive = true

        button.isHidden = true

        return button
    }()

    private lazy var removeVoiceNoteButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(named: "NavbarTrashBinWithLid"), for: .normal)
        button.accessibilityLabel = Localizations.buttonRemove
        button.addTarget(self, action: #selector(removeVoiceNoteClicked), for: .touchUpInside)
        button.tintColor = .lavaOrange

        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true

        button.isHidden = true

        return button
    }()

    private lazy var voiceNoteAudioView: AudioView = {
        let view = AudioView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.state = .played
        view.delegate = self

        return view
    }()

    private lazy var voiceNotePlayerTime: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .caption2)
        label.textColor = UIColor.chatTime

        label.widthAnchor.constraint(equalToConstant: 32).isActive = true

        return label
    }()

    private lazy var voiceNotePlayer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .voiceNoteInputField
        view.layer.cornerRadius = 19
        view.layer.masksToBounds = true

        view.widthAnchor.constraint(equalToConstant: 266).isActive = true
        view.heightAnchor.constraint(equalToConstant: 38).isActive = true

        view.isHidden = true

        view.addSubview(voiceNoteAudioView)
        view.addSubview(voiceNotePlayerTime)

        voiceNoteAudioView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        voiceNoteAudioView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16).isActive = true
        voiceNotePlayerTime.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        voiceNotePlayerTime.leadingAnchor.constraint(equalTo: voiceNoteAudioView.trailingAnchor, constant: 12).isActive = true
        voiceNotePlayerTime.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16).isActive = true

        return view
    }()

    private lazy var mediaView: UIImageView = {
        let mediaView = UIImageView()
        mediaView.contentMode = .scaleAspectFit
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        mediaView.widthAnchor.constraint(equalToConstant: 100).isActive = true
        mediaView.heightAnchor.constraint(equalToConstant: 100).isActive = true
        return mediaView
    }()

    lazy var duration: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .right
        label.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white

        return label
    }()

    static private let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.zeroFormattingBehavior = .pad
        formatter.allowedUnits = [.second, .minute]

        return formatter
    }()

    private lazy var mediaCloseButton: UIButton = {
        let closeButton = UIButton(type: .custom)
        closeButton.bounds.size = CGSize(width: closeButtonDiameter, height: closeButtonDiameter)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill")?.withRenderingMode(.alwaysTemplate), for: .normal)
        closeButton.tintColor = .placeholderText
        closeButton.layer.cornerRadius = 0.5 * closeButtonDiameter
        closeButton.addTarget(self, action: #selector(didTapCloseMediaPanel), for: .touchUpInside)
        return closeButton
    }()

    private lazy var mediaPanel: UIView = {
        var mediaPanel = UIView()
        mediaPanel.translatesAutoresizingMaskIntoConstraints = false
        mediaPanel.preservesSuperviewLayoutMargins = true

        let backgroundView = UIView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        mediaPanel.addSubview(backgroundView)
        backgroundView.leadingAnchor.constraint(equalTo: mediaPanel.leadingAnchor).isActive = true
        backgroundView.topAnchor.constraint(equalTo: mediaPanel.topAnchor).isActive = true
        backgroundView.trailingAnchor.constraint(equalTo: mediaPanel.trailingAnchor).isActive = true
        backgroundView.bottomAnchor.constraint(equalTo: mediaPanel.bottomAnchor).isActive = true
        return mediaPanel
    }()

    private lazy var cancelRecordingButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(cancelRecordingButtonClicked), for: .touchUpInside)
        button.tintColor = UIColor.primaryBlue
        button.setTitle(Localizations.buttonCancel, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 19)
        button.isHidden = true

        return button
    }()

    private lazy var voiceNoteTime: AudioRecorderTimeView = {
        let view = AudioRecorderTimeView()
        return view
    }()

    private lazy var recordVoiceNoteControl: AudioRecorderControlView = {
        let controlView = AudioRecorderControlView(configuration: .comment)
        controlView.translatesAutoresizingMaskIntoConstraints = false
        controlView.layer.zPosition = 1

        controlView.widthAnchor.constraint(equalToConstant: 38).isActive = true
        controlView.heightAnchor.constraint(equalToConstant: 24).isActive = true

        controlView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        controlView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        return controlView
    }()

    private lazy var contactNameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 2
        return label
    }()

    private lazy var deleteReplyContextButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "ReplyPanelClose"), for: .normal)
        button.contentEdgeInsets = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        button.tintColor = UIColor(white: 1, alpha: 0.8)
        button.addTarget(self, action: #selector(didTapCloseReplyPanel), for: .touchUpInside)
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }()

    private lazy var replyContextPanel: UIView = {
        let panel = UIView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.preservesSuperviewLayoutMargins = true

        let backgroundView = UIView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.7)
        panel.addSubview(backgroundView)
        backgroundView.leadingAnchor.constraint(equalTo: panel.leadingAnchor).isActive = true
        backgroundView.topAnchor.constraint(equalTo: panel.topAnchor).isActive = true
        backgroundView.trailingAnchor.constraint(equalTo: panel.trailingAnchor).isActive = true
        backgroundView.bottomAnchor.constraint(equalTo: panel.bottomAnchor).isActive = true

        let hStack = UIStackView(arrangedSubviews: [ self.contactNameLabel, self.deleteReplyContextButton ])
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.preservesSuperviewLayoutMargins = true
        hStack.axis = .horizontal
        hStack.spacing = 8
        panel.addSubview(hStack)
        hStack.leadingAnchor.constraint(equalTo: panel.layoutMarginsGuide.leadingAnchor).isActive = true
        hStack.topAnchor.constraint(equalTo: panel.layoutMarginsGuide.topAnchor).isActive = true
        hStack.trailingAnchor.constraint(equalTo: panel.layoutMarginsGuide.trailingAnchor).isActive = true
        hStack.bottomAnchor.constraint(equalTo: panel.layoutMarginsGuide.bottomAnchor).isActive = true

        return panel
    }()
    
    private lazy var mentionPicker: MentionPickerView = {
        let picker = MentionPickerView(avatarStore: MainAppContext.shared.avatarStore)
        picker.cornerRadius = 10
        picker.borderColor = .systemGray
        picker.borderWidth = 1
        picker.clipsToBounds = true
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.isHidden = true // Hide until content is set
        picker.didSelectItem = { [weak self] item in self?.acceptMentionPickerItem(item) }
        return picker
    }()
    
    private lazy var tapRecognizer: UITapGestureRecognizer = {
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapMediaAction))
        tapRecognizer.numberOfTouchesRequired = 1
        tapRecognizer.numberOfTapsRequired = 1
        return tapRecognizer
    }()

    // Quoted replied for the new flat comments view
    private lazy var quotedPanel: UIView =  {
        var quotedPanel = UIView()
        quotedPanel.translatesAutoresizingMaskIntoConstraints = false
        quotedPanel.preservesSuperviewLayoutMargins = true
        quotedPanel.addSubview(quotedCellView)
        quotedPanel.addSubview(quotedPanelCloseButton)
        quotedCellView.constrainMargins(to: quotedPanel)
        NSLayoutConstraint.activate([
            quotedCellView.leadingAnchor.constraint(equalTo: quotedPanel.leadingAnchor, constant: 8),
            quotedCellView.trailingAnchor.constraint(equalTo: quotedPanel.trailingAnchor, constant: -8),
            quotedPanelCloseButton.trailingAnchor.constraint(equalTo: quotedCellView.trailingAnchor),
            quotedPanelCloseButton.topAnchor.constraint(equalTo: quotedCellView.topAnchor),
        ])
        return quotedPanel
    }()

    private lazy var quotedCellView: QuotedMessageCellView =  {
        let quotedCellView = QuotedMessageCellView()
        quotedCellView.translatesAutoresizingMaskIntoConstraints = false
        return quotedCellView
    }()

    private lazy var quotedPanelCloseButton: UIButton = {
        let closeButton = UIButton(type: .custom)
        closeButton.bounds.size = CGSize(width: closeButtonDiameter, height: closeButtonDiameter)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(named: "NavbarClose")?.withRenderingMode(.alwaysTemplate), for: .normal)
        closeButton.tintColor = .placeholderText
        closeButton.layer.cornerRadius = 0.5 * closeButtonDiameter
        closeButton.addTarget(self, action: #selector(didTapCloseQuotedPanel), for: .touchUpInside)
        closeButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        return closeButton
    }()

    private lazy var backgroundView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.messageFooterBackground
        view.layer.borderColor = UIColor.chatTextFieldStroke.cgColor
        view.layer.borderWidth = 1

        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        previousHeight = frame.size.height
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardDidShow), name: UIResponder.keyboardDidShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardDidHide), name: UIResponder.keyboardDidHideNotification, object: nil)

        self.autoresizingMask = .flexibleHeight

        addSubview(backgroundView)
        backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -1).isActive = true
        backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 1).isActive = true
        backgroundView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 50).isActive = true

        // Container view - needs for correct size calculations.
        self.addSubview(self.containerView)
        self.containerView.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
        self.containerView.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        self.containerView.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
        self.containerView.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true

        // Content view - everything must go in there.
        self.containerView.addSubview(self.contentView)
        self.contentView.leadingAnchor.constraint(equalTo: self.containerView.leadingAnchor).isActive = true
        self.contentView.topAnchor.constraint(equalTo: self.containerView.topAnchor).isActive = true
        self.contentView.trailingAnchor.constraint(equalTo: self.containerView.trailingAnchor).isActive = true

        bottomConstraint = self.contentView.bottomAnchor.constraint(equalTo: self.containerView.bottomAnchor, constant: 0)
        bottomConstraint?.isActive = true


        // Input field wrapper
        self.textView.inputTextViewDelegate = self
        self.textView.text = ""

        // Placeholder
        self.placeholder.text = nil

        // Vertical stack view:
        // [Replying to]?
        // [Input Field]
        self.contentView.addSubview(self.vStack)
        self.vStack.addArrangedSubview(textFieldPanel)
        self.vStack.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor).isActive = true
        self.vStack.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor).isActive = true
        self.vStack.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor).isActive = true
        self.vStackTopConstraint = self.vStack.topAnchor.constraint(equalTo: self.contentView.topAnchor)
        self.vStackTopConstraint?.isActive = true

        // mention picker
        self.contentView.addSubview(self.mentionPicker)
        self.mentionPicker.constrain([.leading, .trailing], to: textFieldPanelContent)
        self.mentionPicker.bottomAnchor.constraint(equalTo: self.textView.topAnchor).isActive = true
        self.mentionPicker.heightAnchor.constraint(lessThanOrEqualToConstant: 120).isActive = true
        self.mentionPicker.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        self.mentionPickerTopConstraint = self.mentionPicker.topAnchor.constraint(equalTo: self.contentView.topAnchor)
        
        self.recalculateSingleLineHeight()

        self.textViewHeight = self.textView.heightAnchor.constraint(equalToConstant: self.textView1LineHeight)
        self.textViewHeight?.isActive = true

        voiceNoteRecorder.delegate = self
        recordVoiceNoteControl.delegate = self

        updatePostButtons()
    }

    private func updateBorderRadius() {
        let isLinkPreviewHidden = linkPreviewPanel.superview == nil || linkPreviewPanel.isHidden
        let isMediaPanelHidden = mediaPanel.superview == nil || mediaPanel.isHidden

        if isLinkPreviewHidden && isMediaPanelHidden {
            backgroundView.layer.cornerRadius = 0
        } else {
            backgroundView.layer.cornerRadius = 20
        }
    }

    private func updatePostButtons() {
        pickMediaButton.isHidden = true
        recordVoiceNoteControl.isHidden = true
        postButton.isHidden = true

        guard !isVoiceNoteRecordingLocked && !isShowingVoiceNote else { return }

        if !mentionText.isEmpty() || mediaPanel.superview != nil {
            if ServerProperties.isMediaCommentsEnabled {
                pickMediaButton.isHidden = false
            }

            postButton.isHidden = false
        } else if voiceNoteRecorder.isRecording {
            recordVoiceNoteControl.isHidden = false
        } else {
            if ServerProperties.isMediaCommentsEnabled {
                pickMediaButton.isHidden = false
            }

            if ServerProperties.isVoiceNotesEnabled {
                recordVoiceNoteControl.isHidden = false
            }
        }
    }

    private func updateWithMarkdown() {
        guard textView.markedTextRange == nil else { return } // account for IME
        let font = UIFont.preferredFont(forTextStyle: .subheadline)
        let color = UIColor.label // do not use textView.textColor directly as that changes when attributedText changes color

        let ham = HAMarkdown(font: font, color: color)
        if let text = textView.text {
            if let selectedRange = textView.selectedTextRange {
                textView.attributedText = ham.parseInPlace(text)
                textView.selectedTextRange = selectedRange
            }
        }
    }

    func willAppear(in viewController: UIViewController) {
        self.setInputViewWidth(viewController.view.bounds.size.width)
    }

    func didAppear(in viewController: UIViewController) {
    }

    func willDisappear(in viewController: UIViewController) {
        guard self.isKeyboardVisible || viewController.isFirstResponder else { return }

        var deferResigns = false
        if viewController.isMovingFromParent {
            // Popping
            deferResigns = true
        } else if let nav = viewController.navigationController, nav.isBeingDismissed {
            // Being dismissed (e.g., from activity center)
            deferResigns = true
        } else if self.isKeyboardVisible {
            // Pushing or presenting
            deferResigns = viewController.transitionCoordinator != nil && viewController.transitionCoordinator!.initiallyInteractive
        }
        if deferResigns && viewController.transitionCoordinator != nil {
            viewController.transitionCoordinator?.animate(alongsideTransition: nil,
                                                          completion: { context in
                if !context.isCancelled {
                    self.resignFirstResponderOnDisappear(in: viewController)
                }
            })
        } else {
            self.resignFirstResponderOnDisappear(in: viewController)
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        backgroundView.layer.borderColor = UIColor.chatTextFieldStroke.cgColor
    }

    private func resignFirstResponderOnDisappear(in viewController: UIViewController) {
        self.hideKeyboard()
        viewController.resignFirstResponder()
    }

    // MARK: Reply Context

    var textIsUneditedReplyMention = false

    func addReplyMentionIfPossible(for userID: UserID, name: String) {
        if textView.text.isEmpty || textIsUneditedReplyMention {
            clear()
            textView.addMention(name: name, userID: userID, in: NSRange(location: 0, length: 0))
            textIsUneditedReplyMention = true
        }
    }

    func removeReplyMentionIfPossible() {
        if textIsUneditedReplyMention {
            clear()
        }
    }

    // If `contactName` is nil - replying to myself.
    func showReplyPanel(with contactName: String?) {
        let formatString: String
        if contactName != nil {
            formatString = NSLocalizedString("comment.replying.someone", value: "Replying to %@",
                                             comment: "Text in the reply panel about keyboard. Reply refers to replying to someone's feed post comment.")
        } else {
            formatString = NSLocalizedString("comment.replying.myself", value: "Replying to myself",
                                             comment: "Text in the reply panel about keyboard. Reply refers to replying to user's own feed post comment.")
        }

        let baseFont = UIFont.preferredFont(forTextStyle: .subheadline)
        let attributedText = NSMutableAttributedString(string: formatString, attributes: [ .font: baseFont ])
        if let contactName = contactName {
            let parameterRange = (formatString as NSString).range(of: "%@")
            let semiboldFont = UIFont.systemFont(ofSize: baseFont.pointSize, weight: .semibold)
            let author = NSAttributedString(string: contactName, attributes: [ .font: semiboldFont ])
            attributedText.replaceCharacters(in: parameterRange, with: author)
        }
        attributedText.addAttribute(.foregroundColor, value: UIColor(white: 1, alpha: 0.8), range: NSRange(location: 0, length: attributedText.length))
        self.contactNameLabel.attributedText = attributedText
        if self.vStack.arrangedSubviews.contains(self.replyContextPanel) {
            self.replyContextPanel.isHidden = false
        } else {
            let panelSize = self.replyContextPanel.systemLayoutSizeFitting(CGSize(width: self.bounds.width, height: .greatestFiniteMagnitude),
                                                                           withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
            self.replyContextPanel.bounds = CGRect(origin: .zero, size: panelSize)
            self.replyContextPanel.center = CGPoint(x: self.vStack.bounds.midX, y: self.vStack.bounds.midY)
            self.replyContextPanel.layoutIfNeeded()

            self.vStack.insertArrangedSubview(self.replyContextPanel, at: 0)
        }
        self.setNeedsUpdateHeight()
    }

    func showQuotedReplyPanel(comment: FeedPostComment, userColorAssignment: UIColor) {
        if !vStack.subviews.contains(quotedPanel){
            vStack.insertArrangedSubview(quotedPanel, at: 0)
        }
        quotedCellView.configureWith(comment: comment, userColorAssignment: userColorAssignment)
        textView.becomeFirstResponder()
    }

    func removeQuotedReplyPanel() {
        if vStack.subviews.contains(quotedPanel){
            vStack.removeArrangedSubview(quotedPanel)
            quotedPanel.removeFromSuperview()
        }
    }

    func removeReplyPanel() {
        self.replyContextPanel.isHidden = true
        self.setNeedsUpdateHeight()
    }

    @objc private func didTapCloseReplyPanel() {
        self.delegate?.commentInputViewResetReplyContext(self)
    }

    @objc private func didTapCloseMediaPanel() {
        self.delegate?.commentInputViewResetInputMedia(self)
    }

    @objc private func didTapCloseQuotedPanel() {
        self.delegate?.commentInputViewResetReplyContext(self)
    }

    @objc private func tapMediaAction(sender: UITapGestureRecognizer) {
        guard let pendingMedia = uploadMedia else { return }
        delegate?.commentInputViewDidTapSelectedMedia(self, mediaToEdit: pendingMedia)
    }

    func showMediaPanel(with media : PendingMedia) {
        // Media always takes precedence over link previews.
        // Remove any existing link previews
        resetLinkDetection()
        uploadMedia = media
        // Prepare cell for reuse
        if vStack.arrangedSubviews.contains(mediaPanel) {
            duration.removeFromSuperview()
            mediaView.image = nil
            mediaView.removeFromSuperview()
            mediaCloseButton.removeFromSuperview()
            vStack.removeArrangedSubview(mediaPanel)
            mediaPanel.removeFromSuperview()
        }
        if media.type == .image {
            mediaView.image = media.image
            mediaPanel.addSubview(mediaView)
        } else if media.type == .video {
            guard let url = media.fileURL else { return }
            mediaView.image = VideoUtils.videoPreviewImage(url: url)
            let videoAsset = AVURLAsset(url: url)
            let interval = TimeInterval(CMTimeGetSeconds(videoAsset.duration))
            if var formatted = Self.durationFormatter.string(from: interval) {
                // Display 1:33 instead of 01:33, but keep 0:33
                if formatted.hasPrefix("0") == true && formatted.count > 4 {
                    formatted = String(formatted.dropFirst())
                }
                duration.text = formatted
            }
            mediaPanel.addSubview(mediaView)
            mediaPanel.addSubview(duration)
        } else {
            return
        }

        let closeButtonRadius = closeButtonDiameter / 2
        mediaView.topAnchor.constraint(equalTo: mediaPanel.layoutMarginsGuide.topAnchor, constant: closeButtonRadius).isActive = true
        mediaView.bottomAnchor.constraint(equalTo: mediaPanel.layoutMarginsGuide.bottomAnchor).isActive = true
        mediaView.centerXAnchor.constraint(equalTo: mediaPanel.centerXAnchor).isActive = true
        mediaView.layoutIfNeeded()
        self.vStack.insertArrangedSubview(self.mediaPanel, at: vStack.arrangedSubviews.firstIndex(of: textFieldPanel)!)

        mediaPanel.addSubview(mediaCloseButton)
        mediaView.roundCorner(10)
        if let imageRect = mediaView.getImageRect() {
            let x = imageRect.origin.x > 0 ? (imageRect.origin.x + closeButtonRadius) : closeButtonRadius
            mediaCloseButton.leadingAnchor.constraint(equalTo: mediaView.trailingAnchor, constant: -x).isActive = true
            let y = imageRect.origin.y > 0 ? (imageRect.origin.y + closeButtonRadius) : closeButtonRadius
            mediaCloseButton.bottomAnchor.constraint(equalTo: mediaView.topAnchor, constant: y).isActive = true

            // Display video duration label inside the image
            if media.type == .video {
                let timeLabelInset = CGFloat(6)
                let x = imageRect.origin.x > 0 ? (imageRect.origin.x + timeLabelInset) : timeLabelInset
                duration.rightAnchor.constraint(equalTo: mediaView.rightAnchor, constant: -x).isActive = true
                let y = imageRect.origin.y > 0 ? (imageRect.origin.y + timeLabelInset) : timeLabelInset
                duration.bottomAnchor.constraint(equalTo: mediaView.bottomAnchor, constant: -y).isActive = true
            }
        }

        // Add tap gesture to the media view
        mediaPanel.addGestureRecognizer(tapRecognizer)
        postButton.isEnabled = isPostButtonEnabled
        updatePostButtons()
        updateBorderRadius()
    }

    func removeMediaPanel() {
        // remove media panel from stack
        uploadMedia = nil
        mediaCloseButton.removeFromSuperview()
        mediaView.image = nil
        vStack.removeArrangedSubview(mediaPanel)
        mediaPanel.removeFromSuperview()
        postButton.isEnabled = isPostButtonEnabled
        updatePostButtons()
        setNeedsUpdateHeight()
        updateBorderRadius()
    }

    // MARK: Link Preview

    private let activityIndicator: UIActivityIndicatorView = {
        let activityIndicator = UIActivityIndicatorView()
        activityIndicator.color = .secondaryLabel
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        return activityIndicator
    }()

    private lazy var linkPreviewTitleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(forTextStyle: .caption1, weight: .semibold)
        titleLabel.numberOfLines = 2
        titleLabel.textColor = .label.withAlphaComponent(0.5)
        return titleLabel
    }()

    private lazy var linkImageView: UIView = {
        let image = UIImage(named: "LinkIcon")?.withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: image)
        imageView.tintColor = UIColor.label.withAlphaComponent(0.5)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isHidden = true
        return imageView
    }()

    private lazy var linkPreviewURLLabel: UILabel = {
        let urlLabel = UILabel()
        urlLabel.translatesAutoresizingMaskIntoConstraints = false
        urlLabel.font = UIFont.systemFont(forTextStyle: .caption1)
        urlLabel.textColor = .label.withAlphaComponent(0.5)
        urlLabel.textAlignment = .natural
        return urlLabel
    }()

    private var linkPreviewLinkStack: UIStackView {
        let linkStack = UIStackView(arrangedSubviews: [ linkImageView, linkPreviewURLLabel, UIView() ])
        linkStack.translatesAutoresizingMaskIntoConstraints = false
        linkStack.spacing = 2
        linkStack.alignment = .center
        linkStack.axis = .horizontal
        return linkStack
    }

    private lazy var linkPreviewTextStack: UIStackView = {
        let textStack = UIStackView(arrangedSubviews: [ linkPreviewTitleLabel, linkPreviewLinkStack ])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.layoutMargins = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        textStack.isLayoutMarginsRelativeArrangement = true
        return textStack
    }()

    private lazy var linkPreviewMediaView: UIImageView = {
        let mediaView = UIImageView()
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        mediaView.contentMode = .scaleAspectFill
        mediaView.clipsToBounds = true
        mediaView.layer.cornerRadius = 8
        mediaView.widthAnchor.constraint(equalToConstant: 60).isActive = true
        mediaView.heightAnchor.constraint(equalToConstant: 60).isActive = true
        return mediaView
    }()

    private lazy var linkPreviewHStack: UIStackView = {
        let hStack = UIStackView(arrangedSubviews: [ linkPreviewMediaView, linkPreviewTextStack])
        hStack.translatesAutoresizingMaskIntoConstraints = false
        let backgroundView = UIView()
        backgroundView.backgroundColor = .linkPreviewBackground
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        hStack.insertSubview(backgroundView, at: 0)
        backgroundView.leadingAnchor.constraint(equalTo: hStack.leadingAnchor).isActive = true
        backgroundView.topAnchor.constraint(equalTo: hStack.topAnchor).isActive = true
        backgroundView.trailingAnchor.constraint(equalTo: hStack.trailingAnchor).isActive = true
        backgroundView.bottomAnchor.constraint(equalTo: hStack.bottomAnchor).isActive = true

        hStack.axis = .horizontal
        hStack.alignment = .center
        hStack.backgroundColor = .commentVoiceNoteBackground
        hStack.layer.borderWidth = 0.5
        hStack.layer.borderColor = UIColor.black.withAlphaComponent(0.1).cgColor
        hStack.layer.cornerRadius = 15
        hStack.layer.shadowColor = UIColor.black.withAlphaComponent(0.05).cgColor
        hStack.layer.shadowOffset = CGSize(width: 0, height: 2)
        hStack.layer.shadowRadius = 4
        hStack.layer.shadowOpacity = 0.5
        hStack.isLayoutMarginsRelativeArrangement = true
        hStack.clipsToBounds = true

        return hStack
    }()

    private lazy var linkPreviewPanel: UIView = {
        var linkPreviewPanel = UIView()
        linkPreviewPanel.translatesAutoresizingMaskIntoConstraints = false
        linkPreviewPanel.preservesSuperviewLayoutMargins = true
        linkPreviewPanel.addSubview(linkPreviewHStack)
        linkPreviewPanel.addSubview(activityIndicator)
        linkPreviewPanel.addSubview(linkPreviewCloseButton)

        activityIndicator.centerXAnchor.constraint(equalTo: linkPreviewPanel.layoutMarginsGuide.centerXAnchor).isActive = true
        activityIndicator.centerYAnchor.constraint(equalTo: linkPreviewPanel.layoutMarginsGuide.centerYAnchor).isActive = true
        activityIndicator.startAnimating()


        linkPreviewCloseButton.trailingAnchor.constraint(equalTo: linkPreviewHStack.trailingAnchor, constant: -8).isActive = true
        linkPreviewCloseButton.topAnchor.constraint(equalTo: linkPreviewHStack.topAnchor, constant: 8).isActive = true
        linkPreviewMediaView.leadingAnchor.constraint(equalTo: linkPreviewHStack.leadingAnchor, constant: 8).isActive = true
        linkPreviewHStack.topAnchor.constraint(equalTo: linkPreviewPanel.topAnchor, constant: 8).isActive = true
        linkPreviewHStack.bottomAnchor.constraint(equalTo: linkPreviewPanel.bottomAnchor, constant: -8).isActive = true
        linkPreviewHStack.leadingAnchor.constraint(equalTo: linkPreviewPanel.leadingAnchor, constant: 8).isActive = true
        linkPreviewHStack.trailingAnchor.constraint(equalTo: linkPreviewPanel.trailingAnchor, constant: -8).isActive = true
        linkPreviewPanel.heightAnchor.constraint(equalToConstant: 90).isActive = true

        return linkPreviewPanel
    }()

    private lazy var linkPreviewCloseButton: UIButton = {
        let closeButton = UIButton(type: .custom)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(named: "ReplyPanelClose")?.withRenderingMode(.alwaysTemplate), for: .normal)

        closeButton.tintColor = .label.withAlphaComponent(0.5)
        closeButton.addTarget(self, action: #selector(didTapCloseLinkPreviewPanel), for: .touchUpInside)
        closeButton.widthAnchor.constraint(equalToConstant: 12).isActive = true
        closeButton.heightAnchor.constraint(equalToConstant: 12).isActive = true
        return closeButton
    }()

    private func updateLinkPreviewViewIfNecessary() {
        // if has media OR empty text, we need to remove link previews
        if uploadMedia != nil || textView.text == "" {
            resetLinkDetection()
            return
        }
        if !linkDetectionTimer.isValid {
            if let url = detectLink() {
                // Start timer for 1 second before fetching link preview.
                setLinkDetectionTimers(url: url)
            }
        }
    }

    private func setLinkDetectionTimers(url: URL?) {
        linkPreviewUrl = url
        linkDetectionTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(updateLinkDetectionTimer), userInfo: nil, repeats: true)
    }

    private func detectLink() -> URL? {
        let linkDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = linkDetector.matches(in: textView.text, options: [], range: NSRange(location: 0, length: textView.text.utf16.count))
        for match in matches {
            guard let range = Range(match.range, in: textView.text) else { continue }
            let url = textView.text[range]
            if let url = URL(string: String(url)) {
                // We only care about the first link
                return url
            }
        }
        return nil
    }

    @objc private func updateLinkDetectionTimer() {
        linkDetectionTimer.invalidate()
        // After waiting for 1 second, if the url did not change, fetch link preview info
        if let url = detectLink() {
            if url == linkPreviewUrl {
                // Have we already fetched the link? then do not fetch again
                // have we previously fetched the link and it was invalid? then do not fetch again
                if linkPreviewData?.url == linkPreviewUrl || linkPreviewUrl == invalidLinkPreviewUrl {
                    return
                }
                fetchURLPreview()
            } else {
                // link has changed... reset link fetch cycle
                setLinkDetectionTimers(url: url)
            }
        }
    }

    func fetchURLPreview() {
        guard let url = linkPreviewUrl else { return }
        removeLinkPreviewPanel()
        LinkPreviewMetadataProvider.startFetchingMetadata(for: url) { linkPreviewData, previewImage, error in
            guard let data = linkPreviewData, error == nil else {
                self.invalidLinkPreviewUrl = url
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.resetLinkDetection()
                }
                return
            }
            self.linkPreviewData = data
            self.invalidLinkPreviewUrl = nil
            if let previewImage = previewImage {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.activityIndicator.stopAnimating()
                    self.linkPreviewMediaView.isHidden = false
                    self.linkPreviewMediaView.image = previewImage
                    self.linkImageView.isHidden = false
                    self.linkPreviewTitleLabel.text = data.title
                    self.linkPreviewURLLabel.text = data.url.host
                }
            } else {
                // No Image info
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.activityIndicator.stopAnimating()
                    self.linkImageView.isHidden = false
                    self.linkPreviewMediaView.isHidden = true
                    self.linkPreviewTitleLabel.text = data.title
                    self.linkPreviewURLLabel.text = data.url.host
                }
            }
        }
        self.vStack.insertArrangedSubview(self.linkPreviewPanel, at: vStack.arrangedSubviews.firstIndex(of: textFieldPanel)!)
        self.activityIndicator.startAnimating()
        updateBorderRadius()
    }

    private func resetLinkDetection() {
        linkDetectionTimer.invalidate()
        linkPreviewUrl = nil
        linkPreviewData = nil
        removeLinkPreviewPanel()
    }

    func removeLinkPreviewPanel() {
        // remove media panel from stack
        linkPreviewTitleLabel.text = ""
        linkPreviewURLLabel.text = ""
        linkImageView.isHidden = true
        linkPreviewMediaView.image = nil
        linkPreviewPanel.removeFromSuperview()
        postButton.isEnabled = isPostButtonEnabled
        updatePostButtons()
        setNeedsUpdateHeight()
        updateBorderRadius()
    }

    @objc private func didTapCloseLinkPreviewPanel() {
        resetLinkDetection()
    }

    // MARK: Text view

    func clear() {
        uploadMedia = nil
        textView.text = ""
        textView.resetMentions()
        removeMediaPanel()
        removeQuotedReplyPanel()
        self.inputTextViewDidChange(self.textView)
        self.setNeedsUpdateHeight(animationDuration: 0.25)
        resetLinkDetection()
        invalidLinkPreviewUrl = nil
    }

    var text: String! {
        get {
            return self.textView.text
        }
    }

    // MARK: Voice note

    func show(voiceNote url: URL) {
        isShowingVoiceNote = true
        placeholder.isHidden = true
        textView.text = ""
        textView.isHidden = true
        postVoiceNoteButton.isHidden = false
        removeVoiceNoteButton.isHidden = false
        voiceNotePlayer.isHidden = false
        updatePostButtons()

        voiceNoteAudioView.url = url
    }

    func hideVoiceNote() {
        isShowingVoiceNote = false
        voiceNoteAudioView.pause()
        placeholder.isHidden = false
        textView.isHidden = false
        postVoiceNoteButton.isHidden = true
        removeVoiceNoteButton.isHidden = true
        voiceNotePlayer.isHidden = true
        updatePostButtons()
    }
    
    // MARK: Mention Picker
    
    private func updateMentionPickerContent() {

        let mentionableUsers = fetchMentionPickerContent(for: textView.mentionInput)

        self.mentionPicker.items = mentionableUsers
        self.mentionPicker.isHidden = mentionableUsers.isEmpty
        self.mentionPickerTopConstraint?.isActive = !mentionableUsers.isEmpty
        self.vStackTopConstraint?.isActive = mentionableUsers.isEmpty
    }

    @objc func postButtonClicked() {
        if isShowingVoiceNote, let url = voiceNoteAudioView.url {
            hideVoiceNote()

            let media = PendingMedia(type: .audio)
            media.size = .zero
            media.order = 1
            media.fileURL = url

            let text = MentionText(expandedText: "", mentionRanges: [:])
            delegate?.commentInputView(self, wantsToSend: text, andMedia: media, linkPreviewData: nil, linkPreviewMedia: nil)
        } else if voiceNoteRecorder.isRecording {
            voiceNoteRecorder.stop(cancel: false)

            let media = PendingMedia(type: .audio)
            media.size = .zero
            media.order = 1
            media.fileURL = voiceNoteRecorder.url

            let text = MentionText(expandedText: "", mentionRanges: [:])
            delegate?.commentInputView(self, wantsToSend: text, andMedia: media, linkPreviewData: nil, linkPreviewMedia: nil)
        } else if uploadMedia != nil || linkPreviewUrl == nil {
            acceptAutoCorrection()
            delegate?.commentInputView(self, wantsToSend: mentionText.trimmed(), andMedia: uploadMedia, linkPreviewData: nil, linkPreviewMedia: nil)
        } else {
            acceptAutoCorrection()
            guard let image = linkPreviewMediaView.image  else {
                self.delegate?.commentInputView(self, wantsToSend: mentionText.trimmed(), andMedia: nil, linkPreviewData: linkPreviewData, linkPreviewMedia: nil)
                return
            }
            // Send link preview with image
            let linkPreviewMedia = PendingMedia(type: .image)
            linkPreviewMedia.image = image
            if linkPreviewMedia.ready.value {
                self.delegate?.commentInputView(self, wantsToSend: mentionText.trimmed(), andMedia: nil, linkPreviewData: linkPreviewData, linkPreviewMedia: linkPreviewMedia)
            } else {
                self.cancellableSet.insert(
                    linkPreviewMedia.ready.sink { [weak self] ready in
                        guard let self = self else { return }
                        guard ready else { return }
                        self.delegate?.commentInputView(self, wantsToSend: self.mentionText.trimmed(), andMedia: nil, linkPreviewData: self.linkPreviewData, linkPreviewMedia: linkPreviewMedia)
                    }
                )
            }
        }
    }
    
    @objc func pickMediaButtonClicked() {
        delegate?.commentInputViewPickMedia(self)
    }

    @objc func cancelRecordingButtonClicked() {
        if voiceNoteRecorder.isRecording {
            voiceNoteRecorder.stop(cancel: true)
        }
    }

    @objc func removeVoiceNoteClicked() {
        hideVoiceNote()

        if let url = voiceNoteAudioView.url {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                DDLogError("chatInputView/removeVoiceNoteClicked/error [\(error)]")
            }
        }
    }

    var mentionText: MentionText {
        get {
            return MentionText(expandedText: textView.text, mentionRanges: textView.mentions)
        }
        
        set {
            let textAndMentions = newValue.expandedTextAndMentions(nameProvider: { userId in
                MainAppContext.shared.contactStore.fullName(for: userId)
            })
            
            textView.text = textAndMentions.text.string
            textView.mentions = textAndMentions.mentions
        }
    }

    private func acceptAutoCorrection() {
        if self.textView.isFirstResponder {
            if !self.textView.text.isEmpty {
                // Accept auto-correction.
                self.textView.selectedRange = NSRange(location: 0, length: 0)
                // Must clear selection to allow auto-correction to work again.
                self.textView.selectedRange = NSRange(location: NSNotFound, length: 0)
            }
        }
    }
    
    private func acceptMentionPickerItem(_ item: MentionableUser) {
        let input = textView.mentionInput
        guard let mentionCandidateRange = input.rangeOfMentionCandidateAtCurrentPosition() else {
            // For now we assume there is a word to replace (but in theory we could just insert at point)
            return
        }

        let utf16Range = NSRange(mentionCandidateRange, in: text)
        textView.addMention(name: item.fullName, userID: item.userID, in: utf16Range)
        self.updateMentionPickerContent()
    }
    
    private func fetchMentionPickerContent(for input: MentionInput) -> [MentionableUser] {
        guard let mentionCandidateRange = input.rangeOfMentionCandidateAtCurrentPosition() else {
            return []
        }
        let mentionCandidate = input.text[mentionCandidateRange]
        let trimmedInput = String(mentionCandidate.dropFirst())
        return delegate?.commentInputView(self, possibleMentionsForInput: trimmedInput) ?? []
    }

    // MARK: InputTextViewDelegate

    func inputTextViewDidChange(_ inputTextView: InputTextView) {
        textIsUneditedReplyMention = false
        postButton.isEnabled = isPostButtonEnabled
        placeholder.isHidden = !inputTextView.text.isEmpty

        updateMentionPickerContent()
        updateLinkPreviewViewIfNecessary()
        updatePostButtons()
        updateWithMarkdown()
    }
    
    func updateInputView() {
        inputTextViewDidChange(textView)
    }

    func inputTextViewDidChangeSelection(_ inputTextView: InputTextView) {
        self.updateMentionPickerContent()
    }

    func maximumHeight(for inputTextView: InputTextView) -> CGFloat {
        var maxHeight = self.textView5LineHeight
        let screenHeight = UIScreen.main.bounds.height
        maxHeight = ceil(max(min(maxHeight, 0.3 * screenHeight), self.textView1LineHeight))
        return maxHeight
    }

    func inputTextView(_ inputTextView: InputTextView, needsHeightChangedTo newHeight: CGFloat) {
        self.textViewHeight?.constant = newHeight
        self.setNeedsUpdateHeight()
    }

    func inputTextViewShouldBeginEditing(_ inputTextView: InputTextView) -> Bool {
        return !voiceNoteRecorder.isRecording
    }

    func inputTextViewDidBeginEditing(_ inputTextView: InputTextView) {

    }

    func inputTextViewShouldEndEditing(_ inputTextView: InputTextView) -> Bool {
        return true
    }

    func inputTextViewDidEndEditing(_ inputTextView: InputTextView) {
        inputTextView.text = inputTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        placeholder.isHidden = !inputTextView.text.isEmpty
    }

    func inputTextView(_ inputTextView: InputTextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        return true
    }

    // MARK: Keyboard
    enum KeyboardState {
        case hidden
        case hiding
        case showing
        case shown
    }
    var bottomInset: CGFloat = 0
    private var ignoreKeyboardNotifications = true
    private var keyboardState: KeyboardState = .hidden
    static let heightChangeAnimationDuration: TimeInterval = 0.15
    private var animationDurationForHeightUpdate: TimeInterval = -1
    private var updateHeightScheduled = false

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if self.window == nil && newWindow != nil {
            self.ignoreKeyboardNotifications = false
        }
    }

    func showKeyboard(from viewController: UIViewController) {
        guard viewController.isFirstResponder || self.isKeyboardVisible else { return }
        self.textView.becomeFirstResponder()
    }

    func hideKeyboard() {
        self.textView.resignFirstResponder()
    }

    var isKeyboardVisible: Bool {
        get {
            return self.textView.isFirstResponder
        }
    }

    private func updateBottomInset(from keyboardEndFrame: CGRect) {
        let screenSize = UIScreen.main.bounds.size
        let keyboardMinY = keyboardEndFrame.minY
        guard keyboardMinY > 0 else {
            DDLogWarn("CommentInputView/InvalidKeyboardSize")
            return
        }
        let newBottomInset = screenSize.height - keyboardMinY
        if newBottomInset > 0 {
            // If newBottomInset is 0.0, the first responder is going away entirely. However we don't
            // want to change _bottomInset immediately because the user could be interactively popping
            // away and we don't want to trigger any contentInset changes until the interaction is
            // completed.
            self.bottomInset = newBottomInset
        }
    }

    @objc private func keyboardWillShow(notification: Notification) {
        guard !self.ignoreKeyboardNotifications else { return }

        let beginFrame: CGRect = (notification.userInfo?[UIResponder.keyboardFrameBeginUserInfoKey] as? NSValue)!.cgRectValue
        let endFrame: CGRect = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)!.cgRectValue
        var duration: TimeInterval = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as! TimeInterval
        var curve: UIView.AnimationCurve = UIView.AnimationCurve(rawValue: notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as! Int)!
        DDLogDebug("keyboard/will-show: \(NSCoder.string(for: beginFrame)) -> \(NSCoder.string(for: endFrame))")
        self.updateBottomInset(from: endFrame)
        if duration == 0 && self.keyboardState == .shown {
            duration = CommentInputView.heightChangeAnimationDuration
            curve = .easeInOut
        }
        let wasHidden = self.keyboardState == .hidden || self.keyboardState == .hiding
        if wasHidden && !self.isKeyboardVisible {
            duration = 0
            curve = .easeInOut
        }
        self.keyboardState = .showing
        self.delegate?.commentInputView(self, didChangeBottomInsetWith: duration, animationCurve: curve)
    }

    @objc private func keyboardDidShow(notification: Notification) {
        guard !self.ignoreKeyboardNotifications else { return }

        self.keyboardState = .shown
        let beginFrame: CGRect = (notification.userInfo?[UIResponder.keyboardFrameBeginUserInfoKey] as? NSValue)!.cgRectValue
        let endFrame: CGRect = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)!.cgRectValue
        DDLogDebug("keyboard/did-show: \(NSCoder.string(for: beginFrame)) -> \(NSCoder.string(for: endFrame))")
    }

    @objc private func keyboardWillHide(notification: Notification) {
        guard !self.ignoreKeyboardNotifications else { return }

        self.keyboardState = .hiding
        let beginFrame: CGRect = (notification.userInfo?[UIResponder.keyboardFrameBeginUserInfoKey] as? NSValue)!.cgRectValue
        let endFrame: CGRect = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)!.cgRectValue
        var duration: TimeInterval = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as! TimeInterval
        var curve: UIView.AnimationCurve = UIView.AnimationCurve(rawValue: notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as! Int)!
        DDLogDebug("keyboard/will-hide: \(NSCoder.string(for: beginFrame)) -> \(NSCoder.string(for: endFrame))")
        self.updateBottomInset(from: endFrame)
        if duration == 0 {
            duration = CommentInputView.heightChangeAnimationDuration
            curve = .easeInOut
        }
        self.delegate?.commentInputView(self, didChangeBottomInsetWith: duration, animationCurve: curve)
    }

    @objc private func keyboardDidHide(notification: NSNotification) {
        guard !self.ignoreKeyboardNotifications else { return }
        guard self.keyboardState == .hiding else { return }

        self.keyboardState = .hidden
        let beginFrame: CGRect = (notification.userInfo?[UIResponder.keyboardFrameBeginUserInfoKey] as? NSValue)!.cgRectValue
        let endFrame: CGRect = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)!.cgRectValue
        DDLogDebug("keyboard/did-hide: \(NSCoder.string(for: beginFrame)) -> \(NSCoder.string(for: endFrame))")

        // If the owning view controller disappears while the keyboard is still visible, we need to
        // manually notify the view controller to update its bottom inset. Otherwise, for certain
        // custom transitions, updating the bottom inset in response to -keyboardWillShow: may be too
        // late to ensure correct layout, since the initial layout pass to set up the custom transition
        // will already have taken place.
        if self.window == nil {
            self.ignoreKeyboardNotifications = true
            if self.bottomInset != self.bounds.height {
                self.bottomInset = self.bounds.height
                self.delegate?.commentInputView(self, didChangeBottomInsetWith: 0, animationCurve: .easeInOut)
            }
        }
    }

    // MARK: Layout

    func setInputViewWidth(_ width: CGFloat) {
        guard self.bounds.size.width != width else { return }
        let height = self.preferredHeight(for: width)
        var bottomSafeAreaInset = self.safeAreaInsets.bottom
        if bottomSafeAreaInset == 0 && keyboardState == .hidden {
            if let windowScene = UIApplication.shared.connectedScenes.randomElement() as? UIWindowScene {
                if let window = windowScene.windows.last {
                    bottomSafeAreaInset = window.safeAreaInsets.bottom
                }
            }
        }
        self.bounds = CGRect(origin: .zero, size: CGSize(width: width, height: height + bottomSafeAreaInset))
    }

    // MARK: ContainerViewDelegate

    func containerView(_ containerView: ContainerView, preferredHeightFor layoutWidth: CGFloat) -> CGFloat {
        return self.preferredHeight(for: layoutWidth)
    }

    func containerView(_ containerView: ContainerView, didChangeBottomSafeAreaHeight safeAreaHeight: CGFloat) {
        bottomConstraint?.constant = -safeAreaHeight
    }

    func currentLayoutWidth(for containerView: ContainerView) -> CGFloat {
        return self.currentLayoutWidth
    }

    private var currentLayoutWidth: CGFloat {
        get {
            var view: UIView? = self.superview
            if view == nil || view?.bounds.size.width == 0 {
                view = self
            }
            return view!.frame.size.width
        }
    }

    private func setNeedsUpdateHeight() {
        self.setNeedsUpdateHeight(animationDuration:CommentInputView.heightChangeAnimationDuration)
    }

    private func setNeedsUpdateHeight(animationDuration: TimeInterval) {
        guard self.window != nil else {
            self.invalidateLayout()
            return
        }

        // Don't defer the initial layout to avoid UI glitches.
        if self.bounds.size.height == 0.0 {
            self.animationDurationForHeightUpdate = 0.0
            self.updateHeight()
            return
        }

        self.animationDurationForHeightUpdate = max(animationDuration, self.animationDurationForHeightUpdate)
        if (!self.updateHeightScheduled) {
            self.updateHeightScheduled = true
            // Coalesce multiple calls to -setNeedsUpdateHeight.
            DispatchQueue.main.async {
                self.updateHeight()
            }
        }
    }

    private func invalidateLayout() {
        self.invalidateIntrinsicContentSize()
        self.containerView.invalidateIntrinsicContentSize()
    }

    private func updateHeight() {
        self.updateHeightScheduled = false
        let duration = self.animationDurationForHeightUpdate
        self.animationDurationForHeightUpdate = -1

        let animationBlock = {
            self.invalidateLayout()
            self.superview?.setNeedsLayout()
            self.superview?.layoutIfNeeded()

            self.window?.rootViewController?.view.setNeedsLayout()
            // Triggering this layout pass will fire UIKeyboardWillShowNotification.
            self.window?.rootViewController?.view.layoutIfNeeded()
        };
        if duration > 0 {
            UIView.animate(withDuration: duration, animations: animationBlock)
        } else {
            animationBlock()
        }
    }

    private func recalculateSingleLineHeight() {
        self.textView5LineHeight = self.textView.bestHeight(for: "\n\n\n\n")
        self.textView1LineHeight = self.textView.bestHeight(for: nil)
    }

    private func preferredHeight(for layoutWidth: CGFloat) -> CGFloat {
        let contentSize = self.contentView.systemLayoutSizeFitting(CGSize(width: layoutWidth, height: 1e5), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
        return contentSize.height
    }

    override var intrinsicContentSize: CGSize {
        get {
            return self.containerView.intrinsicContentSize
        }
    }

    override var bounds: CGRect {
        get {
            return super.bounds
        }
        set {
            let oldBounds = self.bounds
            super.bounds = newValue
            if (newValue.size.height != self.previousHeight) {
                self.previousHeight = newValue.size.height
            }
            if (newValue.size.width != oldBounds.size.width) {
                self.setNeedsUpdateHeight()
            }
        }
    }
}

// MARK: AudioRecorderControlViewDelegate
extension CommentInputView: AudioRecorderControlViewDelegate {
    func audioRecorderControlViewLocked(_ view: AudioRecorderControlView) {
        isVoiceNoteRecordingLocked = true
        cancelRecordingButton.isHidden = false
        postVoiceNoteButton.isHidden = false
        updatePostButtons()
    }

    func audioRecorderControlViewShouldStart(_ view: AudioRecorderControlView) -> Bool {
        guard !MainAppContext.shared.callManager.isAnyCallActive else {
            delegate?.commentInputViewCouldNotRecordDuringCall(self)
            return false
        }
        voiceNoteTime.text = "0:00"
        voiceNoteTime.isHidden = false
        placeholder.isHidden = true
        textView.isHidden = true
        return true
    }

    func audioRecorderControlViewCancelled(_ view: AudioRecorderControlView) {
        voiceNoteTime.isHidden = true
        textView.isHidden = false
        placeholder.isHidden = !textView.text.isEmpty
    }

    func audioRecorderControlViewStarted(_ view: AudioRecorderControlView) {
        voiceNoteRecorder.start()
    }

    func audioRecorderControlViewFinished(_ view: AudioRecorderControlView, cancel: Bool) {
        voiceNoteTime.isHidden = true
        textView.isHidden = false
        placeholder.isHidden = !textView.text.isEmpty

        guard let duration = voiceNoteRecorder.duration, duration >= 1 else {
            voiceNoteRecorder.stop(cancel: true)
            return
        }

        voiceNoteRecorder.stop(cancel: cancel)

        if !cancel {
            let media = PendingMedia(type: .audio)
            media.size = .zero
            media.order = 1
            media.fileURL = voiceNoteRecorder.url

            let mentionText = MentionText(expandedText: "", mentionRanges: [:])
            delegate?.commentInputView(self, wantsToSend: mentionText.trimmed(), andMedia: media, linkPreviewData: nil, linkPreviewMedia: nil)
        }
    }
}

// MARK: AudioRecorderDelegate
extension CommentInputView: AudioRecorderDelegate {
    func audioRecorderInterrupted(_ recorder: AudioRecorder) {
        delegate?.commentInputView(self, didInterruptRecorder: recorder)
    }

    func audioRecorderMicrophoneAccessDenied(_ recorder: AudioRecorder) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.recordVoiceNoteControl.hide()
            self.voiceNoteTime.isHidden = true
            self.textView.isHidden = false
            self.placeholder.isHidden = !self.textView.text.isEmpty
            self.updatePostButtons()
            self.delegate?.commentInputViewMicrophoneAccessDenied(self)
        }
    }

    func audioRecorderStarted(_ recorder: AudioRecorder) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.voiceNoteTime.text = "0:00"
            self.voiceNoteTime.isHidden = false
            self.placeholder.isHidden = true
            self.textView.isHidden = true
            self.updatePostButtons()
        }
    }

    func audioRecorderStopped(_ recorder: AudioRecorder) {
        guard !isShowingVoiceNote else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.recordVoiceNoteControl.hide()
            self.isVoiceNoteRecordingLocked = false
            self.cancelRecordingButton.isHidden = true
            self.voiceNoteTime.isHidden = true
            self.textView.isHidden = false
            self.placeholder.isHidden = !self.textView.text.isEmpty
            self.postVoiceNoteButton.isHidden = true
            self.updatePostButtons()
        }
    }

    func audioRecorder(_ recorder: AudioRecorder, at time: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.voiceNoteTime.text = time
        }
    }
}

// MARK: AudioViewDelegate
extension CommentInputView: AudioViewDelegate {
    func audioView(_ view: AudioView, at time: String) {
        voiceNotePlayerTime.text = time
    }

    func audioViewDidStartPlaying(_ view: AudioView) {
    }

    func audioViewDidEndPlaying(_ view: AudioView, completed: Bool) {
    }
}
