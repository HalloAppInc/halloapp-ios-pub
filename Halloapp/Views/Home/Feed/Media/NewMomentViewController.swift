//
//  NewMomentViewController.swift
//  HalloApp
//
//  Created by Tanveer on 6/12/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Core
import CoreCommon
import CocoaLumberjackSwift
import Combine

protocol NewMomentViewControllerDelegate: MomentViewControllerDelegate {
    func newMomentViewControllerDidPost(_ viewController: NewMomentViewController)
}

/// Handles the creation and posting of a moment, regardless of context.
final class NewMomentViewController: UIViewController {

    enum Context { case normal, unlock(FeedPost) }
    private enum State { case camera, indeterminate, composer }

    private var state: State = .camera
    let context: Context
    var onPost: (() -> Void)?

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    /// Displayed above the camera.
    private var prompt: String {
        switch context {
        case .normal:
            return Localizations.newMomentCameraSubtitle
        case let .unlock(post):
            let name = MainAppContext.shared.contactStore.firstName(for: post.userID,
                                                                     in: MainAppContext.shared.contactStore.viewContext)
            return String(format: Localizations.newMomentCameraUnlockSubtitle, name)
        }
    }

    /// - note: We keep a reference to the view controller itself so that we can easily get
    ///         layout values when performing the animation.
    private lazy var cameraController: NewCameraViewController = {
        let options: NewCameraViewController.Options

#if targetEnvironment(simulator)
        options = [.moment, .showLibraryButton]
#else
        options = [.moment]
#endif

        let vc = NewCameraViewController(style: .moment, options: options)
        vc.delegate = self
        vc.title = Localizations.newMomentTitle
        vc.subtitle = prompt
        return vc
    }()

    private lazy var cameraNavigationController: UINavigationController = {
        let nc = UINavigationController(rootViewController: cameraController)
        return nc
    }()

    private lazy var composerController: MomentComposerViewController = {
        let vc = MomentComposerViewController(context: context)
        vc.onPost = { [weak self] in self?.completeCompose() }
        vc.onCancel = { [weak self] in self?.dismissComposer() }
        return vc
    }()

    private lazy var composerNavigationController: UINavigationController = {
        let nc = UINavigationController(rootViewController: composerController)
        return nc
    }()

    private var sendButtonSnapshot: UIView?
    /// Used to discard invalid capture results on devices that use delayed capture.
    private var shouldDiscardIncomingCaptureResult = false

    /// Used to wait for `PendingMedia`s `ready` property before showing the composer.
    private var mediaLoader: AnyCancellable?
    /// Used when `context` is `.unlock` since the creation of the eventual `FeedPost` is asynchronous.
    private var unlockCancellable: AnyCancellable?
    private var startUnlockTransitionCancellable: AnyCancellable?

    /// The overlay that is above the camera when the user first attempts to unlock a moment.
    private var unlockingExplainerOverlay: UIView?

    weak var delegate: NewMomentViewControllerDelegate?

    init(context: Context = .normal) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
        view.backgroundColor = .black

        overrideUserInterfaceStyle = .dark

        modalPresentationStyle = .custom
        modalTransitionStyle = .coverVertical

