//
//  AccountListViewController.swift
//  HalloApp
//
//  Created by Matt Geimer on 7/9/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import UIKit
import SwiftUI

class SettingsAccountViewController: UITableViewController {

    // MARK: Table View Data Source and Rows

    private enum Section {
        case account
    }

    private enum Row {
        case export
        case delete
    }

    private var dataSource: UITableViewDiffableDataSource<Section, Row>!
    private let cellExport: UITableViewCell = {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = Localizations.exportData
        cell.accessoryType = .disclosureIndicator
        return cell
    }()
    private let cellDelete: UITableViewCell = {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = Localizations.deleteAccount
        cell.accessoryType = .disclosureIndicator
        return cell
    }()

    // MARK: View Controller

    init() {
        super.init(style: .grouped)
        title = Localizations.account
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.backgroundColor = .feedBackground

        dataSource = UITableViewDiffableDataSource<Section, Row>(tableView: tableView, cellProvider: { [weak self] (_, _, row) -> UITableViewCell? in
            guard let self = self else { return nil }
            switch row {
            case .export: return self.cellExport
            case .delete: return self.cellDelete
            }
        })

        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections([ .account ])
        snapshot.appendItems([ .export, .delete ], toSection: .account)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
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
        guard let itemId = dataSource.itemIdentifier(for: indexPath) else {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
        
        switch itemId {
            case .export: openExportView()
            case .delete: openDeleteView()
        }
    }
    
    private func openExportView() {
        let viewController = UIHostingController(rootView: ExportDataView(model: ExportDataModel()))
        viewController.hidesBottomBarWhenPushed = false
        navigationController?.pushViewController(viewController, animated: true)
    }
    
    private func openDeleteView() {
        let viewController = UIHostingController(rootView: DeleteAccountView())
        viewController.hidesBottomBarWhenPushed = false
        navigationController?.pushViewController(viewController, animated: true)
    }
}

private extension Localizations {
    static var account: String {
        NSLocalizedString("settings.account.list.title", value: "Account", comment: "Title for settings page containing account options.")
    }
    
    static var exportData: String {
        NSLocalizedString("settings.account.list.export.data", value: "Export", comment: "Row to export user data for GDPR compliance.")
    }
    
    static var deleteAccount: String {
        NSLocalizedString("settings.account.list.delete.account", value: "Delete", comment: "Button to delete a user's account.")
    }
}
