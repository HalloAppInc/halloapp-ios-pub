//
//  HalloApp
//
//  Created by Tony Jiang on 4/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVKit
import CocoaLumberjackSwift
import Combine
import Core
import UIKit

fileprivate struct Constants {
    static let QuotedMediaSize: CGFloat = 60
}

fileprivate protocol ContainerViewDelegate: AnyObject {
    func containerView(_ containerView: ChatInputView.ContainerView, preferredHeightFor layoutWidth: CGFloat) -> CGFloat
    func currentLayoutWidth(for containerView: ChatInputView.ContainerView) -> CGFloat
}

protocol ChatInputViewDelegate: AnyObject {
    func chatInputView(_ inputView: ChatInputView, didChangeBottomInsetWith animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve)
    func chatInputView(_ inputView: ChatInputView, mentionText: MentionText, media: [PendingMedia])
    func chatInputView(_ inputView: ChatInputView, isTyping: Bool)
    func chatInputViewDidPasteImage(_ inputView: ChatInputView, media: PendingMedia)
    func chatInputViewDidSelectMediaPicker(_ inputView: ChatInputView)
    func chatInputViewMicrophoneAccessDenied(_ inputView: ChatInputView)
    func chatInputViewCloseQuotePanel(_ inputView: ChatInputView)
}

protocol ChatInputViewMentionsDelegate: AnyObject {
    func chatInputView(_ inputView: ChatInputView, possibleMentionsForInput input: String) -> [MentionableUser]
}

class ChatInputView: UIView, UITextViewDelegate, ContainerViewDelegate, MsgUIProtocol {
    private var cancellableSet: Set<AnyCancellable> = []
    weak var delegate: ChatInputViewDelegate?
    weak var mentionsDelegate: ChatInputViewMentionsDelegate?

    static private let voiceNoteDurationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.zeroFormattingBehavior = .pad
        formatter.allowedUnits = [.second, .minute]

