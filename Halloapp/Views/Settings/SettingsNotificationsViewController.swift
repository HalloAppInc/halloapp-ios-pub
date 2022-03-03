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

private extension Localizations {

    static var notifications: String {
        NSLocalizedString("settings.notifications", value: "Notifications", comment: "Settings menu section.")
    }

    static var postNotifications: String {
        NSLocalizedString("settings.notifications.posts", value: "Posts", comment: "Settings > Notifications: label for the toggle that turns new post notifications on or off.")
    }

    static var commentNotifications: String {
        NSLocalizedString("settings.notifications.comments", value: "Comments", comment: "Settings > Notifications: label for the toggle that turns new comment notifications on or off.")
    }

    static var notificationsDisabledInstructions: String {
        NSLocalizedString("settings.notifications.disabled.instructions", value: "Please turn on notifications in Settings.", comment: "Instructions for enabling notifications permissions")
    }
}

class SettingsNotificationsViewController: UITableViewController {

    // MARK: Table View Data Source and Rows

    private enum Section {
        case notifications
    }

    private enum Row {
        case notificationPosts
        case notificationComments
    }

    private static let SettingsReuseIdentifier = "SettingsReuseIdentifier"
    private var isAuthorized: Bool?

    private lazy var disabledWarning: UIView = {
        let label = UILabel()
        label.text = Localizations.notificationsDisabledInstructions
        label.numberOfLines = 0

        let button = UIButton()
        button.setTitle(Localizations.buttonGoToSettings, for: .normal)
        button.setTitleColor(.systemBlue, for: .normal)
        button.addTarget(self, action: #selector(goToSettings), for: .touchUpInside)
        button.contentHorizontalAlignment = .leading

        let view = UIView()
        view.addSubview(label)
        view.addSubview(button)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.constrainMargins([.leading, .top, .trailing], to: view)

        button.translatesAutoresizingMaskIntoConstraints = false
        button.constrainMargins([.leading, .bottom], to: view)
        button.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8).isActive = true
        button.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor).isActive = true

        return view
    }()

    private lazy var dataSource: UITableViewDiffableDataSource<Section, Row> = {
        return UITableViewDiffableDataSource<Section, Row>(tableView: tableView, cellProvider: { [weak self] (tableView, indexPath, row) -> UITableViewCell? in
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.SettingsReuseIdentifier, for: indexPath)
            self?.configure(cell: cell, for: row, settings: NotificationSettings.current, isAuthorized: self?.isAuthorized ?? false)
            return cell
        })
    }()

    // MARK: View Controller

    init() {
        super.init(style: .grouped)
        title = Localizations.titleNotifications
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = .feedBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.SettingsReuseIdentifier)
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadSettingValues()
    }

    // MARK: UITableView

    private func configure(cell: UITableViewCell, for row: Row, settings: NotificationSettings, isAuthorized: Bool) {
        cell.selectionStyle = .none

        switch row {
        case .notificationComments:
            let control = UISwitch()
            control.addTarget(self, action: #selector(commentNotificationsValueChanged), for: .valueChanged)
            control.isOn = settings.isCommentsEnabled
            control.isEnabled = isAuthorized

            cell.textLabel?.text = Localizations.commentNotifications
            cell.accessoryView = control
        case .notificationPosts:
            let control = UISwitch()
            control.addTarget(self, action: #selector(postNotificationsValueChanged), for: .valueChanged)
            control.isOn = settings.isPostsEnabled
            control.isEnabled = isAuthorized

            cell.textLabel?.text = Localizations.postNotifications
            cell.accessoryView = control
        }
    }

    // MARK: Settings

    @objc private func postNotificationsValueChanged(_ sender: AnyObject) {
        guard let postsSwitch = sender as? UISwitch else { return }
        NotificationSettings.current.isPostsEnabled = postsSwitch.isOn
    }

    @objc private func commentNotificationsValueChanged(_ sender: AnyObject) {
        NotificationSettings.current.isCommentsEnabled = sender.isOn
    }

    @objc private func willEnterForeground() {
        reloadSettingValues()
    }

    @objc private func goToSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func updateUI() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections([ .notifications ])
        if isAuthorized != nil {
            snapshot.appendItems([ .notificationPosts, .notificationComments ], toSection: .notifications)
        }
        dataSource.apply(snapshot, animatingDifferences: false)

        let availableSize = CGSize(width: tableView.bounds.width, height: .greatestFiniteMagnitude)
        let fitSize = disabledWarning.systemLayoutSizeFitting(availableSize)
        disabledWarning.frame = CGRect(origin: .zero, size: CGSize(width: availableSize.width, height: fitSize.height))
        tableView.tableFooterView = (isAuthorized ?? true) ? nil : disabledWarning
    }

    private func reloadSettingValues() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let isKnownAuthorized: Bool = {
                switch settings.authorizationStatus {
                case .authorized, .ephemeral, .provisional:
                    return true
                case .denied, .notDetermined:
                    return false
                @unknown default:
                    return false
                }
            }()
            DispatchQueue.main.async {
                self?.isAuthorized = isKnownAuthorized
                self?.updateUI()
            }
        }
    }
}
