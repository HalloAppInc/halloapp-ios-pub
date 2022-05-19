//
//  SecretPostViewController.swift
//  HalloApp
//
//  Created by Tanveer on 5/1/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import Core
import CoreCommon

protocol MomentViewControllerDelegate: PostDashboardViewControllerDelegate {
    func initialTransitionView(for post: FeedPost) -> MomentView?
}

class MomentViewController: UIViewController {

    let post: FeedPost
    let unlockingPost: FeedPost?
    let isFullScreen: Bool
    weak var delegate: MomentViewControllerDelegate?

    private var backgroundColor: UIColor {
        UIColor { traits in
            switch traits.userInterfaceStyle {
            case .dark:
                return .black.withAlphaComponent(0.8)
            default:
                return .feedBackground
            }
        }
    }

    private(set) lazy var momentView: MomentView = {
        let view = MomentView()
        view.configure(with: post)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var unlockingMomentStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [unlockingMomentView, unlockingPostProgressLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 5
        stack.setContentHuggingPriority(.required, for: .vertical)
        stack.setContentCompressionResistancePriority(.required, for: .vertical)
        return stack
    }()
    
    private lazy var unlockingMomentView: MomentView = {
        let view = MomentView(style: .minimal)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        return view
    }()
    
    private lazy var unlockingPostProgressLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.text = Localizations.momentUploadingProgress
        return label
    }()
    
    private lazy var headerView: FeedItemHeaderView = {
        let view = FeedItemHeaderView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.configure(with: post, contentWidth: view.bounds.width, showGroupName: false)
        view.showMoreAction = { [weak self] in self?.showMoreMenu() }
        view.showUserAction = { [weak self] in self?.showUser() }
        return view
    }()
    
    private lazy var facePileView: FacePileView = {
        let view = FacePileView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.configure(with: post)
        view.isHidden = post.userID != MainAppContext.shared.userData.userId
        view.avatarViews.forEach { $0.borderColor = backgroundColor }
        view.addTarget(self, action: #selector(seenByPushed), for: .touchUpInside)
        return view
    }()
    
    private var cancellables: Set<AnyCancellable> = []

    private lazy var contentInputView: ContentInputView = {
        let view = ContentInputView(style: .minimal, options: [])
        view.autoresizingMask = [.flexibleHeight]
        view.blurView.isHidden = true
        view.delegate = self
        let name = MainAppContext.shared.contactStore.firstName(for: post.userID)
        view.placeholderText = String(format: Localizations.privateReplyPlaceholder, name)

        return view
    }()

    private lazy var dismissAnimator = DismissAnimator(referenceView: view)

    override var canBecomeFirstResponder: Bool {
        true
    }

    private var showAccessoryView = false
    override var inputAccessoryView: UIView? {
        showAccessoryView ? contentInputView : nil
    }

    private var toast: Toast?
    private var replyCancellable: AnyCancellable?

    init(post: FeedPost, unlockingPost: FeedPost? = nil, isFullScreen: Bool = true) {
        self.post = post
        self.unlockingPost = unlockingPost
        self.isFullScreen = isFullScreen
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .custom
        transitioningDelegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("SecretPostViewController coder init not implemented...")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .feedBackground

        // With the modal presentation, the system adjusts a black background, causing it to
        // mismatch with the input accessory view
        let backgroundView = UIView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.backgroundColor = backgroundColor
        view.addSubview(backgroundView)
        view.backgroundColor = nil

        view.addSubview(headerView)
        view.addSubview(momentView)
        view.addSubview(facePileView)
        
        let centerYConstraint = momentView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        // post will be off-center if there's an uploading post in the top corner
        centerYConstraint.priority = .defaultLow

        let spacing: CGFloat = 10
        NSLayoutConstraint.activate([
            centerYConstraint,
            momentView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 15),
            momentView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -15),
            headerView.leadingAnchor.constraint(equalTo: momentView.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: momentView.trailingAnchor),
            headerView.bottomAnchor.constraint(equalTo: momentView.topAnchor, constant: -spacing),
            facePileView.leadingAnchor.constraint(greaterThanOrEqualTo: momentView.leadingAnchor),
            facePileView.trailingAnchor.constraint(equalTo: momentView.trailingAnchor),
            facePileView.topAnchor.constraint(equalTo: momentView.bottomAnchor, constant: spacing),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        installUnlockingPost()

        if isFullScreen {
            // arrived from the feed
            installDismissTap()
            backgroundView.backgroundColor = backgroundColor.withAlphaComponent(0.97)
        } else {
            // arrived from the camera
            installDismissButton()
        }

        contentInputView.backgroundColor = backgroundView.backgroundColor

        post.feedMedia.first?.$isMediaAvailable.sink { [weak self] isAvailable in
            DispatchQueue.main.async {
                self?.refreshAccessoryView(show: true)
            }
        }.store(in: &cancellables)
    }

    var attachment: UIAttachmentBehavior!

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        toast?.show()
        refreshAccessoryView(show: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        post.feedMedia.first?.$isMediaAvailable.sink { [weak self] _ in
            self?.expireMomentIfReady()
        }.store(in: &cancellables)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(dismissPan))
        pan.delegate = self
        momentView.addGestureRecognizer(pan)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        toast?.hide()
        refreshAccessoryView(show: false)
    }

