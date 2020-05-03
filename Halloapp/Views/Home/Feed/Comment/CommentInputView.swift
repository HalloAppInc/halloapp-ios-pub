//
//  CommentInputView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/24/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import UIKit

fileprivate protocol ContainerViewDelegate: AnyObject {
    func containerView(_ containerView: CommentInputView.ContainerView, preferredHeightFor layoutWidth: CGFloat) -> CGFloat
    func currentLayoutWidth(for containerView: CommentInputView.ContainerView) -> CGFloat
}

protocol CommentInputViewDelegate: AnyObject {
    func commentInputView(_ inputView: CommentInputView, didChangeBottomInsetWith animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve)
    func commentInputView(_ inputView: CommentInputView, wantsToSend text: String)
    func commentInputViewResetReplyContext(_ inputView: CommentInputView)
}

class CommentInputView: UIView, InputTextViewDelegate, ContainerViewDelegate {

    weak var delegate: CommentInputViewDelegate?

    private var textViewHeight: NSLayoutConstraint?
    private var textView1LineHeight: CGFloat = 0
    private var textView5LineHeight: CGFloat = 0

    private var previousHeight: CGFloat = 0

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
        view.setContentHuggingPriority(.required, for: .vertical)
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
        vStack.spacing = 8
        vStack.axis = .vertical
        vStack.translatesAutoresizingMaskIntoConstraints = false
        return vStack
    }()

    private lazy var textView: InputTextView = {
        let textView = InputTextView(frame: .zero)
        textView.font = UIFont.preferredFont(forTextStyle: .subheadline)
        textView.backgroundColor = .clear
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .yes
        textView.enablesReturnKeyAutomatically = true
        textView.scrollsToTop = false
        textView.textContainerInset.left = 8
        textView.textContainerInset.right = 8
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()

    private lazy var postButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Post", for: .normal)
        button.isEnabled = false
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 0)
        button.addTarget(self, action: #selector(self.postButtonClicked), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var contactNameLabel: UILabel = {
        let label = UILabel()
        label.textColor = UIColor.secondaryLabel
        label.numberOfLines = 2
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        return label
    }()

    private lazy var deleteReplyContextButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.contentEdgeInsets = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        button.tintColor = UIColor.systemGray
        button.addTarget(self, action: #selector(self.closeReplyPanel), for: .touchUpInside)
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }()

    private lazy var replyContextPanel: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [ self.contactNameLabel, self.deleteReplyContextButton ])
        stackView.axis = .horizontal
        stackView.spacing = 8
        return stackView
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

        // Background view.
        let backgroundView = UIView()
        backgroundView.backgroundColor = .systemBackground
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        self.containerView.addSubview(backgroundView)
        backgroundView.leadingAnchor.constraint(equalTo: self.containerView.leadingAnchor).isActive = true
        backgroundView.topAnchor.constraint(equalTo: self.containerView.topAnchor).isActive = true
        backgroundView.trailingAnchor.constraint(equalTo: self.containerView.trailingAnchor).isActive = true
        backgroundView.bottomAnchor.constraint(equalTo: self.containerView.bottomAnchor).isActive = true

        // Content view - everything must go in there.
        self.containerView.addSubview(self.contentView)
        self.contentView.leadingAnchor.constraint(equalTo: self.containerView.leadingAnchor).isActive = true
        self.contentView.topAnchor.constraint(equalTo: self.containerView.topAnchor).isActive = true
        self.contentView.trailingAnchor.constraint(equalTo: self.containerView.trailingAnchor).isActive = true
        self.contentView.bottomAnchor.constraint(equalTo: self.containerView.safeAreaLayoutGuide.bottomAnchor).isActive = true

        let borderWidth = 1 / UIScreen.main.scale

        // Top border.
        let topBorder = UIView()
        topBorder.backgroundColor = .separator
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        self.contentView.addSubview(topBorder)
        topBorder.heightAnchor.constraint(equalToConstant: borderWidth).isActive = true
        topBorder.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor).isActive = true
        topBorder.topAnchor.constraint(equalTo: self.contentView.topAnchor).isActive = true
        topBorder.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor).isActive = true

        // Input field wrapper
        let textViewContainer = UIView()
        textViewContainer.backgroundColor = .clear
        textViewContainer.translatesAutoresizingMaskIntoConstraints = false

        // Rounded rect box.
        let textViewBox = UIView()
        textViewBox.backgroundColor = .secondarySystemBackground
        textViewBox.layer.cornerRadius = 12
        textViewBox.layer.borderColor = UIColor.separator.cgColor
        textViewBox.layer.borderWidth = borderWidth
        textViewBox.translatesAutoresizingMaskIntoConstraints = false
        textViewContainer.addSubview(textViewBox)
        textViewBox.leadingAnchor.constraint(equalTo: textViewContainer.leadingAnchor).isActive = true
        textViewBox.topAnchor.constraint(equalTo: textViewContainer.topAnchor).isActive = true
        textViewBox.trailingAnchor.constraint(equalTo: textViewContainer.trailingAnchor).isActive = true
        textViewBox.bottomAnchor.constraint(equalTo: textViewContainer.bottomAnchor).isActive = true

        textViewContainer.addSubview(self.textView)
        self.textView.leadingAnchor.constraint(equalTo: textViewContainer.leadingAnchor).isActive = true
        self.textView.topAnchor.constraint(equalTo: textViewContainer.topAnchor).isActive = true
        self.textView.trailingAnchor.constraint(equalTo: textViewContainer.trailingAnchor).isActive = true
        self.textView.bottomAnchor.constraint(equalTo: textViewContainer.bottomAnchor).isActive = true
        self.textView.inputTextViewDelegate = self
        self.textView.text = ""

        // Horizontal stack view: [input field][post button]
        let hStack = UIStackView(arrangedSubviews: [textViewContainer, self.postButton ])
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.axis = .horizontal
        hStack.spacing = 0

        // Vertical stack view:
        // [Replying to]?
        // [Input Field]
        self.contentView.addSubview(self.vStack)
        self.vStack.addArrangedSubview(hStack)
        self.vStack.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        self.vStack.topAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.topAnchor).isActive = true
        self.vStack.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor).isActive = true
        self.vStack.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor).isActive = true

        self.recalculateSingleLineHeight()

        self.textViewHeight = self.textView.heightAnchor.constraint(equalToConstant: self.textView1LineHeight)
        self.textViewHeight?.priority = .defaultHigh
        self.textViewHeight?.isActive = true
    }

    func willAppear(in viewController: UIViewController) {
        self.setInputViewWidth(viewController.view.bounds.size.width)
        viewController.becomeFirstResponder()
    }

    func didAppear(in viewController: UIViewController) {
        viewController.becomeFirstResponder()
    }

    func willDisappear(in viewController: UIViewController) {
        guard self.isKeyboardVisible || !viewController.isFirstResponder else { return }

        var deferResigns = false
        if viewController.isMovingFromParent {
            // Popping
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

    func showReplyPanel(with contactName: String) {
        self.contactNameLabel.text = "Replying to \(contactName)"
        if self.vStack.arrangedSubviews.contains(self.replyContextPanel) {
            self.replyContextPanel.isHidden = false
        } else {
            self.vStack.insertArrangedSubview(self.replyContextPanel, at: 0)
        }
        self.setNeedsUpdateHeight()
    }

    func removeReplyPanel() {
        self.replyContextPanel.isHidden = true
        self.setNeedsUpdateHeight()
    }

    @objc private func closeReplyPanel() {
        self.delegate?.commentInputViewResetReplyContext(self)
    }

    // MARK: Text view
    var text: String! {
        get {
            return self.textView.text
        }
        set {
            self.textView.text = newValue
            self.inputTextViewDidChange(self.textView)
        }
    }

    @objc func postButtonClicked() {
        self.acceptAutoCorrection()
        let trimmedText = (self.textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.delegate?.commentInputView(self, wantsToSend: trimmedText)
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

    // MARK: InputTextViewDelegate

    func inputTextViewDidChange(_ inputTextView: InputTextView) {
        let trimmedText = (inputTextView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.postButton.isEnabled = !trimmedText.isEmpty
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
        return true
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