        definesPresentationContext = true
        modalPresentationCapturesStatusBarAppearance = true
    }

    required init?(coder: NSCoder) {
        fatalError("NewMomentViewController coder init not implemented...")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        DDLogInfo("NewMomentViewController/viewDidLoad")

        contain(cameraNavigationController)
        view.insertSubview(composerNavigationController.view, at: 0)
        contain(composerNavigationController)

        let appearance = UINavigationBarAppearance()
        appearance.backgroundColor = .black
        appearance.shadowColor = nil
        appearance.titleTextAttributes = [.font: UIFont.gothamFont(ofFixedSize: 16, weight: .medium)]
        cameraNavigationController.navigationBar.standardAppearance = appearance
        cameraNavigationController.navigationBar.scrollEdgeAppearance = appearance
        composerNavigationController.navigationBar.standardAppearance = appearance
        composerNavigationController.navigationBar.scrollEdgeAppearance = appearance

        NSLayoutConstraint.activate([
            composerController.background.topAnchor.constraint(equalTo: cameraController.background.topAnchor),
            composerController.background.heightAnchor.constraint(equalTo: cameraController.background.heightAnchor),
        ])

        if case .unlock(_) = context, !Self.hasDisplayedUnlockingExplainer {
            setupUnlockingExplainer()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !Self.hasDisplayedMomentsExplainer {
            present(MomentsExplainerViewController(), animated: true) {
                Self.hasDisplayedMomentsExplainer = true
            }
        }
    }

    @objc
    private func cameraDismiss(_ button: UIButton) {
        dismiss(animated: true)
    }

    /// After the photo has been delivered by the camera. Displays the composer with the enabled send button.
    private func displayComposer(with media: PendingMedia) {
        mediaLoader = nil
        composerController.configure(with: media)

        UIView.transition(with: view, duration: 0.3, options: [.transitionCrossDissolve]) {
            self.cameraNavigationController.view.alpha = 0
            self.sendButtonSnapshot?.alpha = 0
        } completion: { _ in
            self.sendButtonSnapshot?.removeFromSuperview()
            self.sendButtonSnapshot = nil

            self.view.sendSubviewToBack(self.cameraNavigationController.view)
            self.cameraNavigationController.view.alpha = 1
            self.cameraController.pause()
        }
    }

    private func displayComposer() {
        guard
            state != .composer,
            let snapshot = view.snapshotView(afterScreenUpdates: false)
        else {
            return
        }

        state = .composer
        view.addSubview(snapshot)
        view.sendSubviewToBack(cameraNavigationController.view)

        UIView.transition(with: view, duration: 0.15, options: [.transitionCrossDissolve, .beginFromCurrentState]) {
            self.sendButtonSnapshot?.alpha = 0
            snapshot.alpha = 0

        } completion: { _ in
            self.sendButtonSnapshot?.removeFromSuperview()
            self.sendButtonSnapshot = nil

            snapshot.removeFromSuperview()
        }
    }

    /// After the user takes the photo. Displays the disabled send button while the camera's viewfinder is still active.
    private func displayIntermediateState() {
        guard
            state != .indeterminate,
            let sendButtonSnapshot = composerController.sendButton.snapshotView(afterScreenUpdates: true)
        else {
            DDLogError("NewMomentViewController/displayIntermediateState/unable to create send button snapshot")
            return
        }

        state = .indeterminate

        sendButtonSnapshot.center = view.convert(composerController.sendButton.center, from: composerController.sendButton.superview)
        sendButtonSnapshot.transform = .identity.scaledBy(x: 0.25, y: 0.25)
        sendButtonSnapshot.alpha = 0

        view.addSubview(sendButtonSnapshot)
        cameraController.hideControls = true
        self.sendButtonSnapshot = sendButtonSnapshot

        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.9) {
            sendButtonSnapshot.alpha = 1
            sendButtonSnapshot.transform = .identity
        }
    }

    /// Dismisses the composer and goes back to the camera.
    private func dismissComposer() {
        // go back to the camera
        state = .camera
        shouldDiscardIncomingCaptureResult = true
        cameraController.hideControls = false
        cameraController.resume()

        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0) {
            self.composerNavigationController.view.alpha = 0
            self.composerController.sendButton.transform = .identity.scaledBy(x: 0.25, y: 0.25)
        } completion: { _ in
            self.view.sendSubviewToBack(self.composerNavigationController.view)
            self.composerNavigationController.view.alpha = 1
            self.composerController.sendButton.transform = .identity
        }
    }

    private func completeCompose() {
        guard case let .unlock(post) = context, let feedData = MainAppContext.shared.feedData else {
            delegate?.newMomentViewControllerDidPost(self)
            return dismiss(animated: true)
        }

        DDLogInfo("NewMomentViewController/completeCompose/creating unlock cancellable")

        unlockCancellable = feedData.validMoment
            .compactMap { $0 }
            .first()
            .sink { [weak self] moment in
                DDLogInfo("NewMomentViewController/completeCompose/received valid moment for unlock")
                self?.prepareForUnlockTransition(post: post, unlockingPost: moment)
            }
    }

    private func prepareForUnlockTransition(post: FeedPost, unlockingPost: FeedPost) {
        let vc = MomentViewController(post: post, unlockingPost: unlockingPost)
        // force the view to load without adding it to the hierarchy since we don't want
        // viewDidAppear to be called yet
        vc.loadViewIfNeeded()

        // want to ensure that the the image view is populated before taking the snapshot
        DDLogInfo("NewMomentViewController/completeCompose/creating transition cancellable")
        startUnlockTransitionCancellable = vc.unlockingMomentView.imageViewsAreReadyPublisher
            .sink(receiveCompletion: { [weak self] _ in
                DDLogInfo("NewMomentViewController/completeCompose/starting transition via cancellable")
                self?.startUnlockTransitionCancellable = nil
                self?.performUnlockTransition(for: vc)
            }, receiveValue: {

            })

        delegate?.newMomentViewControllerDidPost(self)
    }

    private func performUnlockTransition(for momentViewController: MomentViewController) {
        view.insertSubview(momentViewController.view, at: 0)
        contain(momentViewController)
        guard
            let composeSnapshot = composerController.background.snapshotView(afterScreenUpdates: true),
            let unlockSnapshot = momentViewController.unlockingMomentView.snapshotView(afterScreenUpdates: true)
        else {
            return dismiss(animated: true)
        }

        DDLogInfo("NewMomentViewController/performUnlockTransition")

        let finalCenter = view.convert(momentViewController.unlockingMomentView.center, from: momentViewController.unlockingMomentView.superview)
        let finalSize = momentViewController.unlockingMomentView.frame.size

        composeSnapshot.center = view.convert(composerController.background.center, from: composerController.background.superview)
        view.addSubview(composeSnapshot)
        // align the two snapshots
        unlockSnapshot.frame = composeSnapshot.frame
        view.insertSubview(unlockSnapshot, belowSubview: composeSnapshot)

        momentViewController.view.alpha = 0
        momentViewController.unlockingMomentView.alpha = 0
        composerNavigationController.view.removeFromSuperview()
        cameraNavigationController.view.removeFromSuperview()

        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.5, options: [.curveEaseOut]) {
            composeSnapshot.frame.size = finalSize
            composeSnapshot.center = finalCenter

            unlockSnapshot.frame = composeSnapshot.frame
            composeSnapshot.alpha = 0

            self.composerController.sendButton.transform = .identity.scaledBy(x: 0.1, y: 0.1)
            self.composerController.sendButton.alpha = 0

        } completion: { _ in
            momentViewController.unlockingMomentView.alpha = 1
            composeSnapshot.removeFromSuperview()
            // transition the snapshot to the actual view gracefully
            UIView.transition(with: self.view, duration: 0.25, options: [.transitionCrossDissolve]) {
                unlockSnapshot.alpha = 0
            } completion: { _ in
                unlockSnapshot.removeFromSuperview()
            }

            self.transitioningDelegate = momentViewController
            momentViewController.becomeFirstResponder()
            momentViewController.delegate = self.delegate
            DDLogInfo("NewMomentViewController/performUnlockTransition/completed transition")
        }

        UIView.animate(withDuration: 0.3, delay: 0.2, options: [.curveEaseInOut]) {
            momentViewController.view.alpha = 1
        }
    }

    /// Helper for adding a view controller as a child.
    private func contain(_ viewController: UIViewController) {
        if viewController.view.superview !== view {
            view.addSubview(viewController.view)
        }

        viewController.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(viewController)
        viewController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            viewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            viewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            viewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            viewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // ensures that everything gets aligned correctly when using snapshots
        viewController.view.layoutIfNeeded()
    }
}

