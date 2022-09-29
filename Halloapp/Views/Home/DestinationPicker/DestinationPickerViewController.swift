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
                                 value: "Contacts",
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

    static var frequentlyContactedHeader: String {
        return NSLocalizedString("post.privacy.header.frequentlyContacted",
                                 value: "Frequently Contacted",
                                 comment: "Header when selecting destinations to forward a message, this header appears above the feeds section")
    }
}

enum DestinationPickerConfig {
    case composer, forwarding
}

class DestinationPickerViewController: UIViewController, NSFetchedResultsControllerDelegate {
    static let rowHeight = CGFloat(54)
    static let maxGroupsToShowOnLaunch = 3//6
    private var showAllGroups: Bool = false
    private var hasMoreGroups: Bool = false
    private var selectedDestinations: [ShareDestination] = []
    let feedPrivacyTypes = [PrivacyListType.all, PrivacyListType.whitelist]

    private let config: DestinationPickerConfig

    private lazy var frequentlyContactedDataSource = FrequentlyContactedDataSource()

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
        fetchedResultsController.delegate = self
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

            var rowHeight: NSCollectionLayoutDimension = .absolute(ContactSelectionViewController.rowHeight)

            let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: rowHeight)
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: rowHeight)
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

            let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44))
            let sectionHeader = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: headerSize, elementKind: DestinationPickerHeaderView.elementKind, alignment: .top)

            let footerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(44))
            let sectionFooter = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: footerSize, elementKind: DestinationPickerMoreView.elementKind, alignment: .bottom)

            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)

            let backgroundDecoration = NSCollectionLayoutDecorationItem.background(elementKind: DestinationBackgroundDecorationView.elementKind)
            // top inset required avoids header, bottom avoids footer
            backgroundDecoration.contentInsets = NSDirectionalEdgeInsets(top: 44, leading: 16, bottom: 0, trailing: 16)

            // For the groups section, if there are > maxGroupsToShowOnLaunch groups, show the "Show More.." footer
            section.boundarySupplementaryItems = [sectionHeader]
            if let self = self {
                let sections = self.dataSource.snapshot().sectionIdentifiers
                if sectionIndex < sections.count, sections[sectionIndex] == DestinationSection.groups, !self.showAllGroups, self.hasMoreGroups, !self.isFiltering {
                    section.boundarySupplementaryItems = [sectionHeader, sectionFooter]
                    backgroundDecoration.contentInsets.bottom = 44
                }
            }

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
        collectionView.keyboardDismissMode = .interactive

        return collectionView
    }()

    private lazy var selectionRow: DestinationTrayView = {
        let rowView = DestinationTrayView() { [weak self] index in
            guard let self = self else { return }

            self.selectedDestinations.remove(at: index)
            self.onSelectionChange(destinations: self.selectedDestinations)
        }

        return rowView
    }()

    private lazy var selectionRowHeightConstraint: NSLayoutConstraint = {
        selectionRow.heightAnchor.constraint(equalToConstant: 0)
    }()

    private lazy var bottomConstraint: NSLayoutConstraint = {
        bottomView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
    }()

    private lazy var leftBarButtonItem: UIBarButtonItem = {
        let image: UIImage?

        switch config {
        case .composer:
            image = UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))
        case .forwarding:
            image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))
        }

        return UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(backAction))
    }()

    private lazy var rightBarButtonItem: UIBarButtonItem = {
        let image = UIImage(named: "NavCreateGroup")
        return UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(createGroupAction))
    }()

    private lazy var dataSource: UICollectionViewDiffableDataSource<DestinationSection, DestinationPickerDestination> = {
        let source = UICollectionViewDiffableDataSource<DestinationSection, DestinationPickerDestination>(collectionView: collectionView) { [weak self] collectionView, indexPath, destination in
            
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DestinationCell.reuseIdentifier, for: indexPath)
            
            guard let cell = cell as? DestinationCell, let self = self else { return cell }
            let isSelected = self.selectedDestinations.contains(destination.shareDestination)

            cell.separator.isHidden = collectionView.numberOfItems(inSection: indexPath.section) - 1 == indexPath.row

            switch destination.shareDestination {
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
            case .group(let groupID, let name):
                cell.configureGroup(groupID, name: name, isSelected: isSelected)
            case .contact(let userID, let name, let phone):
                cell.configureUser(userID, name: name, phone: phone, isSelected: isSelected)
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

    private func updateSeparators() {
        for cell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell) else { return }
            guard let cell = cell as? DestinationCell else { return }
            cell.separator.isHidden = indexPath.row == collectionView.numberOfItems(inSection: indexPath.section) - 1
        }
    }

    private func sectionHeader(destinationSection : DestinationSection) -> String {
        switch destinationSection {
        case .main:
            return Localizations.feedsHeader
        case .frequentlyContacted:
            return Localizations.frequentlyContactedHeader
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

    private lazy var shareButton: UIButton = {
        let icon = UIImage(named: "icon_share")?.withTintColor(.white, renderingMode: .alwaysOriginal)

        let attributedTitle = NSAttributedString(string: Localizations.buttonShare,
                                                 attributes: [.kern: 0.5, .foregroundColor: UIColor.white])
        let disabledAttributedTitle = NSAttributedString(string: Localizations.buttonShare,
                                                         attributes: [.kern: 0.5, .foregroundColor: UIColor.white])

        let button = RoundedRectButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        // Attributed strings do not respect button title colors
        button.setAttributedTitle(attributedTitle, for: .normal)
        button.setAttributedTitle(disabledAttributedTitle, for: .disabled)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        button.setImage(icon, for: .normal)
        button.imageEdgeInsets = UIEdgeInsets(top: -4, left: 0, bottom: -4, right: 0)

        // keep image on the right & tappable
        if case .rightToLeft = view.effectiveUserInterfaceLayoutDirection {
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 16)
            button.semanticContentAttribute = .forceLeftToRight
        } else {
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
            button.semanticContentAttribute = .forceRightToLeft
        }

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 44),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 90),
        ])

        button.addTarget(self, action: #selector(shareAction), for: .touchUpInside)

        return button
    }()

    private lazy var bottomView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .primaryBg

        view.addSubview(shareButton)

        NSLayoutConstraint.activate([
            shareButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shareButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            shareButton.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        return view
    }()

    private var isFiltering: Bool {
        return searchController.isActive && !(searchController.searchBar.text?.isEmpty ?? true)
    }

    enum DestinationSection {
        case main, frequentlyContacted, groups, contacts
    }

    // Use section to allow differentiation between duplicate groups / contacts
    struct DestinationPickerDestination: Hashable, Equatable {
        let section: DestinationSection
        let shareDestination: ShareDestination
    }

    private var cancellableSet: Set<AnyCancellable> = []

    private var completion: (DestinationPickerViewController, [ShareDestination]) -> ()

    init(config: DestinationPickerConfig, destinations: [ShareDestination], completion: @escaping (DestinationPickerViewController, [ShareDestination]) -> ()) {
        self.completion = completion
        self.config = config
        self.selectedDestinations = destinations
        super.init(nibName: nil, bundle: nil)

        frequentlyContactedDataSource.subject
            .sink { [weak self] _ in self?.updateData() }
            .store(in: &cancellableSet)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        view.backgroundColor = .primaryBg

        navigationItem.title = Localizations.sendTo
        navigationItem.leftBarButtonItem = leftBarButtonItem
        if config != .forwarding {
            navigationItem.rightBarButtonItem = rightBarButtonItem
        }
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.searchController = searchController

        view.addSubview(collectionView)
        view.addSubview(selectionRow)
        view.addSubview(bottomView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            selectionRow.topAnchor.constraint(equalTo: collectionView.bottomAnchor),
            selectionRow.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            selectionRow.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            selectionRowHeightConstraint,
            bottomView.topAnchor.constraint(equalTo: selectionRow.bottomAnchor),
            bottomView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomConstraint,
        ])

        if config == .composer {
            try? fetchedResultsController.performFetch()
        }
        try? contactsFetchedResultsController.performFetch()
        frequentlyContactedDataSource.performFetch()

        updateData()
        updateSelectionRow()
        updateNextBtn()

        handleKeyboardUpdates()
    }

    private func updateData(searchString: String? = nil) {
        var snapshot = NSDiffableDataSourceSnapshot<DestinationSection, DestinationPickerDestination>()
        var allGroups:[ChatThread] = []
        if config == .composer {
            allGroups = fetchedResultsController.fetchedObjects ?? []
        }
        
        hasMoreGroups = allGroups.count > DestinationPickerViewController.maxGroupsToShowOnLaunch

        var contacts = contactsFetchedResultsController.fetchedObjects ?? []
        contacts = ABContact.contactsWithUniquePhoneNumbers(allContacts: contacts)
        
        if let searchString = searchString?.trimmingCharacters(in: CharacterSet.whitespaces).lowercased(), !searchString.isEmpty {
            let searchItems = searchString.components(separatedBy: " ")
            // Add filtered groups
            allGroups.forEach {
                guard let groupID = $0.groupID, let groupTitle = $0.title else { return }
                let groupTitleLowercased = groupTitle.lowercased()
                for searchItem in searchItems {
                    if groupTitleLowercased.contains(searchItem) {
                        if !snapshot.sectionIdentifiers.contains(DestinationSection.groups) {
                            snapshot.appendSections([DestinationSection.groups])
                        }
                        let destination = DestinationPickerDestination(section: .groups, shareDestination: .group(id: groupID, name: groupTitle))
                        snapshot.appendItems([destination], toSection: DestinationSection.groups)
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
                    guard let destination = ShareDestination.destination(from: $0) else { continue }

                    if fullName.contains(searchItem) || phoneNumber.contains(searchItem) {
                        if !snapshot.sectionIdentifiers.contains(DestinationSection.contacts) {
                            snapshot.appendSections([DestinationSection.contacts])
                        }
                        snapshot.appendItems([DestinationPickerDestination(section: .contacts, shareDestination: destination)], toSection: DestinationSection.contacts)
                    }
                }
            }
        } else {
            // No Search in progress

            if hasMoreGroups, !showAllGroups {
                let maxGroups = DestinationPickerViewController.maxGroupsToShowOnLaunch
                var groups = [ChatThread](allGroups[..<maxGroups])

                for group in allGroups[maxGroups...] {
                    if selectedDestinations.contains(.group(id: group.groupID ?? "", name: group.title ?? "")) {
                        groups.append(group)
                    }
                }

                showAllGroups = allGroups.count == groups.count
                allGroups = groups
            }

            if config == .composer {
                snapshot.appendSections([DestinationSection.main])
                snapshot.appendItems([
                    DestinationPickerDestination(section: .main, shareDestination: .feed(.all)),
                    DestinationPickerDestination(section: .main, shareDestination: .feed(.whitelist))
                ], toSection: DestinationSection.main)
            }

            if !frequentlyContactedDataSource.subject.value.isEmpty {
                snapshot.appendSections([.frequentlyContacted])
                let frequentlyContactedDestinations = frequentlyContactedDataSource.subject.value.prefix(4)
                    .compactMap { frequentlyContactedEntity -> DestinationPickerDestination? in
                        switch frequentlyContactedEntity {
                        case .user(userID: let contactID):
                            if let contact = MainAppContext.shared.contactStore.contact(withUserId: contactID, in: MainAppContext.shared.contactStore.viewContext) {
                                return DestinationPickerDestination(section: .frequentlyContacted, shareDestination: .contact(id: contactID, name: contact.fullName, phone: contact.phoneNumber))
                            }
                        case .group(groupID: let groupID):
                            if let group = MainAppContext.shared.chatData.chatGroup(groupId: groupID, in: MainAppContext.shared.chatData.viewContext) {
                                return DestinationPickerDestination(section: .frequentlyContacted, shareDestination: .group(id: groupID, name: group.name))
                            }
                        }
                        return nil
                    }
                snapshot.appendItems(frequentlyContactedDestinations, toSection: .frequentlyContacted)
            }

            if allGroups.count > 0 {
                snapshot.appendSections([DestinationSection.groups])
                snapshot.appendItems(allGroups.compactMap {
                    guard let groupID = $0.groupID, let title = $0.title else { return nil }
                    return DestinationPickerDestination(section: .groups, shareDestination: .group(id: groupID, name: title))
                }, toSection: DestinationSection.groups)
            }
            if contacts.count > 0 {
                snapshot.appendSections([DestinationSection.contacts])
                snapshot.appendItems(contacts.compactMap { contact in
                    return ShareDestination.destination(from: contact).flatMap { DestinationPickerDestination(section: .contacts, shareDestination: $0) }
                }, toSection: DestinationSection.contacts)
            }
        }

        dataSource.apply(snapshot, animatingDifferences: true) {
            self.updateSeparators()
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        updateData()
    }

    private func handleKeyboardUpdates() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification).sink { [weak self] notification in
            guard let self = self else { return }
            guard let info = KeyboardNotificationInfo(userInfo: notification.userInfo) else { return }

            UIView.animate(withKeyboardNotificationInfo: info) {
                self.bottomConstraint.constant = -info.endFrame.height + 16
                self.view?.layoutIfNeeded()
            }
        }.store(in: &cancellableSet)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification).sink { [weak self] notification in
            guard let self = self else { return }
            guard let info = KeyboardNotificationInfo(userInfo: notification.userInfo) else { return }

            UIView.animate(withKeyboardNotificationInfo: info) {
                self.bottomConstraint.constant = 0
                self.view?.layoutIfNeeded()
            }
        }.store(in: &cancellableSet)
    }
}

