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
import CoreData

protocol MomentViewControllerDelegate: MomentViewDelegate {

}

class MomentViewController: UIViewController {

    private(set) var post: FeedPost
    let unlockingPost: FeedPost?

    private let shouldFetchOtherMoments: Bool
    private var otherMoments: [FeedPost] = []

    weak var transitionStartView: MomentView?

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

    private lazy var backButton: UIButton = {
        let button = LargeHitButton(type: .system)
        button.targetIncrease = 10
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        button.setContentHuggingPriority(.defaultHigh, for: .vertical)
        button.setPreferredSymbolConfiguration(.init(pointSize: 20, weight: .medium), forImageIn: .normal)
        button.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        button.tintColor = .label
        button.addTarget(self, action: #selector(dismissAction), for: .touchUpInside)
        return button
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
    /// For observing `post`'s media.
    private var mediaAvailableCancellable: AnyCancellable?
    ///
    private var replyMediaCancellable: AnyCancellable?
    /// For observing the status of private replies.
    private var replyStatusCancellable: AnyCancellable?
    private var replyStatusPublisher: Publishers.MergeMany<AnyPublisher<Bool, Never>>?

    private lazy var contentInputView: ContentInputView = {
        let view = ContentInputView(style: .normal, options: [])
        view.autoresizingMask = [.flexibleHeight]
        view.blurView.isHidden = true
        view.delegate = self
        let name = MainAppContext.shared.contactStore.firstName(for: post.userID, in: MainAppContext.shared.contactStore.viewContext)
        view.placeholderText = String(format: Localizations.privateReplyPlaceholder, name)

        return view
    }()

    private lazy var dismissPanGesture: UIPanGestureRecognizer = {
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(dismissPan))
        gesture.delegate = self
        return gesture
    }()

    private lazy var dismissKeyboardGesture: UISwipeGestureRecognizer = {
        let gesture = UISwipeGestureRecognizer(target: self, action: #selector(keyboardDismissSwipe))
        gesture.delegate = self
        gesture.direction = .down
        return gesture
    }()

    private lazy var dismissTapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(dismissAction))
        gesture.delegate = self
        gesture.cancelsTouchesInView = false
        return gesture
    }()

