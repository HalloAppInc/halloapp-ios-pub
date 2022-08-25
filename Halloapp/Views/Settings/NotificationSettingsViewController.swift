//
//  SettingsViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 11/10/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import SwiftUI
import UIKit
import Combine
import CoreGraphics

class NotificationSettingsViewController: UIViewController, UICollectionViewDelegate {
    
    private lazy var collectionView: InsetCollectionView = {
        let collectionView = InsetCollectionView()
        let layout = InsetCollectionView.defaultLayout
        let config = InsetCollectionView.defaultLayoutConfiguration
        
        config.boundarySupplementaryItems = [
            NSCollectionLayoutBoundarySupplementaryItem(layoutSize: .init(widthDimension: .fractionalWidth(1.0),
                                                                         heightDimension: .estimated(44)),
                                                       elementKind: UICollectionView.elementKindSectionFooter,
                                                         alignment: .bottom),
        ]
    
        layout.configuration = config
        collectionView.collectionViewLayout = layout
        return collectionView
    }()
    
    private var cancellables: Set<AnyCancellable> = []

    init() {
        super.init(nibName: nil, bundle: nil)
        title = Localizations.titleNotifications
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .primaryBg
        
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        collectionView.backgroundColor = nil
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification, object: nil).sink { [weak self] _ in
            self?.fetchNotificationPermissionsAndRefresh()
        }.store(in: &cancellables)

        collectionView.delegate = self
        collectionView.data.supplementaryViewProvider = supplementaryViewProvider
        
        collectionView.register(NotificationsDisabledWarningView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
                                       withReuseIdentifier: NotificationsDisabledWarningView.reuseIdentifier)
        
        fetchNotificationPermissionsAndRefresh()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    private func buildCollection(enabled: Bool) {
        let postsEnabled = NotificationSettings.current.isPostsEnabled
        let commentsEnabled = NotificationSettings.current.isCommentsEnabled
        let momentsEnabled = NotificationSettings.current.isMomentsEnabled
        typealias Item = InsetCollectionView.Item

        collectionView.apply(InsetCollectionView.Collection {
            InsetCollectionView.Section {
                Item(title: Localizations.postNotifications,
                     style: .toggle(initial: postsEnabled,
                                  isEnabled: enabled,
                                  onChanged: { [weak self] in self?.postNotificationsChanged(to: $0) }))

                Item(title: Localizations.commentNotifications,
                     style: .toggle(initial: commentsEnabled,
                                  isEnabled: enabled,
                                  onChanged: { [weak self] in self?.commentsNotificationsChanged(to: $0) }))

                Item(title: Localizations.momentNotifications,
                     style: .toggle(initial: momentsEnabled,
                                  isEnabled: enabled,
                                  onChanged: { [weak self] in self?.momentsNotificationsChanged(to: $0) }))
            }
        }
        .separators())
    }
    
    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        return false
    }
    
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        return false
    }
    
    private func supplementaryViewProvider(_ collectionView: UICollectionView, _ elementKind: String, _ indexPath: IndexPath) -> UICollectionReusableView {
        let footer = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionFooter,
                                                        withReuseIdentifier: NotificationsDisabledWarningView.reuseIdentifier,
                                                                        for: indexPath)
        
        footer.isHidden = true
        (footer as? NotificationsDisabledWarningView)?.settingsAction = goToSettings
        
        return footer
    }

    private func postNotificationsChanged(to value: Bool) {
        NotificationSettings.current.isPostsEnabled = value
    }

    private func commentsNotificationsChanged(to value: Bool) {
        NotificationSettings.current.isCommentsEnabled = value
    }

    private func momentsNotificationsChanged(to value: Bool) {
        NotificationSettings.current.isMomentsEnabled = value
    }

    @objc
    private func goToSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func fetchNotificationPermissionsAndRefresh() {
        Task { [weak self] in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let allowsNotifications: Bool
            
            switch settings.authorizationStatus {
            case .authorized, .ephemeral, .provisional:
                allowsNotifications = true
            case .denied, .notDetermined:
                allowsNotifications = false
            @unknown default:
                allowsNotifications = false
            }
            
            self?.refreshUI(allowsNotifications: allowsNotifications)
        }
    }

    @MainActor
    private func refreshUI(allowsNotifications: Bool) {
        buildCollection(enabled: allowsNotifications)
        
        let footer = collectionView.supplementaryView(forElementKind: UICollectionView.elementKindSectionFooter, at: IndexPath(index: 0))
        footer?.isHidden = allowsNotifications
    }
}

fileprivate class NotificationsDisabledWarningView: UICollectionReusableView {
    static let reuseIdentifier = "notificationsDisabled"
    var settingsAction: (() -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        let messageLabel = UILabel()
        messageLabel.text = Localizations.notificationsDisabledInstructions
        messageLabel.numberOfLines = 0
        messageLabel.font = .systemFont(forTextStyle: .callout)
        
        let button = UIButton(type: .system)
        button.setTitle(Localizations.buttonGoToSettings, for: .normal)
        button.setTitleColor(.systemBlue, for: .normal)
        button.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.font = messageLabel.font
        
        let stack = UIStackView(arrangedSubviews: [messageLabel, button])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 25, left: 20, bottom: 0, right: 20)
        
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    @objc
    private func settingsTapped(_ button: UIButton) {
        settingsAction?()
    }
}

// MARK: - localization

private extension Localizations {
    static var notifications: String {
        NSLocalizedString("settings.notifications",
                   value: "Notifications",
                 comment: "Settings menu section.")
    }

    static var postNotifications: String {
        NSLocalizedString("settings.notifications.posts",
                   value: "Posts",
                 comment: "Settings > Notifications: label for the toggle that turns new post notifications on or off.")
    }

    static var commentNotifications: String {
        NSLocalizedString("settings.notifications.comments",
                   value: "Comments",
                 comment: "Settings > Notifications: label for the toggle that turns new comment notifications on or off.")
    }

    static var momentNotifications: String {
        NSLocalizedString("settings.notifications.moments",
                   value: "Moments",
                 comment: "Settings > Notifications: label for the toggle that turns new moment notifications on or off.")
    }

    static var notificationsDisabledInstructions: String {
        NSLocalizedString("settings.notifications.disabled.instructions",
                   value: "Please turn on notifications in Settings.",
                 comment: "Instructions for enabling notifications permissions")
    }
}