// MARK: - CameraViewControllerDelegate methods

extension NewMomentViewController: CameraViewControllerDelegate {

    func cameraViewController(_ viewController: NewCameraViewController, didCapture results: [CaptureResult], isFinished: Bool) {
        if shouldDiscardIncomingCaptureResult {
            // this result is from a capture the user backed out of; discard the result
            return
        }

        composerController.configure(with: results, animateTrailing: results.count != 2)
        displayComposer()

        if isFinished {
            composerController.sendButton.isEnabled = true
            cameraController.pause()
        }
    }

    func cameraViewControllerDidReleaseShutter(_ viewController: NewCameraViewController) {
        shouldDiscardIncomingCaptureResult = false
        displayIntermediateState()
    }

    func cameraViewController(_ viewController: NewCameraViewController, didSelect media: PendingMedia) {
        displayIntermediateState()

        mediaLoader = media.ready
            .first { $0 }
            .sink { [weak self] image in
                self?.displayComposer(with: media)
                self?.mediaLoader = nil
            }
    }

    func cameraViewController(_ viewController: NewCameraViewController, didRecordVideoTo url: URL) {

    }
}

// MARK: - FTUX methods

extension NewMomentViewController {
    /// Indicates whether we have shown the bottom sheet that explains the feature.
    /// This is shown when the user opens the moments camera for the first time.
    @UserDefault(key: "shown.moment.explainer", defaultValue: false)
    private static var hasDisplayedMomentsExplainer: Bool

