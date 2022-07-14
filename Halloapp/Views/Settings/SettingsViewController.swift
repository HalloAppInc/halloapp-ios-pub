//
//  NewSettingsViewController.swift
//  HalloApp
//
//  Created by Tanveer on 4/18/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import CoreCommon

class SettingsViewController: UIViewController, UICollectionViewDelegate {
    private typealias Section = InsetCollectionView.Section
    private typealias Item = InsetCollectionView.Item

    private lazy var collectionView: InsetCollectionView = {
        let collectionView = InsetCollectionView()
        let layout = InsetCollectionView.defaultLayout()
        let config = InsetCollectionView.defaultLayoutConfiguration()
        
        layout.configuration = config
        collectionView.collectionViewLayout = layout
        return collectionView
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = Localizations.titleSettings
        
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        collectionView.delegate = self
        collectionView.backgroundColor = .primaryBg
        
        buildCollection()
    }
    
    private func buildCollection() {
        collectionView.apply(InsetCollectionView.Collection() {
            Section() {
                Item(title: Localizations.titleNotifications, action: { [weak self] in self?.openNotificationsSettings() })
                Item(title: Localizations.titlePrivacy, action: { [weak self] in self?.openPrivacy() })
                Item(title: Localizations.accountRow, action: { [weak self] in self?.openAccount() })
            }
        }
        .separators()
        .disclosure())
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = self.collectionView.data.itemIdentifier(for: indexPath) as? Item else {
            return
        }
        
        collectionView.deselectItem(at: indexPath, animated: true)
        item.action?()
    }
    
    private func openNotificationsSettings() {
        let viewController = NotificationSettingsViewController()
        viewController.hidesBottomBarWhenPushed = false
        navigationController?.pushViewController(viewController, animated: true)
    }
    
    private func openPrivacy() {
        let viewController = PrivacyViewController()
        viewController.hidesBottomBarWhenPushed = false
        navigationController?.pushViewController(viewController, animated: true)
    }
    
    private func openAccount() {
        let viewController = AccountSettingsViewController()
        viewController.hidesBottomBarWhenPushed = false
        navigationController?.pushViewController(viewController, animated: true)
    }
}

// MARK: - localization

extension Localizations {
    static var accountRow: String {
        NSLocalizedString("profile.row.account",
                   value: "Account",
                 comment: "Row in Profile Screen")
    }
}
