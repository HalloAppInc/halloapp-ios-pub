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

class CommentInputView: UIView, UITextViewDelegate, ContainerViewDelegate {
    weak var delegate: CommentInputViewDelegate?

    private var previousHeight: CGFloat = 0

    class ContainerView: UIView {
        fileprivate weak var delegate: ContainerViewDelegate?

        override init(frame: CGRect) {
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
        }

        func setupView() {
            self.translatesAutoresizingMaskIntoConstraints = false
            self.setContentHuggingPriority(.required, for: .vertical)
            self.setContentCompressionResistancePriority(.required, for: .vertical)
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

    private lazy var contentView: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        view.spacing = 8
        view.preservesSuperviewLayoutMargins = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var textView: UITextView = {
        let textView = UITextView()
        textView.font = UIFont.preferredFont(forTextStyle: .subheadline)
        textView.backgroundColor = UIColor.clear
        textView.delegate = self
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

        self.addSubview(self.containerView)
        self.containerView.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
        self.containerView.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        self.containerView.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
        self.containerView.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true

        let blurView = UIVisualEffectView(effect: UIBlurEffect.init(style: .systemChromeMaterial))
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.preservesSuperviewLayoutMargins = true
        blurView.contentView.preservesSuperviewLayoutMargins = true

        self.containerView.addSubview(blurView)
        blurView.leadingAnchor.constraint(equalTo: self.containerView.leadingAnchor).isActive = true
        blurView.topAnchor.constraint(equalTo: self.containerView.topAnchor).isActive = true
        blurView.trailingAnchor.constraint(equalTo: self.containerView.trailingAnchor).isActive = true
        blurView.bottomAnchor.constraint(equalTo: self.containerView.bottomAnchor).isActive = true

        let borderWidth = 1 / UIScreen.main.scale

        let topBorder = UIView()
        topBorder.backgroundColor = UIColor.separator
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        blurView.contentView.addSubview(topBorder)
        NSLayoutConstraint(item: topBorder, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1.0, constant: borderWidth).isActive = true
        topBorder.leadingAnchor.constraint(equalTo: blurView.leadingAnchor).isActive = true
        topBorder.topAnchor.constraint(equalTo: blurView.topAnchor).isActive = true
        topBorder.trailingAnchor.constraint(equalTo: blurView.trailingAnchor).isActive = true

        blurView.contentView.addSubview(self.contentView)
        self.contentView.leadingAnchor.constraint(equalTo: blurView.layoutMarginsGuide.leadingAnchor).isActive = true
        self.contentView.topAnchor.constraint(equalTo: blurView.layoutMarginsGuide.topAnchor).isActive = true
        self.contentView.trailingAnchor.constraint(equalTo: blurView.layoutMarginsGuide.trailingAnchor).isActive = true
        self.contentView.bottomAnchor.constraint(equalTo: blurView.layoutMarginsGuide.bottomAnchor).isActive = true

        let textViewContainer = UIView()
        textViewContainer.backgroundColor = UIColor.systemBackground
        textViewContainer.layer.cornerRadius = 12
        textViewContainer.layer.borderColor = UIColor.separator.cgColor
        textViewContainer.layer.borderWidth = borderWidth
        textViewContainer.translatesAutoresizingMaskIntoConstraints = false
        textViewContainer.addSubview(self.textView)
        self.textView.leadingAnchor.constraint(equalTo: textViewContainer.leadingAnchor).isActive = true
        self.textView.topAnchor.constraint(equalTo: textViewContainer.topAnchor).isActive = true
        self.textView.trailingAnchor.constraint(equalTo: textViewContainer.trailingAnchor).isActive = true
        self.textView.bottomAnchor.constraint(equalTo: textViewContainer.bottomAnchor).isActive = true
        let textViewHeight = round(2 * self.textView.font!.lineHeight)
        self.textView.addConstraint(NSLayoutConstraint(item: self.textView, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: textViewHeight))

        let hStack = UIStackView(arrangedSubviews: [textViewContainer, self.postButton ])
        hStack.axis = .horizontal
        hStack.spacing = 0

        self.contentView.addArrangedSubview(hStack)
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
        if self.contentView.arrangedSubviews.contains(self.replyContextPanel) {
            self.replyContextPanel.isHidden = false
        } else {
            self.contentView.insertArrangedSubview(self.replyContextPanel, at: 0)
        }
    }

    func removeReplyPanel() {
        self.replyContextPanel.isHidden = true
    }

    @objc private func closeReplyPanel() {
        self.delegate?.commentInputViewResetReplyContext(self)
    }

    // MARK: Text view
    var text: String {
        get {
            return self.textView.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        }
        set {
            self.textView.text = newValue
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        self.postButton.isEnabled = !self.text.isEmpty
    }

    @objc func postButtonClicked() {
        self.delegate?.commentInputView(self, wantsToSend: self.text)
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
            if self.bottomInset != self.containerView.bounds.size.height {
                self.bottomInset = self.containerView.bounds.size.height
                self.delegate?.commentInputView(self, didChangeBottomInsetWith: 0, animationCurve: .easeInOut)
            }
        }
    }

    // MARK: Layout

    func setInputViewWidth(_ width: CGFloat) {
        guard self.bounds.size.width != width else { return }
        self.bounds = CGRect(origin: .zero, size: CGSize(width: width, height: self.containerView.preferredHeight(for: width)))
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
        let duration = self.animationDurationForHeightUpdate;
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
}
