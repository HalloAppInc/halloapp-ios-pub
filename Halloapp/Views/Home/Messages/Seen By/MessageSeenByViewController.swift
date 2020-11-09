//
//  HalloApp
//
//  Created by Tony Jiang on 8/30/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import CoreData
import UIKit

private class SectionHeaderView: UITableViewHeaderFooterView {

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        commonInit()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    var sectionNameLabel: UILabel!

    private func commonInit() {
        directionalLayoutMargins.top = 16
        directionalLayoutMargins.bottom = 16

        let view = UIView(frame: bounds)
        view.backgroundColor = .feedBackground
        backgroundView = view

        sectionNameLabel = UILabel()
        sectionNameLabel.textColor = .label
        sectionNameLabel.font = UIFont.gothamFont(forTextStyle: .headline, weight: .medium)
        sectionNameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sectionNameLabel)
        sectionNameLabel.constrainMargins(to: contentView)
    }
}

private extension Localizations {

    static var viewedBy: String {
        NSLocalizedString("message.info.viewed.by",
                          value: "Viewed by",
                          comment: "Message Info screen: title for group of contacts who has seen your group chat message.")
    }

    static var sentTo: String {
        NSLocalizedString("message.info.sent.to",
                          value: "Sent to",
                          comment: "Message Info screen: title for group of contacts who has not yet seen your group chat message.")
    }

    static var messageNotYetViewedByAnyone: String {
        NSLocalizedString("message.info.not.viewed.yet", value: "No one has viewed your message yet",
                          comment: "Placeholder text displayed in Message Info screen when no one has seen your group chat message yet.")
    }

}

private class MessageReceiptsDataSource: UITableViewDiffableDataSource<ChatGroupMessageReceipt.ReceiptType, ChatGroupMessageReceipt> {

}

class MessageSeenByViewController: UITableViewController, NSFetchedResultsControllerDelegate {

    private struct Constants {
        static let cellReuseIdentifier = "MessageSeenByCell"
        static let placeholderCellReuseIdentifier = "placeholder-cell"
        static let headerReuseIdentifier = "Header"
    }

    private let chatGroupMessageId: String

    private var dataSource: MessageReceiptsDataSource!
    private var fetchedResultsController: NSFetchedResultsController<ChatGroupMessage>!

