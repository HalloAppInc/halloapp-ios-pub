//
//  GroupInviteSheetViewController.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 1/19/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import MessageUI
import UIKit

extension Localizations {

    static var groupInviteSheetTitle: String {
        NSLocalizedString("group.invitesheet.title",
                          value: "Share this link with friends & family and they’ll automatically join this HalloApp group",
                          comment: "Title of invite sheet")
    }

    static var groupInviteSheetUseLinkVia: String {
        NSLocalizedString("group.invitesheet.use.link.via",
                          value: "Share link using…",
                          comment: "Section header describing options to share link")
    }
}

class GroupInviteSheetViewController: UIViewController {

    // Maintain a reference to the presentation controller.
    // The system presentationController property creates a new presentation controller if accessed
    // from different UIViewControllerTransitioningDelegate methods
    private weak var groupInvitePresentationController: GroupInviteSheetPresentationController?

    private let groupInviteLink: String

    init(groupInviteLink: String) {
        self.groupInviteLink = groupInviteLink
        super.init(nibName: nil, bundle: nil)
        transitioningDelegate = self
        modalPresentationStyle = .custom
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 16, weight: .regular)
        titleLabel.numberOfLines = 0
        titleLabel.text = Localizations.groupInviteSheetTitle
        titleLabel.textAlignment = .center
        titleLabel.textColor = .label.withAlphaComponent(0.8)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        let shareUrlLabel = GroupInviteCopyableLabel()
        shareUrlLabel.font = .systemFont(ofSize: 16, weight: .medium)
        shareUrlLabel.text = groupInviteLink
        shareUrlLabel.textColor = .label.withAlphaComponent(0.5)
        shareUrlLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shareUrlLabel)

        let shareViaLabel = UILabel()
        shareViaLabel.font = .systemFont(ofSize: 12, weight: .medium)
        shareViaLabel.text = Localizations.groupInviteSheetUseLinkVia.uppercased()
        shareViaLabel.textColor = .label.withAlphaComponent(0.5)
        shareViaLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shareViaLabel)

        var shareOptionButtons: [GroupInviteSheetButton] = []

        let whatsAppButton = GroupInviteSheetButton()
        whatsAppButton.addTarget(self, action: #selector(inviteViaWhatsApp), for: .touchUpInside)
        whatsAppButton.imageView.image = UIImage(named: "WhatsAppLogo")
        whatsAppButton.titleLabel.text = Localizations.appNameWhatsApp
        shareOptionButtons.append(whatsAppButton)

        let canInviteViaWhatsApp = URL(string: "whatsapp://app").flatMap({ UIApplication.shared.canOpenURL($0) }) ?? false
        whatsAppButton.alpha = canInviteViaWhatsApp ? 1 : 0
        whatsAppButton.isUserInteractionEnabled = canInviteViaWhatsApp

        let messageButton = GroupInviteSheetButton()
        messageButton.addTarget(self, action: #selector(inviteViaMessages), for: .touchUpInside)
        messageButton.imageView.image = UIImage(named: "MessagesLogo")
        messageButton.titleLabel.text = Localizations.appNameSMS
        shareOptionButtons.append(messageButton)

        let canInviteViaText = MFMessageComposeViewController.canSendText()
        messageButton.alpha = canInviteViaText ? 1 : 0
        messageButton.isUserInteractionEnabled = canInviteViaText

        let copyButton = GroupInviteSheetButton()
        copyButton.addTarget(self, action: #selector(copyInviteLink), for: .touchUpInside)
        copyButton.imageView.image = UIImage(systemName: "link")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 21, weight: .bold))
            .withRenderingMode(.alwaysTemplate)
        copyButton.titleLabel.text = Localizations.groupInviteCopyLink
        shareOptionButtons.append(copyButton)

        let moreButton = GroupInviteSheetButton()
        moreButton.addTarget(self, action: #selector(openSystemShareMenu), for: .touchUpInside)
        moreButton.imageView.image = UIImage(systemName: "ellipsis")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 21, weight: .bold))
            .withRenderingMode(.alwaysTemplate)
            .withAlignmentRectInsets(.zero)
        moreButton.titleLabel.text = Localizations.buttonMore
        shareOptionButtons.append(moreButton)

        // UIStackView removes any hidden views, we want to maintain them to take advantage of stack views
        // equal spacing. However, we should move them to end, so we simply sort by alpha.
        var visibleShareOptionButtons: [UIView] = []
        var hiddenShareOptionButtons: [UIView] = []
        shareOptionButtons.forEach { shareOptionButton in
            if shareOptionButton.alpha > 0 {
                visibleShareOptionButtons.append(shareOptionButton)
            } else {
                hiddenShareOptionButtons.append(shareOptionButton)
            }
        }

        let buttonStackView = UIStackView(arrangedSubviews: visibleShareOptionButtons + hiddenShareOptionButtons)
        buttonStackView.axis = .horizontal
        buttonStackView.distribution = .equalSpacing
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(buttonStackView)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),

            shareUrlLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shareUrlLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            shareUrlLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),

            shareViaLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            shareViaLabel.topAnchor.constraint(equalTo: shareUrlLabel.bottomAnchor, constant: 24),

            buttonStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            buttonStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            buttonStackView.topAnchor.constraint(equalTo: shareViaLabel.bottomAnchor, constant: 8),
            buttonStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
        ])
    }

    private var shareText: String {
        return "\(Localizations.groupInviteShareLinkMessage) \(groupInviteLink)"
    }

    @objc private func inviteViaWhatsApp() {
        dismiss(animated: true)

        guard let escapedShareText = shareText.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed),
              let url = URL(string: "whatsapp://send?text=\(escapedShareText)") else {
                  DDLogError("GroupInviteSheetViewController/Unable to create Whatsapp URL")
                  return
              }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    @objc private func inviteViaMessages() {
        dismiss(animated: true) { [presentingViewController, shareText] in
            let messageComposeViewController = GroupInviteSheetMessageComposeViewController()
            messageComposeViewController.body = shareText
            presentingViewController?.present(messageComposeViewController, animated: true)
        }
    }

    @objc private func copyInviteLink() {
        UIPasteboard.general.string = groupInviteLink
        dismiss(animated: true)
    }

    @objc private func openSystemShareMenu() {
        dismiss(animated: true) { [presentingViewController, shareText] in
            let activityViewController = UIActivityViewController(activityItems: [shareText],
                                                                  applicationActivities: nil)
            presentingViewController?.present(activityViewController, animated: true)
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return presentingViewController?.supportedInterfaceOrientations ?? .all
    }
}

