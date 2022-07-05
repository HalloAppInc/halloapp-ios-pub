//
//  ProfileViewController.swift
//  HalloApp
//
//  Created by Tanveer on 4/15/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import CoreCommon
import Core
import SwiftUI

class ProfileViewController: UIViewController, UICollectionViewDelegate {
    private typealias Section = InsetCollectionView.Section
    private typealias Item = InsetCollectionView.Item

    private lazy var collectionView: InsetCollectionView = {
        let collectionView = InsetCollectionView()
        let layout = InsetCollectionView.defaultLayout()
        let config = InsetCollectionView.defaultLayoutConfiguration()

        config.boundarySupplementaryItems = [
            NSCollectionLayoutBoundarySupplementaryItem(layoutSize: .init(widthDimension: .fractionalWidth(1.0),
                                                                         heightDimension: .estimated(44)),
                                                       elementKind: UICollectionView.elementKindSectionHeader,
                                                         alignment: .top)
        ]
        layout.configuration = config
        collectionView.collectionViewLayout = layout

        collectionView.delegate = self
        collectionView.backgroundColor = .primaryBg
        return collectionView
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = Localizations.profile
        
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        let configuration = UIImage.SymbolConfiguration(weight: .bold)
        let chevron = UIImage(systemName: "chevron.down", withConfiguration: configuration)
        let button = UIButton(type: .system)
        button.setImage(chevron, for: .normal)
        button.addTarget(self, action: #selector(dismissPushed), for: .touchUpInside)
        let barButton = UIBarButtonItem(customView: button)
        navigationItem.leftBarButtonItem = barButton

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        collectionView.data.supplementaryViewProvider = { [weak self] collectionView, elementKind, indexPath in
            return self?.supplementaryViewProvider(collectionView, elementKind, indexPath: indexPath) ?? UICollectionReusableView()
        }

        collectionView.register(CollectionProfileHeader.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                       withReuseIdentifier: CollectionProfileHeader.reuseIdentifier)
        buildCollection()
    }

    private func buildCollection() {
        let showDeveloperMenu: Bool
        #if DEBUG
        showDeveloperMenu = true
        #else
        showDeveloperMenu = ServerProperties.isInternalUser
        #endif

        collectionView.apply(InsetCollectionView.Collection {
            Section() {
                Item(title: Localizations.titleMyPosts,
                      icon: UIImage(named: "Posts"),
                    action: { [weak self] in self?.openPosts() })

                Item(title: PrivacyList.name(forPrivacyListType: .all),
                      icon: UIImage(systemName: "person"),
                    action: { [weak self] in self?.openContacts() })

                Item(title: Localizations.favoritesTitle,
                      icon: UIImage(named: "FavoritesOutline"),
                    action: { [weak self] in self?.openFavorites() })
            }
            .rounding(corners: .bottom)
            
            Section() {
                Item(title: Localizations.titleSettings,
                      icon: UIImage(systemName: "gearshape"),
                    action: { [weak self] in self?.openSettings() })

                Item(title: Localizations.help,
                      icon: UIImage(systemName: "questionmark.circle"),
                    action: { [weak self] in self?.openHelp() })

                Item(title: Localizations.inviteFriends,
                      icon: UIImage(named: "InviteEnvelope"),
                    action: { [weak self] in self?.openInviteFriends() })

                Item(title: Localizations.about,
                      icon: UIImage(named: "AboutHalloApp"),
                    action: { [weak self] in self?.pushAbout() })
            }

            if showDeveloperMenu {
                Section() {
                    Item(title: "Developer",
                          icon: UIImage(systemName: "hammer"),
                        action: { [weak self] in self?.openDeveloperMenu() })
                }
            }
        })
    }
    
    private func pushAbout() {
        if let viewController = UIStoryboard.init(name: "AboutView", bundle: Bundle.main).instantiateInitialViewController() {
            viewController.hidesBottomBarWhenPushed = false
            navigationController?.pushViewController(viewController, animated: true)
        }
    }
    
    private func openPosts() {
        let vc = FeedArchiveViewController(nibName: nil, bundle: nil)
        vc.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(vc, animated: true)
    }
    
    private func openContacts() {
        guard ContactStore.contactsAccessAuthorized else {
            let vc = PrivacyPermissionDeniedController()
            present(UINavigationController(rootViewController: vc), animated: true)
            return
        }
        
        let vc = ContactSelectionViewController.forAllContacts(.all,
                                                           in: MainAppContext.shared.privacySettings,
                                                   doneAction: { [weak self] in self?.dismiss(animated: true) },
                                                dismissAction: { [weak self] in self?.dismiss(animated: true) })
        
        let nc = UINavigationController(rootViewController: vc)
        present(nc, animated: true)
    }
    
    private func openFavorites() {
        guard ContactStore.contactsAccessAuthorized else {
            let vc = PrivacyPermissionDeniedController()
            present(UINavigationController(rootViewController: vc), animated: true)
            return
        }
        
        let vc = ContactSelectionViewController.forPrivacyList(MainAppContext.shared.privacySettings.whitelist,
                                                           in: MainAppContext.shared.privacySettings,
                                                setActiveType: true,
                                                   doneAction: { [weak self] in self?.dismiss(animated: true) },
                                                dismissAction: nil)
        
        let nc = UINavigationController(rootViewController: vc)
        present(nc, animated: true)
    }
    
    private func openSettings() {
        let vc = SettingsViewController(nibName: nil, bundle: nil)
        vc.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(vc, animated: true)
    }
    
    private func openHelp() {
        let viewController = HelpViewController()
        viewController.hidesBottomBarWhenPushed = false
        navigationController?.pushViewController(viewController, animated: true)
    }
    
    private func openInviteFriends() {
        guard ContactStore.contactsAccessAuthorized else {
            let inviteVC = InvitePermissionDeniedViewController()
            present(UINavigationController(rootViewController: inviteVC), animated: true)
            return
        }
        
        InviteManager.shared.requestInvitesIfNecessary()
        let inviteVC = InviteViewController(manager: InviteManager.shared, dismissAction: { [weak self] in self?.dismiss(animated: true, completion: nil) })
        present(UINavigationController(rootViewController: inviteVC), animated: true)
    }

    private func openDeveloperMenu() {
        var developerMenuView = DeveloperMenuView()
        developerMenuView.dismiss = {
            self.navigationController?.popViewController(animated: true)
        }
        let viewController = UIHostingController(rootView: developerMenuView)
        viewController.hidesBottomBarWhenPushed = true
        viewController.title = "Developer Menu"
        navigationController?.pushViewController(viewController, animated: true)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = self.collectionView.data.itemIdentifier(for: indexPath) as? Item else {
            return
        }
        
        collectionView.deselectItem(at: indexPath, animated: true)
        item.action?()
    }

    private func supplementaryViewProvider(_ collectionView: UICollectionView, _ elementKind: String, indexPath: IndexPath) -> UICollectionReusableView {
        guard case UICollectionView.elementKindSectionHeader = elementKind else {
            return UICollectionReusableView()
        }

        let header = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader,
                                                        withReuseIdentifier: CollectionProfileHeader.reuseIdentifier,
                                                                        for: indexPath)

        if let profileHeader = (header as? CollectionProfileHeader)?.header {
            addChild(profileHeader)
            profileHeader.didMove(toParent: self)
            profileHeader.isEditingAllowed = true
        }

        return header
    }

