//
//  ActionSheetViewController.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 11/17/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import UIKit
import CocoaLumberjackSwift

class ActionSheetAction {
    enum Style {
        case `default`, cancel, destructive
    }

    let title: String
    let image: UIImage?
    let style: Style
    fileprivate let handler: ((ActionSheetAction) -> Void)?

    init(title: String, image: UIImage? = nil, style: Style, handler: ((ActionSheetAction) -> Void)? = nil) {
        self.title = title
        self.image = image
        self.style = style
        self.handler = handler
    }
}

class ActionSheetViewController: UIViewController, UIViewControllerTransitioningDelegate {

    var message: String?
    private(set) var actions: [ActionSheetAction] = []

    init(title: String? = nil, message: String? = nil) {
        self.message = message
        super.init(nibName: nil, bundle: nil)
        self.title = title
        modalPresentationStyle = .custom
        modalTransitionStyle = .coverVertical
        transitioningDelegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addAction(_ action: ActionSheetAction) {
        guard !isViewLoaded else {
            DDLogInfo("Cannot add actions after an action sheet has been presented")
            return
        }
        actions.append(action)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let primaryActionGroupView = ActionGroupView()

        // Header

        let headerContentView = UIView()

        if let title = title, !title.isEmpty {
            let titleLabel = UILabel()
            let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .footnote).withSymbolicTraits(.traitBold)
            if let fontDescriptor = fontDescriptor {
                titleLabel.font = UIFont(descriptor: fontDescriptor, size: 0)
            }
            titleLabel.numberOfLines = 0
            titleLabel.textAlignment = .center
            titleLabel.text = title
            titleLabel.textColor = .secondaryLabel
            headerContentView.addSubview(titleLabel)
        }

        if let message = message, !message.isEmpty {
            let messageLabel = UILabel()
            messageLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
            messageLabel.numberOfLines = 0
            messageLabel.textAlignment = .center
            messageLabel.text = message
            messageLabel.textColor = .secondaryLabel
            headerContentView.addSubview(messageLabel)
        }

        var previousHeaderSubview: UIView? = nil
        for headerSubview in headerContentView.subviews {
            headerSubview.translatesAutoresizingMaskIntoConstraints = false
            let preferredTopConstraint: NSLayoutConstraint
            let topConstraint: NSLayoutConstraint
            if let previousHeaderSubview = previousHeaderSubview {
                preferredTopConstraint = headerSubview.firstBaselineAnchor.constraint(equalTo: previousHeaderSubview.lastBaselineAnchor,
                                                                                      constant: 22)
                topConstraint = headerSubview.topAnchor.constraint(greaterThanOrEqualTo: previousHeaderSubview.bottomAnchor)
            } else {
                preferredTopConstraint = headerSubview.firstBaselineAnchor.constraint(equalTo: headerContentView.topAnchor,
                                                                                      constant: 27)
                topConstraint = headerSubview.topAnchor.constraint(greaterThanOrEqualTo: headerContentView.topAnchor)
            }
            preferredTopConstraint.priority = .defaultHigh

            NSLayoutConstraint.activate([
                headerSubview.widthAnchor.constraint(equalTo: headerContentView.widthAnchor, constant: -32),
                headerSubview.centerXAnchor.constraint(equalTo: headerContentView.centerXAnchor),
                preferredTopConstraint,
                topConstraint,
            ])
            previousHeaderSubview = headerSubview
        }
        previousHeaderSubview?.lastBaselineAnchor.constraint(equalTo: headerContentView.lastBaselineAnchor,
                                                             constant: -17).isActive = true

        if !headerContentView.subviews.isEmpty {
            // TODO: look into this...
            // not having this check completely breaks layout if neither label has text
            primaryActionGroupView.addArrangedSubview(headerContentView)
        }

        // Primary Actions

        for action in actions where action.style != .cancel {
            if !primaryActionGroupView.arrangedSubviews.isEmpty {
                primaryActionGroupView.addArrangedSubview(ActionSheetDivider())
            }
            primaryActionGroupView.addArrangedSubview(ActionView(action: action))
        }

        // Cancel Actions

        let cancelActionGroupView = ActionGroupView()
        for action in actions where action.style == .cancel {
            if !primaryActionGroupView.arrangedSubviews.isEmpty {
                cancelActionGroupView.addArrangedSubview(ActionSheetDivider())
            }
            cancelActionGroupView.addArrangedSubview(ActionView(action: action))
        }
        // Insert all action group views
        var previousActionGroupView: UIView? = nil
        for actionGroupView in [primaryActionGroupView, cancelActionGroupView] {
            if actionGroupView.arrangedSubviews.isEmpty {
                continue
            }
            actionGroupView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(actionGroupView)

            let topConstraint: NSLayoutConstraint
            if let previousActionGroupView = previousActionGroupView {
                topConstraint = actionGroupView.topAnchor.constraint(equalTo: previousActionGroupView.bottomAnchor, constant: 8)
            } else {
                topConstraint = actionGroupView.topAnchor.constraint(equalTo: view.topAnchor)
            }

            NSLayoutConstraint.activate([
                actionGroupView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                actionGroupView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                topConstraint,
            ])

            previousActionGroupView = actionGroupView
        }
        if let previousActionGroupView = previousActionGroupView {
            previousActionGroupView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        }

        let tapOrHighlightGestureRecognizer = UILongPressGestureRecognizer(target: self,
                                                                           action: #selector(tapOrHighlightGestureRecognizerChanged(_:)))
        tapOrHighlightGestureRecognizer.minimumPressDuration = 0
        view.addGestureRecognizer(tapOrHighlightGestureRecognizer)
    }

    private var previouslyHighlightedActionView: ActionView? = nil

    @objc private func tapOrHighlightGestureRecognizerChanged(_ tapOrHighlightGestureRecognizer: UILongPressGestureRecognizer) {
        let location = tapOrHighlightGestureRecognizer.location(in: view)
        let highlightedActionView = view.hitTest(location, with: nil) as? ActionView

        switch tapOrHighlightGestureRecognizer.state {
        case .began, .changed:
            highlightedActionView?.isHighlighted = true
        case .ended:
            if let highlightedActionView = highlightedActionView, highlightedActionView === previouslyHighlightedActionView {
                previouslyHighlightedActionView = nil
                highlightedActionView.isHighlighted = false

                let action = highlightedActionView.action
                dismiss(animated: true) {
                    action.handler?(action)
                }
                return
            }
        default:
            break
        }

        if previouslyHighlightedActionView !== highlightedActionView {
            previouslyHighlightedActionView?.isHighlighted = false
        }
        previouslyHighlightedActionView = highlightedActionView
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return presentingViewController?.supportedInterfaceOrientations ?? .portrait
    }

    func presentationController(forPresented presented: UIViewController,
                                presenting: UIViewController?,
                                source: UIViewController) -> UIPresentationController? {
        return ActionSheetPresentationController(presentedViewController: presented, presenting: presenting)
    }


    // MARK: - Subviews
    
    private class ActionGroupView: UIStackView {

        override init(frame: CGRect) {
            super.init(frame: frame)

            axis = .vertical
            layer.cornerRadius = 13
            layer.masksToBounds = true

            let backgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
            backgroundView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(backgroundView)
            NSLayoutConstraint.activate([
                backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
                backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
                backgroundView.topAnchor.constraint(equalTo: topAnchor),
                backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    private class ActionView: UIView {
        private var titleLabel = UILabel()
        private var imageView: UIImageView?
        private var highlightBackgroundView = UIVisualEffectView()

        var isHighlighted = false {
            didSet {
                highlightBackgroundView.isHidden = !isHighlighted
            }
        }

        let action: ActionSheetAction

        init(action: ActionSheetAction) {
            self.action = action

            super.init(frame: .zero)

            highlightBackgroundView.effect = UIVibrancyEffect(blurEffect: UIBlurEffect(style: .systemMaterial),
                                                              style: .tertiaryFill)
            highlightBackgroundView.isHidden = true
            highlightBackgroundView.contentView.backgroundColor = .white
            highlightBackgroundView.translatesAutoresizingMaskIntoConstraints = false
            highlightBackgroundView.isUserInteractionEnabled = false
            addSubview(highlightBackgroundView)

            var font = UIFont.preferredFont(forTextStyle: .title3)
            var textColor = UIColor.systemBlue
            switch action.style {
            case .default:
                // Use defaults
                break
            case .cancel:
                let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title3).withSymbolicTraits(.traitBold)
                font = descriptor.flatMap { UIFont(descriptor: $0, size: 0) } ?? font
                backgroundColor = .secondarySystemGroupedBackground
            case .destructive:
                textColor = UIColor.systemRed
            }
            titleLabel.font = font
            titleLabel.textColor = textColor
            titleLabel.text = action.title
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(titleLabel)

            let heightConstraint = heightAnchor.constraint(equalToConstant: 57)
            heightConstraint.priority = .defaultLow
            var imageConstraints = configureImage()

            if let imageView = imageView {
                imageConstraints.append(titleLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 12))
            } else {
                imageConstraints.append(titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor))
            }
            
            NSLayoutConstraint.activate([
                highlightBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
                highlightBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
                highlightBackgroundView.topAnchor.constraint(equalTo: topAnchor),
                highlightBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
                titleLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 8),
                titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),
                titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
                heightConstraint,
            ] + imageConstraints)

            isAccessibilityElement = true
            accessibilityTraits = .button
            accessibilityLabel = action.title
        }
        
        private func configureImage() -> [NSLayoutConstraint] {
            guard let image = action.image else {
                return []
            }
            
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFit
            imageView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(imageView)
            self.imageView = imageView
            
            let constraints = [
                imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                imageView.heightAnchor.constraint(equalToConstant: 27),
                imageView.widthAnchor.constraint(equalToConstant: 27),
                imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            ]
            
            return constraints
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    private class ActionSheetDivider: UIView {

        override init(frame: CGRect) {
            super.init(frame: frame)

            let visualEffectView = UIVisualEffectView()
            visualEffectView.effect = UIVibrancyEffect(blurEffect: UIBlurEffect(style: .systemThinMaterial),
                                                                                style: .separator)
            visualEffectView.contentView.backgroundColor = .white
            visualEffectView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(visualEffectView)
            NSLayoutConstraint.activate([
                visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
                visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
                visualEffectView.topAnchor.constraint(equalTo: topAnchor),
                visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: CGSize {
            return CGSize(width: UIView.noIntrinsicMetric, height: 1 / UIScreen.main.scale)
        }
    }

    // MARK: - Presentation

    private class ActionSheetPresentationController: UIPresentationController {
        private lazy var backgroundView: UIView = {
            let backgroundView = UIView()
            backgroundView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissActionSheet)))
            backgroundView.backgroundColor = .black.withAlphaComponent(0.3)
            return backgroundView
        }()

        override var frameOfPresentedViewInContainerView: CGRect {
            guard let containerView = containerView, let presentedView = presentedViewController.view else {
                return .zero
            }

            // Derived from system action sheet
            let availableWidth = min(containerView.bounds.width - 32, 382)
            let height =  presentedView.systemLayoutSizeFitting(CGSize(width: availableWidth,
                                                                       height: .greatestFiniteMagnitude),
                                                                withHorizontalFittingPriority: .required,
                                                                verticalFittingPriority: .fittingSizeLevel).height

            return CGRect(x: containerView.bounds.midX - availableWidth / 2,
                          y: containerView.bounds.maxY - height - containerView.safeAreaInsets.bottom,
                          width: availableWidth,
                          height: height)

        }

        override func containerViewDidLayoutSubviews() {
            super.containerViewDidLayoutSubviews()

            presentedViewController.view.frame = frameOfPresentedViewInContainerView
        }

        override func presentationTransitionWillBegin() {
            super.presentationTransitionWillBegin()

            guard let containerView = containerView else {
                return
            }

            backgroundView.translatesAutoresizingMaskIntoConstraints = false
            containerView.insertSubview(backgroundView, at: 0)
            NSLayoutConstraint.activate([
                backgroundView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                backgroundView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                backgroundView.topAnchor.constraint(equalTo: containerView.topAnchor),
                backgroundView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            ])

            guard let transitionCoordinator = presentedViewController.transitionCoordinator else {
                return
            }

            backgroundView.alpha = 0
            transitionCoordinator.animate { _ in
                self.backgroundView.alpha = 1
            }
        }

        override func dismissalTransitionWillBegin() {
            super.dismissalTransitionWillBegin()

            guard let transitionCoordinator = presentedViewController.transitionCoordinator else {
                return
            }

            transitionCoordinator.animate { _ in
                self.backgroundView.alpha = 0
            }
        }

        override func dismissalTransitionDidEnd(_ completed: Bool) {
            super.dismissalTransitionDidEnd(completed)

            if completed {
                backgroundView.removeFromSuperview()
            }
        }

        @objc private func dismissActionSheet() {
            presentedViewController.dismiss(animated: true)
        }
    }
}