extension GroupInviteSheetViewController: UIViewControllerTransitioningDelegate {

    func presentationController(forPresented presented: UIViewController,
                                presenting: UIViewController?,
                                source: UIViewController) -> UIPresentationController? {
        let groupInvitePresentationController = GroupInviteSheetPresentationController(presentedViewController: presented,
                                                                                       presenting: presenting)
        self.groupInvitePresentationController = groupInvitePresentationController
        return groupInvitePresentationController
    }

    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return groupInvitePresentationController
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return groupInvitePresentationController
    }

    func interactionControllerForPresentation(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        return groupInvitePresentationController
    }

    func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        return groupInvitePresentationController
    }
}

private class GroupInviteSheetMessageComposeViewController: MFMessageComposeViewController, MFMessageComposeViewControllerDelegate {

    init() {
        super.init(nibName: nil, bundle: nil)
        messageComposeDelegate = self
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        dismiss(animated: true)
    }
}

private class GroupInviteCopyableLabel: UILabel {

    override init(frame: CGRect) {
        super.init(frame: frame)

        isUserInteractionEnabled = true
        addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(openMenu)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeFirstResponder: Bool {
        return true
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return action == #selector(copy(_:))
    }

    override func copy(_ sender: Any?) {
        UIPasteboard.general.string = text
    }

    @objc private func openMenu() {
        becomeFirstResponder()
        UIMenuController.shared.showMenu(from: self, rect: bounds)
    }
}

private class GroupInviteSheetButton: UIControl {

