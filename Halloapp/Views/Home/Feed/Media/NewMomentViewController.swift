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
import CoreData
import CocoaLumberjackSwift

/// Handles the creation and posting of a moment, regardless of context.
final class NewMomentViewController: UIViewController {
    enum Context { case normal, unlock(FeedPost) }

    let context: Context

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

    override var canBecomeFirstResponder: Bool {
        true
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
        vc.onPhotoCapture = { [weak self] image in self?.handleTaken(image: image) }
        vc.subtitle = prompt
        return vc
    }()

    private lazy var cameraNavigationController: UINavigationController = {
        let nc = UINavigationController(rootViewController: cameraController)
        return nc
    }()

    private var composerNavigationController: UIViewController?

    init(context: Context = .normal) {
        self.context = context
        super.init(nibName: nil, bundle: nil)

        overrideUserInterfaceStyle = .dark
        modalPresentationStyle = .overCurrentContext
        definesPresentationContext = true
    }

    required init?(coder: NSCoder) {
        fatalError("NewMomentViewController coder init not implemented...")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        DDLogInfo("NewMomentViewController/viewDidLoad")
        view.backgroundColor = .black

        showCamera()

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

    private func handleTaken(image: UIImage) {
        displayComposer(with: image.correctlyOrientedImage())
    }

    private func displayComposer(with image: UIImage) {
        let composer = MomentComposerViewController(image: image)
        let composerNavigationController = UINavigationController(rootViewController: composer)

        composer.onPost = { [weak self] in
            self?.completeCompose()
        }

        composer.onCancel = { [weak self] in
            self?.dismissComposer()
        }

        composerNavigationController.view.alpha = 0
        contain(composerNavigationController)

        composer.view.layoutIfNeeded()
        composer.momentCardTopConstraint.constant = cameraController.background.frame.minY
        composer.momentCardHeightConstraint.constant = cameraController.background.bounds.height

        self.composerNavigationController = composerNavigationController

        UIView.transition(with: view, duration: 0.1, options: [.transitionCrossDissolve]) {
            self.cameraNavigationController.view.alpha = 0
            composerNavigationController.view.alpha = 1
        } completion: { _ in
            self.cameraNavigationController.view.removeFromSuperview()
        }
    }

    private func dismissComposer() {
        // go back to the camera
        contain(cameraNavigationController)

        UIView.transition(with: view, duration: 0.2, options: [.transitionCrossDissolve]) {
            self.cameraNavigationController.view.alpha = 1
            self.composerNavigationController?.view.alpha = 0
        } completion: { _ in
            self.composerNavigationController?.view.removeFromSuperview()
            self.composerNavigationController = nil
        }
    }

    private func cancelComposer() {
        composerNavigationController?.view.removeFromSuperview()
        composerNavigationController = nil
    }

    private func showCamera() {
        view.insertSubview(cameraNavigationController.view, at: 0)
        contain(cameraNavigationController)
    }

    private func completeCompose() {
        guard
            case let .unlock(post) = context,
            let feedData = MainAppContext.shared.feedData,
            let latest = feedData.fetchLatestMoment(using: feedData.viewContext)
        else {
            return dismiss(animated: true)
        }

        DDLogInfo("NewMomentViewController/completeCompose")

        let vc = MomentViewController(post: post, unlockingPost: latest)
        vc.view.alpha = 0
        contain(vc)

        vc.becomeFirstResponder()
        transitioningDelegate = vc

        cameraController.removeFromParent()
        composerNavigationController?.removeFromParent()

        UIView.animateKeyframes(withDuration: 0.3, delay: 0) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.8) {
                vc.view.alpha = 1
            }

            UIView.addKeyframe(withRelativeStartTime: 0.9, relativeDuration: 0.1) {
                self.view.backgroundColor = .clear
                self.cameraController.view.alpha = 0
                self.composerNavigationController?.view.alpha = 0
            }
        }
    }

    /// Helper for adding a view controller as a child.
    private func contain(_ viewController: UIViewController) {
        addChild(viewController)
        viewController.didMove(toParent: self)

        viewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(viewController.view)

        NSLayoutConstraint.activate([
            viewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            viewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            viewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            viewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
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

        cameraController.shutterButton.isUserInteractionEnabled = false
        cameraController.subtitleLabel.isHidden = true
        unlockingExplainerOverlay = blur
        button.addTarget(self, action: #selector(dismissUnlockingExplainer), for: .touchUpInside)
    }

    @objc
    private func dismissUnlockingExplainer(_ sender: UIButton) {
        cameraController.shutterButton.isUserInteractionEnabled = true
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
                   value: "To see %@'s moment, share your own",
                 comment: "Text shown on the camera screen when composing a new moment to unlock someone else's moment.")
    }
}
