//
//  BottomSheetViewController.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 3/18/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit

class BottomSheetViewController: UIViewController {

    private weak var bottomSheetPresentationController: BottomSheetPresentationController?

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        setupTransition()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTransition()
    }

    private func setupTransition() {
        transitioningDelegate = self
        modalPresentationStyle = .custom
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return presentingViewController?.supportedInterfaceOrientations ?? .all
    }
}

extension BottomSheetViewController: UIViewControllerTransitioningDelegate {

    func presentationController(forPresented presented: UIViewController,
                                presenting: UIViewController?,
                                source: UIViewController) -> UIPresentationController? {
        let bottomSheetPresentationController = BottomSheetPresentationController(presentedViewController: presented,
                                                                                       presenting: presenting)
        self.bottomSheetPresentationController = bottomSheetPresentationController
        return bottomSheetPresentationController
    }

    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return bottomSheetPresentationController
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return bottomSheetPresentationController
    }

    func interactionControllerForPresentation(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        return bottomSheetPresentationController
    }

    func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        return bottomSheetPresentationController
    }
}

// MARK: - BottomSheetPresentationController

private class BottomSheetPresentationController: UIPresentationController, UIAdaptivePresentationControllerDelegate {

    private var scrimView: UIView?
    private var sheetBackgroundView: BottomSheetBackgroundView?
    private var sheetAnimator: UIViewPropertyAnimator?
    private var transitionDriver: BottomSheetTransitionDriver?
    private var isInitiallyInteractive = false

    private static let velocityThreshold: CGFloat = 500
    fileprivate static let transitionDuration: TimeInterval = 0.25

    private var isPresenting: Bool {
        return presentedViewController.isBeingPresented
    }

    private enum Detent {
        case hidden, expanded

        func transform(for sheetBackgroundView: BottomSheetBackgroundView) -> CGAffineTransform {
            // resolve size of sheet
            sheetBackgroundView.superview?.layoutIfNeeded()
            switch self {
            case .hidden:
                let translation = sheetBackgroundView.bounds.height - BottomSheetBackgroundView.additionalBottomPadding
                return CGAffineTransform(translationX: 0, y: translation)
            case .expanded:
                return .identity
            }
        }
    }

    override var presentedView: UIView? {
        return sheetBackgroundView
    }

