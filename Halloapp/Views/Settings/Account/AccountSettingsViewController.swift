//
//  AccountListViewController.swift
//  HalloApp
//
//  Created by Matt Geimer on 7/9/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import UIKit
import SwiftUI

class AccountSettingsViewController: UIViewController, UICollectionViewDelegate {
    typealias Section = InsetCollectionView.Section
    typealias Item = InsetCollectionView.Item
    
    private lazy var collectionView: InsetCollectionView = {
        let collectionView = InsetCollectionView()
        let layout = InsetCollectionView.defaultLayout()
        let config = InsetCollectionView.defaultLayoutConfiguration()
        
        layout.configuration = config
        collectionView.collectionViewLayout = layout
        return collectionView
    }()
    
    init() {
        super.init(nibName: nil, bundle: nil)
        title = Localizations.account
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .primaryBg
        collectionView.backgroundColor = nil
        collectionView.delegate = self
        
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        collectionView.apply(InsetCollectionView.Collection {
            Section {
                if ServerProperties.isInternalUser {
                    Item(title: Localizations.titleStorage, action: { [weak self] in self?.openStorage() })
                }

                Item(title: Localizations.exportData, action: { [weak self] in self?.openExportView() })
                Item(title: Localizations.deleteAccount, action: { [weak self] in self?.openDeleteView() })
            }
        }
        .seperators()
        .disclosure())
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = self.collectionView.data.itemIdentifier(for: indexPath) as? Item else {
            return
        }
        
        collectionView.deselectItem(at: indexPath, animated: true)
        item.action?()
    }
    
    private func openStorage() {
        let viewController = StorageViewController()
        viewController.hidesBottomBarWhenPushed = false
        navigationController?.pushViewController(viewController, animated: true)
    }
    
    private func openExportView() {
        let viewController = UIHostingController(rootView: ExportDataView(model: ExportDataModel()))
        viewController.hidesBottomBarWhenPushed = false
        navigationController?.pushViewController(viewController, animated: true)
    }
    
    private func openDeleteView() {
        let viewController = DeleteAccountViewController()
        viewController.hidesBottomBarWhenPushed = false
        navigationController?.pushViewController(viewController, animated: true)
    }
}

// MARK: - localization

private extension Localizations {
    static var account: String {
        NSLocalizedString("settings.account.list.title",
                   value: "Account",
                 comment: "Title for settings page containing account options.")
    }
    
    static var exportData: String {
        NSLocalizedString("settings.account.list.export.data",
                   value: "Export",
                 comment: "Row to export user data for GDPR compliance.")
    }
    
    static var deleteAccount: String {
        NSLocalizedString("settings.account.list.delete.account",
                   value: "Delete",
                 comment: "Button to delete a user's account.")
    }
}
