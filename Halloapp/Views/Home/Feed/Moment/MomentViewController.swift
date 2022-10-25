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

protocol MomentViewControllerDelegate: MomentViewDelegate, UserActionHandler {

}

class MomentViewController: UIViewController, UIViewControllerMediaSaving {

    private(set) var post: FeedPost
    let unlockingPost: FeedPost?

    private let shouldFetchOtherMoments: Bool
    private var otherMoments: [FeedPost] = []

    weak var transitionStartView: MomentView?

    /// For operations such as expiration and taking a screenshot, we want to make sure the moment is visible.
    private var isReadyForSensitiveOperations: Bool {
        // not the user's own moment
        post.userID != MainAppContext.shared.userData.userId &&
        // the image is loaded
        post.feedMedia.allSatisfy { $0.isMediaAvailable } &&
        // no blur covering the image
        momentView.state == .unlocked &&
        // if this is an unlocking context, make sure the user's moment has been uploaded
        unlockingPost?.status ?? .sent == .sent
    }

    private(set) lazy var momentView: MomentView = {
        let view = MomentView(configuration: .fullscreen)
        view.configure(with: post)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.overrideUserInterfaceStyle = UITraitCollection.current.userInterfaceStyle
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
    
    fileprivate lazy var headerView: FeedItemHeaderView = {
        let view = FeedItemHeaderView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.avatarViewButton.overrideUserInterfaceStyle = UITraitCollection.current.userInterfaceStyle
        view.configure(with: post, contentWidth: view.bounds.width, showGroupName: false)
        view.showUserAction = { [weak self] in self?.showUser() }
        view.moreMenuContent = { [weak self] in self?.configureMoreMenu() ?? [] }
        return view
    }()

    private lazy var facePileView: FacePileView = {
        let view = FacePileView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.avatarViews.forEach { $0.borderColor = view.backgroundColor }
        view.addTarget(self, action: #selector(facePileTapped), for: .touchUpInside)
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

    private var transitionSnapshot: UIView?
    private lazy var transitionAnimator: TransitionAnimator = {
        let animator = TransitionAnimator(referenceView: viewForAnimation())
        return animator
    }()

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
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
        modalPresentationCapturesStatusBarAppearance = true
        transitioningDelegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("MomentViewController coder init not implemented...")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        DDLogInfo("MomentViewController/viewDidLoad/post: \(post.id); unlocking post: \(unlockingPost?.id ?? "nil")")
        view.overrideUserInterfaceStyle = .dark
        contentInputView.overrideUserInterfaceStyle = .dark

        view.backgroundColor = .momentFullscreenBg.withAlphaComponent(0.99)
        contentInputView.backgroundColor = view.backgroundColor

        view.addSubview(headerView)
        view.addSubview(momentView)
        view.addSubview(facePileView)
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

            facePileView.topAnchor.constraint(equalTo: momentView.bottomAnchor, constant: 15),
            facePileView.trailingAnchor.constraint(equalTo: momentView.trailingAnchor, constant: -15),
            facePileView.leadingAnchor.constraint(greaterThanOrEqualTo: momentView.leadingAnchor),

            backButton.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 5),
        ])

        installUnlockingPost()

        view.addGestureRecognizer(dismissTapGesture)
        momentView.addGestureRecognizer(dismissPanGesture)
        view.addGestureRecognizer(dismissKeyboardGesture)

        facePileView.configure(with: post)

        let hideUtilityViews = post.userID != MainAppContext.shared.userData.userId
        facePileView.isHidden = hideUtilityViews
        headerView.moreButton.isHidden = hideUtilityViews

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
        subscribeToSeenStatus()

        if shouldFetchOtherMoments {
            fetchOtherMoments()
            DDLogInfo("MomentViewController/viewDidAppear/loaded \(otherMoments.count) other moments")

            if !otherMoments.isEmpty, !Self.hasSwipedToNext {
                installFTUX()
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            momentView.overrideUserInterfaceStyle = traitCollection.userInterfaceStyle
        }
    }

    private func fetchOtherMoments() {
        func isUnseen(_ post: FeedPost) -> Bool {
            !(post.status == .seen || post.status == .seenSending)
        }

        var otherMoments = MainAppContext.shared.feedData.fetchAllValidMoments()
            .sorted(by: {
                // opposite ordering of the stack since popping from the end is more efficient
                if $0.userID == MainAppContext.shared.userData.userId {
                    return false
                } else if isUnseen($0), !isUnseen($1) {
                    return false
                } else if !isUnseen($0), isUnseen($1) {
                    return true
                } else {
                    return $0.timestamp < $1.timestamp
                }
            })

        if let target = otherMoments.firstIndex(where: { $0.id == post.id }) {
            let startIndex = otherMoments.startIndex
            let endIndex = otherMoments.endIndex
            let index = otherMoments.index(startIndex, offsetBy: target, limitedBy: endIndex) ?? endIndex
            let slice = otherMoments[..<index]

            otherMoments.removeSubrange(..<index)
            otherMoments.insert(contentsOf: slice, at: otherMoments.endIndex)
        }

        self.otherMoments = otherMoments.filter { $0.id != post.id }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        toast?.hide()
        refreshAccessoryView(show: false)
    }

