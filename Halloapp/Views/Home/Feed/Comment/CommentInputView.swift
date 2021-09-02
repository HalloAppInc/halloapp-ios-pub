//
//  CommentInputView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/24/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVKit
import CocoaLumberjackSwift
import Core
import UIKit

fileprivate protocol ContainerViewDelegate: AnyObject {
    func containerView(_ containerView: CommentInputView.ContainerView, preferredHeightFor layoutWidth: CGFloat) -> CGFloat
    func currentLayoutWidth(for containerView: CommentInputView.ContainerView) -> CGFloat
}

protocol CommentInputViewDelegate: AnyObject {
    func commentInputView(_ inputView: CommentInputView, didChangeBottomInsetWith animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve)
    func commentInputView(_ inputView: CommentInputView, wantsToSend text: MentionText, andMedia media: PendingMedia?)
    func commentInputView(_ inputView: CommentInputView, possibleMentionsForInput input: String) -> [MentionableUser]
    func commentInputViewPickMedia(_ inputView: CommentInputView)
    func commentInputViewResetReplyContext(_ inputView: CommentInputView)
    func commentInputViewResetInputMedia(_ inputView: CommentInputView)
    func commentInputViewMicrophoneAccessDenied(_ inputView: CommentInputView)
}

class CommentInputView: UIView, InputTextViewDelegate, ContainerViewDelegate {

    weak var delegate: CommentInputViewDelegate?

    // Only one of these should be active at a time
    private var mentionPickerTopConstraint: NSLayoutConstraint?
    private var vStackTopConstraint: NSLayoutConstraint?
    
    private var textViewHeight: NSLayoutConstraint?
    private var textView1LineHeight: CGFloat = 0
    private var textView5LineHeight: CGFloat = 0

    private var previousHeight: CGFloat = 0
    let closeButtonDiameter: CGFloat = 24

    private var voiceNoteRecorder = AudioRecorder()
    private var isVoiceNoteRecordingLocked = false

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

        override init(frame: CGRect) {
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            self.invalidateIntrinsicContentSize()
        }

        override var intrinsicContentSize: CGSize {
            get {
                let width = self.delegate!.currentLayoutWidth(for: self)
                let height = self.preferredHeight(for: width) + self.safeAreaInsets.bottom
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
        return textView
    }()

    private lazy var textFieldPanel: UIView = {
        let textFieldPanel = UIView()
        textFieldPanel.backgroundColor = .systemBackground
        textFieldPanel.translatesAutoresizingMaskIntoConstraints = false
        textFieldPanel.preservesSuperviewLayoutMargins = true

        textFieldPanel.addSubview(textFieldPanelContent)
        textFieldPanelContent.leadingAnchor.constraint(equalTo: textFieldPanel.layoutMarginsGuide.leadingAnchor).isActive = true
        textFieldPanelContent.topAnchor.constraint(equalTo: textFieldPanel.layoutMarginsGuide.topAnchor).isActive = true
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

        textViewContainer.addSubview(voiceNoteTime)
        voiceNoteTime.leadingAnchor.constraint(equalTo: textViewContainer.leadingAnchor).isActive = true
        voiceNoteTime.centerYAnchor.constraint(equalTo: textViewContainer.centerYAnchor).isActive = true

        let buttonStack = UIStackView(arrangedSubviews: [pickMediaButton, recordVoiceNoteControl, postButton])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .horizontal
        buttonStack.spacing = 10

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
        stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
        buttonStack.bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: -8).isActive = true
        cancelRecordingButton.centerXAnchor.constraint(equalTo: stack.centerXAnchor).isActive = true
        cancelRecordingButton.centerYAnchor.constraint(equalTo: stack.centerYAnchor).isActive = true

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
        button.widthAnchor.constraint(equalToConstant: 19).isActive = true
        return button
    }()

    private lazy var mediaView: UIImageView = {
        let mediaView = UIImageView()
        mediaView.contentMode = .scaleAspectFit
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        mediaView.widthAnchor.constraint(equalToConstant: 100).isActive = true
        mediaView.heightAnchor.constraint(equalToConstant: 100).isActive = true
        return mediaView
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
        mediaPanel.backgroundColor = .systemBackground

        let backgroundView = UIView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.backgroundColor = .systemBackground
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

    private lazy var voiceNoteTime: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 21)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = .lavaOrange
        label.layer.cornerRadius = 10
        label.layer.masksToBounds = true
        label.isHidden = true

        label.widthAnchor.constraint(equalToConstant: 80).isActive = true
        label.heightAnchor.constraint(equalToConstant: 33).isActive = true

