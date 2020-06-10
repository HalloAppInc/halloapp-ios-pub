//
//  HalloApp
//
//  Created by Tony Jiang on 4/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import CocoaLumberjack
import UIKit
import AVKit

fileprivate protocol ContainerViewDelegate: AnyObject {
    func containerView(_ containerView: ChatInputView.ContainerView, preferredHeightFor layoutWidth: CGFloat) -> CGFloat
    func currentLayoutWidth(for containerView: ChatInputView.ContainerView) -> CGFloat
}

protocol ChatInputViewDelegate: AnyObject {
    func chatInputView(_ inputView: ChatInputView, didChangeBottomInsetWith animationDuration: TimeInterval, animationCurve: UIView.AnimationCurve)
    func chatInputView(_ inputView: ChatInputView, wantsToSend text: String)
    func chatInputView(_ inputView: ChatInputView)
    func chatInputViewCloseQuotePanel(_ inputView: ChatInputView)
}

class ChatInputView: UIView, UITextViewDelegate, ContainerViewDelegate {
    weak var delegate: ChatInputViewDelegate?

    private var previousHeight: CGFloat = 0
    
    private var placeholderText = "Type a message"

    // MARK: ChatInput Lifecycle

    override init(frame: CGRect) {
        super.init(frame: frame)
        previousHeight = frame.size.height
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    func willAppear(in viewController: UIViewController) {
        self.setInputViewWidth(viewController.view.bounds.size.width)
//        viewController.becomeFirstResponder()
    }

    func didAppear(in viewController: UIViewController) {
//        viewController.becomeFirstResponder()
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
        view.translatesAutoresizingMaskIntoConstraints = false
        view.preservesSuperviewLayoutMargins = true
        view.spacing = 8

        return view
    }()

    private lazy var quoteFeedPanelNameLabel: UILabel = {
        let label = UILabel()
        label.textColor = UIColor.label
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        return label
    }()
    
    private lazy var quoteFeedPanelTextLabel: UILabel = {
        let label = UILabel()
        label.textColor = UIColor.secondaryLabel
        label.numberOfLines = 2
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        return label
    }()
    
    private lazy var quoteFeedPanelTextContent: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [ self.quoteFeedPanelNameLabel, self.quoteFeedPanelTextLabel ])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.layoutMargins = UIEdgeInsets(top: 0, left: 5, bottom: 10, right: 0)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.axis = .vertical
        stackView.spacing = 3
        return stackView
    }()
    
    private lazy var quoteFeedPanelImage: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        
        imageView.layer.cornerRadius = 10
        imageView.layer.masksToBounds = true
        imageView.isHidden = true
        
        return imageView
    }()
    
    private lazy var quoteFeedPanelTextMediaContent: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ self.quoteFeedPanelTextContent, self.quoteFeedPanelImage ])
        view.translatesAutoresizingMaskIntoConstraints = false

        view.axis = .horizontal
        view.spacing = 3
        view.alignment = .top
        
        view.layoutMargins = UIEdgeInsets(top: 10, left: 5, bottom: 10, right: 10)
        view.isLayoutMarginsRelativeArrangement = true
        
        let subView = UIView(frame: view.bounds)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        subView.layer.cornerRadius = 15
        subView.layer.borderWidth = 1
        subView.layer.borderColor = UIColor.link.cgColor
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        
        view.insertSubview(subView, at: 0)
        
        return view
    }()
    
    private lazy var quoteFeedPanelCloseButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.contentEdgeInsets = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        button.tintColor = UIColor.systemGray
        button.addTarget(self, action: #selector(self.closeQuoteFeedPanel), for: .touchUpInside)
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }()
    
    private lazy var quoteFeedPanel: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [ self.quoteFeedPanelTextMediaContent, self.quoteFeedPanelCloseButton ])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .top
        stackView.spacing = 8

        stackView.isHidden = true
        return stackView
    }()

    private var textViewContainerHeightConstraint: NSLayoutConstraint?
    
    private lazy var textView: UITextView = {
        let view = UITextView()
        view.isScrollEnabled = false
        view.delegate = self
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.clear
        view.textContainerInset.left = 8
        view.textContainerInset.right = 8
        view.font = UIFont.preferredFont(forTextStyle: .subheadline)

        return view
    }()
    
    private lazy var textViewContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.systemBackground
        view.addSubview(self.textView)
        return view
    }()
    
    private lazy var postMediaButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "photo.fill"), for: .normal)
        button.addTarget(self, action: #selector(self.postMediaButtonClicked), for: .touchUpInside)
        button.isEnabled = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 20)
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        button.tintColor = UIColor.systemGray
        return button
    }()
    
    private lazy var postButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "paperplane.fill"), for: .normal)
        button.addTarget(self, action: #selector(self.postButtonClicked), for: .touchUpInside)
        button.isEnabled = false
        button.translatesAutoresizingMaskIntoConstraints = false
        // gotcha: keep insets at 6 or higher to have a bigger hit area,
        // rotating image by 45 degree is problematic so perhaps getting a pre-rotated custom icon is better
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        button.tintColor = UIColor.link
        button.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi / 4))
        
        
        button.layer.zPosition = -10
        
        button.backgroundColor = UIColor.systemBackground