        return formatter
    }()

    private var previousHeight: CGFloat = 0
    
    private var isVisible: Bool = false
    private var makeTextViewFirstResponderWhenReady: Bool = false
    
    // only send a typing indicator once in 10 seconds
    private let typingThrottleInterval: TimeInterval = 10
    private var typingThrottleTimer: Timer? = nil
    
    // only send an available indicator after 3 seconds of no typing
    private let typingDebounceInterval: TimeInterval = 3
    private var typingDebounceTimer: Timer? = nil

    private var voiceNoteRecorder = AudioRecorder()
    private var isVoiceNoteRecordingLocked = false
    
    // MARK: ChatInput Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        previousHeight = frame.size.height
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    func willAppear(in viewController: UIViewController) {
        setInputViewWidth(viewController.view.bounds.size.width)
    }

    func didAppear(in viewController: UIViewController) {
        isVisible = true
        
        // fix for intermittent keyboard not showing up,
        // dispatch to fix issue prior to iOS 14.4 where manual swipe back gets keyboard
        // floating in the air when it's opened
        // should revisit/refactor keyboard logic eventually
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            viewController.becomeFirstResponder()

            if self.makeTextViewFirstResponderWhenReady {
                self.textView.becomeFirstResponder()
                self.makeTextViewFirstResponderWhenReady = false
            }
        }
    }

    func willDisappear(in viewController: UIViewController) {
        isVisible = false
        makeTextViewFirstResponderWhenReady = false
        guard isKeyboardVisible || !viewController.isFirstResponder else { return }

        var deferResigns = false
        if viewController.isMovingFromParent {
            // Popping
            deferResigns = true
        } else if isKeyboardVisible {
            // Pushing or presenting
            deferResigns = viewController.transitionCoordinator != nil && viewController.transitionCoordinator!.initiallyInteractive
        }
        if deferResigns && viewController.transitionCoordinator != nil {
            viewController.transitionCoordinator?.animate(alongsideTransition: nil, completion: { [weak self] context in
                guard let self = self else { return }
                if !context.isCancelled {
                    self.resignFirstResponderOnDisappear(in: viewController)
                }
            })
        } else {
            resignFirstResponderOnDisappear(in: viewController)
        }

        resetTypingTimers()
    }

    // Only one of these should be active at a time
    private var mentionPickerTopConstraint: NSLayoutConstraint?
    private var vStackTopConstraint: NSLayoutConstraint?

    private func setup() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidShow), name: UIResponder.keyboardDidShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidHide), name: UIResponder.keyboardDidHideNotification, object: nil)

        autoresizingMask = .flexibleHeight

        layer.borderWidth = 1
        layer.borderColor = UIColor.chatTextFieldStroke.cgColor

        addSubview(containerView)
        containerView.backgroundColor = UIColor.messageFooterBackground
        containerView.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        containerView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        containerView.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        containerView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true

        containerView.addSubview(contentView)

        contentView.leadingAnchor.constraint(equalTo: containerView.layoutMarginsGuide.leadingAnchor).isActive = true
        contentView.topAnchor.constraint(equalTo: containerView.layoutMarginsGuide.topAnchor).isActive = true
        contentView.trailingAnchor.constraint(equalTo: containerView.layoutMarginsGuide.trailingAnchor).isActive = true
        contentView.bottomAnchor.constraint(equalTo: containerView.layoutMarginsGuide.bottomAnchor).isActive = true

        textView.leadingAnchor.constraint(equalTo: textViewContainer.leadingAnchor).isActive = true
        textView.topAnchor.constraint(equalTo: textViewContainer.topAnchor).isActive = true
        textView.trailingAnchor.constraint(equalTo: textViewContainer.trailingAnchor).isActive = true
        textView.bottomAnchor.constraint(equalTo: textViewContainer.bottomAnchor).isActive = true

        placeholder.leadingAnchor.constraint(equalTo: textViewContainer.leadingAnchor, constant: 5).isActive = true
        placeholder.topAnchor.constraint(equalTo: textViewContainer.topAnchor, constant: textView.textContainerInset.top + 1).isActive = true

        voiceNoteTime.leadingAnchor.constraint(equalTo: textViewContainer.leadingAnchor, constant: 14).isActive = true
        voiceNoteTime.centerYAnchor.constraint(equalTo: textViewContainer.centerYAnchor).isActive = true

        postVoiceNoteButton.trailingAnchor.constraint(equalTo: textInputRow.trailingAnchor).isActive = true
        postVoiceNoteButton.centerYAnchor.constraint(equalTo: textInputRow.centerYAnchor).isActive = true

        textInputRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true

        cancelRecordingButton.centerXAnchor.constraint(equalTo: textInputRow.centerXAnchor).isActive = true
        cancelRecordingButton.centerYAnchor.constraint(equalTo: textInputRow.centerYAnchor).isActive = true

        textViewContainerHeightConstraint = textViewContainer.heightAnchor.constraint(equalToConstant: 115)

        contentView.addSubview(vStack)

        vStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor).isActive = true
        vStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor).isActive = true
        vStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor).isActive = true
                
        vStackTopConstraint = vStack.topAnchor.constraint(equalTo: contentView.topAnchor)
        vStackTopConstraint?.isActive = true
        
        // mention picker
        contentView.addSubview(mentionPicker)
        
        mentionPicker.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 25).isActive = true
        mentionPicker.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -25).isActive = true
        
        mentionPicker.bottomAnchor.constraint(equalTo: textView.topAnchor).isActive = true
        mentionPicker.heightAnchor.constraint(lessThanOrEqualToConstant: 120).isActive = true
        mentionPicker.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        
        mentionPickerTopConstraint = mentionPicker.topAnchor.constraint(equalTo: contentView.topAnchor)
        
        placeholder.isHidden = false
        updatePostButtons()

        voiceNoteRecorder.delegate = self
        recordVoiceNoteControl.delegate = self
    }

    private func updatePostButtons() {
        postMediaButton.isHidden = true
        recordVoiceNoteControl.isHidden = true
        postButton.isHidden = true

        let mentionText = MentionText(expandedText: textView.text, mentionRanges: textView.mentions)

        if !mentionText.isNonMentionTextEmpty() {
            postMediaButton.isHidden = false
            postButton.isHidden = false
        } else if voiceNoteRecorder.isRecording {
            if !isVoiceNoteRecordingLocked {
                recordVoiceNoteControl.isHidden = false
            }
        } else {
            postMediaButton.isHidden = false

            if ServerProperties.isVoiceNotesEnabled {
                recordVoiceNoteControl.isHidden = false
            }
        }
    }
    
    class ContainerView: UIView {
        fileprivate weak var delegate: ContainerViewDelegate?

        override init(frame: CGRect) {
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

        func setupView() {
            translatesAutoresizingMaskIntoConstraints = false
            setContentHuggingPriority(.required, for: .vertical)
            setContentCompressionResistancePriority(.required, for: .vertical)
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            invalidateIntrinsicContentSize()
        }

        override var intrinsicContentSize: CGSize {
            get {
                let width = delegate!.currentLayoutWidth(for: self)
                let height = preferredHeight(for: width) + self.safeAreaInsets.bottom
                return CGSize(width: width, height: height)
            }
        }

        func preferredHeight(for layoutWidth: CGFloat) -> CGFloat {
            return delegate!.containerView(self, preferredHeightFor: layoutWidth)
        }
    }

    private lazy var containerView: ContainerView = {
        let view = ContainerView()
        view.delegate = self
        
        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()

    private lazy var contentView: UIStackView = {
        let view = UIStackView()
        
        view.axis = .vertical
        view.spacing = 8
        
        view.translatesAutoresizingMaskIntoConstraints = false
                
        return view
    }()
    
    private lazy var vStack: UIStackView = {
        let view = UIStackView(arrangedSubviews: [quoteFeedPanel, textInputRow])
        view.axis = .vertical
        view.alignment = .trailing
        view.spacing = 4
    
        let subView = UIView(frame: view.bounds)
        subView.backgroundColor = UIColor.messageFooterBackground
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(subView, at: 0)
        
        view.layoutMargins = UIEdgeInsets(top: 5, left: 15, bottom: 8, right: 15)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
                
        quoteFeedPanel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor).isActive = true
        
        textInputRow.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor).isActive = true
        textInputRow.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor).isActive = true
        
        return view
    }()
    
    private lazy var mentionPicker: MentionPickerView = {
        let picker = MentionPickerView(avatarStore: MainAppContext.shared.avatarStore)
        picker.cornerRadius = 10
        picker.borderWidth = 1
        picker.borderColor = .systemGray
        picker.clipsToBounds = true
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.isHidden = true // Hide until content is set
        picker.didSelectItem = { [weak self] item in
            self?.acceptMentionPickerItem(item)
        }
        return picker
    }()
    
    private func acceptAutoCorrection() {
        guard textView.isFirstResponder else { return }
        guard !textView.text.isEmpty else { return }
        // Accept auto-correction.
        textView.selectedRange = NSRange(location: 0, length: 0)
        // Must clear selection to allow auto-correction to work again.
        textView.selectedRange = NSRange(location: NSNotFound, length: 0)
    }
    
    private lazy var quoteFeedPanel: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ quoteFeedPanelTextMediaContent, quoteFeedPanelCloseButton ])
        view.axis = .horizontal
        view.alignment = .top
        view.spacing = 8

        let subView = UIView(frame: view.bounds)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        subView.layer.cornerRadius = 15
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        view.insertSubview(subView, at: 0)
        
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    private lazy var quoteFeedPanelTextMediaContent: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ quoteFeedPanelTextContent, quoteFeedPanelImage ])
        view.axis = .horizontal
        view.alignment = .top
        view.spacing = 3
        
        view.layoutMargins = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 8)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        quoteFeedPanelImage.widthAnchor.constraint(equalToConstant: Constants.QuotedMediaSize).isActive = true
        quoteFeedPanelImage.heightAnchor.constraint(equalToConstant: Constants.QuotedMediaSize).isActive = true

        return view
    }()
    
    private lazy var quoteFeedPanelTextContent: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ quoteFeedPanelNameLabel, quoteFeedPanelTextLabel ])
        view.axis = .vertical
        view.spacing = 3
        view.layoutMargins = UIEdgeInsets(top: 0, left: 5, bottom: 10, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var quoteFeedPanelNameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.textColor = UIColor.label
        
        return label
    }()
    
    private lazy var quoteFeedPanelTextLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 2
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.textColor = UIColor.secondaryLabel
        
        return label
    }()
    
    private lazy var quoteFeedPanelImage: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        
        imageView.layer.cornerRadius = 5
        imageView.layer.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        imageView.isHidden = true
        
        return imageView
    }()

    private lazy var quoteFeedPanelCloseButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 0, bottom: 0, right: 10)
        button.tintColor = UIColor.systemGray
        button.addTarget(self, action: #selector(self.closeQuoteFeedPanel), for: .touchUpInside)
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }()
    
    private var textViewContainerHeightConstraint: NSLayoutConstraint?
    
    private lazy var textInputRow: UIStackView = {
        // use a separate holder to keep the buttons at the bottom while textview is expanding
        let buttonHolder = UIStackView(arrangedSubviews: [postMediaButton, recordVoiceNoteControl, postButton])
        buttonHolder.translatesAutoresizingMaskIntoConstraints = false
        buttonHolder.axis = .horizontal
        buttonHolder.alignment = .center
        buttonHolder.spacing = 16

        buttonHolder.heightAnchor.constraint(equalToConstant: 38).isActive = true

        let view = UIStackView(arrangedSubviews: [textViewContainer, buttonHolder])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .horizontal
        view.alignment = .bottom
        view.spacing = 0

        view.addSubview(cancelRecordingButton)
        view.addSubview(postVoiceNoteButton)

        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }()
    
    private lazy var textView: InputTextView = {
        let view = InputTextView(frame: .zero)
        view.isScrollEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.messageFooterBackground
        view.font = UIFont.preferredFont(forTextStyle: .subheadline)
        view.tintColor = .systemBlue
        view.textColor = .label
        
        view.inputTextViewDelegate = self
        view.onPasteImage = { [weak self] in
            if let image = UIPasteboard.general.image {
                let media = PendingMedia(type: .image)
                media.image = image
                if let self = self, media.ready.value {
                    self.delegate?.chatInputViewDidPasteImage(self,media: media)
                } else {
                    self?.cancellableSet.insert(
                        media.ready.sink { [weak self] ready in
                            guard let self = self else { return }
                            guard ready else { return }
                            self.delegate?.chatInputViewDidPasteImage(self, media: media)
                        }
                    )
                }
            }
        }

        return view
    }()

    private lazy var placeholder: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .primaryBlackWhite
        label.text = Localizations.chatInputPlaceholder
        label.isHidden = true
        label.alpha = 0.4

        return label
    }()
    
    private lazy var textViewContainer: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemBackground
        view.addSubview(textView)
        view.addSubview(placeholder)
        view.addSubview(voiceNoteTime)
        
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        return view
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
        let controlView = AudioRecorderControlView()
        controlView.translatesAutoresizingMaskIntoConstraints = false
        controlView.layer.zPosition = 1

        controlView.widthAnchor.constraint(equalToConstant: 38).isActive = true
        controlView.heightAnchor.constraint(equalToConstant: 24).isActive = true

        controlView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        controlView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        return controlView
    }()
    
    private lazy var postMediaButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "Photo")?.withTintColor(.primaryBlue), for: .normal)
        button.addTarget(self, action: #selector(postMediaButtonClicked), for: .touchUpInside)
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        button.tintColor = UIColor.primaryBlue
        button.accessibilityLabel = Localizations.fabAccessibilityPhotoLibrary
        
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true

        return button
    }()
    
    private lazy var postButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: "Send"), for: .normal)
        button.accessibilityLabel = Localizations.buttonSend
        button.addTarget(self, action: #selector(postButtonClicked), for: .touchUpInside)

        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        button.tintColor = UIColor.systemBlue

        button.backgroundColor = UIColor.clear
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        button.widthAnchor.constraint(equalToConstant: 38).isActive = true
        button.heightAnchor.constraint(equalToConstant: 38).isActive = true
   
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
    
    private func resignFirstResponderOnDisappear(in viewController: UIViewController) {
        self.hideKeyboard()
        viewController.resignFirstResponder()
    }

    // MARK: Layout

    func setInputViewWidth(_ width: CGFloat) {
        guard bounds.size.width != width else { return }
        bounds = CGRect(origin: .zero, size: CGSize(width: width, height: containerView.preferredHeight(for: width)))
    }

    func containerView(_ containerView: ContainerView, preferredHeightFor layoutWidth: CGFloat) -> CGFloat {
        return preferredHeight(for: layoutWidth)
    }

    func currentLayoutWidth(for containerView: ContainerView) -> CGFloat {
        return currentLayoutWidth
    }

    private var currentLayoutWidth: CGFloat {
        get {
            var view: UIView? = superview
            if view == nil || view?.bounds.size.width == 0 {
                view = self
            }
            return view!.frame.size.width
        }
    }

    private func setNeedsUpdateHeight() {
        setNeedsUpdateHeight(animationDuration:CommentInputView.heightChangeAnimationDuration)
    }

    private func setNeedsUpdateHeight(animationDuration: TimeInterval) {
        guard window != nil else {
            invalidateLayout()
            return
        }

        // Don't defer the initial layout to avoid UI glitches.
        if bounds.size.height == 0.0 {
            animationDurationForHeightUpdate = 0.0
            updateHeight()
            return
        }

        animationDurationForHeightUpdate = max(animationDuration, animationDurationForHeightUpdate)
        if (!updateHeightScheduled) {
            updateHeightScheduled = true
            // Coalesce multiple calls to -setNeedsUpdateHeight.
            DispatchQueue.main.async {
                self.updateHeight()
            }
        }
    }

    private func invalidateLayout() {
        invalidateIntrinsicContentSize()
        containerView.invalidateIntrinsicContentSize()
    }

    private func updateHeight() {
        updateHeightScheduled = false
        let duration = animationDurationForHeightUpdate
        animationDurationForHeightUpdate = -1

        let animationBlock = {
            self.invalidateLayout()
            self.superview?.setNeedsLayout()
            self.superview?.layoutIfNeeded()

            self.window?.rootViewController?.view.setNeedsLayout()
            // Triggering this layout pass will fire UIKeyboardWillShowNotification.
            self.window?.rootViewController?.view.layoutIfNeeded()
        }
        if duration > 0 {
            UIView.animate(withDuration: duration, animations: animationBlock)
        } else {
            animationBlock()
        }
    }

    private func preferredHeight(for layoutWidth: CGFloat) -> CGFloat {
        return 0
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

    // MARK: Quote Panel
    
    func showQuoteFeedPanel(with userId: String, text: String, mediaType: ChatMessageMediaType?, mediaUrl: URL?, groupID: GroupID? = nil, from viewController: UIViewController) {
        quoteFeedPanelNameLabel.text = MainAppContext.shared.contactStore.fullName(for: userId)
        quoteFeedPanelTextLabel.text = text

        if userId == MainAppContext.shared.userData.userId {
            quoteFeedPanelNameLabel.textColor = .chatOwnMsg
        } else {
            quoteFeedPanelNameLabel.textColor = .label
        }

        quoteFeedPanel.subviews[0].backgroundColor = quoteFeedPanelNameLabel.textColor.withAlphaComponent(0.1)

        if let type = mediaType, let url = mediaUrl {
            quoteFeedPanelImage.isHidden = false

            switch type {
            case .image:
                if let image = UIImage(contentsOfFile: url.path) {
                    quoteFeedPanelImage.contentMode = .scaleAspectFill
                    quoteFeedPanelImage.image = image
                }
            case .video:
                if let image = VideoUtils.videoPreviewImage(url: url) {
                    quoteFeedPanelImage.contentMode = .scaleAspectFill
                    quoteFeedPanelImage.image = image
                }
            case .audio:
                quoteFeedPanelImage.isHidden = true

                let text = NSMutableAttributedString()

                if let icon = UIImage(named: "Microphone")?.withTintColor(.systemGray) {
                    let attachment = NSTextAttachment(image: icon)
                    attachment.bounds = CGRect(x: 0, y: -3, width: 16, height: 16)

                    text.append(NSAttributedString(attachment: attachment))
                }

                text.append(NSAttributedString(string: Localizations.chatMessageAudio))

                if FileManager.default.fileExists(atPath: url.path) {
                    let duration = Self.voiceNoteDurationFormatter.string(from: AVURLAsset(url: url).duration.seconds) ?? ""
                    text.append(NSAttributedString(string: " (" + duration + ")"))
                }

                quoteFeedPanelTextLabel.attributedText = text.with(
                    font: UIFont.preferredFont(forTextStyle: .subheadline),
                    color: UIColor.secondaryLabel)
            }
        } else {
            quoteFeedPanelImage.isHidden = true
        }

        quoteFeedPanel.isHidden = false

        if !isVisible {
            makeTextViewFirstResponderWhenReady = true
        } else {
            textView.becomeFirstResponder()
        }
    }

    @objc func closeQuoteFeedPanel() {
        quoteFeedPanel.isHidden = true
        delegate?.chatInputViewCloseQuotePanel(self)
    }
    
    private func resetTypingTimers() {
        
        // set typing indicator back to available first
        if typingThrottleTimer != nil {
            delegate?.chatInputView(self, isTyping: false)
        }
        
        typingThrottleTimer?.invalidate()
        typingThrottleTimer = nil

        typingDebounceTimer?.invalidate()
        typingDebounceTimer = nil
        
    }
    
    // MARK: Text view
    
    func setDraftText(text: String) {
        guard !text.isEmpty else { return }
        textView.text = text
        placeholder.isHidden = true
        updatePostButtons()
    }
    
    var text: String {
        get {
            textView.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        }
        set {
            textView.text = newValue
            textView.sizeToFit()
            textView.textViewDidChange(textView)
        }
    }

    var textIsUneditedReplyMention = false
    
    
    func addReplyMentionIfPossible(for userID: UserID, name: String) {
        if textView.text.isEmpty || textIsUneditedReplyMention {
//            clear()
            textView.addMention(name: name, userID: userID, in: NSRange(location: 0, length: 0))
            textIsUneditedReplyMention = true
        }
    }

    @objc func cancelRecordingButtonClicked() {
        if voiceNoteRecorder.isRecording {
            voiceNoteRecorder.stop(cancel: true)
        }
    }
    
    @objc func postButtonClicked() {
        resetTypingTimers()
        acceptAutoCorrection()

        if voiceNoteRecorder.isRecording {
            guard let duration = voiceNoteRecorder.duration, duration >= 1 else {
                voiceNoteRecorder.stop(cancel: true)
                return
            }

            voiceNoteRecorder.stop(cancel: false)

            let media = PendingMedia(type: .audio)
            media.size = .zero
            media.order = 1
            media.fileURL = voiceNoteRecorder.url

            let mentionText = MentionText(expandedText: "", mentionRanges: [:])
            delegate?.chatInputView(self, mentionText: mentionText, media: [media])
        } else {
            let mentionText = MentionText(expandedText: textView.text, mentionRanges: textView.mentions)
            delegate?.chatInputView(self, mentionText: mentionText, media: [])
        }

        closeQuoteFeedPanel()
        textView.resetMentions()
    }

    @objc func postMediaButtonClicked() {
        guard voiceNoteRecorder.isRecording != true else { return }
        
        resetTypingTimers()
        
        delegate?.chatInputViewDidSelectMediaPicker(self)
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
        guard isVisible else { return }
        guard viewController.isFirstResponder || self.isKeyboardVisible else { return }
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1.3) {
            self.textView.becomeFirstResponder()
        }
    }
    
    func hideKeyboard() {
        textView.resignFirstResponder()
    }

    var isKeyboardVisible: Bool {
        get {
            return textView.isFirstResponder
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
            bottomInset = newBottomInset
        }
    }

    @objc private func keyboardWillShow(notification: Notification) {
        guard !self.ignoreKeyboardNotifications else { return }

//        let beginFrame: CGRect = (notification.userInfo?[UIResponder.keyboardFrameBeginUserInfoKey] as? NSValue)!.cgRectValue
        let endFrame: CGRect = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)!.cgRectValue
        var duration: TimeInterval = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as! TimeInterval
        var curve: UIView.AnimationCurve = UIView.AnimationCurve(rawValue: notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as! Int)!
//        DDLogDebug("chatView/keyboard/will-show: \(NSCoder.string(for: beginFrame)) -> \(NSCoder.string(for: endFrame))")
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
        self.delegate?.chatInputView(self, didChangeBottomInsetWith: duration, animationCurve: curve)
    }

    @objc private func keyboardDidShow(notification: Notification) {
        guard !self.ignoreKeyboardNotifications else { return }

        self.keyboardState = .shown
//        let beginFrame: CGRect = (notification.userInfo?[UIResponder.keyboardFrameBeginUserInfoKey] as? NSValue)!.cgRectValue
//        let endFrame: CGRect = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)!.cgRectValue
//        DDLogDebug("chatView/keyboard/did-show: \(NSCoder.string(for: beginFrame)) -> \(NSCoder.string(for: endFrame))")
    }

    @objc private func keyboardWillHide(notification: Notification) {
        guard !self.ignoreKeyboardNotifications else { return }

        self.keyboardState = .hiding
//        let beginFrame: CGRect = (notification.userInfo?[UIResponder.keyboardFrameBeginUserInfoKey] as? NSValue)!.cgRectValue
        let endFrame: CGRect = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)!.cgRectValue
        var duration: TimeInterval = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as! TimeInterval
        var curve: UIView.AnimationCurve = UIView.AnimationCurve(rawValue: notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as! Int)!
