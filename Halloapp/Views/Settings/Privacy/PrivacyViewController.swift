//
//  PrivacyViewController.swift
//  HalloApp
//
//  Created by Tony Jiang on 1/20/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import SwiftUI
import UIKit

private extension Localizations {

    static var privacy: String {
        NSLocalizedString("settings.privacy", value: "Privacy", comment: "Settings menu section")
    }

    static var postsPrivacy: String {
        NSLocalizedString("settings.privacy.posts", value: "Posts", comment: "Settings > Privacy: name of a setting that defines who can see your posts.")
    }
}

class PrivacyViewController: UITableViewController {

    // MARK: Table View Data Source and Rows

    private enum Section {
        case privacy
    }

    private enum Row {
        case privacyPosts
        case privacyBlocked
    }

    private class PrivacyTableViewDataSource: UITableViewDiffableDataSource<Section, Row> {

        override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
            let section = snapshot().sectionIdentifiers[section]
            switch section {
            case .privacy:
                return Localizations.privacy
            }
        }
    }


    private var dataSource: PrivacyTableViewDataSource!
    private var switchPostNotifications: UISwitch!
    private var switchCommentNotifications: UISwitch!
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
        title = Localizations.titlePrivacy
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.backgroundColor = .feedBackground

        dataSource = PrivacyTableViewDataSource(tableView: tableView, cellProvider: { [weak self] (_, _, row) -> UITableViewCell? in
            guard let self = self else { return nil }
            switch row {
            case .privacyPosts: return self.cellPostsPrivacy
            case .privacyBlocked: return self.cellBlockedContacts
            }
        })

        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections([ .privacy ])
        snapshot.appendItems([ .privacyPosts, .privacyBlocked ], toSection: .privacy)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadPrivacyValues()
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
        }

    }

    // MARK: Settings

    @objc private func postNotificationsValueChanged() {
        NotificationSettings.current.isPostsEnabled = switchPostNotifications.isOn
    }

    @objc private func commentNotificationsValueChanged() {
        NotificationSettings.current.isCommentsEnabled = switchCommentNotifications.isOn
    }

    private func reloadPrivacyValues() {
        let privacySettings = MainAppContext.shared.privacySettings
        cellPostsPrivacy.detailTextLabel?.text = privacySettings.shortFeedSetting
        cellBlockedContacts.detailTextLabel?.text = privacySettings.blockedSetting
    }

    private func openPostsPrivacy() {
        let privacySettings = MainAppContext.shared.privacySettings
        let feedPrivacyView = FeedPrivacyView(privacySettings: privacySettings)
        navigationController?.pushViewController(UIHostingController(rootView: feedPrivacyView), animated: true)
    }

    private func openBlockedContacts() {
        let privacySettings = MainAppContext.shared.privacySettings
        let viewController = PrivacyListViewController(privacyList: privacySettings.blocked, settings: privacySettings)
        viewController.dismissAction = {
            self.reloadPrivacyValues()
            self.dismiss(animated: true)
        }
        present(UINavigationController(rootViewController: viewController), animated: true) {
            if let indexPathForSelectedRow = self.tableView.indexPathForSelectedRow {
                self.tableView.deselectRow(at: indexPathForSelectedRow, animated: false)
            }
        }
    }

}

