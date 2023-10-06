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
        let layout = InsetCollectionView.defaultLayout
        let config = InsetCollectionView.defaultLayoutConfiguration
        
        layout.configuration = config
        collectionView.collectionViewLayout = layout
        return collectionView
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

        let context = MainAppContext.shared.mainDataStore.viewContext
        let predicate = NSPredicate(format: "isBlocked == YES")
        CountPublisher<UserProfile>(context: context, predicate: predicate)
            .sink { [weak self] count in
                self?.buildCollection(blockedUsers: count)
            }
            .store(in: &cancellables)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    private func buildCollection(blockedUsers: Int) {
        let title = PrivacyList.name(forPrivacyListType: .blocked)
        let blockedUsers = String(format: Localizations.userCountFormat, blockedUsers)

        collectionView.apply(InsetCollectionView.Collection {
            InsetCollectionView.Section {
                InsetCollectionView.Item(title: title,
                                 accessoryText: blockedUsers,
                                         style: .standard,
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
        let viewController = UIHostingController(rootView: FriendSelection(model: BlockedSelectionModel()))
        present(viewController, animated: true)
    }
}

// MARK: - localization

extension Localizations {
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

    static var userCountFormat: String {
        NSLocalizedString("privacy.n.contacts",
                          comment: "Generic setting value telling how many contacts are blocked or muted.")
    }
}
