//
//  MomentsExplainerViewController.swift
//  HalloApp
//
//  Created by Tanveer on 6/16/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Core
import CoreCommon

class MomentsExplainerViewController: UIViewController, UIViewControllerTransitioningDelegate {

    private lazy var vStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel, actionButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 25
        stack.setCustomSpacing(35, after: descriptionLabel)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.insetsLayoutMarginsFromSafeArea = true
        stack.layoutMargins = UIEdgeInsets(top: 50, left: 15, bottom: 50, right: 15)
        return stack
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 35, weight: .bold)
        label.text = Localizations.introducingMoments
        label.numberOfLines = 0
        label.textColor = .black.withAlphaComponent(0.9)
        return label
    }()

    private lazy var descriptionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(forTextStyle: .headline)
        label.text = Localizations.describingMoments
        label.numberOfLines = 0
        label.textColor = .black.withAlphaComponent(0.9)
        return label
    }()

    private lazy var actionButton: UIButton = {
        let button = UIButton(type: .system)
        button.contentEdgeInsets = UIEdgeInsets(top: 15, left: 10, bottom: 15, right: 10)
        button.setBackgroundColor(.systemBlue, for: .normal)

        button.setTitleColor(.white, for: .normal)
        button.setTitle(Localizations.tryMoments, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        button.addTarget(self, action: #selector(closeButtonPushed), for: .touchUpInside)

        button.layer.masksToBounds = true
        button.layer.cornerRadius = 12
        button.layer.cornerCurve = .continuous

        return button
    }()

    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 30, weight: .regular, scale: .default)
        let image = UIImage(systemName: "xmark.circle.fill", withConfiguration: config)

        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(image, for: .normal)
        button.addTarget(self, action: #selector(closeButtonPushed), for: .touchUpInside)
        button.tintColor = .lightGray

        return button
    }()

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .custom
        modalTransitionStyle = .coverVertical
        transitioningDelegate = self
    }

    @objc
    private func closeButtonPushed(_ sender: UIButton) {
        close()
    }

    func close() {
        dismiss(animated: true)
    }

    required init?(coder: NSCoder) {
        fatalError("MomentsExplainerViewController coder init not implemented...")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        view.addSubview(vStack)
        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            vStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            vStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            vStack.topAnchor.constraint(equalTo: view.topAnchor),
            vStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            closeButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
        ])
    }

    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        return MomentsExplainerPresentationController(presentedViewController: presented, presenting: presenting)
    }
}

// MARK: -

fileprivate class MomentsExplainerPresentationController: UIPresentationController {
    private lazy var backgroundView: UIView = {
        let view = UIView()
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissActionSheet)))
        view.backgroundColor = .black.withAlphaComponent(0.4)
        return view
    }()

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView = containerView, let presentedView = presentedViewController.view else {
            return .zero
        }

        let width = containerView.bounds.width
        let height =  presentedView.systemLayoutSizeFitting(CGSize(width: width,
                                                                  height: .greatestFiniteMagnitude),
                             withHorizontalFittingPriority: .required,
                                   verticalFittingPriority: .fittingSizeLevel).height

        return CGRect(x: containerView.bounds.midX - width / 2,
                      y: containerView.bounds.maxY - height,
                  width: width,
                 height: height)
    }

    override func containerViewDidLayoutSubviews() {
        super.containerViewDidLayoutSubviews()
        guard let presentedView = presentedViewController.view else {
            return
        }

        presentedView.frame = frameOfPresentedViewInContainerView

        presentedView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        presentedView.layer.cornerRadius = 15
        presentedView.layer.cornerCurve = .continuous
        presentedView.layer.masksToBounds = true
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

    public override func dismissalTransitionWillBegin() {
        super.dismissalTransitionWillBegin()

        guard let transitionCoordinator = presentedViewController.transitionCoordinator else {
            return
        }

        transitionCoordinator.animate { _ in
            self.backgroundView.alpha = 0
        }
    }

    public override func dismissalTransitionDidEnd(_ completed: Bool) {
        super.dismissalTransitionDidEnd(completed)

        if completed {
            backgroundView.removeFromSuperview()
        }
    }

    @objc private func dismissActionSheet() {
        (presentedViewController as? MomentsExplainerViewController)?.close()
    }
}

// MARK: - localization

fileprivate extension Localizations {
    static var introducingMoments: String {
        NSLocalizedString("introducing.moments",
                   value: "Introducing Moments",
                 comment: "Title of the bottom sheet that is presented only once to explain the moments feature.")
    }

    static var describingMoments: String {
        NSLocalizedString("describing.moments",
                   value: "See your friends’ moments by sharing your own. Moments are casual, they disappear after 24 hours.",
                 comment: "Body of the bottom sheet that is presented only once to explain the moments feature.")
    }

    static var tryMoments: String {
        NSLocalizedString("try.moments",
                   value: "Try Moments",
                 comment: "Text on the bottom sheet's button that dismisses the sheet.")
    }
}