    private lazy var nextMomentTapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(nextMomentTapped))
        gesture.delegate = self
        gesture.cancelsTouchesInView = false
        return gesture
    }()

    private var transitionSnapshot: UIView?
    private lazy var transitionAnimator: TransitionAnimator = {
        let animator = TransitionAnimator(referenceView: viewForAnimation())
        return animator
    }()

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    /// `true` if the user is in the process of transitioning from one moment to the next, interactively or not.
    @Published private var isAnimatingToNextMoment = false

    private var showAccessoryView = false
    override var inputAccessoryView: UIView? {
        showAccessoryView ? contentInputView : nil
    }

    private var toast: Toast?
    private var ftuxLabel: UILabel?

    weak var delegate: MomentViewControllerDelegate?

    init(post: FeedPost, unlockingPost: FeedPost? = nil, shouldFetchOtherMoments: Bool = true) {
        self.post = post
        self.unlockingPost = unlockingPost
        self.shouldFetchOtherMoments = shouldFetchOtherMoments
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .custom
        transitioningDelegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("MomentViewController coder init not implemented...")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        DDLogInfo("MomentViewController/viewDidLoad/post: \(post.id); unlocking post: \(unlockingPost?.id ?? "nil")")

        view.backgroundColor = .momentFullscreenBg.withAlphaComponent(0.99)
        contentInputView.backgroundColor = view.backgroundColor

        view.addSubview(headerView)
        view.addSubview(momentView)
        view.addSubview(backButton)

        let spacing: CGFloat = 10
        let centerYConstraint = momentView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        // post will be off-center if there's an uploading post in the top corner
        centerYConstraint.priority = .defaultLow

        NSLayoutConstraint.activate([
            centerYConstraint,
            momentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            momentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            headerView.leadingAnchor.constraint(equalTo: momentView.leadingAnchor, constant: 10),
            headerView.trailingAnchor.constraint(equalTo: momentView.trailingAnchor, constant: -10),
            headerView.bottomAnchor.constraint(equalTo: momentView.topAnchor, constant: -spacing),

            backButton.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 5),
        ])

        installUnlockingPost()

        view.addGestureRecognizer(dismissTapGesture)
        momentView.addGestureRecognizer(dismissPanGesture)
        momentView.addGestureRecognizer(nextMomentTapGesture)
        view.addGestureRecognizer(dismissKeyboardGesture)

        NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)
            .sink { [weak self] _ in
                self?.screenshotWasTaken()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                if let self = self {
                    self.headerView.refreshTimestamp(with: self.post)
                }
            }
            .store(in: &cancellables)

        $isAnimatingToNextMoment
            .removeDuplicates()
            .map { !$0 }
            .assign(to: \.isUserInteractionEnabled, onWeak: contentInputView)
            .store(in: &cancellables)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DDLogInfo("MomentViewController/viewWillAppear")

        toast?.show()
        refreshAccessoryView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        subscribeToMediaUpdates()

        if shouldFetchOtherMoments, post.userId != MainAppContext.shared.userData.userId {
            otherMoments = MainAppContext.shared.feedData.fetchAllIncomingMoments().filter { $0.id != self.post.id }
            DDLogInfo("MomentViewController/viewDidAppear/loaded \(otherMoments.count) other moments")

            if !otherMoments.isEmpty, !Self.hasSwipedToNext {
                installFTUX()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        toast?.hide()
        refreshAccessoryView(show: false)
    }

    private func subscribeToMediaUpdates() {
        mediaAvailableCancellable = nil
        guard let media = post.feedMedia.first, !media.isMediaAvailable else {
            expireMomentIfReady()
            refreshAccessoryView()
            return
        }

        mediaAvailableCancellable = media.imageDidBecomeAvailable
            .sink { [weak self] _ in
                self?.expireMomentIfReady()
                self?.refreshAccessoryView()
            }
    }

    private func refreshAccessoryView(show: Bool = true) {
        let show = post.userID == MainAppContext.shared.userData.userId ? false : show
        let enable = isReadyForSensitiveOperations

        contentInputView.isEnabled = enable

        if show != showAccessoryView {
            showAccessoryView = show
            reloadInputViews()
        }
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
        
        unlockingPost.publisher(for: \.statusValue)
            .compactMap { FeedPost.Status(rawValue: $0) }
            .sink { [weak self] in
                switch $0 {
                case .sent:
                    self?.momentView.setState(.unlocked, animated: true)
                    self?.refreshAccessoryView()
                    self?.expireMomentIfReady()
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    @objc
    private func dismissAction(_ sender: AnyObject) {
        if let snapshot = transitionSnapshot {
            // since we attach the snapshot to the window, we need to make sure we clean it up during a dismiss
            UIView.animate(withDuration: 0.15) {
                snapshot.alpha = 0
            } completion: { _ in
                self.cleanUpAfterAnimation()
            }
        }

        dismiss(animated: true)
    }

    @objc
    private func nextMomentTapped(_ sender: UITapGestureRecognizer) {
        if let moment = otherMoments.popLast() {
            setupAndAnimate(toNext: moment)
        }
    }

    @objc
    private func keyboardDismissSwipe(_ gesture: UISwipeGestureRecognizer) {
        if contentInputView.textView.isFirstResponder {
            contentInputView.textView.resignFirstResponder()
        }
    }

    private func showUser() {
        delegate?.momentView(momentView, didSelect: .view(profile: post.userId))
    }

    private func expireMomentIfReady() {
        guard isReadyForSensitiveOperations else {
            DDLogInfo("MomentViewController/expireMomentIfReady/failed guard")
            return
        }

        DDLogInfo("MomentViewController/expireMomentIfReady/passed guard")
        MainAppContext.shared.feedData.momentWasViewed(post)
        UNUserNotificationCenter.current().removeDeliveredMomentNotifications()
    }

    private func screenshotWasTaken() {
        guard isReadyForSensitiveOperations else {
            return
        }

        DDLogInfo("MomentViewController/screenshotWasTaken")
        MainAppContext.shared.feedData.sendScreenshotReceipt(for: post)
    }
}

// MARK: - UIGestureRecognizerDelegate delegate methods

extension MomentViewController: UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        switch (gestureRecognizer, otherGestureRecognizer) {
        case (dismissPanGesture, is UIPinchGestureRecognizer):
            // don't want the pan being caused while the user is pinching to zoom
            return false

        default:
            return true
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        switch (gestureRecognizer, otherGestureRecognizer) {
        case (dismissPanGesture, is UITapGestureRecognizer):
            return true

        default:
            return false
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        switch gestureRecognizer {
        case is UITapGestureRecognizer where [.began, .changed].contains(dismissPanGesture.state):
            return false

        case dismissTapGesture:
            return !momentView.bounds.contains(touch.location(in: momentView))

        case nextMomentTapGesture:
            return momentView.bounds.contains(touch.location(in: momentView))

        default:
            return true
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        switch gestureRecognizer {
        case is UITapGestureRecognizer where contentInputView.textView.isFirstResponder:
            contentInputView.textView.resignFirstResponder()
            fallthrough

        case dismissPanGesture where contentInputView.textView.isFirstResponder:
            return false

        default:
            return !isAnimatingToNextMoment
        }
    }
}

// MARK: - DismissAnimator implementation

fileprivate class TransitionAnimator: UIDynamicAnimator {
    var attachment: UIAttachmentBehavior?
}

// MARK: - Moment transition methods

extension MomentViewController {
    @objc
    private func dismissPan(_ gesture: UIPanGestureRecognizer) {
        guard !contentInputView.textView.isFirstResponder else {
            // don't allow the flick-to-dismiss when the keyboard is showing
            return
        }

        switch gesture.state {
        case .began where transitionSnapshot == nil:
            // don't start if the animation is being reset
            isAnimatingToNextMoment = true
            makeTransitionSnapshot()
            momentView.isHidden = true

            installAttachmentBehavior(gesture)
            fallthrough

        case .changed:
            let anchor = gesture.location(in: view)
            transitionAnimator.attachment?.anchorPoint = anchor

        case .ended:
            transitionAnimator.removeAllBehaviors()
            if !shouldCompleteInteractiveTransition(gesture) {
                return resetTransitionAnimator()
            }

            handleSuccessfulPanGestureEnd(gesture)

        default:
            break
        }
    }

    private func handleSuccessfulPanGestureEnd(_ gesture: UIPanGestureRecognizer) {
        guard let snapshot = transitionSnapshot else {
            return
        }

        let closure = !otherMoments.isEmpty ? nil : { [weak self] in
            guard let self = self, !self.view.bounds.intersects(snapshot.frame) else {
                return
            }
            // when there are no other moments, we dismiss once the snapshot leaves the frame entirely
            self.dismiss(animated: true)
        }

        installPushBehavior(gesture, closure)
        if let moment = otherMoments.popLast() {
            setupAndAnimate(toNext: moment, interactive: true)
        }
    }

    private func installAttachmentBehavior(_ gesture: UIPanGestureRecognizer) {
        guard let snapshot = transitionSnapshot else {
            return
        }

        let location = gesture.location(in: snapshot)
        let offset = UIOffset(horizontal: location.x - snapshot.bounds.width / 2,
                                vertical: location.y - snapshot.bounds.height / 2)

        let anchor = gesture.location(in: view)
        let attachment = UIAttachmentBehavior(item: snapshot, offsetFromCenter: offset, attachedToAnchor: anchor)

        transitionAnimator.attachment = attachment
        transitionAnimator.addBehavior(attachment)
    }

    /// Resets the view if the interactive transition didn't complete.
    private func resetTransitionAnimator() {
        guard let snapshot = transitionSnapshot else {
            return
        }

        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.95, initialSpringVelocity: 1) {
            snapshot.transform = .identity
            snapshot.center = self.momentView.center
        } completion: { _ in
            self.momentView.isHidden = false
            self.cleanUpAfterAnimation()
            self.isAnimatingToNextMoment = false
        }
    }

    private func shouldCompleteInteractiveTransition(_ gesture: UIPanGestureRecognizer) -> Bool {
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        let translationThreshold: CGFloat = 300 * 300
        let velocityThreshold: CGFloat = 500 * 500

        let translationValue = translation.x * translation.x + translation.y * translation.y
        let velocityValue = velocity.x * velocity.x + velocity.y * velocity.y

        return translationValue > translationThreshold || velocityValue > velocityThreshold
    }

    private func installPushBehavior(_ gesture: UIPanGestureRecognizer, _ block: (() -> Void)? = nil) {
        guard let snapshot = transitionSnapshot else {
            return
        }

        let velocity = gesture.velocity(in: view)
        let pushBehavior = UIPushBehavior(items: [snapshot], mode: .instantaneous)
        let magnitude = sqrt((velocity.x * velocity.x) + (velocity.y * velocity.y))
        pushBehavior.pushDirection = CGVector(dx: velocity.x / 1, dy: velocity.y / 1)
        pushBehavior.magnitude = min(magnitude / 6.5, 700)

        let finalPoint = gesture.location(in: view)
        let center = snapshot.center
        let offset = UIOffset(horizontal: finalPoint.x - center.x, vertical: finalPoint.y - center.y)
        pushBehavior.setTargetOffsetFromCenter(offset, for: snapshot)

        pushBehavior.action = block

        let gravityBehavior = UIGravityBehavior(items: [snapshot])
        gravityBehavior.magnitude = 1.5

        let resistanceBehavior = UIDynamicItemBehavior(items: [snapshot])
        resistanceBehavior.angularResistance = 5

        transitionAnimator.addBehavior(resistanceBehavior)
        transitionAnimator.addBehavior(pushBehavior)
        transitionAnimator.addBehavior(gravityBehavior)
    }

    private func animate(toNext moment: FeedPost, interactive: Bool = false, completion: @escaping () -> ()) {
        guard let snapshot = transitionSnapshot else {
            DDLogError("MomentViewController/animateToNext/no snapshot present (interactive: \(interactive)")
            return
        }

        let nextMomentState: MomentView.State = unlockingPost?.status ?? .sent == .sent ? .unlocked : .indeterminate
        momentView.setState(.indeterminate)

        let name = MainAppContext.shared.contactStore.firstName(for: moment.userID,
                                                                 in: MainAppContext.shared.contactStore.viewContext)
        let firstDuration = 0.25
        let firstDelay = 0.15
        let secondDuration = 0.175
        let secondDelay = (firstDuration + firstDelay) * 0.5

        if interactive {
            momentView.alpha = 0
            momentView.isHidden = false
            momentView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)

            UIView.animate(withDuration: firstDuration, delay: firstDelay, options: [.curveEaseOut]) {
                self.momentView.alpha = 1
                self.momentView.transform = .identity
                self.unlockingMomentView.alpha = 1
                self.momentView.setState(nextMomentState)
                snapshot.alpha = 0
            }
        }

        UIView.transition(with: self.headerView, duration: secondDuration, delay: interactive ? secondDelay : 0, options: [.transitionCrossDissolve]) {
            self.headerView.configure(with: moment, contentWidth: self.view.bounds.width, showGroupName: false)
            self.headerView.alpha = 1
            self.contentInputView.placeholderText = String(format: Localizations.privateReplyPlaceholder, name)

            if !interactive {
                self.momentView.setState(nextMomentState)
                self.momentView.isHidden = false
                snapshot.alpha = 0
            }

        } completion: { _ in
            self.cleanUpAfterAnimation()
            completion()
        }
    }

    private func setupAndAnimate(toNext moment: FeedPost, interactive: Bool = false) {
        if ftuxLabel != nil {
            removeFTUX()
        }

        if !interactive {
            isAnimatingToNextMoment = true
            makeTransitionSnapshot()
        }

        post = moment
        momentView.configure(with: moment)

        contentInputView.reset()

        animate(toNext: moment, interactive: interactive) { [weak self, post] in
            DDLogInfo("MomentViewController/animateToNext completion/transitioned to \(post.id); interactive: \(interactive)")

            self?.isAnimatingToNextMoment = false
            // this will expire the new moment when ready
            self?.subscribeToMediaUpdates()
        }
    }

    @discardableResult
    private func makeTransitionSnapshot() -> UIView? {
        guard let snapshot = momentView.snapshotView(afterScreenUpdates: false) else {
            return nil
        }

        let view = transitionAnimator.referenceView ?? viewForAnimation()
        snapshot.center = view.convert(momentView.center, from: self.view)
        view.addSubview(snapshot)

        transitionSnapshot = snapshot
        return snapshot
    }

    /// Gets the last window in the scene so that the snapshot is above the input accessory view.
    private func viewForAnimation() -> UIView {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes where scene.activationState == .foregroundActive {
            if let last = scene.windows.last {
                return last
            }
        }

        return view
    }

    private func cleanUpAfterAnimation() {
        transitionAnimator.removeAllBehaviors()
        transitionAnimator.attachment = nil
        transitionSnapshot?.removeFromSuperview()
        transitionSnapshot = nil
    }
}

// MARK: - ContentInputView delegate methods

extension MomentViewController: ContentInputDelegate {

    func inputView(_ inputView: ContentInputView, didPost content: ContentInputView.InputContent) {
        let text = content.mentionText.trimmed().collapsedText
        contentInputView.textView.resignFirstResponder()

        showToast()

        Task { @MainActor [weak self] in
            guard let message = await MainAppContext.shared.chatData.sendMomentReply(chatMessageRecipient: .oneToOneChat(toUserId: post.userId, fromUserId: MainAppContext.shared.userData.userId), postID: post.id, text: text, media: content.media, files: content.files) else {
                self?.finalizeToast(success: false)
                return
            }

            self?.beginObserving(message: message)
        }
    }

    private func beginObserving(message: ChatMessage) {
        let existing = replyStatusPublisher?.publishers ?? []
        let manyPublisher = Publishers.MergeMany(existing + [message.didSendPublisher])

        replyStatusCancellable = manyPublisher
            .collect()
            .sink { [weak self] result in
                if result.allSatisfy({ $0 }) {
                    DDLogInfo("MomentViewController/beginObserving-message/successfully sent \(result.count) messages")
                    self?.finalizeToast(success: true)
                } else {
                    DDLogError("MomentViewController/beginObserving-message/failed to send \(result.count) messages")
                    self?.finalizeToast(success: false)
                }

                self?.replyStatusPublisher = nil
            }

        replyStatusPublisher = manyPublisher
    }

    private func showToast() {
        guard toast == nil else {
            // reset back to the indicator in case it's in a finalized state
            toast?.update(type: .activityIndicator, text: Localizations.sending, shouldAutodismiss: false)
            return
        }

        toast = Toast(type: .activityIndicator, text: Localizations.sending)
        toast?.show(viewController: self, shouldAutodismiss: false)
    }

    private func finalizeToast(success: Bool) {
        let icon = success ? UIImage(systemName: "checkmark") : UIImage(systemName: "xmark")
        let text = success ? Localizations.sent : Localizations.failedToSend

        toast?.update(type: .icon(icon), text: text, shouldAutodismiss: true)
        toast = nil
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
        let vc = MediaPickerViewController(config: .moment) { [weak self] controller, _, media, cancel in
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
        vc.delegate = self

        let nc = UINavigationController(rootViewController: vc)
        nc.modalPresentationStyle = .fullScreen

        present(nc, animated: true)
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

// MARK: - CameraViewControllerDelegate methods

extension MomentViewController: CameraViewControllerDelegate {

    func cameraViewController(_ viewController: NewCameraViewController, didCapture results: [CaptureResult], isFinished: Bool) {
        if let image = results.first?.image, isFinished {
            let media = PendingMedia(type: .image)
            media.image = image
            addMediaWhenAvailable(media)

            viewController.dismiss(animated: true)
        }
    }

    func cameraViewControllerDidReleaseShutter(_ viewController: NewCameraViewController) {

    }

    func cameraViewController(_ viewController: NewCameraViewController, didTake photo: UIImage) {
        viewController.dismiss(animated: true)

        let media = PendingMedia(type: .image)
        media.image = photo
        addMediaWhenAvailable(media)
    }

    func cameraViewController(_ viewController: NewCameraViewController, didRecordVideoTo url: URL) {
        viewController.dismiss(animated: true)

        let media = PendingMedia(type: .video)
        media.originalVideoURL = url
        media.fileURL = url
        addMediaWhenAvailable(media)
    }

    func cameraViewController(_ viewController: NewCameraViewController, didSelect media: PendingMedia) {

    }
}

// MARK: - FTUX methods

extension MomentViewController {

    @UserDefault(key: "shown.fs.moment.swipe.indicator", defaultValue: false)
    static private var hasSwipedToNext: Bool

    private func installFTUX() {
        guard
            let momentFooterView = momentView.dayOfWeekLabel.superview,
            let image = UIImage(systemName: "hand.draw")
        else {
            return
        }

        let string = NSMutableAttributedString.string(Localizations.swipeForMore,
                                                with: image,
                                             spacing: 2,
                                     imageAttributes: [.font: UIFont.systemFont(ofSize: 19, weight: .semibold), .foregroundColor: UIColor.lavaOrange],
                                      textAttributes: [.font: UIFont.gothamFont(ofFixedSize: 18, weight: .medium), .foregroundColor: UIColor.lavaOrange])

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.attributedText = string
        label.textAlignment = .center

        label.alpha = 0
        momentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: momentFooterView.topAnchor),
            label.bottomAnchor.constraint(equalTo: momentFooterView.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: momentView.leadingAnchor, constant: MomentView.Layout.mediaPadding),
            label.trailingAnchor.constraint(equalTo: momentView.trailingAnchor, constant: -MomentView.Layout.mediaPadding),
        ])

        ftuxLabel = label

        UIView.animate(withDuration: 0.2, delay: 0.15) {
            label.alpha = 1
            self.momentView.dayOfWeekLabel.alpha = 0
        }
    }

    private func removeFTUX() {
        guard let ftuxLabel = ftuxLabel else {
            return
        }

        momentView.dayOfWeekLabel.alpha = 1
        ftuxLabel.removeFromSuperview()
        self.ftuxLabel = nil

        Self.hasSwipedToNext = true
    }
}

// MARK: - UIViewControllerTransitioningDelegate methods

extension MomentViewController: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return MomentPresenter(startView: transitionStartView)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return MomentDismisser(startView: transitionStartView)
    }
}

