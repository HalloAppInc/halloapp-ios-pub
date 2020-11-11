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

    static var privacy: String {
        NSLocalizedString("settings.privacy", value: "Privacy", comment: "Settings menu section")
    }

    static var postsPrivacy: String {
        NSLocalizedString("settings.privacy.posts", value: "Posts", comment: "Settings > Privacy: name of a setting that defines who can see your posts.")
    }
}

class SettingsViewController: UITableViewController {

    // MARK: Table View Data Source and Rows

    private enum Section {
        case notifications
        case privacy
    }

    private enum Row {
        case notificationPosts
        case notificationComments
        case privacyPosts
        case privacyBlocked
    }

    private class SettingsTableViewDataSource: UITableViewDiffableDataSource<Section, Row> {

        override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
            let section = snapshot().sectionIdentifiers[section]
            switch section {
            case .notifications:
                return Localizations.notifications
            case .privacy:
                return Localizations.privacy
            }
        }
    }


    private var dataSource: SettingsTableViewDataSource!
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
    private let cellPostsPrivacy: UITableViewCell = {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.accessoryType = .disclosureIndicator
        cell.textLabel?.text = Localizations.postsPrivacy
        return cell
    }()
    private let cellBlockedContacts: UITableViewCell = {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.accessoryType = .disclosureIndicator
        cell.textLabel?.text = PrivacyList.name(forPrivacyListType: .blocked)
        return cell
    }()

    // MARK: View Controller

    init() {
        super.init(style: .grouped)
        title = Localizations.titleSettings
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

        dataSource = SettingsTableViewDataSource(tableView: tableView, cellProvider: { [weak self] (_, _, row) -> UITableViewCell? in
            guard let self = self else { return nil }
            switch row {
            case .notificationPosts: return self.cellPostNotifications
            case .notificationComments: return self.cellCommentNotifications
            case .privacyPosts: return self.cellPostsPrivacy
            case .privacyBlocked: return self.cellBlockedContacts
            }
        })

        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections([ .notifications, .privacy ])
        snapshot.appendItems([ .notificationPosts, .notificationComments ], toSection: .notifications)
        snapshot.appendItems([ .privacyPosts, .privacyBlocked ], toSection: .privacy)
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
        guard let row = dataSource.itemIdentifier(for: indexPath) else {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }

        switch row {
        case .privacyPosts:
            openPostsPrivacy()
        case .privacyBlocked:
            openBlockedContacts()
        default:
            tableView.deselectRow(at: indexPath, animated: true)
        }

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

        let privacySettings = MainAppContext.shared.privacySettings!
        cellPostsPrivacy.detailTextLabel?.text = privacySettings.shortFeedSetting
        cellBlockedContacts.detailTextLabel?.text = privacySettings.blockedSetting
    }

    private func openPostsPrivacy() {
        let privacySettings = MainAppContext.shared.privacySettings!
        let feedPrivacyView = FeedPrivacyView(privacySettings: privacySettings)
        navigationController?.pushViewController(UIHostingController(rootView: feedPrivacyView), animated: true)
    }

    private func openBlockedContacts() {
        let privacySettings = MainAppContext.shared.privacySettings!
        let viewController = PrivacyListViewController(privacyList: privacySettings.blocked, settings: privacySettings)
        viewController.dismissAction = {
            self.reloadSettingValues()
            self.dismiss(animated: true)
        }
        present(UINavigationController(rootViewController: viewController), animated: true) {
            if let indexPathForSelectedRow = self.tableView.indexPathForSelectedRow {
                self.tableView.deselectRow(at: indexPathForSelectedRow, animated: false)
            }
        }
    }

}
