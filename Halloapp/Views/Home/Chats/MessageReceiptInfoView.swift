//
//  MessageReceiptInfoView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 10/26/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Combine
import Core
import CoreCommon
import CoreData
import UIKit

private extension Localizations {
    static var readyByHeader: String {
        return NSLocalizedString("chat.status.read.by",
                                 value: "Read By",
                                 comment: "Section title showing all the users who have read a particular message in group chat")
    }

    static var deliveredToHeader: String {
        return NSLocalizedString("chat.status.delivered.to",
                                 value: "Delivered To",
                                 comment: "Section title showing all the users to whom a particular message has been delivered to in a group chat")
    }

    static var playedByHeader: String {
        return NSLocalizedString("chat.status.played.by",
                                 value: "Played By",
                                 comment: "Section title showing all the users who have played a particular audio message in group chat")
    }
}

class MessageReceiptInfoView: UIViewController, NSFetchedResultsControllerDelegate {

    enum Section {
        case readBy, deliveredTo, played
    }

    fileprivate struct MessageReceiptData: Equatable, Hashable {
        let userId: UserID
        let status: Int16
    }

    fileprivate enum MessageReceiptRow: Hashable, Equatable {
        case userRow(MessageReceiptData)
        case emptyRow
    }

    var chatMessage: ChatMessage
    var contactsMap: [UserID : ABContact]
    static let rowHeight = CGFloat(54)
    private lazy var dataSource: UICollectionViewDiffableDataSource<Section, MessageReceiptRow> = {
        let dataSource = UICollectionViewDiffableDataSource<Section, MessageReceiptRow>(collectionView: collectionView, cellProvider: { [weak self] collectionView, indexPath, messageReceiptRow in

            switch messageReceiptRow {
            case .userRow(let messageReceiptData):
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DestinationCell.reuseIdentifier, for: indexPath)
                
                guard let cell = cell as? DestinationCell, let self = self, let contactInfo = self.contactsMap[messageReceiptData.userId] else { return cell }

                cell.separator.isHidden = collectionView.numberOfItems(inSection: indexPath.section) - 1 == indexPath.row
                cell.configureUser(messageReceiptData.userId, name: contactInfo.fullName, phone: contactInfo.phoneNumber, enableSelection: false)
                return cell
            case .emptyRow:
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: EmptyDestinationCell.reuseIdentifier, for: indexPath)
                return cell
            }
            
        })
        dataSource.supplementaryViewProvider = { [weak self] (collectionView, kind, indexPath) in
            let view = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: DestinationPickerHeaderView.elementKind, for: indexPath)

            if let self = self, let headerView = view as? DestinationPickerHeaderView {
                let sections = self.dataSource.snapshot().sectionIdentifiers

                if indexPath.section < sections.count {
                    let section = sections[indexPath.section]
                    headerView.text = self.sectionHeader(section: section)
                }
            }

            return view
        }
        return dataSource
    }()

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: self.view.bounds, collectionViewLayout: createLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = UIColor.primaryBg
        collectionView.allowsSelection = false
        collectionView.contentInsetAdjustmentBehavior = .scrollableAxes
        collectionView.preservesSuperviewLayoutMargins = true
        collectionView.register(DestinationCell.self, forCellWithReuseIdentifier: DestinationCell.reuseIdentifier)
        collectionView.register(EmptyDestinationCell.self, forCellWithReuseIdentifier: EmptyDestinationCell.reuseIdentifier)
        collectionView.register(DestinationPickerHeaderView.self, forSupplementaryViewOfKind: DestinationPickerHeaderView.elementKind, withReuseIdentifier: DestinationPickerHeaderView.elementKind)
         collectionView.delegate = self
        return collectionView
    }()

    private func createLayout() -> UICollectionViewCompositionalLayout {
        let layout = UICollectionViewCompositionalLayout { (sectionIndex: Int, layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? in

            let rowHeight: NSCollectionLayoutDimension = .absolute(ContactSelectionViewController.rowHeight)
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
        return layout
    }

    init(chatMessage: ChatMessage) {
        self.chatMessage = chatMessage
        let userIds = chatMessage.orderedInfo.map { $0.userId }
        var contacts = MainAppContext.shared.contactStore.contacts(withUserIds: userIds, in: MainAppContext.shared.contactStore.viewContext)
        contacts = ABContact.contactsWithUniquePhoneNumbers(allContacts: contacts)
        contactsMap = contacts.reduce(into: [UserID: ABContact]()) { (map, contact) in
            if let userID = contact.userId {
                map[userID] = contact
            }
        }
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private lazy var leftBarButtonItem: UIBarButtonItem = {
        let image = UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))

        return UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(backAction))
    }()

    private lazy var receiptInfoFetchedResultsController: NSFetchedResultsController<ChatReceiptInfo> = {
        let request = ChatReceiptInfo.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "timestamp", ascending: false),
        ]

        request.predicate = NSPredicate(format: "chatMessageId = %@", chatMessage.id)
        let fetchedResultsController = NSFetchedResultsController<ChatReceiptInfo>(fetchRequest: request,
                                                                              managedObjectContext: MainAppContext.shared.chatData.viewContext,
                                                                              sectionNameKeyPath: nil,
                                                                              cacheName: nil)
        fetchedResultsController.delegate = self
        return fetchedResultsController
    }()

    override func viewDidLoad() {
        view.backgroundColor = .primaryBg

        navigationItem.title = Localizations.messageInfoTitle
        navigationItem.leftBarButtonItem = leftBarButtonItem

        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swipeToDismiss))
        swipe.direction = .right
        view.addGestureRecognizer(swipe)
        try? receiptInfoFetchedResultsController.performFetch()

        updateData()
    }

    private func updateData() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, MessageReceiptRow>()
        let receiptInfoItems = receiptInfoFetchedResultsController.fetchedObjects
        let isAudioMessage = chatMessage.media?.count == 1 && chatMessage.media?.first?.type == .audio
        if isAudioMessage {
            snapshot.appendSections([Section.played])
        }
        guard let receiptInfoItems = receiptInfoItems else { return }
        var delivered: [MessageReceiptRow] = []
        var readBy: [MessageReceiptRow] = []
        for receiptInfo in receiptInfoItems {
            switch receiptInfo.outgoingStatus {
            case .none:
                break
            case .delivered:
                delivered.append(MessageReceiptRow.userRow(MessageReceiptData(userId: receiptInfo.userId, status: receiptInfo.status)))
            case .seen:
                readBy.append(MessageReceiptRow.userRow(MessageReceiptData(userId: receiptInfo.userId, status: receiptInfo.status)))
            case .played:
                snapshot.appendItems([MessageReceiptRow.userRow(MessageReceiptData(userId: receiptInfo.userId, status: receiptInfo.status))], toSection: Section.played)
            }
        }
        if readBy.count > 0 {
            snapshot.appendSections([Section.readBy])
            snapshot.appendItems(readBy, toSection: Section.readBy)
        } else if !isAudioMessage  {
            // Add empty read by section if message is not an audio message
            snapshot.appendSections([Section.readBy])
            snapshot.appendItems([MessageReceiptRow.emptyRow], toSection: Section.readBy)
        }
        // Add delivered section only if there are delivered items
        if delivered.count > 0 {
            snapshot.appendSections([Section.deliveredTo])
            snapshot.appendItems(delivered, toSection: Section.deliveredTo)
        }
        if isAudioMessage, snapshot.itemIdentifiers(inSection: Section.played).count == 0 {
            snapshot.appendItems([MessageReceiptRow.emptyRow], toSection: Section.played)
        }

        dataSource.apply(snapshot, animatingDifferences: true) {
            self.updateSeparators()
        }
    }

    private func updateSeparators() {
        for cell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell) else { return }
            guard let cell = cell as? DestinationCell else { return }
            cell.separator.isHidden = indexPath.row == collectionView.numberOfItems(inSection: indexPath.section) - 1
        }
    }

    @objc func backAction() {
        navigationController?.popViewController(animated: true)
    }

    private func sectionHeader(section : Section) -> String {
        switch section {
        case .readBy:
            return Localizations.readyByHeader
        case .deliveredTo:
            return Localizations.deliveredToHeader
        case .played:
            return Localizations.playedByHeader
        }
    }

    @objc
    private func swipeToDismiss(_ gesture: UISwipeGestureRecognizer) {
        navigationController?.popViewController(animated: true)
    }

}

extension MessageReceiptInfoView: UICollectionViewDelegate {
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>,
                    didChange anObject: Any,
                    at indexPath: IndexPath?,
                    for type: NSFetchedResultsChangeType,
                    newIndexPath: IndexPath?) {
        updateData()
    }
}