        return label
    }()

    private lazy var recordVoiceNoteControl: AudioRecorderControlView = {
        let controlView = AudioRecorderControlView()
        controlView.translatesAutoresizingMaskIntoConstraints = false
        controlView.layer.zPosition = 1

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
        panel.backgroundColor = .systemBackground

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
        self.contentView.bottomAnchor.constraint(equalTo: self.containerView.safeAreaLayoutGuide.bottomAnchor).isActive = true

        // Bottom Safe Area background
        let bottomBackgroundView = UIView()
        bottomBackgroundView.backgroundColor = .systemBackground
        bottomBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        self.containerView.addSubview(bottomBackgroundView)
        bottomBackgroundView.leadingAnchor.constraint(equalTo: self.containerView.leadingAnchor).isActive = true
        bottomBackgroundView.topAnchor.constraint(equalTo: self.contentView.bottomAnchor).isActive = true
        bottomBackgroundView.trailingAnchor.constraint(equalTo: self.containerView.trailingAnchor).isActive = true
        bottomBackgroundView.bottomAnchor.constraint(equalTo: self.containerView.bottomAnchor).isActive = true

        // Input field wrapper
        self.textView.inputTextViewDelegate = self
        self.textView.text = ""

        // Placeholder
        self.placeholder.text = NSLocalizedString("comment.textfield.placeholder",
                                                  value: "Add a comment",
                                                  comment: "Text displayed in gray inside of the comment input field when there is no user input.")

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

    private func updatePostButtons() {
        pickMediaButton.isHidden = true
        recordVoiceNoteControl.isHidden = true
        postButton.isHidden = true

        if !textView.text.isEmpty || mediaPanel.superview != nil {
            if ServerProperties.isMediaCommentsEnabled {
                pickMediaButton.isHidden = false
            }

            postButton.isHidden = false
        } else if voiceNoteRecorder.isRecording {
            if isVoiceNoteRecordingLocked {
                postButton.isHidden = false
            } else {
                recordVoiceNoteControl.isHidden = false
            }
        } else {
            if ServerProperties.isMediaCommentsEnabled {
                pickMediaButton.isHidden = false
            }

            if ServerProperties.isVoiceNotesEnabled {
                recordVoiceNoteControl.isHidden = false
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

    func showMediaPanel(with media : PendingMedia) {
        // Prepare cell for reuse
        if vStack.arrangedSubviews.contains(mediaPanel) {
            mediaView.image = nil
            mediaView.removeFromSuperview()
            mediaCloseButton.removeFromSuperview()
            vStack.removeArrangedSubview(mediaPanel)
            mediaPanel.removeFromSuperview()
        }
        if media.type == .image {
            mediaView.image = media.image
        } else if media.type == .video {
            guard let url = media.fileURL else { return }
            mediaView.image = VideoUtils.videoPreviewImage(url: url)
        } else {
         return
        }
        mediaPanel.addSubview(mediaView)

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
        }
        postButton.isEnabled = isPostButtonEnabled
        updatePostButtons()
    }

    func removeMediaPanel() {
        // remove media panel from stack
        mediaCloseButton.removeFromSuperview()
        mediaView.image = nil
        vStack.removeArrangedSubview(mediaPanel)
        mediaPanel.removeFromSuperview()
        postButton.isEnabled = isPostButtonEnabled
        updatePostButtons()
        self.setNeedsUpdateHeight()
    }


    // MARK: Text view

    func clear() {
        textView.text = ""
        textView.resetMentions()
        removeMediaPanel()
        self.inputTextViewDidChange(self.textView)
        self.setNeedsUpdateHeight(animationDuration: 0.25)
    }

    var text: String! {
        get {
            return self.textView.text
        }
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
        if voiceNoteRecorder.isRecording {
            voiceNoteRecorder.stop(cancel: false)

            let media = PendingMedia(type: .audio)
            media.size = .zero
            media.order = 1
            media.fileURL = voiceNoteRecorder.url

            let text = MentionText(expandedText: "", mentionRanges: [:])
            delegate?.commentInputView(self, wantsToSend: text, andMedia: media)
        } else {
            acceptAutoCorrection()
            delegate?.commentInputView(self, wantsToSend: mentionText.trimmed(), andMedia: nil)
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
        updatePostButtons()
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
        let newBottomInset = screenSize.height - keyboardEndFrame.origin.y
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

    func containerView(_ containerView: ContainerView, preferredHeightFor layoutWidth: CGFloat) -> CGFloat {
        return self.preferredHeight(for: layoutWidth)
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
        postButton.tintColor = .white
        postButton.backgroundColor = .primaryBlue
        postButton.layer.cornerRadius = 18
        postButton.layer.masksToBounds = true
        postButton.isEnabled = true
        updatePostButtons()
    }

    func audioRecorderControlViewStarted(_ view: AudioRecorderControlView) {
        voiceNoteRecorder.start()
    }

    func audioRecorderControlViewFinished(_ view: AudioRecorderControlView, cancel: Bool) {
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
            delegate?.commentInputView(self, wantsToSend: mentionText.trimmed(), andMedia: media)
        }
    }
}

// MARK: AudioRecorderDelegate
extension CommentInputView: AudioRecorderDelegate {
    func audioRecorderMicrphoneAccessDenied(_ recorder: AudioRecorder) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
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
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isVoiceNoteRecordingLocked = false
            self.cancelRecordingButton.isHidden = true
            self.voiceNoteTime.isHidden = true
            self.textView.isHidden = false
            self.placeholder.isHidden = !self.textView.text.isEmpty
            self.postButton.tintColor = .primaryBlue
            self.postButton.backgroundColor = .none
            self.postButton.layer.cornerRadius = 0
            self.postButton.layer.masksToBounds = false
            self.postButton.isEnabled = false
            self.hideKeyboard()
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
