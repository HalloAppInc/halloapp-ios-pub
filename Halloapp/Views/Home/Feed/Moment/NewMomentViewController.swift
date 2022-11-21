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

    private enum State { case camera, indeterminate, composer }

    private var state: State = .camera
    let context: MomentContext
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
    private(set) lazy var cameraViewController: NewCameraViewController = {
        let vc = NewCameraViewController(presets: [.moment(context)], initialPresetIndex: 0)
        vc.delegate = self
        vc.title = Localizations.newMomentTitle
        return vc
    }()

    private weak var composer: MomentComposerViewController?

    private lazy var cameraNavigationController: UINavigationController = {
        let nc = UINavigationController(rootViewController: cameraViewController)
        return nc
    }()

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

    init(context: MomentContext = .normal) {
        self.context = context
        super.init(nibName: nil, bundle: nil)

        commonInit()
    }

    init(notificationMetadata: NotificationMetadata) {
        context = .normal
        super.init(nibName: nil, bundle: nil)

        commonInit()
    }

    private func commonInit() {
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

        let appearance = UINavigationBarAppearance()
        appearance.backgroundColor = .black
        appearance.shadowColor = nil
        appearance.titleTextAttributes = [.font: UIFont.gothamFont(ofFixedSize: 16, weight: .medium)]
        cameraNavigationController.navigationBar.standardAppearance = appearance
        cameraNavigationController.navigationBar.scrollEdgeAppearance = appearance

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

    private func presentComposer(_ completion: (() -> Void)? = nil) {
        let composer = MomentComposerViewController(context: context)
        let nc = UINavigationController(rootViewController: composer)

        nc.modalPresentationStyle = .custom
        nc.transitioningDelegate = composer

        composer.delegate = self
        self.composer = composer

        present(nc, animated: true) {
            completion?()
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
        vc.modalPresentationStyle = .custom
        vc.transitioningDelegate = vc

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
        composer?.present(momentViewController, animated: true) { [weak self] in
            // hide these views so that a dismissal from `momentViewController` appears as if it's
            // going straight back to the feed
            self?.view.isHidden = true
            self?.composer?.view.isHidden = true
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

    func cameraViewController(_ viewController: NewCameraViewController, didCapture results: [CaptureResult], with preset: CameraPreset) {
        if shouldDiscardIncomingCaptureResult {
            // this result is from a capture the user backed out of; discard the result
            return
        }

        composer?.configure(with: results, animateTrailing: results.count != 2)
    }

    func cameraViewControllerDidReleaseShutter(_ viewController: NewCameraViewController) {
        shouldDiscardIncomingCaptureResult = false
        presentComposer()
    }

    func cameraViewController(_ viewController: NewCameraViewController, didSelect media: [PendingMedia]) {
        guard let first = media.first else {
            return
        }

        mediaLoader = first.ready
            .first { $0 }
            .compactMap { _ -> CaptureResult? in
                guard let image = first.image else {
                    return nil
                }

                return CaptureResult(identifier: UUID(),
                                          image: image.correctlyOrientedImage(),
                                 cameraPosition: .unspecified,
                                    orientation: .portrait,
                                         layout: .fullPortrait(.unspecified),
                     resultsNeededForCompletion: 1)
            }
            .sink { [weak self] result in
                self?.presentComposer() {
                    self?.composer?.configure(with: [result], animateTrailing: false)
                }
            }
    }

    func cameraViewController(_ viewController: NewCameraViewController, didRecordVideoTo url: URL) {

    }
}

// MARK: - MomentComposerPresenter methods

extension NewMomentViewController: MomentComposerViewControllerDelegate {

    var distanceFromTopForBackground: CGFloat {
        view.layoutIfNeeded()
        return cameraViewController.background.frame.origin.y
    }

    var heightForBackground: CGFloat {
        view.layoutIfNeeded()
        return cameraViewController.background.bounds.height
    }

    func momentComposerDidEnableSend(_ composer: MomentComposerViewController) {
        cameraViewController.pause()
    }

    func momentComposerDidSend(_ composer: MomentComposerViewController) {
        completeCompose()
    }

    func momentComposerDidCancel(_ composer: MomentComposerViewController) {
        shouldDiscardIncomingCaptureResult = true

        cameraViewController.resume()
        dismiss(animated: true)
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
        blur.layer.cornerRadius = 15

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

        blur.contentView.addSubview(stack)

        unlockingExplainerOverlay = blur
        button.addTarget(self, action: #selector(dismissUnlockingExplainer), for: .touchUpInside)
    }

    @objc
    private func dismissUnlockingExplainer(_ sender: UIButton) {
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