    override func presentationTransitionWillBegin() {
        super.presentationTransitionWillBegin()

        guard let containerView = containerView else {
            return
        }

        let scrimView = UIView()
        scrimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismiss)))
        scrimView.backgroundColor = UIColor(dynamicProvider: { traitCollection in
            let alpha: CGFloat
            switch traitCollection.userInterfaceStyle {
            case .dark:
                alpha = 0.75
            default:
                alpha = 0.5
            }
            return .black.withAlphaComponent(alpha)
        })
        scrimView.translatesAutoresizingMaskIntoConstraints = false
        containerView.insertSubview(scrimView, at: 0)
        self.scrimView = scrimView

        NSLayoutConstraint.activate([
            scrimView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrimView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrimView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrimView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        guard let transitionCoordinator = presentedViewController.transitionCoordinator else {
            return
        }

        scrimView.alpha = 0
        transitionCoordinator.animate { _ in
            scrimView.alpha = 1
        }
    }

    override func presentationTransitionDidEnd(_ completed: Bool) {
        super.presentationTransitionDidEnd(completed)

        if !completed {
            scrimView?.removeFromSuperview()
        }
    }

    override func dismissalTransitionWillBegin() {
        super.dismissalTransitionWillBegin()

        presentedViewController.transitionCoordinator?.animate { _ in
            self.scrimView?.alpha = 0
        }
    }

    override func dismissalTransitionDidEnd(_ completed: Bool) {
        super.dismissalTransitionDidEnd(completed)

        if completed {
            scrimView?.removeFromSuperview()
        }
    }

    @objc private func dismiss() {
        presentedViewController.dismiss(animated: true)
    }

    @objc private func panGestureChanged(_ gestureRecognizer: UIPanGestureRecognizer) {
        guard let sheetBackgroundView = sheetBackgroundView else {
            return
        }

        let velocity = gestureRecognizer.velocity(in: sheetBackgroundView).y
        let offset = sheetBackgroundView.transform.ty
        let height = sheetBackgroundView.bounds.height - BottomSheetBackgroundView.additionalBottomPadding

        var translation = gestureRecognizer.translation(in: sheetBackgroundView).y
        if translation + offset < 0 {
            translation = translation - (translation / 1.1)
        }
        gestureRecognizer.setTranslation(.zero, in: sheetBackgroundView)

        var progress = max(0, min((offset + translation) / height, 1))
        if isPresenting {
            progress = 1 - progress
        }
        switch gestureRecognizer.state {
        case .began:
            isInitiallyInteractive = true
            if let transitionDriver = transitionDriver {
                transitionDriver.pauseAnimation()
            } else {
                presentingViewController.dismiss(animated: true)
            }
            sheetAnimator?.stopAnimation(true)
            fallthrough
        case .changed:
            let adjustedTranslation = max(offset + translation, -BottomSheetBackgroundView.additionalBottomPadding)
            sheetBackgroundView.transform = CGAffineTransform(translationX: 0.0, y: adjustedTranslation)
            transitionDriver?.update(progress: progress)
        case .ended, .cancelled:
            let completeTransition: Bool
            let detent: Detent
            if isPresenting {
                completeTransition = progress >= 0.5 || velocity < -Self.velocityThreshold
                detent = completeTransition ? .expanded : .hidden
            } else {
                completeTransition = progress >= 0.5 || velocity > Self.velocityThreshold
                detent = completeTransition ? .hidden : .expanded
            }

            animate(to: detent, shouldBounce: !completeTransition, progress: progress, initialVelocity: velocity)
            transitionDriver?.endInteraction(willCompleteTransition: completeTransition)
            isInitiallyInteractive = false
        default:
            break
        }
    }

    private func animate(to detent: Detent, shouldBounce: Bool = false, progress: CGFloat = 0, initialVelocity: CGFloat = 0) {
        guard let sheetBackgroundView = sheetBackgroundView else {
            return
        }

        let duration = TimeInterval(1.0 - progress) * Self.transitionDuration
        let timingParameters: UITimingCurveProvider
        if shouldBounce {
            timingParameters = UISpringTimingParameters(dampingRatio: 0.6, initialVelocity: CGVector(dx: 0, dy: abs(initialVelocity)))
        } else {
            timingParameters = UICubicTimingParameters(animationCurve: .easeInOut)
        }

        let sheetAnimator = UIViewPropertyAnimator(duration: duration, timingParameters: timingParameters)
        sheetAnimator.addAnimations {
            sheetBackgroundView.transform = detent.transform(for: sheetBackgroundView)
        }
        sheetAnimator.addCompletion { [weak self] _ in
            self?.sheetAnimator = nil
        }
        self.sheetAnimator = sheetAnimator
        sheetAnimator.startAnimation()
    }

    private func setupView() {
        guard let containerView = containerView, let presentedView = presentedViewController.view else {
            return
        }

        let sheetBackgroundView = BottomSheetBackgroundView(contentView: presentedView)
        sheetBackgroundView.addGestureRecognizer(UIPanGestureRecognizer(target: self,
                                                                        action: #selector(panGestureChanged(_:))))
        sheetBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(sheetBackgroundView)
        self.sheetBackgroundView = sheetBackgroundView

        NSLayoutConstraint.activate([
            presentedView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            presentedView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            presentedView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])

        sheetBackgroundView.transform = Detent.hidden.transform(for: sheetBackgroundView)
    }
}

extension BottomSheetPresentationController: UIViewControllerAnimatedTransitioning {

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return Self.transitionDuration
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        // no-op, interactive transition
    }

    func interruptibleAnimator(using transitionContext: UIViewControllerContextTransitioning) -> UIViewImplicitlyAnimating {
        guard let transitionDriver = transitionDriver else {
            fatalError("Transition Driver does not exist")
        }
        return transitionDriver.transitionAnimator
    }

    func animationEnded(_ transitionCompleted: Bool) {
        transitionDriver = nil
    }
}

extension BottomSheetPresentationController: UIViewControllerInteractiveTransitioning {

    func startInteractiveTransition(_ transitionContext: UIViewControllerContextTransitioning) {
        let transitionDriver = BottomSheetTransitionDriver(transitionContext: transitionContext)
        self.transitionDriver = transitionDriver

        // Set up views when we are presenting
        if transitionContext.viewController(forKey: .to) === presentedViewController {
            setupView()
        }

        if !transitionContext.isInteractive {
            transitionDriver.animate(to: .end)

            // the animation will not run unless we dispatch async.
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    return
                }
                self.animate(to: self.isPresenting ? .expanded : .hidden)
            }
        }
    }

    var wantsInteractiveStart: Bool {
        return isInitiallyInteractive
    }
}