extension DestinationPickerViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let destination = dataSource.itemIdentifier(for: indexPath) else { return }
        //toggle selection
        toggleDestinationSelection(destination.shareDestination)
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
        guard config != .composer else { return }

        if selectedDestinations.count > 0 && selectionRowHeightConstraint.constant == 0 {
            UIView.animate(withDuration: 0.3, animations: {
                self.selectionRowHeightConstraint.constant = 100
                self.selectionRow.layoutIfNeeded()
            }) { _ in
                self.selectionRow.update(with: self.selectedDestinations)
            }
        } else if selectedDestinations.count == 0 && selectionRowHeightConstraint.constant > 0 {
            selectionRow.update(with: self.selectedDestinations)

            UIView.animate(withDuration: 0.3) {
                self.selectionRowHeightConstraint.constant = 0
                self.selectionRow.layoutIfNeeded()
            }
        } else {
            selectionRow.update(with: self.selectedDestinations)
        }
    }

    private func updateNextBtn() {
        shareButton.isEnabled = selectedDestinations.count > 0
    }

    @objc private func createGroupAction() {
        let controller = CreateGroupViewController(groupType: GroupType.groupFeed) { [weak self] groupID in
            guard let self = self else { return }
            self.dismiss(animated: true)
        }

        present(UINavigationController(rootViewController: controller), animated: true)
    }

    @objc private func shareAction() {
        guard selectedDestinations.count > 0 else { return }
        if searchController.isActive {
            dismiss(animated: true)
        }

        completion(self, selectedDestinations)
    }

    @objc func backAction() {
        if searchController.isActive {
            dismiss(animated: true)
        }

        completion(self, [])
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