    private func refreshAccessoryView(show: Bool) {
        guard
            post.userID != MainAppContext.shared.userData.userId,
            showAccessoryView != show,
            post.feedMedia.first?.isMediaAvailable ?? false,
            case .unlocked = momentView.state
        else {
            // we want to show the accessory view when:
            // 1. post isn't locked (not blurred)
            // 2. media is available
            // 3. someone else's post
            return
        }

        showAccessoryView = show
        reloadInputViews()
    }
    
    private func installUnlockingPost() {
        guard let unlockingPost = unlockingPost else {
            momentView.setState(.unlocked)
            return
        }

        view.addSubview(unlockingMomentStack)
        unlockingMomentView.configure(with: unlockingPost)
        momentView.setState(unlockingPost.status == .sent ? .unlocked : .indeterminate)
        
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: unlockingMomentStack.bottomAnchor, constant: 25),
            unlockingMomentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            unlockingMomentStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            unlockingMomentStack.widthAnchor.constraint(equalToConstant: 85),
        ])
        
        unlockingPost.publisher(for: \.statusValue).sink { [weak self] _ in
            self?.updateUploadState()
        }.store(in: &cancellables)
        
        updateUploadState()
    }

    private func installDismissTap() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissTapped))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        view.addGestureRecognizer(tap)
    }
    
    private func installDismissButton() {
        let config = UIImage.SymbolConfiguration(weight: .bold)
        let image = UIImage(systemName: "chevron.down", withConfiguration: config)
        
        let button = UIButton(type: .system)
        button.setImage(image, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(dismissPushed), for: .touchUpInside)
        view.addSubview(button)
        
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 15),
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
        ])
    }

    @objc
    private func seenByPushed(_ sender: AnyObject) {
        let viewController = PostDashboardViewController(feedPost: post)
        viewController.delegate = self
        present(UINavigationController(rootViewController: viewController), animated: true)
    }

    @objc
    private func dismissTapped(_ sender: UITapGestureRecognizer) {
        if contentInputView.textView.isFirstResponder {
            contentInputView.textView.resignFirstResponder()
        } else {
            dismiss(animated: true)
        }
    }

    @objc
    private func dismissPushed(_ sender: UIButton) {
        dismiss(animated: true)
    }

    private func showUser() {
        delegate?.postDashboardViewController(didRequestPerformAction: .profile(post.userId))
    }
    
    private func showMoreMenu() {
        let menu = FeedPostMenuViewController.Menu {
            if post.canDeletePost {
                FeedPostMenuViewController.Section {
                    FeedPostMenuViewController.Item(style: .destructive,
                                                     icon: UIImage(systemName: "trash"),
                                                    title: Localizations.deletePostButtonTitle) { [weak self, post] _ in
                        self?.handleDeletePostTapped(postID: post.id)
                    }
                }
            }
        }
        
        present(FeedPostMenuViewController(menu: menu), animated: true)
    }
    
    private func handleDeletePostTapped(postID: FeedPostID) {
        let actionSheet = UIAlertController(title: nil,
                                          message: Localizations.deletePostConfirmationPrompt,
                                   preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: Localizations.deletePostButtonTitle, style: .destructive) { _ in
            self.reallyRetractPost(postID: postID)
        })
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        actionSheet.view.tintColor = .systemBlue
        
        present(actionSheet, animated: true)
    }

    private func reallyRetractPost(postID: FeedPostID) {
        guard let feedPost = MainAppContext.shared.feedData.feedPost(with: postID) else {
            dismiss(animated: true)
            return
        }
        
        MainAppContext.shared.feedData.retract(post: feedPost) { [weak self] result in
            switch result {
            case .failure(_):
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: Localizations.deletePostError, message: nil, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: nil))
                    self?.present(alert, animated: true, completion: nil)
                }
            default:
                break
            }
        }
        
        dismiss(animated: true)
    }

    private func updateUploadState() {
        guard let unlockingPost = unlockingPost else {
            return
        }
        
        switch unlockingPost.status {
        case .sent:
            unlockingPostProgressLabel.text = Localizations.momentUploadingSuccess
            momentView.setState(.unlocked, animated: true)
            refreshAccessoryView(show: true)
            expireMomentIfReady()
        case .sending:
            unlockingPostProgressLabel.text = Localizations.momentUploadingProgress
        case .sendError:
            unlockingPostProgressLabel.text = Localizations.momentUploadingFailed
        default:
            break
        }
    }

    private func expireMomentIfReady() {
        guard
            post.userId != MainAppContext.shared.userData.userId,
            post.feedMedia.first?.isMediaAvailable ?? true,
            case .unlocked = momentView.state,
            case .sent = unlockingPost?.status ?? .sent
        else {
            return
        }

        MainAppContext.shared.feedData.momentWasViewed(post)
    }

    private func showToast() {
        toast = Toast(type: .activityIndicator, text: Localizations.sending)
        toast?.show(viewController: self, shouldAutodismiss: false)
    }

    private func finalizeToast(success: Bool) {
        let icon = success ? UIImage(systemName: "checkmark") : UIImage(systemName: "xmark")
        let text = success ? Localizations.sent : Localizations.failedToSend

        toast?.update(type: .icon(icon), text: text, shouldAutodismiss: true)
        toast = nil
    }

    private func beginObserving(message: ChatMessage) {
        replyCancellable?.cancel()
        replyCancellable = message.publisher(for: \.outgoingStatusValue).sink { [weak self] _ in
            let success: Bool?
            switch message.outgoingStatus {
            case .sentOut, .delivered, .seen, .played:
                success = true
            case .error, .retracted:
                success = false
            case .none, .pending, .retracting:
                success = nil
            }

            if let success = success {
                self?.finalizeToast(success: success)
                self?.replyCancellable?.cancel()
                self?.replyCancellable = nil
            }
        }
    }
}