    let imageView = UIImageView()
    let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        imageView.backgroundColor = UIColor(red: 0.855, green: 0.843, blue: 0.812, alpha: 1)
        imageView.contentMode = .center
        imageView.layer.cornerRadius = 13
        imageView.layer.masksToBounds = true
        imageView.tintColor = .black.withAlphaComponent(0.7)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        titleLabel.font = .systemFont(ofSize: 10, weight: .regular)
        titleLabel.textColor = .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        let imageViewLeadingConstraint = imageView.leadingAnchor.constraint(equalTo: leadingAnchor)
        imageViewLeadingConstraint.priority = .defaultLow

        NSLayoutConstraint.activate([
            imageViewLeadingConstraint,
            imageView.widthAnchor.constraint(equalToConstant: 55),
            imageView.heightAnchor.constraint(equalToConstant: 55),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),

            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            let alpha = isHighlighted ? 0.8 : 1
            imageView.alpha = alpha
            titleLabel.alpha = alpha
        }
    }
}

private class GroupInviteSheetBackgroundView: UIView {

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

        backgroundColor = .systemGray6

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

private class GroupInviteSheetPresentationController: UIPresentationController, UIAdaptivePresentationControllerDelegate {

    private var scrimView: UIView?
    private var sheetBackgroundView: GroupInviteSheetBackgroundView?
    private var sheetAnimator: UIViewPropertyAnimator?
    private var transitionDriver: GroupInviteSheetTransitionDriver?
    private var isInitiallyInteractive = false

    private static let velocityThreshold: CGFloat = 500
    fileprivate static let transitionDuration: TimeInterval = 0.25

    private var isPresenting: Bool {
        return presentedViewController.isBeingPresented
    }

    private enum SheetDetent {
        case hidden, expanded

        func transform(for sheetBackgroundView: GroupInviteSheetBackgroundView) -> CGAffineTransform {
            sheetBackgroundView.window?.layoutIfNeeded()
            switch self {
            case .hidden:
                let translation = sheetBackgroundView.bounds.height - GroupInviteSheetBackgroundView.additionalBottomPadding
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
                alpha = 0.288
            default:
                alpha = 0.12
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
        let height = sheetBackgroundView.bounds.height - GroupInviteSheetBackgroundView.additionalBottomPadding

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
            let adjustedTranslation = max(offset + translation, -GroupInviteSheetBackgroundView.additionalBottomPadding)
            sheetBackgroundView.transform = CGAffineTransform(translationX: 0.0, y: adjustedTranslation)
            transitionDriver?.update(progress: progress)
        case .ended, .cancelled:
            let completeTransition: Bool
            let detent: SheetDetent
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

    private func animate(to detent: SheetDetent, shouldBounce: Bool = false, progress: CGFloat = 0, initialVelocity: CGFloat = 0) {
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

        let sheetBackgroundView = GroupInviteSheetBackgroundView(contentView: presentedView)
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

        sheetBackgroundView.transform = SheetDetent.hidden.transform(for: sheetBackgroundView)
    }
}

extension GroupInviteSheetPresentationController: UIViewControllerAnimatedTransitioning {

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

extension GroupInviteSheetPresentationController: UIViewControllerInteractiveTransitioning {

    func startInteractiveTransition(_ transitionContext: UIViewControllerContextTransitioning) {
        let transitionDriver = GroupInviteSheetTransitionDriver(transitionContext: transitionContext)
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

/*
 We use a dummy animator object to drive the transition.
 This allows us to independently position and animate our sheet.
 */
private class GroupInviteSheetTransitionDriver: NSObject {

    private let transitionContext: UIViewControllerContextTransitioning
    let transitionAnimator: UIViewPropertyAnimator

    init(transitionContext: UIViewControllerContextTransitioning) {
        self.transitionContext = transitionContext
        transitionAnimator = UIViewPropertyAnimator(duration: GroupInviteSheetPresentationController.transitionDuration,
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
