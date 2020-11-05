//
//  ContactsPermissionsViewController.swift
//  HalloApp
//
//  Created by Garrett on 11/5/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import Core
import UIKit

protocol ContactsPermissionsViewControllerDelegate: AnyObject {
    func didAcknowledgeContactsPermissions()
}

final class ContactsPermissionsViewController: UIViewController {

    weak var delegate: ContactsPermissionsViewControllerDelegate?

    let logo = UIImageView()
    let scrollView = UIScrollView()
    let buttonLearnMore = UIButton()
    let buttonNext = UIButton()

    private weak var overlay: Overlay?
    private lazy var overlayContainer: OverlayContainer = {
        let targetView: UIView = tabBarController?.view ?? view
        let overlayContainer = OverlayContainer()
        overlayContainer.translatesAutoresizingMaskIntoConstraints = false
        targetView.addSubview(overlayContainer)
        overlayContainer.constrain(to: targetView)
        return overlayContainer
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.hidesBackButton = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.preservesSuperviewLayoutMargins = true

        navigationItem.backButtonTitle = ""

        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.image = UIImage(named: "RegistrationLogo")?.withRenderingMode(.alwaysTemplate)
        logo.tintColor = .lavaOrange
        logo.setContentCompressionResistancePriority(.required, for: .vertical)

        let labelTitle = UILabel()
        labelTitle.translatesAutoresizingMaskIntoConstraints = false
        labelTitle.text = Localizations.registrationContactPermissionsTitle
        labelTitle.font = .systemFont(forTextStyle: .title1, weight: .medium)
        labelTitle.numberOfLines = 0

        let labelExplanation = UILabel()
        labelExplanation.translatesAutoresizingMaskIntoConstraints = false
        labelExplanation.text = Localizations.registrationContactPermissionsContent
        labelExplanation.textColor = .secondaryLabel
        labelExplanation.font = .systemFont(forTextStyle: .callout)
        labelExplanation.numberOfLines = 0
        labelExplanation.setContentCompressionResistancePriority(.required, for: .vertical)

        buttonLearnMore.translatesAutoresizingMaskIntoConstraints = false
        buttonLearnMore.setTitle(Localizations.linkLearnMore, for: .normal)
        buttonLearnMore.setTitleColor(.label, for: .normal)
        buttonLearnMore.contentHorizontalAlignment = .leading
        buttonLearnMore.setContentCompressionResistancePriority(.required, for: .vertical)
        buttonLearnMore.addTarget(self, action: #selector(didTapLearnMore), for: .touchUpInside)

        buttonNext.translatesAutoresizingMaskIntoConstraints = false
        buttonNext.layer.masksToBounds = true
        buttonNext.setTitle(Localizations.buttonNext, for: .normal)
        buttonNext.setBackgroundColor(.lavaOrange, for: .normal)
        buttonNext.setBackgroundColor(UIColor.lavaOrange.withAlphaComponent(0.5), for: .highlighted)
        buttonNext.setBackgroundColor(.systemGray4, for: .disabled)
        buttonNext.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        buttonNext.setContentCompressionResistancePriority(.required, for: .vertical)
        buttonNext.addTarget(self, action: #selector(didTapNext), for: .touchUpInside)

        let stackView = UIStackView(arrangedSubviews: [labelTitle, labelExplanation, buttonLearnMore])
        stackView.alignment = .fill
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.setCustomSpacing(4, after: labelExplanation)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        view.backgroundColor = .feedBackground

        // View hierarchy

        scrollView.addSubview(logo)
        scrollView.addSubview(stackView)
        scrollView.addSubview(buttonNext)

        view.addSubview(scrollView)

        // Constraints

        scrollView.constrain([.leading, .trailing, .top, .bottom], to: view)

        logo.constrain(anchor: .top, to: scrollView.contentLayoutGuide, constant: 32)
        logo.constrainMargin(anchor: .leading, to: scrollView)

        stackView.constrainMargins([.leading, .trailing], to: view)
        stackView.topAnchor.constraint(equalTo: logo.bottomAnchor, constant: 32).isActive = true
        stackView.bottomAnchor.constraint(lessThanOrEqualTo: buttonNext.topAnchor, constant: -32).isActive = true

        buttonNext.constrainMargins([.leading, .trailing], to: view)
        buttonNext.constrain([.centerY], to: view, priority: .defaultHigh)
        buttonNext.constrain(anchor: .bottom, to: scrollView.contentLayoutGuide)
        buttonNext.topAnchor.constraint(greaterThanOrEqualTo: stackView.topAnchor, constant: 32).isActive = true
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        buttonNext.layer.cornerRadius = (0.5 * buttonNext.frame.height).rounded()
        let effectiveContentHeight = scrollView.contentSize.height + scrollView.adjustedContentInset.bottom + scrollView.adjustedContentInset.top
        scrollView.isScrollEnabled = effectiveContentHeight > self.scrollView.frame.height
    }

    @objc
    private func didTapNext() {
        delegate?.didAcknowledgeContactsPermissions()
    }

    @objc
    private func didTapLearnMore() {
        showPrivacyModal()
    }

    private func showPrivacyModal(completion: (() -> Void)? = nil) {
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = Localizations.registrationPrivacyModalTitle
        titleLabel.numberOfLines = 0
        titleLabel.font = .systemFont(forTextStyle: .title3, weight: .medium)
        titleLabel.textColor = UIColor.label

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = Localizations.registrationPrivacyModalContent
        label.numberOfLines = 0
        label.font = .systemFont(forTextStyle: .callout)
        label.textColor = UIColor.label.withAlphaComponent(0.5)

        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentCompressionResistancePriority(.required, for: .vertical)
        button.setTitle(Localizations.buttonOK, for: .normal)
        button.setTitleColor(UIColor.nux, for: .normal)
        button.titleLabel?.font = .systemFont(forTextStyle: .callout, weight: .bold)
        button.addTarget(self, action: #selector(dismissOverlay), for: .touchUpInside)

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(titleLabel)
        contentView.addSubview(label)
        contentView.addSubview(button)

        titleLabel.constrainMargins([.top, .leading, .trailing], to: contentView)

        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.constrainMargins([.leading, .trailing], to: contentView)
        label.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 15).isActive = true

        button.constrainMargins([.trailing, .bottom], to: contentView)
        button.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 15).isActive = true
        button.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor).isActive = true

        let sheet = BottomSheet(innerView: contentView, completion: completion)

        overlay = sheet
        overlayContainer.display(sheet)
    }

    @objc
    private func dismissOverlay() {
        if let currentOverlay = overlay {
            overlayContainer.dismiss(currentOverlay)
        }
        overlay = nil
    }
}
