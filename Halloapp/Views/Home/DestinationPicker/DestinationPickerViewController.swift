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
    static var feedsHeader: String {
        return NSLocalizedString("post.privacy.header.feeds",
                                 value: "Feeds",
                                 comment: "Header when selecting destinations to forward a message, this header appears above the feeds section")
    }

    static var frequentlyContactedHeader: String {
        return NSLocalizedString("post.privacy.header.frequentlyContacted",
                                 value: "Frequently Contacted",
                                 comment: "Header when selecting destinations to forward a message, this header appears above the frequently contacted section")
    }

    static var recentHeader: String {
        return NSLocalizedString("post.privacy.header.recent",
                                 value: "Recent",
                                 comment: "Header when selecting destinations to forward a message, this header appears above the recent section")
    }
}

enum DestinationPickerConfig {
    case composer, forwarding
}

class DestinationPickerViewController: UIViewController, NSFetchedResultsControllerDelegate {
    static let rowHeight = CGFloat(54)
    private var selectedDestinations: [ShareDestination] = []
    let feedPrivacyTypes = [PrivacyListType.all, PrivacyListType.whitelist]

    private let config: DestinationPickerConfig

    private lazy var frequentlyContactedDataSource = {
        let supportedEntityTypes: FrequentlyContactedDataSource.EntityType
        switch self.config {
        case .composer:
            supportedEntityTypes = .all
        case .forwarding:
            supportedEntityTypes = [.user, .chatGroup]
        }
        return FrequentlyContactedDataSource(supportedEntityTypes: supportedEntityTypes)
    }()