//        DDLogDebug("chatView/keyboard/will-hide: \(NSCoder.string(for: beginFrame)) -> \(NSCoder.string(for: endFrame))")
        self.updateBottomInset(from: endFrame)
        if duration == 0 {
            duration = CommentInputView.heightChangeAnimationDuration
            curve = .easeInOut
        }
        self.delegate?.chatInputView(self, didChangeBottomInsetWith: duration, animationCurve: curve)
    }

    @objc private func keyboardDidHide(notification: NSNotification) {
        guard !self.ignoreKeyboardNotifications else { return }
        guard self.keyboardState == .hiding else { return }

        self.keyboardState = .hidden
//        let beginFrame: CGRect = (notification.userInfo?[UIResponder.keyboardFrameBeginUserInfoKey] as? NSValue)!.cgRectValue
//        let endFrame: CGRect = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)!.cgRectValue
//        DDLogDebug("chatView/keyboard/did-hide: \(NSCoder.string(for: beginFrame)) -> \(NSCoder.string(for: endFrame))")

        // If the owning view controller disappears while the keyboard is still visible, we need to
        // manually notify the view controller to update its bottom inset. Otherwise, for certain
        // custom transitions, updating the bottom inset in response to -keyboardWillShow: may be too
        // late to ensure correct layout, since the initial layout pass to set up the custom transition
        // will already have taken place.
        if self.window == nil {
            self.ignoreKeyboardNotifications = true
            if self.bottomInset != self.containerView.bounds.size.height {
                self.bottomInset = self.containerView.bounds.size.height
                self.delegate?.chatInputView(self, didChangeBottomInsetWith: 0, animationCurve: .easeInOut)
            }
        }
    }
}

