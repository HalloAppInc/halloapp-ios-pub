//
//  UnknownContactSheetViewController.swift
//  HalloApp
//
//  Created by Tanveer on 3/24/22.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import UIKit
import Core
import CoreCommon

class UnknownContactSheetViewController: UIViewController, UIViewControllerTransitioningDelegate {
    private lazy var vStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [summaryLabel, acceptMessageButton, secondaryButtonStack, cancelButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.backgroundColor = .primaryBg
        stack.layoutMargins = UIEdgeInsets(top: 20, left: 27, bottom: 0, right: 27)
        
        stack.setCustomSpacing(20, after: summaryLabel)
        stack.setCustomSpacing(15, after: acceptMessageButton)
        stack.setCustomSpacing(15, after: secondaryButtonStack)
        
        return stack
    }()
    
    private lazy var secondaryButtonStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [addContactButtonContainer, blockButtonContainer])
        stack.axis = .horizontal
        stack.spacing = 12
        
        return stack
    }()
    
    private lazy var summaryLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 15)
        label.textAlignment = .center
        label.text = Localizations.unknownContactNotInContactBook
        
        return label
    }()
    
    private lazy var acceptMessageButton: UIButton = {
        var acceptMessageButtonConfiguration: UIButton.Configuration = .filledCapsule(backgroundColor: .primaryBlue)
        acceptMessageButtonConfiguration.attributedTitle = .init(Localizations.unknownContactAcceptToMessage, 
                                                                 attributes: .init([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]))
        acceptMessageButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 11, leading: 20, bottom: 13, trailing: 20)

        let button = UIButton()
        button.configuration = acceptMessageButtonConfiguration
        button.addTarget(self, action: #selector(pushedAcceptMessage), for: .touchUpInside)
        
        return button
    }()
    
    /// - note: Use a container so we can have both rounded corners and a shadow.
    private lazy var addContactButtonContainer: UIView = {
        let view = UIView()
        view.addSubview(addContactButton)
        NSLayoutConstraint.activate([
            addContactButton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            addContactButton.topAnchor.constraint(equalTo: view.topAnchor),
            addContactButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            addContactButton.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        view.layer.shadowColor = UIColor.black.withAlphaComponent(0.15).cgColor
        view.layer.shadowRadius = 0.5
        view.layer.shadowOpacity = 1
        view.layer.shadowOffset = CGSize(width: 0, height: 0.5)
        
        return view
    }()
    
    private lazy var addContactButton: UIButton = {
        var addContactButtonConfiguration: UIButton.Configuration = .filledCapsule(backgroundColor: .primaryWhiteBlack)
        addContactButtonConfiguration.attributedTitle = .init(Localizations.addToContactBook,
                                                                 attributes: .init([.font: UIFont.systemFont(ofSize: 17, weight: .medium)]))
        addContactButtonConfiguration.baseForegroundColor = .primaryBlue
        addContactButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 11, leading: 20, bottom: 13, trailing: 20)

        let button = UIButton()
        button.configuration = addContactButtonConfiguration
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(pushedAddContact), for: .touchUpInside)
        
        return button
    }()
    
    private lazy var blockButtonContainer: UIView = {
        let view = UIView()
        view.addSubview(blockButton)
        NSLayoutConstraint.activate([
            blockButton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blockButton.topAnchor.constraint(equalTo: view.topAnchor),
            blockButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blockButton.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        view.layer.shadowColor = UIColor.black.withAlphaComponent(0.15).cgColor
        view.layer.shadowRadius = 0.5
        view.layer.shadowOpacity = 1
        view.layer.shadowOffset = CGSize(width: 0, height: 0.5)
        
        return view
    }()
    
    private lazy var blockButton: UIButton = {
        var blockButtonConfiguration: UIButton.Configuration = .filledCapsule(backgroundColor: .primaryWhiteBlack)
        blockButtonConfiguration.attributedTitle = .init(Localizations.blockButton,
                                                                 attributes: .init([.font: UIFont.systemFont(ofSize: 17, weight: .medium)]))
        blockButtonConfiguration.baseForegroundColor = .red
        blockButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 11, leading: 20, bottom: 13, trailing: 20)

        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(pushedBlock), for: .touchUpInside)
        return button
    }()
    
    private lazy var cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(Localizations.buttonCancel, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.addTarget(self, action: #selector(pushedCancel), for: .touchUpInside)
        button.setTitleColor(.systemBlue, for: .normal)
        
        return button
    }()
    
    var acceptAction: (() -> Void)?
    var addContactAction: (() -> Void)?
    var blockAction: (() -> Void)?
    var cancelAction: (() -> Void)?
    
    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .custom
        modalTransitionStyle = .coverVertical
        transitioningDelegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("Unknown contact sheet required init not implemented...")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(vStack)
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: view.topAnchor),
            vStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            vStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            vStack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        addContactButtonContainer.layer.shadowPath = UIBezierPath(roundedRect: addContactButton.bounds,
                                                                 cornerRadius: addContactButton.bounds.height / 2).cgPath
        
        blockButtonContainer.layer.shadowPath = UIBezierPath(roundedRect: blockButton.bounds,
                                                            cornerRadius: blockButton.bounds.height / 2).cgPath
    }
    
    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        return ContactSheetPresentationController(presentedViewController: presented, presenting: presenting)
    }
}

// MARK: - button selectors

extension UnknownContactSheetViewController {
    @objc
    private func pushedAcceptMessage(_ button: UIButton) {
        acceptAction?()
    }
    
    @objc
    private func pushedAddContact(_ button: UIButton) {
        addContactAction?()
    }
    
    @objc
    private func pushedBlock(_ button: UIButton) {
        blockAction?()
    }
    
    @objc
    private func pushedCancel(_ button: UIButton) {
        cancelAction?()
    }
}

// MARK: - presentation controller implementation

public class ContactSheetPresentationController: UIPresentationController {
    private lazy var backgroundView: UIView = {
        let backgroundView = UIView()
        backgroundView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissActionSheet)))
        backgroundView.backgroundColor = .black.withAlphaComponent(0.1)
        return backgroundView
    }()

    public override var frameOfPresentedViewInContainerView: CGRect {
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

    public override func containerViewDidLayoutSubviews() {
        super.containerViewDidLayoutSubviews()
        guard let presentedView = presentedViewController.view else {
            return
        }

        presentedView.frame = frameOfPresentedViewInContainerView
        
        presentedView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        presentedView.layer.cornerRadius = 15
        presentedView.layer.masksToBounds = true
    }

    public override func presentationTransitionWillBegin() {
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
        (presentedViewController as? UnknownContactSheetViewController)?.cancelAction?()
    }
}

// MARK: - localization

extension Localizations {
    static var unknownContactNotInContactBook: String {
        NSLocalizedString("unknown.contact.not.in.contact.book",
                   value: "This sender is not in your contact book.",
                 comment: "Informational label that's shown in the banner for an unknown contact when they message the user for the first time")
    }
    
    static var unknownContactAcceptToMessage: String {
        NSLocalizedString("unknown.contact.accept.to.message",
                   value: "Accept Message",
                 comment: "Text for action label that lets the user accept messages from unknown contacts")
    }
}