    required init(chatGroupMessageId: String) {
        self.chatGroupMessageId = chatGroupMessageId
        super.init(style: .grouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = ""
        navigationItem.standardAppearance = .opaqueAppearance
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(closeAction))

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Constants.placeholderCellReuseIdentifier)
        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: Constants.cellReuseIdentifier)
        tableView.register(SectionHeaderView.self, forHeaderFooterViewReuseIdentifier: Constants.headerReuseIdentifier)
        tableView.allowsSelection = false
        tableView.backgroundColor = .feedBackground
        tableView.delegate = self

        dataSource = MessageReceiptsDataSource(tableView: tableView) { (tableView, indexPath, receipt) in
            if receipt.type == .placeholder {
                let cell = tableView.dequeueReusableCell(withIdentifier: Constants.placeholderCellReuseIdentifier, for: indexPath)
                cell.selectionStyle = .none
                cell.textLabel?.textAlignment = .center
                cell.textLabel?.textColor = .secondaryLabel
                cell.textLabel?.text = Localizations.messageNotYetViewedByAnyone
                return cell
            }
            let cell = tableView.dequeueReusableCell(withIdentifier: Constants.cellReuseIdentifier, for: indexPath) as! ContactTableViewCell
            cell.configureWithReceipt(receipt, using: MainAppContext.shared.avatarStore)
            return cell
        }

        let fetchRequest: NSFetchRequest<ChatGroupMessage> = ChatGroupMessage.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", chatGroupMessageId)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \ChatGroupMessage.timestamp, ascending: true) ]
        fetchedResultsController = NSFetchedResultsController<ChatGroupMessage>(fetchRequest: fetchRequest, managedObjectContext: MainAppContext.shared.chatData.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        fetchedResultsController.delegate = self
        do {
            try fetchedResultsController.performFetch()
            if let chatGroupMessage = fetchedResultsController.fetchedObjects?.first {
                reloadData(from: chatGroupMessage)
            }
        }
        catch {
            fatalError("Failed to fetch feed post. \(error)")
        }
    }

    @objc private func closeAction() {
        dismiss(animated: true)
    }

    // MARK: Table View Support

    private func titleForHeader(inSection section: Int) -> String? {
        guard let receiptType = ChatGroupMessageReceipt.ReceiptType(rawValue: section) else { return nil }
        switch receiptType  {
        case .seen:
            return Localizations.viewedBy

        case .sentTo:
            return Localizations.sentTo

        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        var headerView: SectionHeaderView! = tableView.dequeueReusableHeaderFooterView(withIdentifier: Constants.headerReuseIdentifier) as? SectionHeaderView
        if headerView == nil {
            headerView = SectionHeaderView(reuseIdentifier: Constants.headerReuseIdentifier)
        }
        headerView.directionalLayoutMargins.top = section > 0 ? 32 : 16
        headerView.sectionNameLabel.text = titleForHeader(inSection: section)
        return headerView
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        if let chatGroupMessage = controller.fetchedObjects?.last as? ChatGroupMessage {
            reloadData(from: chatGroupMessage)
        }
    }

    private func reloadData(from chatGroupMessage: ChatGroupMessage) {

        var seenRows = [ChatGroupMessageReceipt]()
        var sentToRows = [ChatGroupMessageReceipt]()
        
        chatGroupMessage.info?.forEach { (info) in
            let abContact = MainAppContext.shared.contactStore.sortedContacts(withUserIds: [info.userId]).first
            let name = MainAppContext.shared.contactStore.fullName(for: info.userId)
            let phone = abContact?.phoneNumber?.formattedPhoneNumber

            if info.outboundStatus == .seen {
                seenRows.append(ChatGroupMessageReceipt(userId: info.userId,
                                                        type: .seen,
                                                        contactName: name,
                                                        phoneNumber: phone,
                                                        timestamp: info.timestamp))
            } else if chatGroupMessage.outboundStatus != .pending && info.outboundStatus != .error {
                sentToRows.append(ChatGroupMessageReceipt(userId: info.userId,
                                                          type: .sentTo,
                                                          contactName: name,
                                                          phoneNumber: phone,
                                                          timestamp: info.timestamp))
            }
        }

        if seenRows.isEmpty {
            seenRows.append(ChatGroupMessageReceipt(userId: "", type: .placeholder, contactName: nil, phoneNumber: nil, timestamp: Date()))
        }

        var snapshot = NSDiffableDataSourceSnapshot<ChatGroupMessageReceipt.ReceiptType, ChatGroupMessageReceipt>()
        snapshot.appendSections([ .seen ])
        snapshot.appendItems(seenRows, toSection: .seen)
        if !sentToRows.isEmpty {
            snapshot.appendSections([ .sentTo ])
            snapshot.appendItems(sentToRows, toSection: .sentTo)
        }
        dataSource?.apply(snapshot, animatingDifferences: viewIfLoaded?.window != nil)
    }

}

private struct ChatGroupMessageReceipt: Hashable, Equatable {
    enum ReceiptType: Int {
        case seen = 0
        case sentTo = 1
        case placeholder
    }

    let userId: UserID
    let type: ReceiptType
    let contactName: String?
    let phoneNumber: String?
    let timestamp: Date
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(userId)
        hasher.combine(type)
    }
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.userId == rhs.userId && lhs.type == rhs.type
    }
}

private extension ContactTableViewCell {

    func configureWithReceipt(_ receipt: ChatGroupMessageReceipt, using avatarStore: AvatarStore) {
        contactImage.configure(with: receipt.userId, using: avatarStore)

        nameLabel.text = receipt.contactName
        subtitleLabel.text = receipt.phoneNumber
    }
}
