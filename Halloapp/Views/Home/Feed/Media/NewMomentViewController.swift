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

enum MomentContext {
    case normal
    case unlock(FeedPost)
}

/// Handles the creation and posting of a moment, regardless of context.
final class NewMomentViewController: UIViewController {

    let context: MomentContext

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
        let vc = NewCameraViewController(style: .moment)
        vc.title = Localizations.newMomentTitle
        vc.onShutterRelease = { [weak self] in self?.displayIntermediateState() }
        vc.onPhotoCapture = { [weak self] in self?.displayComposer(with: $0) }
        vc.subtitle = prompt
        return vc
    }()

    private lazy var cameraNavigationController: UINavigationController = {
        let nc = UINavigationController(rootViewController: cameraController)
        return nc
    }()

    private var sendButtonSnapshot: UIView?
    private var composerController: MomentComposerViewController?
    private var composerNavigationController: UIViewController?

    private var startUnlockTransitionCancellable: AnyCancellable?

    init(context: MomentContext = .normal) {
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

        if case .unlock(_) = context, !hasDisplayedUnlockingExplainer {
            setupUnlockingExplainer()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !hasDisplayedMomentsExplainer {
            present(MomentsExplainerViewController(), animated: true) {
                self.hasDisplayedMomentsExplainer = true
            }
        }
    }

    @objc
    private func cameraDismiss(_ button: UIButton) {
        dismiss(animated: true)
    }

    /// After the photo has been delivered by the camera. Displays the composer with the enabled send button.
    private func displayComposer(with image: UIImage) {
        guard let composer = composerController else {
            DDLogError("NewMomentViewController/displayComposer/composer does not exist")
            return
        }

        composer.image = image
        composer.onPost = { [weak self] in
            self?.completeCompose()
        }

        composer.onCancel = { [weak self] in
            self?.dismissComposer()
        }

        UIView.transition(with: view, duration: 0.3) {
            self.cameraNavigationController.view.alpha = 0
            self.sendButtonSnapshot?.alpha = 0
        } completion: { _ in
            self.sendButtonSnapshot?.removeFromSuperview()
            self.sendButtonSnapshot = nil
            self.cameraNavigationController.view.removeFromSuperview()
            self.cameraNavigationController.view.alpha = 1
        }
    }

    /// After the user takes the photo. Displays the disabled send button while the camera's viewfinder is still active.
    private func displayIntermediateState() {
        let composer = MomentComposerViewController(context: context)
        let composerNavigationController = UINavigationController(rootViewController: composer)

        view.insertSubview(composerNavigationController.view, at: 0)
        contain(composerNavigationController)
        composer.momentCardTopConstraint.constant = cameraController.background.frame.minY
        composer.momentCardHeightConstraint.constant = cameraController.background.bounds.height

        guard let sendButtonSnapshot = composer.sendButton.snapshotView(afterScreenUpdates: true) else {
            DDLogError("NewMomentViewController/displayIntermediateState/unable to create send button snapshot")
            return composerNavigationController.view.removeFromSuperview()
        }

        self.composerNavigationController = composerNavigationController
        self.composerController = composer

        sendButtonSnapshot.center = view.convert(composer.sendButton.center, from: composer.sendButton.superview)
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
        view.insertSubview(cameraNavigationController.view, at: 0)
        contain(cameraNavigationController)
        cameraController.hideControls = false

        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0) {
            self.composerNavigationController?.view.alpha = 0
            self.composerController?.sendButton.transform = .identity.scaledBy(x: 0.25, y: 0.25)
        } completion: { _ in
            self.composerNavigationController?.view.removeFromSuperview()
            self.composerNavigationController = nil
            self.composerController = nil
        }
    }

    private func completeCompose() {
        guard
            case let .unlock(post) = context,
            let feedData = MainAppContext.shared.feedData,
            let latest = feedData.fetchLatestMoment(using: feedData.viewContext)
        else {
            return dismiss(animated: true)
        }

        let vc = MomentViewController(post: post, unlockingPost: latest)
        // force the view to load without adding it to the hierarchy since we don't want
        // viewDidAppear to be called yet
        vc.loadViewIfNeeded()

        // want to ensure that the the image view is populated before taking the snapshot
        if vc.unlockingMomentView.imageView.image != nil {
            performUnlockTransition(for: vc)
        } else {
            DDLogInfo("NewMomentViewController/completeCompose/creating transition cancellable")
            startUnlockTransitionCancellable = vc.unlockingMomentView.imageView.publisher(for: \.image)
                .compactMap { $0 }
                .sink { [weak self] _ in
                    DDLogInfo("NewMomentViewController/completeCompose/starting transition via cancellable")
                    self?.startUnlockTransitionCancellable = nil
                    self?.performUnlockTransition(for: vc)
                }
        }
    }

    private func performUnlockTransition(for momentViewController: MomentViewController) {
        view.insertSubview(momentViewController.view, at: 0)
        contain(momentViewController)
        guard
            let composer = composerController,
            let composeSnapshot = composer.container.snapshotView(afterScreenUpdates: true),
            let unlockSnapshot = momentViewController.unlockingMomentView.snapshotView(afterScreenUpdates: true)
        else {
            return dismiss(animated: true)
        }

        DDLogInfo("NewMomentViewController/performUnlockTransition")

        let finalCenter = view.convert(momentViewController.unlockingMomentView.center, from: momentViewController.unlockingMomentView.superview)
        let finalSize = momentViewController.unlockingMomentView.frame.size

        composeSnapshot.center = view.convert(composer.container.center, from: composer.container.superview)
        view.addSubview(composeSnapshot)
        // align the two snapshots
        unlockSnapshot.frame = composeSnapshot.frame
        view.insertSubview(unlockSnapshot, belowSubview: composeSnapshot)

        momentViewController.view.alpha = 0
        momentViewController.unlockingMomentView.alpha = 0
        composerNavigationController?.view.removeFromSuperview()

        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.5, options: [.curveEaseOut]) {
            composeSnapshot.frame.size = finalSize
            composeSnapshot.center = finalCenter

            unlockSnapshot.frame = composeSnapshot.frame
            composeSnapshot.alpha = 0

            composer.sendButton.transform = .identity.scaledBy(x: 0.1, y: 0.1)
            composer.sendButton.alpha = 0

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

    /// The overlay that is above the camera when the user first attempts to unlock a moment.
    private var unlockingExplainerOverlay: UIView?

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
            blur.leadingAnchor.constraint(equalTo: cameraController.preview.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: cameraController.preview.trailingAnchor),
            blur.topAnchor.constraint(equalTo: cameraController.preview.topAnchor),
            blur.bottomAnchor.constraint(equalTo: cameraController.preview.bottomAnchor),

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

        hasDisplayedUnlockingExplainer = true
    }
}