// MARK: - MomentPresenter implementation

fileprivate class MomentPresenter: NSObject, UIViewControllerAnimatedTransitioning {

    private typealias TransitionViews = (momentView: MomentView, feedSnapshot: UIView)
    static weak var fromViewSnapshot: UIView?
    private weak var startView: MomentView?

    init(startView: MomentView? = nil) {
        super.init()
        self.startView = startView
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.37
    }

    private func transitionSnapshots(_ context: UIViewControllerContextTransitioning) -> TransitionViews? {
        guard
            let from = context.viewController(forKey: .from),
            let to = context.viewController(forKey: .to) as? MomentViewController,
            let currentFrom = from.view.snapshotView(afterScreenUpdates: false),
            let startView = startView
        else {
            return nil
        }

        context.containerView.alpha = 0
        context.containerView.addSubview(to.view)
        to.view.layoutIfNeeded()

        to.view.alpha = 0
        context.containerView.alpha = 1

        // we want a snapshot of the feed with the above cell hidden
        context.containerView.addSubview(currentFrom)
        startView.alpha = 0
        let updatedFrom = from.view.snapshotView(afterScreenUpdates: true)
        startView.alpha = 1
        currentFrom.removeFromSuperview()

        guard let updatedFrom = updatedFrom, let post = startView.feedPost else {
            return nil
        }

        let momentViewForAnimation = MomentView()
        momentViewForAnimation.configure(with: post)

        let views: TransitionViews = (momentViewForAnimation, updatedFrom)
        context.containerView.insertSubview(views.feedSnapshot, belowSubview: to.view)
        context.containerView.addSubview(views.momentView)

        let center = context.containerView.convert(startView.center, from: startView.superview)
        views.momentView.frame.size = startView.bounds.size
        views.momentView.center = center
        views.momentView.layoutIfNeeded()
        views.momentView.transform = CGAffineTransform(rotationAngle: startView.transform.rotationAngle)

        return views
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard
            let to = transitionContext.viewController(forKey: .to) as? MomentViewController,
            let transitionViews = transitionSnapshots(transitionContext)
        else {
            return performSimpleTransition(using: transitionContext)
        }

        to.momentView.alpha = 0
        let transitionMomentViewFinalState: MomentView.State
        if let validMoment = MainAppContext.shared.feedData.validMoment.value, validMoment.status == .sent {
            transitionMomentViewFinalState = .unlocked
        } else {
            transitionMomentViewFinalState = .indeterminate
        }

        UIView.animate(withDuration: transitionDuration(using: nil), delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: .curveEaseInOut) {
            to.view.alpha = 1

            transitionViews.momentView.transform = .identity
            transitionViews.momentView.frame = to.momentView.frame
            transitionViews.momentView.layoutIfNeeded()
            transitionViews.momentView.setState(transitionMomentViewFinalState)

        } completion: { _ in
            to.momentView.alpha = 1
            transitionViews.momentView.removeFromSuperview()
            transitionContext.completeTransition(true)
        }

        Self.fromViewSnapshot = transitionViews.feedSnapshot
    }

    /// A simple fade that's used when not being presented from the feed.
    private func performSimpleTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let to = transitionContext.viewController(forKey: .to) else {
            return transitionContext.completeTransition(false)
        }

        if to.view.superview == nil {
            transitionContext.containerView.addSubview(to.view)
            to.view.layoutIfNeeded()
        }

        to.view.alpha = 0

        UIView.animate(withDuration: transitionDuration(using: nil), delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: .curveEaseInOut) {
            self.startView?.alpha = 1
            to.view.alpha = 1
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

// MARK: - ChatMessage extension

fileprivate extension ChatMessage {
    /// A publisher for notifying whether the message has been sent or not.
    /// Sends `true` if the message has been successfully sent. Only fires once.
    var didSendPublisher: AnyPublisher<Bool, Never> {
        return publisher(for: \.outgoingStatusValue)
            .compactMap {
                switch ChatMessage.OutgoingStatus(rawValue: $0) {
                case .sentOut, .delivered, .seen, .played:
                    return true
                case .error, .retracted:
                    return false
                default:
                    return nil
                }
            }
            .first()
            .eraseToAnyPublisher()
    }
}

// MARK: - UIView transition extension

fileprivate extension UIView {

    class func transition(
        with view: UIView,
        duration: TimeInterval,
        delay: TimeInterval,
        options: UIView.AnimationOptions = [],
        animations: (() -> Void)?,
        completion: ((Bool) -> Void)? = nil
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Self.transition(with: view, duration: duration, options: options, animations: animations, completion: completion)
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