//        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
//        button.setContentHuggingPriority(.defaultHigh, for: .vertical)
//        button.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
//        button.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        
//        let buttonSize: CGFloat = 30.0
//
//        NSLayoutConstraint(item: button, attribute: .width, relatedBy: .equal, toItem: button, attribute: .width, multiplier: 1, constant: buttonSize).isActive = true
//        NSLayoutConstraint(item: button, attribute: .height, relatedBy: .equal, toItem: button, attribute: .width, multiplier: 1, constant: 0).isActive = true

        
        return button
    }()
    
    private lazy var postButtonsContainer: UIStackView = {
        let view = UIStackView(arrangedSubviews: [self.postMediaButton, self.postButton ])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .horizontal
        return view
    }()
    
    private lazy var textInputRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [self.textViewContainer, self.postButtonsContainer ])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .horizontal
        
        view.spacing = 0
        return view
    }()
    
    private lazy var vStack: UIStackView = {
        let view = UIStackView(arrangedSubviews: [self.quoteFeedPanel, self.textInputRow ])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .vertical
        view.alignment = .trailing
        return view
    }()
    
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

        self.quoteFeedPanel.leadingAnchor.constraint(equalTo: self.vStack.leadingAnchor).isActive = true
        
        self.textView.leadingAnchor.constraint(equalTo: self.textViewContainer.leadingAnchor).isActive = true
        self.textView.topAnchor.constraint(equalTo: self.textViewContainer.topAnchor).isActive = true
        self.textView.trailingAnchor.constraint(equalTo: self.textViewContainer.trailingAnchor).isActive = true
        self.textView.bottomAnchor.constraint(equalTo: self.textViewContainer.bottomAnchor).isActive = true
        
        self.textViewContainer.leadingAnchor.constraint(equalTo: self.textInputRow.leadingAnchor).isActive = true
        self.textViewContainer.topAnchor.constraint(equalTo: self.textInputRow.topAnchor).isActive = true
        self.textViewContainer.trailingAnchor.constraint(equalTo: self.textInputRow.trailingAnchor, constant: -40).isActive = true
        self.textViewContainer.bottomAnchor.constraint(equalTo: self.textInputRow.bottomAnchor).isActive = true
        
        self.textViewContainerHeightConstraint = self.textViewContainer.heightAnchor.constraint(equalToConstant: 115)
        
        self.textInputRow.leadingAnchor.constraint(equalTo: self.vStack.leadingAnchor).isActive = true
        
        self.textInputRow.trailingAnchor.constraint(equalTo: self.vStack.trailingAnchor).isActive = true
      

