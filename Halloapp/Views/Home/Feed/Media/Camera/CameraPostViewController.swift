//
//  CameraPostViewController.swift
//  HalloApp
//
//  Created by Tanveer on 11/9/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Core

protocol CameraPostViewControllerDelegate: AnyObject {
    func cameraPostViewController(_ viewController: CameraPostViewController, didPostTo destinations: [ShareDestination])
}

class CameraPostViewController: UIViewController {

    private let transitionStartPoint: CGPoint
    weak var delegate: CameraPostViewControllerDelegate?

    private lazy var cameraViewController: NewCameraViewController = {
        let vc = NewCameraViewController(presets: [.photo, .moment(.normal)], initialPresetIndex: 0)
        vc.delegate = self
        vc.overrideUserInterfaceStyle = .dark
        return vc
    }()

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

    override var childForStatusBarStyle: UIViewController? {
        cameraViewController
    }

    private weak var momentComposer: MomentComposerViewController?

    init(startPoint: CGPoint) {
        transitionStartPoint = startPoint
        super.init(nibName: nil, bundle: nil)

        modalPresentationCapturesStatusBarAppearance = true
        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        cameraViewController.onDismiss = { [weak self] in
            self?.dismiss(animated: true)
        }

        let nc = UINavigationController(rootViewController: cameraViewController)
        nc.willMove(toParent: self)
        addChild(nc)

        nc.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nc.view)

        NSLayoutConstraint.activate([
            nc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            nc.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            nc.view.topAnchor.constraint(equalTo: view.topAnchor),
            nc.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func withContainer(_ viewController: UIViewController) -> UIViewController {
        let container = UIViewController()
        viewController.willMove(toParent: container)
        container.addChild(viewController)

        viewController.view.translatesAutoresizingMaskIntoConstraints = false
        container.view.addSubview(viewController.view)

        NSLayoutConstraint.activate([
            viewController.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            viewController.view.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),
            viewController.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            viewController.view.bottomAnchor.constraint(equalTo: container.view.bottomAnchor),
        ])

        return container
    }

    private func showPostComposer(with media: [PendingMedia]) {
        let state = NewPostState(pendingMedia: media, mediaSource: .unified)
        let vc = NewPostViewController(state: state, destination: .feed(.all), showDestinationPicker: true) { [weak self] didPost, destinations in
            guard let self else {
                return
            }

            if didPost {
                self.delegate?.cameraPostViewController(self, didPostTo: destinations)
                self.showSnapshotAndDismiss()
            } else {
                self.cameraViewController.resume()
                self.dismiss(animated: true)
            }
        }

        vc.modalPresentationStyle = .custom
        vc.modalPresentationCapturesStatusBarAppearance = true
        vc.transitioningDelegate = self

        present(vc, animated: true)
        cameraViewController.pause()
    }

    private func showMomentComposer() {
        let composer = MomentComposerViewController(context: .normal)
        let nc = UINavigationController(rootViewController: composer)

        nc.modalPresentationStyle = .custom
        nc.transitioningDelegate = composer

        composer.delegate = self
        self.momentComposer = composer
        
        present(nc, animated: true)
    }

    private func showSnapshotAndDismiss() {
        // dismissing without the snapshot will animate all of the different transitions that each view controller uses
        // instead we take a snapshot so that it looks like only the circle animation is performed
        if let snapshot = presentedViewController?.view.snapshotView(afterScreenUpdates: false) {
            view.addSubview(snapshot)
            presentedViewController?.view.isHidden = true
        }

        presentingViewController?.dismiss(animated: true)
    }
}

// MARK: - CameraViewControllerDelegate methods

extension CameraPostViewController: CameraViewControllerDelegate {

    func cameraViewControllerDidReleaseShutter(_ viewController: NewCameraViewController) {
        if .moment(.normal) == cameraViewController.viewModel.activePreset {
            showMomentComposer()
        }
    }

    func cameraViewController(_ viewController: NewCameraViewController, didRecordVideoTo url: URL) {

    }

    func cameraViewController(_ viewController: NewCameraViewController, didCapture results: [CaptureResult], with preset: CameraPreset) {
        switch preset {
        case .moment(.normal):
            momentComposer?.configure(with: results, animateTrailing: results.count != 2)
        default:
            let media = results
                .map {
                    let pending = PendingMedia(type: .image)
                    pending.image = $0.image
                    return pending
                }

            showPostComposer(with: media)
        }
    }

    func cameraViewController(_ viewController: NewCameraViewController, didSelect media: [PendingMedia]) {
        showPostComposer(with: media)
    }
}

// MARK: - UIViewControllerTransitioningDelegate methods

extension CameraPostViewController: UIViewControllerTransitioningDelegate {

    func animationController(forPresented presented: UIViewController,
                             presenting: UIViewController,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning? {

        switch presented {
        case is CameraPostViewController:
            return CameraTabPresenter(startPoint: transitionStartPoint)
        default:
            return PushDissolveTransition()
        }
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        switch dismissed {
        case is CameraPostViewController:
            return CameraTabDismisser(startPoint: transitionStartPoint)
        default:
            return PopDissolveTransition()
        }
    }
}

// MARK: - MomentComposerPresenter methods

extension CameraPostViewController: MomentComposerViewControllerDelegate {

    var distanceFromTopForBackground: CGFloat {
        view.layoutIfNeeded()
        return cameraViewController.background.frame.minY
    }

    var heightForBackground: CGFloat {
        view.layoutIfNeeded()
        return cameraViewController.background.bounds.height
    }

    func momentComposerDidEnableSend(_ composer: MomentComposerViewController) {
        cameraViewController.pause()
    }

    func momentComposerDidSend(_ composer: MomentComposerViewController) {
        showSnapshotAndDismiss()
    }

    func momentComposerDidCancel(_ composer: MomentComposerViewController) {
        cameraViewController.resume()
        dismiss(animated: true)
    }
}

fileprivate class PushDissolveTransition: NSObject, UIViewControllerAnimatedTransitioning {

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.3
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let to = transitionContext.viewController(forKey: .to) else {
            return
        }

        to.view.alpha = 0
        transitionContext.containerView.addSubview(to.view)

        UIView.transition(with: transitionContext.containerView, duration: transitionDuration(using: nil), options: [.transitionCrossDissolve]) {
            to.view.alpha = 1
        } completion: { _ in
            transitionContext.completeTransition(true)
        }
    }
}

fileprivate class PopDissolveTransition: NSObject, UIViewControllerAnimatedTransitioning {

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.3
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let from = transitionContext.viewController(forKey: .from) else {
            return
        }

        UIView.transition(with: transitionContext.containerView, duration: transitionDuration(using: nil), options: [.transitionCrossDissolve]) {
            from.view.alpha = 0
        } completion: { _ in
            transitionContext.completeTransition(true)
        }
    }
}
