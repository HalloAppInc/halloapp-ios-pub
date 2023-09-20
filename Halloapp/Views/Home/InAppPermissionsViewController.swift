//
//  InAppPermissionsViewController.swift
//  HalloApp
//
//  Created by Tanveer on 9/19/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import CoreCommon
import Core

class InAppPermissionsViewController: UIViewController {

    enum Configuration { case chat, activityCenter }
    let configuration: Configuration
    private var foregroundCancellable: AnyCancellable?

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        return scrollView
    }()

    private lazy var vStack: UIStackView = {
        let titleStack = UIStackView(arrangedSubviews: [titleLabel])
        titleStack.axis = .vertical
        titleStack.alignment = .center

        let buttonStack = UIStackView(arrangedSubviews: [openSettingsButton])
        buttonStack.axis = .vertical
        buttonStack.alignment = .center
        buttonStack.isLayoutMarginsRelativeArrangement = true
        buttonStack.layoutMargins.top = 30

        let emoji = UILabel()
        emoji.text = "🙂"
        emoji.font = .systemFont(forTextStyle: .title1)
        emoji.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [emoji, titleStack, contactsPermissionExplainer, notificationsPermissionExplainer, buttonStack])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 15
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 50, left: 15, bottom: 50, right: 15)
        stack.setCustomSpacing(10, after: emoji)

        return stack
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = .gothamFont(forTextStyle: .title2, weight: .medium)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        switch configuration {
        case .chat:
            label.text = Localizations.allowContactsForChat
        case .activityCenter:
            label.text = Localizations.allowContactsForActivity
        }

        return label
    }()

    private lazy var contactsPermissionExplainer: PermissionsExplainerView = {
        let view = PermissionsExplainerView(permissionType: .contacts)
        view.titleLabel.text = Localizations.allowContactsTitleNumbered
        view.bodyLabel.text = Localizations.allowContactsMessage
        return view
    }()

    private lazy var notificationsPermissionExplainer: PermissionsExplainerView = {
        let view = PermissionsExplainerView(permissionType: .notifications)
        view.titleLabel.text = Localizations.allowNotificationsTitleNumbered
        view.bodyLabel.text = Localizations.allowNotificationsMessage
        return view
    }()

    private lazy var openSettingsButton: RoundedRectChevronButton = {
        let button = RoundedRectChevronButton()
        button.configuration?.baseBackgroundColor = .systemBlue
        button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 15, leading: 15, bottom: 15, trailing: 15)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(Localizations.allowInSettingsTitle, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.setTitleColor(.white, for: .disabled)
        button.addTarget(self, action: #selector(openSettingsPushed), for: .touchUpInside)
        return button
    }()

    init(configuration: Configuration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("InAppPermissionsViewController coder init not implemented...")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .feedBackground

        view.addSubview(scrollView)
        scrollView.addSubview(vStack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            vStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            vStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            vStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            vStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            vStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            titleLabel.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.75),
            openSettingsButton.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.85),
        ])

        foregroundCancellable = NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task { await self?.checkForNotificationPermissions() }
            }

        Task { await checkForNotificationPermissions() }
    }

    @objc
    private func openSettingsPushed(_ button: UIButton) {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        UIApplication.shared.open(url)
    }

    @MainActor
    private func checkForNotificationPermissions() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus

        switch status {
        case .authorized where !notificationsPermissionExplainer.isHidden:
            notificationsPermissionExplainer.isHidden = true
        case .denied, .notDetermined:
            if notificationsPermissionExplainer.isHidden {
                notificationsPermissionExplainer.isHidden = false
            }
        default:
            break
        }
    }
}

// MARK: - Localization

extension Localizations {

    static var allowContactsTitleNumbered: String {
        NSLocalizedString("allow.contacts.permission.title.numbered",
                   value: "1. Allow Contacts",
                 comment: "Title of the container that explains the need for contacts permission.")
    }

    static var allowNotificationsTitleNumbered: String {
        NSLocalizedString("allow.notifications.permission.title.numbered",
                   value: "2. Allow Notifications",
                 comment: "Title of the container that explains the need for notifications permission.")
    }

    static var allowContactsMessage: String {
        NSLocalizedString("allow.contacts.permission.message",
                   value: "HalloApp needs access to your phone contacts only to connect you with your friends & family. HalloApp never messages anyone on your behalf.",
                 comment: "Message used in the app to explain the need for contacts permission.")
    }

    static var allowNotificationsMessage: String {
        NSLocalizedString("allow.notifications.permission.message",
                   value: "Allow notifications from HalloApp so you don’t miss messages, calls and post updates from your friends.",
                 comment: "Message used in the app to explain the need for notifications permission.")
    }

    static var allowInSettingsTitle: String {
        NSLocalizedString("allow.in.settings.title",
                   value: "Allow in Settings",
                 comment: "Title of a button that opens the settings app.")
    }

    static var allowContactsForChat: String {
        NSLocalizedString("allow.contacts.for.chat",
                   value: "To start chatting, allow access to contacts",
                 comment: "Title of the chats tab when contacts permissions aren't given.")
    }

    static var allowContactsForActivity: String {
        NSLocalizedString("allow.contacts.for.activity",
                   value: "To receive updates from your friends, allow access to contacts.",
                 comment: "Title of the activity tab when contacts permissions aren't given.")
    }
}