// MARK: - UIGestureRecognizerDelegate delegate methods

extension MomentViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // don't want the pan being caused while the user is pinching to zoom
        return !otherGestureRecognizer.isKind(of: UIPinchGestureRecognizer.self)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer.isKind(of: UITapGestureRecognizer.self) {
            return !facePileView.frame.contains(touch.location(in: view))
        }

        return true
    }
}

// MARK: - DismissAnimator implementation

/// Used to encapsulate the other objects needed during dismissal.
fileprivate class DismissAnimator: UIDynamicAnimator {
    var snapshot: UIView?
    var attachment: UIAttachmentBehavior?
    var propertyAnimator: UIViewPropertyAnimator?

    func reset() {
        removeAllBehaviors()

        snapshot?.removeFromSuperview()
        snapshot = nil
        attachment = nil

        propertyAnimator?.stopAnimation(false)
        propertyAnimator?.finishAnimation(at: .start)
        propertyAnimator = nil
    }
}

// MARK: - Interactive dismiss methods

extension MomentViewController {
    @objc
    private func dismissPan(_ gesture: UIPanGestureRecognizer) {
        guard !contentInputView.textView.isFirstResponder, isFullScreen else {
            // don't allow the flick-to-dismiss when the keyboard is showing or when presented via the camera
            return
        }

        switch gesture.state {
        case .began:
            dismissAnimator.reset()
            installDismissSnapshot()
            installAttachmentBehavior(gesture)
            createPropertyAnimator()
            refreshAccessoryView(show: false)
        case .changed:
            let anchor = gesture.location(in: view)
            attachment.anchorPoint = anchor
        case .ended:
            dismissAnimator.removeAllBehaviors()

            if !shouldCompleteInteractiveDismiss(gesture) {
                return installSnapBehavior()
            }

            let velocity = gesture.velocity(in: view)
            installPushBehavior(gesture, velocity: velocity)
        default:
            break
        }
    }

    /**
     Creates the attachment behavior that allows the snapshot to follow the user's finger and
     rotate around an anchor point.
     */
    private func installAttachmentBehavior(_ gesture: UIPanGestureRecognizer) {
        guard let snapshot = dismissAnimator.snapshot else {
            return
        }

        let location = gesture.location(in: snapshot)
        let offset = UIOffset(horizontal: location.x - snapshot.bounds.width / 2,
                                vertical: location.y - snapshot.bounds.height / 2)

        let anchor = gesture.location(in: view)
        let attachment = UIAttachmentBehavior(item: snapshot, offsetFromCenter: offset, attachedToAnchor: anchor)

        attachment.action = { [weak self] in
            self?.updatePropertyAnimator()
        }

        dismissAnimator.addBehavior(attachment)
        self.attachment = attachment
    }

