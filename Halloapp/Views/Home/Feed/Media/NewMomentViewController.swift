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