// MARK: - FTUX computed properties

extension NewMomentViewController {
    /// Indicates whether we have shown the bottom sheet that explains the feature.
    /// This is shown when the user opens the moments camera for the first time.
    private var hasDisplayedMomentsExplainer: Bool {
        get {
            MainAppContext.shared.userDefaults.bool(forKey: "shown.moment.explainer")
        }

        set {
            MainAppContext.shared.userDefaults.set(newValue, forKey: "shown.moment.explainer")
        }
    }

    /// Shown as a blurred overlay above the camera. This is shown when the user attempts to
    /// unlock someone else's moment for the first time.
    private var hasDisplayedUnlockingExplainer: Bool {
        get {
            MainAppContext.shared.userDefaults.bool(forKey: "shown.moment.unlock.explainer")
        }

        set {
            MainAppContext.shared.userDefaults.set(newValue, forKey: "shown.moment.unlock.explainer")
        }
    }
}

// - MARK: - localization

extension Localizations {
    static var newMomentTitle: String {
        NSLocalizedString("composer.moment.post.title",
                   value: "New Moment",
                 comment: "Composer New Moment Post title.")
    }

    static var newMomentCameraSubtitle: String {
        NSLocalizedString("camera.moment.subtitle",
                   value: "Moments disappear after 24 hours and can only be viewed once",
                 comment: "Text shown on the camera screen when composing a new moment.")
    }

    static var newMomentCameraUnlockSubtitle: String {
        NSLocalizedString("camera.moment.unlock.subtitle",
                   value: "To see %@’s moment, share your own",
                 comment: "Text shown on the camera screen when composing a new moment to unlock someone else's moment.")
    }
}