// MARK: Mentions
extension ChatInputView {
    
    private func fetchMentionPickerContent(for input: MentionInput) -> [MentionableUser] {
        guard let mentionCandidateRange = input.rangeOfMentionCandidateAtCurrentPosition() else {
            return []
        }
        let mentionCandidate = input.text[mentionCandidateRange]
        let trimmedInput = String(mentionCandidate.dropFirst())
        return mentionsDelegate?.chatInputView(self, possibleMentionsForInput: trimmedInput) ?? []
    }
    
    private func updateMentionPickerContent() {
        let mentionableUsers = fetchMentionPickerContent(for: textView.mentionInput)

        mentionPicker.items = mentionableUsers
        mentionPicker.isHidden = mentionableUsers.isEmpty
        
        mentionPickerTopConstraint?.isActive = !mentionableUsers.isEmpty
        vStackTopConstraint?.isActive = mentionableUsers.isEmpty
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
}

// MARK: InputTextViewDelegate
extension ChatInputView: InputTextViewDelegate {

    // unused
    func maximumHeight(for inputTextView: InputTextView) -> CGFloat {
        return 120
    }
    
    func inputTextView(_ inputTextView: InputTextView, needsHeightChangedTo newHeight: CGFloat) {
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
        inputTextView.text = inputTextView.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        placeholder.isHidden = !inputTextView.text.isEmpty
    }
    