    @objc
    private func dismissPushed(_ sender: UIButton) {
        dismiss(animated: true)
    }
}

fileprivate class CollectionProfileHeader: UICollectionReusableView {
    static let reuseIdentifier = "profileHeader"
    private var cancellable: AnyCancellable?

    private(set) lazy var header: ProfileHeaderViewController = ProfileHeaderViewController()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let padding = InsetCollectionView.insets.leading
        let line = UIView()
        line.backgroundColor = .opaqueSeparator
        line.translatesAutoresizingMaskIntoConstraints = false

        header.view.translatesAutoresizingMaskIntoConstraints = false
        header.view.backgroundColor = .feedPostBackground
        header.changeAvatarHeight(to: 145)

        addSubview(header.view)
        addSubview(line)

        NSLayoutConstraint.activate([
            header.view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            header.view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            header.view.topAnchor.constraint(equalTo: topAnchor),
            header.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            line.leadingAnchor.constraint(equalTo: header.view.leadingAnchor, constant: 15),
            line.trailingAnchor.constraint(equalTo: header.view.trailingAnchor, constant: -15),
            line.bottomAnchor.constraint(equalTo: header.view.bottomAnchor),
            line.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale)
        ])

        cancellable = MainAppContext.shared.userData.userNamePublisher.receive(on: DispatchQueue.main).sink { [weak self] userName in
            self?.header.configureForCurrentUser(withName: userName)
            self?.setNeedsLayout()
        }

        let mask = CACornerMask([.layerMinXMinYCorner, .layerMaxXMinYCorner])
        header.view.layer.cornerRadius = InsetCollectionView.cornerRadius
        header.view.layer.maskedCorners = mask
    }

    required init?(coder: NSCoder) {
        fatalError()
    }
}

// MARK: - localization

extension Localizations {
    static var profile: String {
        NSLocalizedString("profile.title",
                   value: "Profile",
                 comment: "Title of the screen with the user's profile.")
    }
    
    static var inviteFriends: String {
        NSLocalizedString("profile.row.invite",
                   value: "Invite to HalloApp",
                 comment: "Row in Profile screen.")
    }

    static var help: String {
        NSLocalizedString("profile.row.help",
                   value: "Help",
                 comment: "Row in Profile screen.")
    }

    static var about: String {
        NSLocalizedString("profile.row.about",
                   value: "About HalloApp",
                 comment: "Row in Profile screen.")
    }
}
