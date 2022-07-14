//
//  PrivacyViewController.swift
//  HalloApp
//
//  Created by Tony Jiang on 1/20/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import SwiftUI
import UIKit
import Combine

class PrivacyViewController: UIViewController, UICollectionViewDelegate {

    private lazy var collectionView: InsetCollectionView = {
       let collectionView = InsetCollectionView()
        let layout = InsetCollectionView.defaultLayout()
        let config = InsetCollectionView.defaultLayoutConfiguration()
        
        layout.configuration = config
        collectionView.collectionViewLayout = layout
        return collectionView
    }()
    
    private lazy var blockedAccessoryLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17)
        label.textColor = .secondaryLabel
        label.text = MainAppContext.shared.privacySettings.blockedSetting
        
        return label
    }()
    
    private var cancellables: Set<AnyCancellable> = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = Localizations.titlePrivacy

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        view.backgroundColor = .feedBackground
        collectionView.backgroundColor = nil
        collectionView.delegate = self

        MainAppContext.shared.privacySettings.$blockedSetting.receive(on: DispatchQueue.main).sink { [weak self] value in
            self?.buildCollection()
        }.store(in: &cancellables)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    private func buildCollection() {
        let title = PrivacyList.name(forPrivacyListType: .blocked)
        let blockedUsers = MainAppContext.shared.privacySettings.blockedSetting

        collectionView.apply(InsetCollectionView.Collection {
            InsetCollectionView.Section {
                InsetCollectionView.Item(title: title,
                                         style: .label(string: blockedUsers),
                                        action: { [weak self] in self?.openBlockedContacts() })
            }
        }
        .separators()
        .disclosure())
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = self.collectionView.data.itemIdentifier(for: indexPath) as? InsetCollectionView.Item else {
            return
        }
        
        collectionView.deselectItem(at: indexPath, animated: true)
        item.action?()
    }

    private func openBlockedContacts() {
        guard ContactStore.contactsAccessAuthorized else {
            let vc = PrivacyPermissionDeniedController()
            present(UINavigationController(rootViewController: vc), animated: true)
            return
        }

        let privacySettings = MainAppContext.shared.privacySettings
        let vc = ContactSelectionViewController.forPrivacyList(privacySettings.blocked, in: privacySettings, setActiveType: false) { [weak self] in
            self?.dismiss(animated: true)
        }
        
        present(UINavigationController(rootViewController: vc), animated: true)
    }
}

// MARK: - localization

private extension Localizations {
    static var privacy: String {
        NSLocalizedString("settings.privacy",
                   value: "Privacy",
                 comment: "Settings menu section")
    }

    static var postsPrivacy: String {
        NSLocalizedString("settings.privacy.posts",
                   value: "Posts",
                 comment: "Settings > Privacy: name of a setting that defines who can see your posts.")
    }
}
