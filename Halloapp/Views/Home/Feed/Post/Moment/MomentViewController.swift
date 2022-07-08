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
import CocoaLumberjackSwift

protocol MomentViewControllerDelegate: PostDashboardViewControllerDelegate {
    func initialTransitionView(for post: FeedPost) -> MomentView?
}

class MomentViewController: UIViewController {

    let post: FeedPost
    let unlockingPost: FeedPost?
    weak var delegate: MomentViewControllerDelegate?

    /// For operations such as expiration and taking a screenshot, we want to make sure the moment is visible.
    private var isReadyForSensitiveOperations: Bool {
        // not the user's own moment
        post.userId != MainAppContext.shared.userData.userId &&
        // the image is loaded
        post.feedMedia.first?.isMediaAvailable ?? true &&
        // no blur covering the image
        momentView.state == .unlocked &&
        // if this is an unlocking context, make sure the user's moment has been uploaded
        unlockingPost?.status ?? .sent == .sent
    }

    private(set) lazy var momentView: MomentView = {
        let view = MomentView()
        view.configure(with: post)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private(set) lazy var unlockingMomentView: MinimalMomentView = {
        let view = MinimalMomentView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        return view
    }()
    
    private lazy var headerView: FeedItemHeaderView = {
        let view = FeedItemHeaderView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.configure(with: post, contentWidth: view.bounds.width, showGroupName: false)
        view.showUserAction = { [weak self] in self?.showUser() }
        view.moreButton.isHidden = true
        return view
    }()

    private var cancellables: Set<AnyCancellable> = []

    private var replyMediaCancellable: AnyCancellable?

    private lazy var contentInputView: ContentInputView = {
        let view = ContentInputView(style: .normal, options: [])
        view.autoresizingMask = [.flexibleHeight]
        view.blurView.isHidden = true
        view.delegate = self
        let name = MainAppContext.shared.contactStore.firstName(for: post.userID, in: MainAppContext.shared.contactStore.viewContext)
        view.placeholderText = String(format: Localizations.privateReplyPlaceholder, name)

        return view
    }()

    private lazy var dismissKeyboardGesture = UISwipeGestureRecognizer(target: self, action: #selector(keyboardDismissSwipe))
    private lazy var dismissPanGesture = UIPanGestureRecognizer(target: self, action: #selector(dismissPan))
    private lazy var dismissTapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissTapped))

    private lazy var dismissAnimator: DismissAnimator = {
        let animator = DismissAnimator(referenceView: view)
        return animator
    }()

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

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
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .custom
        transitioningDelegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("SecretPostViewController coder init not implemented...")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        DDLogInfo("MomentViewController/viewDidLoad/post: \(post.id); unlocking post: \(unlockingPost?.id ?? "nil")")
        // With the modal presentation, the system adjusts a black background, causing it to
        // mismatch with the input accessory view
        let backgroundView = UIView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.backgroundColor = .momentFullscreenBg
        view.addSubview(backgroundView)

        view.addSubview(headerView)
        view.addSubview(momentView)
        
        let centerYConstraint = momentView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        // post will be off-center if there's an uploading post in the top corner
        centerYConstraint.priority = .defaultLow

        let spacing: CGFloat = 10
        NSLayoutConstraint.activate([
            centerYConstraint,
            momentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            momentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.leadingAnchor.constraint(equalTo: momentView.leadingAnchor, constant: 10),
            headerView.trailingAnchor.constraint(equalTo: momentView.trailingAnchor, constant: -10),
            headerView.bottomAnchor.constraint(equalTo: momentView.topAnchor, constant: -spacing),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        installUnlockingPost()
        installGestures()
        backgroundView.backgroundColor = .momentFullscreenBg.withAlphaComponent(0.97)

        momentView.dayOfWeekLabel.textColor = .black.withAlphaComponent(0.9)
        contentInputView.backgroundColor = backgroundView.backgroundColor

        NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)
            .sink { [weak self] _ in
                self?.screenshotWasTaken()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self, post] _ in
                self?.headerView.refreshTimestamp(with: post)
            }
            .store(in: &cancellables)

        let uploadControl = UploadProgressControl()
        view.addSubview(uploadControl)
        uploadControl.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            uploadControl.widthAnchor.constraint(equalToConstant: 75),
            uploadControl.heightAnchor.constraint(equalToConstant: 75),
            uploadControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            uploadControl.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DDLogInfo("MomentViewController/viewWillAppear")

        toast?.show()
        refreshAccessoryView(show: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if post.feedMedia.first?.isMediaAvailable ?? true {
            expireMomentIfReady()
        } else {
            post.feedMedia.first?.imageDidBecomeAvailable
                .sink { [weak self] _ in
                    self?.expireMomentIfReady()
                    self?.refreshAccessoryView(show: true)
                }
                .store(in: &cancellables)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        toast?.hide()
        refreshAccessoryView(show: false)
    }

    private func refreshAccessoryView(show: Bool) {
        guard isReadyForSensitiveOperations, show != showAccessoryView else {
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

        view.addSubview(unlockingMomentView)
        unlockingMomentView.configure(with: unlockingPost)
        momentView.setState(unlockingPost.status == .sent ? .unlocked : .indeterminate)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: unlockingMomentView.bottomAnchor, constant: 7),
            unlockingMomentView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -15),
            unlockingMomentView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 5),
            unlockingMomentView.widthAnchor.constraint(equalToConstant: 75),
        ])
        
        unlockingPost.publisher(for: \.statusValue).sink { [weak self] _ in
            self?.updateUploadState()
        }.store(in: &cancellables)
        
        updateUploadState()
    }

    private func installGestures() {
        dismissTapGesture.cancelsTouchesInView = false
        dismissTapGesture.delegate = self
        view.addGestureRecognizer(dismissTapGesture)

        dismissPanGesture.delegate = self
        momentView.addGestureRecognizer(dismissPanGesture)

        dismissKeyboardGesture.direction = .down
        dismissKeyboardGesture.delegate = self
        view.addGestureRecognizer(dismissKeyboardGesture)
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

    private func updateUploadState() {
        guard let unlockingPost = unlockingPost else {
            return
        }
        
        switch unlockingPost.status {
        case .sent:
            momentView.setState(.unlocked, animated: true)
            refreshAccessoryView(show: true)
            expireMomentIfReady()
        default:
            break
        }
    }

    private func expireMomentIfReady() {
        guard isReadyForSensitiveOperations else {
            DDLogInfo("MomentViewController/expireMomentIfReady/failed guard")
            return
        }

        DDLogInfo("MomentViewController/expireMomentIfReady/passed guard")
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
        if gestureRecognizer === dismissPanGesture, otherGestureRecognizer.isKind(of: UIPinchGestureRecognizer.self) {
            // don't want the pan being caused while the user is pinching to zoom
            return false
        }

        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return gestureRecognizer === dismissPanGesture && otherGestureRecognizer === dismissTapGesture
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer.isKind(of: UITapGestureRecognizer.self) {
            // prevent the dismiss tap from working when tapping on the moment, or when the dismiss pan is active
            if [.began, .changed].contains(dismissPanGesture.state) {
                return false
            }

            if momentView.isHidden {
                return true
            } else {
                return !momentView.bounds.contains(touch.location(in: momentView))
            }
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
    }
}

// MARK: - Interactive dismiss methods

extension MomentViewController {
    @objc
    private func dismissPan(_ gesture: UIPanGestureRecognizer) {
        guard !contentInputView.textView.isFirstResponder else {
            // don't allow the flick-to-dismiss when the keyboard is showing
            return
        }

        switch gesture.state {
        case .began where dismissAnimator.snapshot == nil:
            // don't start if the animation is being reset
            installDismissSnapshot()
            installAttachmentBehavior(gesture)
            createPropertyAnimator()
            refreshAccessoryView(show: false)
        case .changed:
            let anchor = gesture.location(in: view)
            dismissAnimator.attachment?.anchorPoint = anchor
        case .ended:
            dismissAnimator.removeAllBehaviors()

            if !shouldCompleteInteractiveDismiss(gesture) {
                refreshAccessoryView(show: true)
                return resetDismissAnimation()
            }

            let velocity = gesture.velocity(in: view)
            installPushBehavior(gesture, velocity: velocity)
        default:
            break
        }
    }

    @objc
    private func keyboardDismissSwipe(_ gesture: UISwipeGestureRecognizer) {
        if contentInputView.textView.isFirstResponder {
            contentInputView.textView.resignFirstResponder()
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

        dismissAnimator.attachment = attachment
        dismissAnimator.addBehavior(attachment)
    }

    /**
     Creates the behavior that snaps the view back in place if the conditions to complete the dismiss
     interaction fail.
     */
    private func resetDismissAnimation() {
        guard let snapshot = dismissAnimator.snapshot else {
            return
        }

        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.95, initialSpringVelocity: 1) {
            snapshot.transform = .identity
            snapshot.center = self.momentView.center
        } completion: { _ in
            self.momentView.isHidden = false
            self.dismissAnimator.reset()
        }

        dismissAnimator.propertyAnimator?.isReversed = true
        dismissAnimator.propertyAnimator?.startAnimation()
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

        let pushBehavior = UIPushBehavior(items: [snapshot], mode: .instantaneous)
        let magnitude = sqrt((velocity.x * velocity.x) + (velocity.y * velocity.y))
        pushBehavior.pushDirection = CGVector(dx: velocity.x / 5, dy: velocity.y / 5)
        pushBehavior.magnitude = magnitude / 8.5

        let finalPoint = gesture.location(in: view)
        let center = snapshot.center
        let offset = UIOffset(horizontal: finalPoint.x - center.x, vertical: finalPoint.y - center.y)
        pushBehavior.setTargetOffsetFromCenter(offset, for: snapshot)

        pushBehavior.action = { [weak self] in
            guard let self = self, !self.view.bounds.intersects(snapshot.frame) else {
                return
            }

            self.dismiss(animated: true)
        }

        let gravityBehavior = UIGravityBehavior(items: [snapshot])
        gravityBehavior.magnitude = 1.5

        let resistanceBehavior = UIDynamicItemBehavior(items: [snapshot])
        resistanceBehavior.angularResistance = 3

        dismissAnimator.addBehavior(resistanceBehavior)
        dismissAnimator.addBehavior(pushBehavior)
        dismissAnimator.addBehavior(gravityBehavior)

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
        dismissAnimator.propertyAnimator = UIViewPropertyAnimator(duration: 0.3, curve: .linear) {
            self.headerView.alpha = 0.25
            self.unlockingMomentView.alpha = 0.25
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

// MARK: - handling screenshots

extension MomentViewController {
    private func screenshotWasTaken() {
        guard isReadyForSensitiveOperations else {
            return
        }

        DDLogInfo("MomentViewController/screenshotWasTaken")
        MainAppContext.shared.feedData.sendScreenshotReceipt(for: post)
    }
}

// MARK: - ContentInputView delegate methods

extension MomentViewController: ContentInputDelegate {
    func inputView(_ inputView: ContentInputView, didPost content: ContentInputView.InputContent) {
        contentInputView.textView.resignFirstResponder()
        let text = content.mentionText.trimmed().collapsedText
        showToast()

        Task { @MainActor in
            guard let message = await MainAppContext.shared.chatData.sendMomentReply(to: post.userID, postID: post.id, text: text, media: content.media) else {
                finalizeToast(success: false)
                return
            }

            beginObserving(message: message)
        }
    }

    func inputViewContentOptionsMenu(_ inputView: ContentInputView) -> HAMenu.Content {
        HAMenuButton(title: Localizations.photoAndVideoLibrary, image: UIImage(systemName: "photo.fill.on.rectangle.fill")) { [weak self] in
            self?.presentMediaPicker()
        }
        HAMenuButton(title: Localizations.fabAccessibilityCamera, image: UIImage(systemName: "camera.fill")) { [weak self] in
            self?.presentCameraViewController()
        }
        
    }

    func presentMediaPicker() {
        let vc = MediaPickerViewController(config: .moment) { [weak self] controller, _, _, media, cancel in
            controller.dismiss(animated: true)
            guard let media = media.first, !cancel else {
                return
            }

            self?.addMediaWhenAvailable(media)
        }

        present(UINavigationController(rootViewController: vc), animated: true)
    }

    func inputViewDidSelectCamera(_ inputView: ContentInputView) {
        presentCameraViewController()
    }

    private func presentCameraViewController() {
        let vc = NewCameraViewController()
        vc.onPhotoCapture = { [weak self] image in
            vc.dismiss(animated: true)
            let media = PendingMedia(type: .image)
            media.image = image

            self?.addMediaWhenAvailable(media)
        }

        vc.onVideoCapture = { [weak self] url in
            vc.dismiss(animated: true)
            let media = PendingMedia(type: .video)
            media.originalVideoURL = url
            media.fileURL = url

            self?.addMediaWhenAvailable(media)
        }

        present(UINavigationController(rootViewController: vc), animated: true)
    }

    private func addMediaWhenAvailable(_ media: PendingMedia) {
        replyMediaCancellable?.cancel()
        guard !media.ready.value else {
            contentInputView.add(media: media)
            return
        }

        replyMediaCancellable = media.ready.sink { [weak self] ready in
            if ready {
                self?.contentInputView.add(media: media)
            }
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
    private typealias TransitionSnapshots = (cell: UIView, finalMoment: UIView, fromViewController: UIView)
    static weak var fromViewSnapshot: UIView?
    private weak var startView: MomentView?

    init(startView: MomentView? = nil) {
        super.init()
        self.startView = startView
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.3
    }

    private func transitionSnapshots(_ context: UIViewControllerContextTransitioning) -> TransitionSnapshots? {
        guard
            let from = context.viewController(forKey: .from),
            let to = context.viewController(forKey: .to) as? MomentViewController,
            let currentFrom = from.view.snapshotView(afterScreenUpdates: false)
        else {
            return nil
        }

        context.containerView.alpha = 0
        context.containerView.addSubview(to.view)
        to.view.layoutIfNeeded()

        // get a snapshot of the moment view in its feed cell
        let momentCellSnapshot = startView?.snapshotView(afterScreenUpdates: false)
        // get a snapshot of the moment view in the final view controller
        let finalMomentSnapshot = to.momentView.snapshotView(afterScreenUpdates: true)

        to.view.alpha = 0
        context.containerView.alpha = 1

        // we want a snapshot of the feed with the above cell hidden
        context.containerView.addSubview(currentFrom)
        startView?.alpha = 0
        let updatedFrom = from.view.snapshotView(afterScreenUpdates: true)
        startView?.alpha = 1
        currentFrom.removeFromSuperview()

        guard
            let cellSnapshot = momentCellSnapshot,
            let finalSnapshot = finalMomentSnapshot,
            let updatedFrom = updatedFrom
        else {
            return nil
        }

        let snapshots: TransitionSnapshots = (cellSnapshot, finalSnapshot, updatedFrom)
        context.containerView.insertSubview(snapshots.fromViewController, belowSubview: to.view)
        context.containerView.addSubview(snapshots.cell)
        context.containerView.addSubview(snapshots.finalMoment)

        return snapshots
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard
            let to = transitionContext.viewController(forKey: .to) as? MomentViewController,
            let snapshots = transitionSnapshots(transitionContext)
        else {
            return performSimpleTransition(using: transitionContext)
        }

        if let cellMomentViewFrame = startView?.frame, let momentCell = startView?.superview {
            snapshots.cell.frame = transitionContext.containerView.convert(cellMomentViewFrame, from: momentCell)
        }

        snapshots.finalMoment.frame = snapshots.cell.frame
        to.momentView.alpha = 0

        UIView.animate(withDuration: transitionDuration(using: nil), delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
            snapshots.cell.alpha = 0
            to.view.alpha = 1

            snapshots.cell.frame = to.momentView.frame
            snapshots.finalMoment.frame = to.momentView.frame
        } completion: { _ in
            to.momentView.alpha = 1
            snapshots.cell.removeFromSuperview()
            snapshots.finalMoment.removeFromSuperview()

            transitionContext.completeTransition(true)
        }

        Self.fromViewSnapshot = snapshots.fromViewController
    }

    /// A simple fade that's used when not being presented from the feed.
    private func performSimpleTransition(using transitionContext: UIViewControllerContextTransitioning) {
        UIView.animate(withDuration: transitionDuration(using: nil), delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
            self.startView?.alpha = 1
            transitionContext.viewController(forKey: .to)?.view.alpha = 1
        } completion: { _ in
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
            MomentPresenter.fromViewSnapshot?.alpha = 0
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
