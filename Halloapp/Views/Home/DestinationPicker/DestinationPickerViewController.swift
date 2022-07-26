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
                                 comment: "Header when selecting destinations to forward a message, this header appears above the groups section")
    }

    static var feedsHeader: String {
        return NSLocalizedString("post.privacy.header.feeds",
                                 value: "Feeds",
                                 comment: "Header when selecting destinations to forward a message, this header appears above the feeds section")
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

class DestinationPickerViewController: UIViewController, NSFetchedResultsControllerDelegate {
    static let rowHeight = CGFloat(54)
    static let maxGroupsToShowOnLaunch = 6
    private var showAllGroups: Bool = false
    private var hasMoreGroups: Bool = false
    private var selectedDestinations: [ShareDestination] = []
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

            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(53))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            var groupHeight: NSCollectionLayoutDimension = .absolute(ContactSelectionViewController.rowHeight)

            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(53))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

            let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(44))
            let sectionHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: headerSize, elementKind: DestinationPickerHeaderView.elementKind, alignment: .top)

            let footerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44))
            let sectionFooter = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: footerSize, elementKind: DestinationPickerMoreView.elementKind, alignment: .bottom)

            let section = NSCollectionLayoutSection(group: group)

            // For the groups section, if there are > maxGroupsToShowOnLaunch groups, show the "Show More.." footer
            section.boundarySupplementaryItems = [sectionHeader]
            if let self = self {
                let sections = self.dataSource.snapshot().sectionIdentifiers
                if sectionIndex < sections.count, sections[sectionIndex] == DestinationSection.groups, !self.showAllGroups, self.hasMoreGroups {
                    section.boundarySupplementaryItems = [sectionHeader, sectionFooter]
                }
            }
            section.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)

            let backgroundDecoration = NSCollectionLayoutDecorationItem.background(elementKind: DestinationBackgroundDecorationView.elementKind)
            backgroundDecoration.contentInsets = NSDirectionalEdgeInsets(top: 50, leading: 16, bottom: 0, trailing: 16)

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
        collectionView.register(DestinationPickerMoreView.self, forSupplementaryViewOfKind: DestinationPickerMoreView.elementKind, withReuseIdentifier: DestinationPickerMoreView.elementKind)
        collectionView.delegate = self
        collectionView.keyboardDismissMode = .onDrag

        return collectionView
    }()

    private lazy var selectionRow: DestinationTrayView = {
        let rowView = DestinationTrayView() { [weak self] index in
            guard let self = self else { return }

            self.selectedDestinations.remove(at: index)
            self.onSelectionChange(destinations: self.selectedDestinations)
        }

        return rowView
    } ()

    private lazy var selectionRowHeightConstraint: NSLayoutConstraint = {
        selectionRow.heightAnchor.constraint(equalToConstant: 0)
    } ()

    private lazy var bottomConstraint: NSLayoutConstraint = {
        selectionRow.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    } ()

    private lazy var leftBarButtonItem: UIBarButtonItem = {
        let image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))
        let item = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(backAction))

        return item
    }()

    private lazy var dataSource: UICollectionViewDiffableDataSource<DestinationSection, ShareDestination> = {
        let source = UICollectionViewDiffableDataSource<DestinationSection, ShareDestination>(collectionView: collectionView) { [weak self] collectionView, indexPath, shareDestination in
            
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DestinationCell.reuseIdentifier, for: indexPath)
            
            guard let cell = cell as? DestinationCell, let self = self else { return cell }
            let isSelected = self.selectedDestinations.contains { $0 == shareDestination }
            switch shareDestination {
            case .feed(let privacyListType):
                switch privacyListType {
                case .all:
                    cell.configure(
                        title: PrivacyList.name(forPrivacyListType: .all),
                        subtitle: Localizations.feedPrivacyShareWithAllContacts,
                        privacyListType: .all,
                        isSelected: isSelected)
                case .whitelist:
                    cell.configure(
                        title: PrivacyList.name(forPrivacyListType: .whitelist),
                        subtitle: Localizations.feedPrivacyShareWithSelected,
                        privacyListType: .whitelist,
                        isSelected: isSelected)
                default:
                    break
                }
            case .group(let group):
                cell.configure(group, isSelected: isSelected)
            case .contact(let contact):
                cell.configure(contact, isSelected: isSelected)
            }
            return cell
        }

        source.supplementaryViewProvider = { [weak self] (collectionView, kind, indexPath) in
            switch kind {
            case DestinationPickerMoreView.elementKind:
                let view = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: DestinationPickerMoreView.elementKind, for: indexPath)

                if let view = view as? DestinationPickerMoreView {
                    view.delegate = self
                }
                return view
            default:
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
        }
        return source
    }()

    private func sectionHeader(destinationSection : DestinationSection) -> String {
        switch destinationSection {
        case .main:
            return Localizations.feedsHeader
        case .groups:
            return Localizations.groupsHeader
        case .contacts:
            return Localizations.contactsHeader
        }
    }

    private lazy var searchController: UISearchController = {
        let searchController = UISearchController()
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.definesPresentationContext = true
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchBar.autocapitalizationType = .none
        return searchController
    }()

    private var isFiltering: Bool {
        return searchController.isActive && !(searchController.searchBar.text?.isEmpty ?? true)
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
        navigationItem.searchController = searchController

        view.addSubview(collectionView)
        view.addSubview(selectionRow)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            selectionRow.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            selectionRow.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            selectionRowHeightConstraint,
            bottomConstraint,
        ])

        try? fetchedResultsController.performFetch()
        try? contactsFetchedResultsController.performFetch()

        updateData()
    }

    private func updateData(searchString: String? = nil) {
        var snapshot = NSDiffableDataSourceSnapshot<DestinationSection, ShareDestination>()
        var allGroups = fetchedResultsController.fetchedObjects ?? []
        hasMoreGroups = allGroups.count > DestinationPickerViewController.maxGroupsToShowOnLaunch
        if hasMoreGroups, !showAllGroups {
            allGroups = [ChatThread](allGroups[..<DestinationPickerViewController.maxGroupsToShowOnLaunch])
        }
        var contacts = contactsFetchedResultsController.fetchedObjects ?? []
        contacts = ABContact.contactsWithUniquePhoneNumbers(allContacts: contacts)
        
        if let searchString = searchString?.trimmingCharacters(in: CharacterSet.whitespaces).lowercased(), !searchString.isEmpty {
            let searchItems = searchString.components(separatedBy: " ")
            // Add filtered groups
            allGroups.forEach {
                guard $0.groupID != nil, let groupTitle = $0.title?.lowercased() else { return }
                for searchItem in searchItems {
                    if groupTitle.contains(searchItem) {
                        if !snapshot.sectionIdentifiers.contains(DestinationSection.groups) {
                            snapshot.appendSections([DestinationSection.groups])
                        }
                        snapshot.appendItems([ShareDestination.group($0)], toSection: DestinationSection.groups)
                    }
                }
            }
            // Add filtered contacts
            contacts.forEach {
                // We support search on firtname and phone number
                let fullName = $0.fullName?.lowercased() ?? ""
                let phoneNumber = $0.phoneNumber ?? ""
                let searchItems = searchString.components(separatedBy: " ")
                for searchItem in searchItems {
                    if fullName.contains(searchItem) || phoneNumber.contains(searchItem) {
                        if !snapshot.sectionIdentifiers.contains(DestinationSection.contacts) {
                            snapshot.appendSections([DestinationSection.contacts])
                        }
                        snapshot.appendItems([ShareDestination.contact($0)], toSection: DestinationSection.contacts)
                    }
                }
            }
            dataSource.apply(snapshot)
            return
        }
        // No Search in progress
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

extension DestinationPickerViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let shareDestination = dataSource.itemIdentifier(for: indexPath) else { return }
        //toggle selection
        toggleDestinationSelection(shareDestination)
        onSelectionChange(destinations: selectedDestinations)
    }

    private func toggleDestinationSelection(_ shareDestination: ShareDestination) {
        if let idx = selectedDestinations.firstIndex(where: { $0 == shareDestination }) {
            selectedDestinations.remove(at: idx)
        } else {
            selectedDestinations.append(shareDestination)
        }
        // Home and Favorites need to be mutually exclusive
        switch shareDestination {
        case .feed(let privacyListType):
            switch privacyListType {
            case .all:
                selectedDestinations.removeAll(where: {$0 == .feed(.whitelist)})
            case .whitelist:
                selectedDestinations.removeAll(where: {$0 == .feed(.all)})
            default:
                break
            }
        default:
            break
        }
    }
    private func onSelectionChange(destinations: [ShareDestination]) {
        selectedDestinations = destinations
            updateNextBtn()
            updateSelectionRow()
            collectionView.reloadData()
        }

    private func updateSelectionRow() {
        if selectedDestinations.count > 0 && selectionRowHeightConstraint.constant == 0 {
            UIView.animate(withDuration: 0.3, animations: {
                self.selectionRowHeightConstraint.constant = 100
                let bottomContentInset = 100 - self.view.safeAreaInsets.bottom
                self.collectionView.contentInset.bottom = bottomContentInset
                self.collectionView.verticalScrollIndicatorInsets.bottom = bottomContentInset
                self.selectionRow.layoutIfNeeded()
            }) { _ in
                self.selectionRow.update(with: self.selectedDestinations)
            }
        } else if selectedDestinations.count == 0 && selectionRowHeightConstraint.constant > 0 {
            selectionRow.update(with: self.selectedDestinations)

            UIView.animate(withDuration: 0.3) {
                self.selectionRowHeightConstraint.constant = 0
                self.collectionView.contentInset.bottom = 0
                self.collectionView.verticalScrollIndicatorInsets.bottom = 0
                self.selectionRow.layoutIfNeeded()
            }
        } else {
            selectionRow.update(with: self.selectedDestinations)
        }
    }

    private func updateNextBtn() {
        if selectedDestinations.count > 0 {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: Localizations.buttonNext, style: .done, target: self, action: #selector(nextAction))
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    @objc private func nextAction() {
        guard selectedDestinations.count > 0 else { return }
        if searchController.isActive {
            dismiss(animated: true)
        }
        // TODO what's next Dini?
    }

    @objc func backAction() {
        if searchController.isActive {
            dismiss(animated: true)
        }
    }

    @objc func moreAction() {
        showAllGroups = true
        updateData(searchString: nil)
    }
}

// MARK: UISearchResultsUpdating
extension DestinationPickerViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        updateData(searchString: searchController.searchBar.text)
    }
}

// MARK: DestinationPickerMoreViewDelegate
extension DestinationPickerViewController: DestinationPickerMoreViewDelegate {
    func moreAction(_ view: DestinationPickerMoreView) {
        moreAction()
    }
}
