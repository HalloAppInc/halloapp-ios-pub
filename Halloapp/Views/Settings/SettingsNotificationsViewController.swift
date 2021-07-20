//
//  SettingsViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 11/10/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import Core
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

    private class SettingsNotificationsTableViewDataSource: UITableViewDiffableDataSource<Section, Row> {

        override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
            let section = snapshot().sectionIdentifiers[section]
            switch section {
            case .notifications:
                return nil
            }
        }
    }


    private var dataSource: SettingsNotificationsTableViewDataSource!
    private var switchPostNotifications: UISwitch!
    private var switchCommentNotifications: UISwitch!
    private let cellPostNotifications: UITableViewCell = {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.textLabel?.text = Localizations.postNotifications
        return cell
    }()
    private let cellCommentNotifications: UITableViewCell = {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.textLabel?.text = Localizations.commentNotifications
        return cell
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

        switchPostNotifications = UISwitch()
        switchPostNotifications.addTarget(self, action: #selector(postNotificationsValueChanged), for: .valueChanged)
        cellPostNotifications.accessoryView = switchPostNotifications

        switchCommentNotifications = UISwitch()
        switchCommentNotifications.addTarget(self, action: #selector(commentNotificationsValueChanged), for: .valueChanged)
        cellCommentNotifications.accessoryView = switchCommentNotifications

        dataSource = SettingsNotificationsTableViewDataSource(tableView: tableView, cellProvider: { [weak self] (_, _, row) -> UITableViewCell? in
            guard let self = self else { return nil }
            switch row {
            case .notificationPosts: return self.cellPostNotifications
            case .notificationComments: return self.cellCommentNotifications
            }
        })

        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections([ .notifications ])
        snapshot.appendItems([ .notificationPosts, .notificationComments ], toSection: .notifications)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadSettingValues()
    }

    // MARK: UITableViewDelegate

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        guard let cell = tableView.cellForRow(at: indexPath) else {
            return nil
        }
        guard cell.selectionStyle != .none else {
            return nil
        }
        return indexPath
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard dataSource.itemIdentifier(for: indexPath) != nil else {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }

    // MARK: Settings

    @objc private func postNotificationsValueChanged() {
        NotificationSettings.current.isPostsEnabled = switchPostNotifications.isOn
    }

    @objc private func commentNotificationsValueChanged() {
        NotificationSettings.current.isCommentsEnabled = switchCommentNotifications.isOn
    }

    private func reloadSettingValues() {
        let notificationSettings = NotificationSettings.current
        switchPostNotifications.isOn = notificationSettings.isPostsEnabled
        switchCommentNotifications.isOn = notificationSettings.isCommentsEnabled
    }
}