    /**
     Creates the behavior that snaps the view back in place if the conditions to complete the dismiss
     interaction fail.
     */
    private func installSnapBehavior() {
        guard let snapshot = dismissAnimator.snapshot else {
            return
        }

        let snap = UISnapBehavior(item: snapshot, snapTo: momentView.center)
        snap.damping = 1

        snap.action = { [weak self] in
            guard let self = self else {
                return
            }

            self.updatePropertyAnimator()
            // without rounding, these points never match up in this block
            let r1 = CGPoint(x: round(snapshot.center.x), y: round(snapshot.center.y))
            let r2 = CGPoint(x: round(self.momentView.center.x), y: round(self.momentView.center.y))

            if r1 == r2 {
                self.dismissAnimator.removeAllBehaviors()
                self.dismissAnimator.snapshot?.removeFromSuperview()
                self.dismissAnimator.snapshot = nil
                self.momentView.isHidden = false

                self.dismissAnimator.propertyAnimator?.isReversed = true
                self.dismissAnimator.propertyAnimator?.startAnimation()

                self.refreshAccessoryView(show: true)
            }
        }

        dismissAnimator.addBehavior(snap)
    }

    private func shouldCompleteInteractiveDismiss(_ gesture: UIPanGestureRecognizer) -> Bool {
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        let translationThreshold: CGFloat = 300 * 300
        let velocityThreshold: CGFloat = 800 * 800

        let translationValue = translation.x * translation.x + translation.y * translation.y
        let velocityValue = velocity.x * velocity.x + velocity.y * velocity.y

        return translationValue > translationThreshold || velocityValue > velocityThreshold
    }

    /**
     Completes the interactive dismiss animation by creating a behavior that pushes the snapshot off-screen.
     */
    private func installPushBehavior(_ gesture: UIPanGestureRecognizer, velocity: CGPoint) {
        guard let snapshot = dismissAnimator.snapshot else {
            return
        }

        let behavior = UIPushBehavior(items: [snapshot], mode: .instantaneous)
        let magnitude = sqrt((velocity.x * velocity.x) + (velocity.y * velocity.y))
        behavior.pushDirection = CGVector(dx: velocity.x / 5, dy: velocity.y / 5)
        behavior.magnitude = magnitude / 10

        let finalPoint = gesture.location(in: view)
        let center = snapshot.center
        let offset = UIOffset(horizontal: finalPoint.x - center.x, vertical: finalPoint.y - center.y)
        behavior.setTargetOffsetFromCenter(offset, for: snapshot)

        behavior.action = { [weak self] in
            guard let self = self, !self.view.bounds.intersects(snapshot.frame) else {
                return
            }

            self.dismiss(animated: true)
        }

        let gravity = UIGravityBehavior(items: [snapshot])
        gravity.magnitude = 1.5

        dismissAnimator.addBehavior(behavior)
        dismissAnimator.addBehavior(gravity)

        dismissAnimator.propertyAnimator?.startAnimation()
    }

    private func updatePropertyAnimator() {
        guard let snapshot = dismissAnimator.snapshot else {
            return
        }

        let center = CGPoint(x: view.bounds.width / 2, y: view.bounds.height / 2)
        let distance = sqrt(pow(center.x - snapshot.center.x, 2) + pow(center.y - snapshot.center.y, 2))

        dismissAnimator.propertyAnimator?.fractionComplete = distance / 100
    }

    private func createPropertyAnimator() {
        dismissAnimator.propertyAnimator = UIViewPropertyAnimator(duration: 0.4, curve: .linear) {
            self.headerView.alpha = 0.25
            self.facePileView.alpha = 0.25
        }

        dismissAnimator.propertyAnimator?.addCompletion { [weak self] _ in
            self?.dismissAnimator.propertyAnimator = nil
        }

        dismissAnimator.propertyAnimator?.startAnimation()
        dismissAnimator.propertyAnimator?.pauseAnimation()
    }

    private func installDismissSnapshot() {
        guard let snapshot = momentView.snapshotView(afterScreenUpdates: true) else {
            return
        }

        snapshot.center = momentView.center
        view.addSubview(snapshot)
        momentView.isHidden = true
        dismissAnimator.snapshot = snapshot
    }
}

// MARK: - PostDashboardViewController delegate methods

extension MomentViewController: PostDashboardViewControllerDelegate {
    func postDashboardViewController(didRequestPerformAction action: PostDashboardViewController.UserAction) {
        delegate?.postDashboardViewController(didRequestPerformAction: action)
    }
}