    /// Shown as a blurred overlay above the camera. This is shown when the user attempts to
    /// unlock someone else's moment for the first time.
    @UserDefault(key: "shown.moment.unlock.explainer", defaultValue: false)
    private static var hasDisplayedUnlockingExplainer: Bool

    private func setupUnlockingExplainer() {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .prominent))
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.layer.masksToBounds = true
        blur.layer.cornerCurve = .continuous
        blur.layer.cornerRadius = NewCameraViewController.Layout.innerRadius(for: .moment)

        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = prompt

        let button = CapsuleButton()
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 30, bottom: 10, right: 30)
        button.setBackgroundColor(.systemBlue, for: .normal)
        button.setTitle(Localizations.buttonOK, for: .normal)

        let stack = UIStackView(arrangedSubviews: [label, button])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 25, left: 35, bottom: 15, right: 35)
        stack.spacing = 20

        cameraController.view.addSubview(blur)
        blur.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: cameraController.primaryViewfinder.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: cameraController.primaryViewfinder.trailingAnchor),
            blur.topAnchor.constraint(equalTo: cameraController.primaryViewfinder.topAnchor),
            blur.bottomAnchor.constraint(equalTo: cameraController.primaryViewfinder.bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: blur.contentView.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: blur.contentView.bottomAnchor),
            stack.centerYAnchor.constraint(equalTo: blur.contentView.centerYAnchor)
        ])

        cameraController.isEnabled = false
        cameraController.subtitleLabel.isHidden = true
        unlockingExplainerOverlay = blur
        button.addTarget(self, action: #selector(dismissUnlockingExplainer), for: .touchUpInside)
    }

    @objc
    private func dismissUnlockingExplainer(_ sender: UIButton) {
        cameraController.isEnabled = true
        cameraController.subtitleLabel.isHidden = false
        unlockingExplainerOverlay?.removeFromSuperview()

        Self.hasDisplayedUnlockingExplainer = true
    }
}

// MARK: - localization

extension Localizations {
    static var newMomentTitle: String {
        NSLocalizedString("composer.moment.post.title",
                   value: "New Moment",
                 comment: "Composer New Moment Post title.")
    }

    static var newMomentCameraSubtitle: String {
        NSLocalizedString("camera.moment.subtitle",
                   value: "Moments disappear after 24 hours",
                 comment: "Text shown on the camera screen when composing a new moment.")
    }

    static var newMomentCameraUnlockSubtitle: String {
        NSLocalizedString("camera.moment.unlock.subtitle",
                   value: "To see %@’s moment, share your own",
                 comment: "Text shown on the camera screen when composing a new moment to unlock someone else's moment.")
    }
}