    func inputTextViewDidChange(_ inputTextView: InputTextView) {

        placeholder.isHidden = !inputTextView.text.isEmpty
        textIsUneditedReplyMention = false
        updateMentionPickerContent()
        
        if textView.contentSize.height >= 115 {
            textViewContainerHeightConstraint?.constant = 115
            textViewContainerHeightConstraint?.isActive = true
            textView.isScrollEnabled = true
        } else {
            if textView.isScrollEnabled {
                textViewContainerHeightConstraint?.constant = textView.contentSize.height
                textView.isScrollEnabled = false
            } else {
                textViewContainerHeightConstraint?.isActive = false
            }
        }
        
        if typingThrottleTimer == nil && !text.isEmpty {
            delegate?.chatInputView(self, isTyping: true)
            typingThrottleTimer = Timer.scheduledTimer(withTimeInterval: typingThrottleInterval, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.typingThrottleTimer = nil
            }
        }

        typingDebounceTimer?.invalidate()
        typingDebounceTimer = Timer.scheduledTimer(withTimeInterval: typingDebounceInterval, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.delegate?.chatInputView(self, isTyping: false)
            
            self.typingThrottleTimer?.invalidate()
            self.typingThrottleTimer = nil
        }

        updatePostButtons()
    }
    
    func inputTextViewDidChangeSelection(_ inputTextView: InputTextView) {
    }
    