//        self.postButtonsContainer.leadingAnchor.constraint(equalTo: textInputRow.leadingAnchor).isActive = false
//        self.postButtonsContainer.topAnchor.constraint(equalTo: textInputRow.topAnchor).isActive = true
        self.postButtonsContainer.trailingAnchor.constraint(equalTo: textInputRow.trailingAnchor).isActive = true
//        self.postButtonsContainer.bottomAnchor.constraint(equalTo: textInputRow.bottomAnchor).isActive = true
        

//        let textViewHeight = round(2 * self.textView.font!.lineHeight)
//        self.textView.addConstraint(NSLayoutConstraint(item: self.textView, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: textViewHeight))
        
        self.contentView.addArrangedSubview(self.vStack)
        
        self.vStack.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor).isActive = true
        self.vStack.topAnchor.constraint(equalTo: self.contentView.topAnchor).isActive = true
        self.vStack.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor).isActive = true
        self.vStack.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor).isActive = true
        
        self.postMediaButton.isHidden = true
        
        setPlaceholderText()
    }
    
    private func resignFirstResponderOnDisappear(in viewController: UIViewController) {
        self.hideKeyboard()
        viewController.resignFirstResponder()
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

    // MARK: Quote Panel

    func videoPreviewImage(url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        if let cgImage = try? generator.copyCGImage(at: CMTime(seconds: 2, preferredTimescale: 60), actualTime: nil) {
            return UIImage(cgImage: cgImage)
        }
        else {
            return nil
        }
    }
    
    func showQuoteFeedPanel(with userId: String, text: String, mediaType: FeedMediaType?, mediaUrl: String?) {
        self.quoteFeedPanelNameLabel.text = MainAppContext.shared.contactStore.fullName(for: userId)
        self.quoteFeedPanelTextLabel.text = text
        if self.vStack.arrangedSubviews.contains(self.quoteFeedPanel) {
            self.quoteFeedPanel.isHidden = false
        } else {
            self.vStack.insertArrangedSubview(self.quoteFeedPanel, at: 0)
        }
        
        if mediaType != nil && mediaUrl != nil {
            let fileURL = MainAppContext.mediaDirectoryURL.appendingPathComponent(mediaUrl ?? "", isDirectory: false)
            
            if mediaType == .image {
                if let image = UIImage(contentsOfFile: fileURL.path) {
                    self.quoteFeedPanelImage.image = image
                }
            } else if mediaType == .video {
                if let image = self.videoPreviewImage(url: fileURL) {
                    self.quoteFeedPanelImage.image = image
                }
            }
            
            let imageSize: CGFloat = 80.0
            
            NSLayoutConstraint(item: self.quoteFeedPanelImage, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: imageSize).isActive = true
            NSLayoutConstraint(item: self.quoteFeedPanelImage, attribute: .height, relatedBy: .equal, toItem: self.quoteFeedPanelImage, attribute: .width, multiplier: 1, constant: 0).isActive = true
            self.quoteFeedPanelImage.isHidden = false
            
        } else {
            self.quoteFeedPanelImage.isHidden = true
        }
    

        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.9) {
            self.textView.becomeFirstResponder()
        }
      
//        self.setNeedsUpdateHeight()
    }

    @objc private func closeQuoteFeedPanel() {
        self.quoteFeedPanel.isHidden = true
        self.delegate?.chatInputViewCloseQuotePanel(self)
//        self.setNeedsUpdateHeight()
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
        self.postMediaButton.isHidden = !self.text.isEmpty

        
        if self.textView.contentSize.height >= 115 {
            self.textViewContainerHeightConstraint?.constant = 115
            self.textViewContainerHeightConstraint?.isActive = true
            self.textView.isScrollEnabled = true
        } else {

            if self.textView.isScrollEnabled {
                self.textViewContainerHeightConstraint?.constant = self.textView.contentSize.height
                self.textView.isScrollEnabled = false
            } else {
                self.textViewContainerHeightConstraint?.isActive = false
            }
        }

        
    }

    @objc func postButtonClicked() {
        self.delegate?.chatInputView(self, wantsToSend: self.text)
        self.closeQuoteFeedPanel()
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
}