// MARK: - BottomSheetTransitionDriver
/*
 We use a dummy animator object to drive the transition.
 This allows us to independently position and animate our sheet.
 */
private class BottomSheetTransitionDriver: NSObject {

    private let transitionContext: UIViewControllerContextTransitioning
    let transitionAnimator: UIViewPropertyAnimator

    init(transitionContext: UIViewControllerContextTransitioning) {
        self.transitionContext = transitionContext
        transitionAnimator = UIViewPropertyAnimator(duration: BottomSheetPresentationController.transitionDuration,
                                                    curve: .easeInOut)
        transitionAnimator.addAnimations { }
        transitionAnimator.addCompletion { [transitionContext] position in
            let completed = (position == .end)
            transitionContext.completeTransition(completed)
        }
        transitionAnimator.pauseAnimation()
        super.init()
    }

    func animate(to position: UIViewAnimatingPosition) {
        transitionAnimator.isReversed = (position == .start)
        transitionAnimator.startAnimation()
    }

    func pauseAnimation() {
        transitionAnimator.pauseAnimation()
        transitionContext.pauseInteractiveTransition()
    }

    func update(progress: CGFloat) {
        transitionAnimator.fractionComplete = progress
        transitionContext.updateInteractiveTransition(progress)
    }

    func endInteraction(willCompleteTransition: Bool) {
        if willCompleteTransition {
            transitionContext.finishInteractiveTransition()
        } else {
            transitionContext.cancelInteractiveTransition()
        }
        animate(to: willCompleteTransition ? .end : .start)
    }
}

// MARK: - BottomSheetBackgroundView

private class BottomSheetBackgroundView: UIView {

    static let additionalBottomPadding: CGFloat = 100

    private let handleSize = CGSize(width: 36, height: 4)

    private lazy var handle: UIView = {
        let handle = UIView()
        handle.backgroundColor = .label.withAlphaComponent(0.33)
        handle.layer.cornerRadius = handleSize.height / 2.0
        handle.translatesAutoresizingMaskIntoConstraints = false
        return handle
    }()

    init(contentView: UIView) {
        super.init(frame: .zero)

        backgroundColor = .bottomSheetBackground

        // mimic outset border with shadow
        layer.shadowOffset = .zero
        layer.shadowOpacity = 1.0
        layer.shadowRadius = 1.0 / UIScreen.main.scale

        layer.cornerRadius = 20

        addSubview(handle)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        NSLayoutConstraint.activate([
            handle.centerXAnchor.constraint(equalTo: centerXAnchor),
            handle.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            handle.widthAnchor.constraint(equalToConstant: handleSize.width),
            handle.heightAnchor.constraint(equalToConstant: handleSize.height),

            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: 16),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.additionalBottomPadding),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        updateShadowColor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: traitCollection) {
            updateShadowColor()
        }
    }

    private func updateShadowColor() {
        layer.shadowColor = UIColor.label.resolvedColor(with: traitCollection).withAlphaComponent(0.64).cgColor
    }
}
