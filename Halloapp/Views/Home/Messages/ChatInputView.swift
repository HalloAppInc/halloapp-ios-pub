//
//  HalloApp
//
//  Created by Tony Jiang on 4/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import UIKit

fileprivate protocol ContainerViewDelegate: AnyObject {
    func containerView(_ containerView: ChatInputView.ContainerView, preferredHeightFor layoutWidth: CGFloat) -> CGFloat
    func currentLayoutWidth(for containerView: ChatInputView.ContainerView) -> CGFloat
}

protocol ChatInputViewDelegate: AnyObject {
    func chatInputView(_ inputView: ChatInputView, didChangeBottomInsetWith animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve)
    func chatInputView(_ inputView: ChatInputView, wantsToSend text: String)
    func chatInputView(_ inputView: ChatInputView)
}

class ChatInputView: UIView, UITextViewDelegate, ContainerViewDelegate {
    weak var delegate: ChatInputViewDelegate?

    private var previousHeight: CGFloat = 0
    
    private var placeholderText = "Type something"

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
    
    private lazy var postMediaButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isEnabled = true
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 20)
        button.addTarget(self, action: #selector(self.postMediaButtonClicked), for: .touchUpInside)
        button.setImage(UIImage(systemName: "photo.fill"), for: .normal)
        button.tintColor = UIColor.systemGray
        return button
    }()
    
    private lazy var postButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isEnabled = false
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        button.addTarget(self, action: #selector(self.postButtonClicked), for: .touchUpInside)
        button.setImage(UIImage(systemName: "paperplane.fill"), for: .normal)
        button.tintColor = UIColor.link
        button.transform = CGAffineTransform(rotationAngle: CGFloat.pi / 4.0)
        return button
    }()

    private lazy var contactNameLabel: UILabel = {
        let label = UILabel()
        label.textColor = UIColor.secondaryLabel
        label.numberOfLines = 2
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        return label
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
        self.containerView.backgroundColor = UIColor.systemBackground
        self.containerView.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
        self.containerView.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
        self.containerView.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
        self.containerView.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
                
        self.containerView.addSubview(self.contentView)
        
        self.contentView.leadingAnchor.constraint(equalTo: self.containerView.layoutMarginsGuide.leadingAnchor).isActive = true
        self.contentView.topAnchor.constraint(equalTo: self.containerView.layoutMarginsGuide.topAnchor).isActive = true
        self.contentView.trailingAnchor.constraint(equalTo: self.containerView.layoutMarginsGuide.trailingAnchor).isActive = true
        self.contentView.bottomAnchor.constraint(equalTo: self.containerView.layoutMarginsGuide.bottomAnchor).isActive = true

        let textViewContainer = UIView()
        textViewContainer.backgroundColor = UIColor.systemBackground

        textViewContainer.translatesAutoresizingMaskIntoConstraints = false
        textViewContainer.addSubview(self.textView)
        self.textView.leadingAnchor.constraint(equalTo: textViewContainer.leadingAnchor).isActive = true
        self.textView.topAnchor.constraint(equalTo: textViewContainer.topAnchor).isActive = true
        self.textView.trailingAnchor.constraint(equalTo: textViewContainer.trailingAnchor).isActive = true
        self.textView.bottomAnchor.constraint(equalTo: textViewContainer.bottomAnchor).isActive = true
        let textViewHeight = round(2 * self.textView.font!.lineHeight)
        self.textView.addConstraint(NSLayoutConstraint(item: self.textView, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: textViewHeight))
        
        let hStack = UIStackView(arrangedSubviews: [textViewContainer, self.postMediaButton, self.postButton ])
        hStack.axis = .horizontal
        hStack.spacing = 0

        self.contentView.addArrangedSubview(hStack)
        
        
        self.postMediaButton.isHidden = true 
        
        setPlaceholderText()
        
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

    // MARK: Text view
    
    var text: String {
        get {
            return self.textView.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        }
        set {
            self.textView.text = newValue
            self.textViewDidChange(self.textView)
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        self.postButton.isEnabled = !self.text.isEmpty
//        self.postMediaButton.isHidden = !self.text.isEmpty
    }

    @objc func postButtonClicked() {
        self.delegate?.chatInputView(self, wantsToSend: self.text)
    }

    @objc func postMediaButtonClicked() {
        print("postMediaButton Clicked")
        self.delegate?.chatInputView(self)
    }
    
    private func setPlaceholderText() {
        if self.textView.text.isEmpty {
            self.textView.text = placeholderText
            self.textView.textColor = UIColor.systemGray3
            self.textView.tag = 0
        }
    }
    
    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        if (textView.tag == 0){
            textView.text = ""
            textView.textColor = UIColor.label
            textView.tag = 1
        }
        return true
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        setPlaceholderText()
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
        self.delegate?.chatInputView(self, didChangeBottomInsetWith: duration, animationCurve: curve)
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
        self.delegate?.chatInputView(self, didChangeBottomInsetWith: duration, animationCurve: curve)
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
                self.delegate?.chatInputView(self, didChangeBottomInsetWith: 0, animationCurve: .easeInOut)
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