    private func subscribeToSeenStatus() {
        DDLogInfo("MomentViewController/subscribeToSeenStatus")

        mediaAvailableCancellable = hasSeenPublisher
            .sink(receiveCompletion: { [weak self] _ in
                DDLogInfo("MomentViewController/hasSeenCancellable/completion [\(String(describing: self?.post.id))]")
                self?.sendSeenReceiptIfReady()
                self?.refreshAccessoryView()
            }, receiveValue: {

            })
    }

    /// Publishes only once when all media is ready and the unlocking post (if there is one) has been sent.
    private var hasSeenPublisher: AnyPublisher<Void, Never> {
        let imagePublishers: [AnyPublisher<Void, Never>] = post.feedMedia
            .map {
                $0.imagePublisher
                    .first { $0 != nil }
                    .map { _ in }
                    .eraseToAnyPublisher()
            }

        let allImagesReadyPublisher = Publishers.MergeMany(imagePublishers)
            .collect()
            .map { _ in }
            .eraseToAnyPublisher()

        let unlockingPostStatusPublisher = unlockingPost?.publisher(for: \.statusValue)
            .compactMap { FeedPost.Status(rawValue: $0) }
            .first { $0 == .sent }
            .map { _ in }
            .eraseToAnyPublisher() ?? Just(()).eraseToAnyPublisher()

        let momentViewIsUnlockedPublisher = momentView.statePublisher
            .first { $0 == .unlocked }
            .map { _ in }
            .eraseToAnyPublisher()

        return Publishers.Merge3(allImagesReadyPublisher, unlockingPostStatusPublisher, momentViewIsUnlockedPublisher)
            .eraseToAnyPublisher()
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
        guard let unlockingPost else {
            return
        }

        view.addSubview(unlockingMomentView)
        unlockingMomentView.configure(with: unlockingPost)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: unlockingMomentView.bottomAnchor, constant: 7),
            unlockingMomentView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -15),
            unlockingMomentView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 5),
            unlockingMomentView.widthAnchor.constraint(equalToConstant: 75),
        ])

        if unlockingPost.id == post.id {
            // hide the unlocking post if the user started out on their own post
            unlockingMomentView.alpha = 0
        }
    }

    private func forward(action: UserAction) {
        presentingViewController?.dismiss(animated: true) { [delegate] in
            delegate?.handle(action: action)
        }
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
    private func facePileTapped(_ sender: UIControl) {
        let vc = PostDashboardViewController(feedPost: post)
        let nc = UINavigationController(rootViewController: vc)

        vc.delegate = self
        nc.overrideUserInterfaceStyle = .dark

        present(nc, animated: true)
    }

    @objc
    private func keyboardDismissSwipe(_ gesture: UISwipeGestureRecognizer) {
        if contentInputView.textView.isFirstResponder {
            contentInputView.textView.resignFirstResponder()
        }
    }

    private func showUser() {
        forward(action: .viewProfile(post.userID))
    }

    private func sendSeenReceiptIfReady() {
        guard isReadyForSensitiveOperations else {
            DDLogInfo("MomentViewController/sendSeenReceiptIfReady/failed guard")
            return
        }

        DDLogInfo("MomentViewController/sendSeenReceiptIfReady/passed guard")
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

    @HAMenuContentBuilder
    private func configureMoreMenu() -> HAMenu.Content {
        HAMenu {
            if post.hasSaveablePostMedia, post.canSaveMedia {
                let title = Localizations.buttonSave
                HAMenuButton(title: title, image: UIImage(systemName: "photo.on.rectangle.angled")) { [weak self] in
                    await self?.handleSaveMomentMedia()
                }
            }
        }
        .displayInline()

        HAMenu {
            if post.canDeletePost {
                let title = Localizations.deleteMomentButtonTitle
                HAMenuButton(title: title, image: UIImage(systemName: "trash")) { [weak self] in
                    self?.handleDeleteMoment()
                }
                .destructive()
            }
        }
        .displayInline()
    }

    private func handleSaveMomentMedia() async {
        await saveMedia(source: .post(post.id)) { [post] in
            guard let expected = post.media?.count else {
                return []
            }

            let media = MainAppContext.shared.feedData.media(for: post)
                .compactMap {
                    if $0.isMediaAvailable, let url = $0.fileURL {
                        return ($0.type, url)
                    }

                    return nil
                }

            return media.count == expected ? media : []
        }
    }

    private func handleDeleteMoment() {
        let title = Localizations.deleteMomentButtonTitle
        let message = Localizations.deleteMomentConfirmationPrompt

        let alert = UIAlertController(title: nil,
                                    message: message,
                             preferredStyle: .actionSheet)

        alert.addAction(.init(title: title, style: .destructive) { [weak self] _ in
            self?.deleteMoment()
        })

        alert.addAction(.init(title: Localizations.buttonCancel, style: .cancel))

        present(alert, animated: true)
    }

    private func deleteMoment() {
        MainAppContext.shared.feedData.retract(post: post) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .failure(_):
                    let alert = UIAlertController(title: Localizations.deletePostError,
                                                message: nil,
                                         preferredStyle: .alert)

                    alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: nil))
                    self?.present(alert, animated: true, completion: nil)

                default:
                    self?.presentingViewController?.dismiss(animated: true)
                }
            }
        }
    }
}

