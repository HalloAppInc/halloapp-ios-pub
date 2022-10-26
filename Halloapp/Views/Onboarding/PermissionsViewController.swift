//
//  PermissionsViewController.swift
//  HalloApp
//
//  Created by Tanveer on 8/17/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import CoreCommon
import CocoaLumberjackSwift

class PermissionsViewController: UIViewController {

    let onboardingManager: OnboardingManager
    private var cancellables: Set<AnyCancellable> = []

    private lazy var logoView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.image = UIImage(named: "RegistrationLogo")?.withRenderingMode(.alwaysTemplate)
        view.tintColor = .lavaOrange
        view.contentMode = .scaleAspectFit
        return view
    }()

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        return scrollView
    }()

    private lazy var vStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [UIView(), contactPermissionsExplainer, notificationPermissionsExplainer, syncProgressStack, UIView()])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 15)
        stack.axis = .vertical
        stack.spacing = 20
        stack.setCustomSpacing(40, after: notificationPermissionsExplainer)

        return stack
    }()

    private lazy var contactPermissionsExplainer: PermissionsExplainerView = {
        let view = PermissionsExplainerView(permissionType: .contacts)
        view.titleLabel.text = Localizations.contactsPermissionExplanationTitle
        view.bodyLabel.text = Localizations.registrationContactPermissionsMessage
        return view
    }()

    private lazy var notificationPermissionsExplainer: PermissionsExplainerView = {
        let view = PermissionsExplainerView(permissionType: .notifications)
        view.titleLabel.text = Localizations.titleNotifications
        view.bodyLabel.text = Localizations.registrationNotificationPermissionsMessage
        return view
    }()

    private lazy var getStartedButtonStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [getStartedButton])
        let padding = OnboardingConstants.bottomButtonPadding
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.axis = .vertical
        stack.alignment = .center
        stack.layoutMargins = UIEdgeInsets(top: padding, left: 0, bottom: padding, right: 0)
        return stack
    }()

    private lazy var getStartedButton: RoundedRectButton = {
        let button = RoundedRectButton()
        let font = UIFont.systemFont(ofSize: 18, weight: .semibold)

        button.backgroundTintColor = .lavaOrange
        button.layer.cornerCurve = .continuous
        button.setTitle(Localizations.registrationGetStarted, for: .normal)
        button.titleLabel?.font = font
        button.tintColor = .white

        button.contentEdgeInsets = OnboardingConstants.bottomButtonInsets
        button.setContentCompressionResistancePriority(.required, for: .vertical)

        button.addTarget(self, action: #selector(getStartedButtonPushed), for: .touchUpInside)
        return button
    }()

    private lazy var syncProgressStack: UIStackView = {
        let label = UILabel()
        label.text = Localizations.registrationSyncingContacts
        label.font = .systemFont(forTextStyle: .body, pointSizeChange: -3)
        label.textColor = .tertiaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [syncProgressView, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 15
        stack.arrangedSubviews.forEach { $0.isHidden = true }

        return stack
    }()

    private lazy var syncProgressView: UIProgressView = {
        let progressView = UIProgressView()
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.tintColor = .systemBlue
        return progressView
    }()

    init(onboardingManager: OnboardingManager) {
        self.onboardingManager = onboardingManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("PermissionsViewController coder init not implemented...")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.hidesBackButton = true
        view.backgroundColor = .feedBackground

        view.addSubview(logoView)
        view.addSubview(scrollView)
        scrollView.addSubview(vStack)
        view.addSubview(getStartedButtonStack)

        let vStackCenterConstraint = vStack.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        vStackCenterConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            logoView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 40),
            logoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            logoView.heightAnchor.constraint(equalToConstant: 30),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: logoView.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: getStartedButtonStack.topAnchor),

            vStack.topAnchor.constraint(greaterThanOrEqualTo: scrollView.topAnchor),
            vStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            vStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            vStack.bottomAnchor.constraint(lessThanOrEqualTo: scrollView.bottomAnchor),
            vStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            vStackCenterConstraint,

            syncProgressView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.65),

            getStartedButtonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            getStartedButtonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            getStartedButtonStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -OnboardingConstants.bottomButtonBottomDistance),
        ])
    }

    @objc
    private func getStartedButtonPushed(_ button: UIButton) {
        getStartedButton.isEnabled = false
        Task { await requestContactAccess() }
    }

    @MainActor
    private func requestContactAccess() async {
        guard await onboardingManager.hasContactsPermission else {
            // enter the app without permission
            return onboardingManager.didCompleteOnboardingFlow()
        }

        for await progress in onboardingManager.contactsSyncProgress {
            updateSyncProgress(progress)
        }

        goToNextScreen()
    }

    private func updateSyncProgress(_ progress: Double) {
        DDLogInfo("PermissionsViewController/updateSyncProgress/updating with progress [\(progress)]")
        // allocate 25% of the bar for loading contacts
        let adjusted = Float(progress == 0 ? 0 : 0.25 + 0.75 * progress)
        guard adjusted >= 0, adjusted <= 1 else {
            return
        }

        let shouldScrollToBottom = syncProgressStack.arrangedSubviews.first?.isHidden ?? false

        UIView.animate(withDuration: 0.275, delay: 0, options: [.curveEaseOut]) {
            self.showSyncProgressIfNecessary()
            self.syncProgressView.setProgress(adjusted, animated: true)

            if self.getStartedButton.isEnabled {
                self.getStartedButton.isEnabled = false
            }

        } completion: { [scrollView] _ in
            if shouldScrollToBottom, scrollView.contentSize.height > scrollView.bounds.height {
                let offset = CGPoint(x: 0, y: scrollView.contentSize.height - scrollView.bounds.height + scrollView.contentInset.bottom)
                scrollView.setContentOffset(offset, animated: true)
            }
        }
    }

    private func showSyncProgressIfNecessary() {
        guard syncProgressStack.arrangedSubviews.first?.isHidden ?? false else {
            return
        }

        syncProgressStack.arrangedSubviews.forEach { $0.isHidden = false }
    }

    private func goToNextScreen() {
        let contacts = onboardingManager.fellowContactIDs()

        if contacts.count < 5 {
            // show more onboarding screens
            let vc = ExistingNetworkViewController(onboardingManager: onboardingManager, userIDs: contacts)
            navigationController?.setViewControllers([vc], animated: true)
        } else {
            onboardingManager.didCompleteOnboardingFlow()
        }
    }
}

// MARK: - Localization

extension Localizations {

    static var registrationContactPermissionsMessage: String {
        NSLocalizedString("registration.contact.permissions.mesage",
                   value: "HalloApp never messages anyone on your behalf, and only uses your phone contacts to connect you with friends & family.",
                 comment: "An explainer during registration for why we need contact permissions.")
    }

    static var registrationNotificationPermissionsMessage: String {
        NSLocalizedString("registration.notification.permissions.mesage",
                   value: "Get messages, calls and post updates. You can customize your notifications any time.",
                 comment: "An explainer during registration for why we'd like notification permissions.")
    }

    static var registrationGetStarted: String {
        NSLocalizedString("registration.get.started",
                   value: "Get started!",
                 comment: "Title of a button.")
    }

    static var registrationSyncingContacts: String {
        NSLocalizedString("registration.syncing.contacts",
                   value: "Syncing Contacts",
                 comment: "Message displayed below the progress bar during the app's initial contacts sync.")
    }
}