    private lazy var recentFetchedResultsController: NSFetchedResultsController<ChatThread> = {
        let request = ChatThread.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "lastTimestamp", ascending: false),
            NSSortDescriptor(key: "title", ascending: true)
        ]

        if config == .forwarding {
            request.predicate = NSPredicate(format: "typeValue in %@", [ThreadType.oneToOne.rawValue, ThreadType.groupChat.rawValue])
        }
        
        let fetchedResultsController = NSFetchedResultsController<ChatThread>(fetchRequest: request,
                                                                              managedObjectContext: MainAppContext.shared.chatData.viewContext,
                                                                              sectionNameKeyPath: nil,
                                                                              cacheName: nil)
        fetchedResultsController.delegate = self
        return fetchedResultsController
    }()
    
    private lazy var friendsFetchedResultsController: NSFetchedResultsController<UserProfile> = {
        let fetchRequest = UserProfile.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "friendshipStatusValue == %d", UserProfile.FriendshipStatus.friends.rawValue)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \UserProfile.name, ascending: true)]

        let controller = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                    managedObjectContext: MainAppContext.shared.mainDataStore.viewContext,
                                                    sectionNameKeyPath: nil,
                                                    cacheName: nil)
        controller.delegate = self
        return controller
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

            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)

            let backgroundDecoration = NSCollectionLayoutDecorationItem.background(elementKind: DestinationBackgroundDecorationView.elementKind)
            // top inset required avoids header, bottom avoids footer
            backgroundDecoration.contentInsets = NSDirectionalEdgeInsets(top: 44, leading: 16, bottom: 0, trailing: 16)

            // For the groups section, if there are > maxGroupsToShowOnLaunch groups, show the "Show More.." footer
            section.boundarySupplementaryItems = [sectionHeader]

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
                        title: Localizations.friendsShare,
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
            case .group(let groupID, _, let name):
                cell.configureGroup(groupID, name: name, isSelected: isSelected)
            case .user(let userID, let name, let username):
                let username = username.flatMap { $0.isEmpty ? "" : "@\($0)" } ?? ""
                cell.configureUser(userID, name: name, username: username, isSelected: isSelected)
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
        case .recent:
            return Localizations.recentHeader
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
        let button = RoundedRectButton()
        button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: -1.5, leading: 32, bottom: 0, trailing: 12)
        button.configuration?.imageColorTransformer = UIConfigurationColorTransformer { _ in .white }
        button.configuration?.imagePlacement = .trailing
        button.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributeContainer in
            var updatedAttributeContainer = attributeContainer
            updatedAttributeContainer.font = .systemFont(ofSize: 17, weight: .semibold)
            updatedAttributeContainer.kern = 0.5
            return updatedAttributeContainer
        }

        button.setImage(UIImage(named: "icon_share"), for: .normal)
        button.setTitle(Localizations.buttonShare, for: .normal)
        // Default button configurations override the title color for disabled buttons
        button.setTitleColor(.white, for: .normal)
        button.setTitleColor(.white, for: .disabled)
        button.translatesAutoresizingMaskIntoConstraints = false

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
        case main, frequentlyContacted, recent
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

        try? recentFetchedResultsController.performFetch()
        try? friendsFetchedResultsController.performFetch()
        frequentlyContactedDataSource.performFetch()

        updateData()
        updateSelectionRow()
        updateNextBtn()

        handleKeyboardUpdates()
    }

    private func updateData(searchString: String? = nil) {
        var snapshot = NSDiffableDataSourceSnapshot<DestinationSection, DestinationPickerDestination>()
        var recentItems = recentFetchedResultsController.fetchedObjects ?? []
        let friends = friendsFetchedResultsController.fetchedObjects ?? []

        let usernames = friends.reduce(into: [UserID: String]()) {
            $0[$1.id] = $1.username
        }

        if let searchString = searchString?.trimmingCharacters(in: CharacterSet.whitespaces).lowercased(), !searchString.isEmpty {
            let searchItems = searchString.components(separatedBy: " ")

            recentItems = recentItems.filter { item in
                if let userID = item.userID, let name = item.title?.lowercased() {
                    let username = usernames[userID] ?? ""

                    for term in searchItems {
                        if name.contains(term) || username.contains(term) {
                            return true
                        }
                    }
                } else if item.groupID != nil, let title = item.title?.lowercased() {
                    for term in searchItems {
                        if title.contains(term) {
                            return true
                        }
                    }
                }

                return false
            }
        } else {
            // No Search in progress

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
                        case .user(userID: let userID):
                            if let user = friends.first(where: { $0.id == userID }) {
                                return DestinationPickerDestination(section: .frequentlyContacted, shareDestination: .user(id: userID, name: user.name, username: user.username))
                            }
                        case .chatGroup(groupID: let groupID):
                            if let group = MainAppContext.shared.chatData.chatGroup(groupId: groupID, in: MainAppContext.shared.chatData.viewContext) {
                                return DestinationPickerDestination(section: .frequentlyContacted, shareDestination: .group(id: groupID, type: .groupChat, name: group.name))
                            }
                        case .feedGroup(groupID: let groupID):
                            if let group = MainAppContext.shared.chatData.chatGroup(groupId: groupID, in: MainAppContext.shared.chatData.viewContext) {
                                return DestinationPickerDestination(section: .frequentlyContacted, shareDestination: .group(id: groupID, type: .groupFeed, name: group.name))
                            }
                        }
                        return nil
                    }
                snapshot.appendItems(frequentlyContactedDestinations, toSection: .frequentlyContacted)
            }
        }

        if recentItems.count > 0 {
            snapshot.appendSections([DestinationSection.recent])

            for item in recentItems {
                if let userID = item.userID, let name = item.title {
                    let destination: ShareDestination = .user(id: userID, name: name, username: usernames[userID])
                    snapshot.appendItems([DestinationPickerDestination(section: .recent, shareDestination: destination)], toSection: .recent)
                } else if let groupID = item.groupID, let title = item.title {
                    let destination: ShareDestination = .group(id: groupID, type: item.type, name: title)
                    snapshot.appendItems([DestinationPickerDestination(section: .recent, shareDestination: destination)], toSection: .recent)
                }
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
            Analytics.log(event: .createGroup, properties: [.groupType: "feed"])
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
}

// MARK: UISearchResultsUpdating
extension DestinationPickerViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        updateData(searchString: searchController.searchBar.text)
    }
}