// MARK: - PostDashboardViewController delegate methods

extension MomentViewController: PostDashboardViewControllerDelegate, UserActionHandler {

    func postDashboardViewController(didRequestPerformAction action: PostDashboardViewController.UserAction) {
        switch action {
        case .profile(let id):
            forward(action: .viewProfile(id))
        case .message(let id, _):
            forward(action: .message(id))
        case .blacklist(let id):
            handle(action: .block(id))
        }
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

        default:
            return true
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        switch gestureRecognizer {
        case is UITapGestureRecognizer where contentInputView.textView.isFirstResponder:
            contentInputView.textView.resignFirstResponder()
            return false

        case dismissPanGesture where contentInputView.textView.isFirstResponder:
            return false

        case dismissTapGesture:
            return view.hitTest(gestureRecognizer.location(in: view), with: nil) === view

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
            setupAndAnimate(toNext: moment)
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

    private func animate(toNext moment: FeedPost, completion: @escaping () -> ()) {
        guard let snapshot = transitionSnapshot else {
            DDLogError("MomentViewController/animateToNext/no snapshot present")
            return
        }

        let name = MainAppContext.shared.contactStore.firstName(for: moment.userID,
                                                                 in: MainAppContext.shared.contactStore.viewContext)
        let firstDuration = 0.25
        let firstDelay = 0.15
        let secondDuration = 0.175
        let secondDelay = (firstDuration + firstDelay) * 0.5

        momentView.alpha = 0
        momentView.isHidden = false
        momentView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)

        UIView.animate(withDuration: firstDuration, delay: firstDelay, options: [.curveEaseOut]) {
            self.momentView.alpha = 1
            self.momentView.transform = .identity
            self.unlockingMomentView.alpha = 1
            self.headerView.moreButton.alpha = 0
            self.facePileView.alpha = 0
            snapshot.alpha = 0

            if self.unlockingPost != nil {
                self.unlockingMomentView.alpha = 1
            }

        } completion: { _ in
            self.headerView.moreButton.alpha = 1
            self.facePileView.alpha = 1
            self.headerView.moreButton.isHidden = true
            self.facePileView.isHidden = true
        }

        UIView.transition(with: self.headerView, duration: secondDuration, delay: secondDelay, options: [.transitionCrossDissolve]) {
            self.headerView.configure(with: moment, contentWidth: self.view.bounds.width, showGroupName: false)
            self.headerView.alpha = 1
            self.contentInputView.placeholderText = String(format: Localizations.privateReplyPlaceholder, name)
        } completion: { _ in
            self.cleanUpAfterAnimation()
            completion()
        }
    }

    private func setupAndAnimate(toNext moment: FeedPost) {
        if ftuxLabel != nil {
            removeFTUX()
        }

        post = moment
        momentView.configure(with: moment)

        contentInputView.reset()

        animate(toNext: moment) { [weak self, post] in
            DDLogInfo("MomentViewController/animateToNext completion/transitioned to \(post.id)")

            self?.isAnimatingToNextMoment = false
            // this will expire the new moment when ready
            self?.subscribeToSeenStatus()
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
            let momentFooterView = momentView.footerLabel.superview,
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
            self.momentView.footerLabel.alpha = 0
        }
    }

    private func removeFTUX() {
        guard let ftuxLabel = ftuxLabel else {
            return
        }

        momentView.footerLabel.alpha = 1
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

    private struct TransitionViews {
        let feedSnapshot: UIView
        let momentView: MomentView
        let finalMomentViewSnapshot: UIView
        let avatarSnapshot: UIView?
    }

    private weak var startView: MomentView?

    init(startView: MomentView? = nil) {
        super.init()
        self.startView = startView
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.45
    }

    private func transitionSnapshots(_ context: UIViewControllerContextTransitioning) -> TransitionViews? {
        guard
            let from = context.viewController(forKey: .from),
            let to = context.viewController(forKey: .to) as? MomentViewController,
            let currentFrom = from.view.snapshotView(afterScreenUpdates: false),
            let startView = startView,
            let post = startView.feedPost
        else {
            return nil
        }

        context.containerView.alpha = 0
        context.containerView.addSubview(to.view)
        to.view.layoutIfNeeded()

        guard let finalMomentSnapshot = to.momentView.snapshotView(afterScreenUpdates: true) else {
            return nil
        }

        to.view.alpha = 0
        context.containerView.alpha = 1

        // we want a snapshot of the feed with the above cell hidden
        context.containerView.addSubview(currentFrom)
        startView.alpha = 0
        let feedSnapshot = from.view.snapshotView(afterScreenUpdates: true)
        startView.alpha = 1
        currentFrom.removeFromSuperview()

        guard let feedSnapshot else {
            return nil
        }

        let momentViewForAnimation = MomentView(configuration: .stacked)
        momentViewForAnimation.configure(with: post)

        var avatarSnapshot: UIView?
        if case .unlocked = momentViewForAnimation.state, let snapshot = startView.smallAvatarView.snapshotView(afterScreenUpdates: false) {
            avatarSnapshot = snapshot
        }

        let views = TransitionViews(feedSnapshot: feedSnapshot,
                                      momentView: momentViewForAnimation,
                         finalMomentViewSnapshot: finalMomentSnapshot,
                                  avatarSnapshot: avatarSnapshot)

        context.containerView.insertSubview(views.feedSnapshot, belowSubview: to.view)
        context.containerView.addSubview(views.finalMomentViewSnapshot)
        context.containerView.addSubview(views.momentView)

        // position the view used for the transition in the same spot as the feed item
        let center = context.containerView.convert(startView.center, from: startView.superview)
        views.momentView.frame.size = startView.bounds.size
        views.momentView.center = center
        views.momentView.layer.shadowOpacity = 0
        views.momentView.layoutIfNeeded()
        views.momentView.transform = CGAffineTransform(rotationAngle: startView.transform.rotationAngle)

        // shrink the snapshot of the final view to the size of the feed item
        // we use this snapshot so that we can gracefully animate the change in font size
        views.finalMomentViewSnapshot.frame = views.momentView.frame
        views.finalMomentViewSnapshot.transform = views.momentView.transform

        if let avatar = views.avatarSnapshot {
            avatar.center = context.containerView.convert(startView.smallAvatarView.center, from: startView.smallAvatarView.superview)
            context.containerView.addSubview(avatar)
        }

        return views
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard
            let to = transitionContext.viewController(forKey: .to) as? MomentViewController,
            let transitionViews = transitionSnapshots(transitionContext)
        else {
            return performSimpleTransition(using: transitionContext)
        }

        transitionViews.momentView.smallAvatarView.alpha = 0
        to.headerView.avatarViewButton.isHidden = transitionViews.avatarSnapshot != nil
        to.momentView.isHidden = true

        UIView.animate(withDuration: transitionDuration(using: nil), delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.75, options: .curveEaseOut) {
            to.view.alpha = 1

            transitionViews.momentView.transform = .identity
            transitionViews.momentView.frame = to.momentView.frame
            transitionViews.momentView.layoutIfNeeded()

            transitionViews.momentView.setState(to.momentView.state)

            transitionViews.momentView.backgroundColor = .clear
            transitionViews.momentView.footerLabel.alpha = 0

            transitionViews.finalMomentViewSnapshot.transform = .identity
            transitionViews.finalMomentViewSnapshot.frame = to.momentView.frame

            let center = transitionContext.containerView.convert(to.headerView.avatarViewButton.center, from: to.headerView.avatarViewButton.superview)
            transitionViews.avatarSnapshot?.center = center

            transitionViews.momentView.additionalAnimationsForTransition()
        } completion: { _ in
            to.momentView.isHidden = false
            transitionViews.momentView.isHidden = true
            transitionViews.finalMomentViewSnapshot.isHidden = true
            to.headerView.avatarViewButton.isHidden = false

            transitionViews.momentView.removeFromSuperview()
            transitionViews.feedSnapshot.removeFromSuperview()
            transitionViews.finalMomentViewSnapshot.removeFromSuperview()
            transitionViews.avatarSnapshot?.removeFromSuperview()

            transitionContext.completeTransition(true)
        }
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