// MARK: - ContentInputView delegate methods

extension MomentViewController: ContentInputDelegate {
    func inputView(_ inputView: ContentInputView, didPost content: ContentInputView.InputContent) {
        contentInputView.textView.resignFirstResponder()
        let text = content.mentionText.trimmed().collapsedText
        showToast()

        Task {
            guard let message = await MainAppContext.shared.chatData.sendMomentReply(to: post.userID, postID: post.id, text: text) else {
                finalizeToast(success: false)
                return
            }

            beginObserving(message: message)
        }
    }
}

// MARK: - UIViewControllerTransitioningDelegate methods

extension MomentViewController: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return MomentPresenter(startView: delegate?.initialTransitionView(for: self.post))
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return MomentDismisser(startView: delegate?.initialTransitionView(for: self.post))
    }
}

// MARK: - MomentPresenter implementation

fileprivate class MomentPresenter: NSObject, UIViewControllerAnimatedTransitioning {
    private weak var startView: MomentView?

    init(startView: MomentView? = nil) {
        super.init()
        self.startView = startView
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.3
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let to = transitionContext.viewController(forKey: .to) as? MomentViewController else {
            return
        }

        to.view.alpha = 0
        let startSnapshot = startView?.snapshotView(afterScreenUpdates: true)
        transitionContext.containerView.addSubview(to.view)
        to.view.layoutIfNeeded()
        if let snapshot = startSnapshot {
            transitionContext.containerView.addSubview(snapshot)
        }

        startView?.alpha = 0
        if let originalFrame = startView?.frame, let startViewSuperview = startView?.superview {
            startSnapshot?.frame = transitionContext.containerView.convert(originalFrame, from: startViewSuperview)
        }

        let finalSnapshot = to.momentView.snapshotView(afterScreenUpdates: true)
        finalSnapshot?.frame = startSnapshot?.frame ?? .zero
        if let snapshot = finalSnapshot {
            transitionContext.containerView.addSubview(snapshot)
        }

        finalSnapshot?.alpha = 0
        to.momentView.alpha = 0

        UIView.animate(withDuration: transitionDuration(using: nil), delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
            startSnapshot?.alpha = 0
            to.view.alpha = 1
            finalSnapshot?.alpha = 1

            startSnapshot?.frame = to.momentView.frame
            finalSnapshot?.frame = to.momentView.frame
        } completion: { _ in
            finalSnapshot?.alpha = 0
            to.momentView.alpha = 1

            startSnapshot?.removeFromSuperview()
            finalSnapshot?.removeFromSuperview()

            transitionContext.completeTransition(true)
        }
    }
}

// MARK: - MomentDismisser implementation

fileprivate class MomentDismisser: NSObject, UIViewControllerAnimatedTransitioning {
    private weak var startView: MomentView?

    init(startView: MomentView? = nil) {
        super.init()
        self.startView = startView
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.3
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let from = transitionContext.viewController(forKey: .from) else {
            return
        }

        UIView.animate(withDuration: transitionDuration(using: nil), delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
            from.view.alpha = 0
            self.startView?.alpha = 1
        } completion: { _ in
            transitionContext.completeTransition(true)
        }
    }
}

// MARK: - localization

extension Localizations {
    static var momentUploadingProgress: String {
        NSLocalizedString("moment.uploading.progress",
                   value: "Uploading...",
                 comment: "For indicating that a post is uploading.")
    }
    
    static var momentUploadingSuccess: String {
        NSLocalizedString("moment.uploading.success",
                   value: "Shared!",
                 comment: "For indicating that a post has been successfully uploaded and shared.")
    }
    
    static var momentUploadingFailed: String {
        NSLocalizedString("moment.uploading.failure",
                   value: "Error",
                 comment: "For indicating that there was an error while uploading the post.")
    }

    static var privateReplyPlaceholder: String {
        NSLocalizedString("private.reply.placeholder",
                   value: "Reply to %@",
                 comment: "Placeholder text for the text field for private replies. The argument is the first name of the contact.")
    }

    static var sending: String {
        NSLocalizedString("sending.title",
                   value: "Sending",
                 comment: "Indicates that an item is in the process of being sent.")
    }

    static var sent: String {
        NSLocalizedString("sent.title",
                   value: "Sent",
                 comment: "Indicates that an item has successfully been sent.")
    }

    static var failedToSend: String {
        NSLocalizedString("failed.to.send",
                   value: "Failed to send",
                 comment: "Indicates that an item has failed to be sent.")
    }
}