    func inputTextView(_ inputTextView: InputTextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        return true
    }
    
}

// MARK: AudioRecorderControlViewDelegate
extension ChatInputView: AudioRecorderControlViewDelegate {
    func audioRecorderControlViewLocked(_ view: AudioRecorderControlView) {
        isVoiceNoteRecordingLocked = true
        cancelRecordingButton.isHidden = false
        postVoiceNoteButton.isHidden = false
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
            delegate?.chatInputView(self, mentionText: mentionText, media: [media])
        }
    }
}

// MARK: AudioRecorderDelegate
extension ChatInputView: AudioRecorderDelegate {
    func audioRecorderMicrphoneAccessDenied(_ recorder: AudioRecorder) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.chatInputViewMicrophoneAccessDenied(self)
        }
    }

    func audioRecorderStarted(_ recorder: AudioRecorder) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.voiceNoteTime.text = "0:00"
            self.voiceNoteTime.isHidden = false
            self.placeholder.isHidden = true
            self.textView.text = ""
            self.updatePostButtons()
        }
    }

    func audioRecorderStopped(_ recorder: AudioRecorder) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isVoiceNoteRecordingLocked = false
            self.cancelRecordingButton.isHidden = true
            self.voiceNoteTime.isHidden = true
            self.postVoiceNoteButton.isHidden = true
            self.placeholder.isHidden = false
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

extension Localizations {
    static var chatInputPlaceholder: String {
        NSLocalizedString("chat.message.placeholder", value: "Write a message", comment: "Text shown when chat input box is empty")
    }
}
