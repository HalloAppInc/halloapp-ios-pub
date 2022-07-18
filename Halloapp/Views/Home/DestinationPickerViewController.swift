//
//  DestinationPickerViewController.swift
//  HalloApp
//
//  Created by Nandini Shetty on 7/14/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Combine
import Core
import CoreCommon
import CoreData
import UIKit

private extension Localizations {
    static var contactsHeader: String {
        return NSLocalizedString("post.privacy.title",
                                 value: "Recent Contacts",
                                 comment: "Header when selecting contacts to share with")
    }

    static var groupsHeader: String {
        return NSLocalizedString("post.privacy.header.groups",
                                 value: "Your Groups",
                                 comment: "Header when selecting groups to share with")
    }
}

class DestinationPickerViewController: UIViewController, NSFetchedResultsControllerDelegate {
    static let rowHeight = CGFloat(54)
    private var contacts: [ABContact] = []
    private var allGroups: [ChatThread] = []
    private var groups: [ChatThread] = []
    private var hasMoreGroups: Bool = true
    let feedPrivacyTypes = [PrivacyListType.all, PrivacyListType.whitelist]

    private lazy var fetchedResultsController: NSFetchedResultsController<ChatThread> = {
        let request = ChatThread.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "lastTimestamp", ascending: false),
            NSSortDescriptor(key: "title", ascending: true)
        ]
        request.predicate = NSPredicate(format: "groupID != nil")
        
        let fetchedResultsController = NSFetchedResultsController<ChatThread>(fetchRequest: request,
                                                                              managedObjectContext: MainAppContext.shared.chatData.viewContext,
                                                                              sectionNameKeyPath: nil,
                                                                              cacheName: nil)
        return fetchedResultsController
    }()
    
    private lazy var contactsFetchedResultsController: NSFetchedResultsController<ABContact> = {
        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userId != nil")
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \ABContact.sort, ascending: true) ]
        contactsFetchedResultsController = NSFetchedResultsController<ABContact>(fetchRequest: fetchRequest,
             managedObjectContext: MainAppContext.shared.contactStore.viewContext,
             sectionNameKeyPath: nil,
             cacheName: nil)
        contactsFetchedResultsController.delegate = self
        return contactsFetchedResultsController
    }()

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { [weak self] (sectionIndex: Int, layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? in

            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            var groupHeight: NSCollectionLayoutDimension = .absolute(ContactSelectionViewController.rowHeight)

            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

            let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(44))
            let sectionHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: headerSize, elementKind: DestinationPickerHeaderView.elementKind, alignment: .top)

            let section = NSCollectionLayoutSection(group: group)
            section.boundarySupplementaryItems = [sectionHeader]
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)

            let backgroundDecoration = NSCollectionLayoutDecorationItem.background(elementKind: DestinationBackgroundDecorationView.elementKind)
            backgroundDecoration.contentInsets = NSDirectionalEdgeInsets(top: 40, leading: 16, bottom: -8, trailing: 16)

            section.decorationItems = [backgroundDecoration]

            return section
        }

        layout.register(DestinationBackgroundDecorationView.self, forDecorationViewOfKind: DestinationBackgroundDecorationView.elementKind)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .primaryBg
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 16, right: 0)
        collectionView.register(DestinationCell.self, forCellWithReuseIdentifier: DestinationCell.reuseIdentifier)
        collectionView.register(DestinationPickerHeaderView.self, forSupplementaryViewOfKind: DestinationPickerHeaderView.elementKind, withReuseIdentifier: DestinationPickerHeaderView.elementKind)
        //collectionView.delegate = self
        collectionView.keyboardDismissMode = .onDrag

        return collectionView
    }()

    private lazy var leftBarButtonItem: UIBarButtonItem = {
        let image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))
        let item = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(backAction))

        return item
    }()

    private lazy var dataSource: UICollectionViewDiffableDataSource<DestinationSection, ShareDestination> = {
        let source = UICollectionViewDiffableDataSource<DestinationSection, ShareDestination>(collectionView: collectionView) { [weak self] collectionView, indexPath, shareDestination in
            
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DestinationCell.reuseIdentifier, for: indexPath)
            
            guard let cell = cell as? DestinationCell, let self = self else { return cell }

            switch shareDestination {
            case .feed(let privacyListType):
                switch privacyListType {
                case .all:
                    cell.configure(
                        title: PrivacyList.name(forPrivacyListType: .all),
                        subtitle: Localizations.feedPrivacyShareWithAllContacts,
                        privacyListType: .all,
                        isSelected: false,
                        hasNext: true)
                case .whitelist:
                    cell.configure(
                        title: PrivacyList.name(forPrivacyListType: .whitelist),
                        subtitle: Localizations.feedPrivacyShareWithSelected,
                        privacyListType: .whitelist,
                        isSelected: false,
                        hasNext: true)
                default:
                    break
                }
            case .group(let group):
                cell.configure(group, isSelected: false)
            case .contact(let contact):
                cell.configure(contact, isSelected: false)
            }
            return cell
        }

        source.supplementaryViewProvider = { [weak self] (collectionView, kind, indexPath) in
            let view = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: DestinationPickerHeaderView.elementKind, for: indexPath)

            if let self = self, let headerView = view as? DestinationPickerHeaderView {
                let sections = self.dataSource.snapshot().sectionIdentifiers
                if indexPath.section < sections.count {
                    let section = sections[indexPath.section]
                    headerView.text = self.sectionHeader(destinationSection: section)
                }
            }

            return view
        }

        return source
    }()

    private func sectionHeader(destinationSection : DestinationSection) -> String {
        switch destinationSection {
        case .main:
            return ""
        case .groups:
            return Localizations.groupsHeader
        case .contacts:
            return Localizations.contactsHeader
        }
   }

    enum ShareDestination: Equatable, Hashable {
        case feed(PrivacyListType)
        case group(ChatThread)
        case contact(ABContact)

        static func == (lhs: ShareDestination, rhs: ShareDestination) -> Bool {
            switch (lhs, rhs) {
            case (.feed(let lf), .feed(let rf)):
                return lf == rf
            case (.group(let lg), .group(let rg)):
                return lg.groupID == rg.groupID
            case (.contact(let lc), .contact(let rc)):
                return lc == rc
            default:
                return false
            }
        }

        func hash(into hasher: inout Hasher) {
            switch(self) {
            case .feed:
                hasher.combine("feed")
            case .group(let group):
                hasher.combine(group.groupID)
            case .contact(let contact):
                hasher.combine(contact)
            }
        }
    }

    enum DestinationSection {
        case main, groups, contacts
    }

    private var cancellableSet: Set<AnyCancellable> = []

    override func viewDidLoad() {
        view.backgroundColor = .primaryBg

        navigationItem.title = Localizations.titlePrivacy
        navigationItem.leftBarButtonItem = leftBarButtonItem
        navigationItem.hidesSearchBarWhenScrolling = false

        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        try? fetchedResultsController.performFetch()
        try? contactsFetchedResultsController.performFetch()

        updateData()
    }

    @objc func backAction() {
    }

    private func updateData(searchString: String? = nil) {
        var snapshot = NSDiffableDataSourceSnapshot<DestinationSection, ShareDestination>()
        allGroups = fetchedResultsController.fetchedObjects ?? []
        contacts = contactsFetchedResultsController.fetchedObjects ?? []
        contacts = ABContact.contactsWithUniquePhoneNumbers(allContacts: contacts)
        snapshot.appendSections([DestinationSection.main])
        snapshot.appendItems([
            ShareDestination.feed(.all),
            ShareDestination.feed(.whitelist)
            
        ], toSection: DestinationSection.main)

        if allGroups.count > 0 {
            snapshot.appendSections([DestinationSection.groups])
            snapshot.appendItems(allGroups.compactMap {
                return ShareDestination.group($0)
            }, toSection: DestinationSection.groups)
        }
        if contacts.count > 0 {
            snapshot.appendSections([DestinationSection.contacts])
            snapshot.appendItems(contacts.compactMap {
                return ShareDestination.contact($0)
            }, toSection: DestinationSection.contacts)
        }
        dataSource.apply(snapshot)
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        updateData()
    }
}
