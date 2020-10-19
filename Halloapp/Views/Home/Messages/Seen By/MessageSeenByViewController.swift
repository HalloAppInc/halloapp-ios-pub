//
//  HalloApp
//
//  Created by Tony Jiang on 8/30/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import CoreData
import UIKit

fileprivate class SectionHeaderView: UITableViewHeaderFooterView {

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

fileprivate class PostReceiptsDataSource: UITableViewDiffableDataSource<ChatGroupMessageReceipt.ReceiptType, ChatGroupMessageReceipt> {

}

class MessageSeenByViewController: UITableViewController, NSFetchedResultsControllerDelegate {

    private struct Constants {
        static let cellReuseIdentifier = "MessageSeenByCell"
        static let headerReuseIdentifier = "Header"
    }

    private let chatGroupMessageId: String

    private var dataSource: PostReceiptsDataSource!
    private var fetchedResultsController: NSFetchedResultsController<ChatGroupMessage>!

    required init(chatGroupMessageId: String) {
        self.chatGroupMessageId = chatGroupMessageId
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = ""
        navigationItem.standardAppearance = .opaqueAppearance
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(closeAction))

        tableView.register(MessageSeenByCell.self, forCellReuseIdentifier: Constants.cellReuseIdentifier)
        tableView.register(SectionHeaderView.self, forHeaderFooterViewReuseIdentifier: Constants.headerReuseIdentifier)
        tableView.allowsSelection = false
        tableView.backgroundColor = .feedBackground
        tableView.delegate = self

        tableView.estimatedRowHeight = 50
        tableView.rowHeight = UITableView.automaticDimension
        
        
        dataSource = PostReceiptsDataSource(tableView: tableView) { (tableView, indexPath, receipt) in
            let cell = tableView.dequeueReusableCell(withIdentifier: Constants.cellReuseIdentifier, for: indexPath) as! MessageSeenByCell
            cell.configure(receipt, using: MainAppContext.shared.avatarStore)
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
        guard let receiptType = FeedPostReceipt.ReceiptType(rawValue: section) else { return nil }
        switch receiptType  {
        case .seen:
            return "Viewed by"

        case .sent:
            return "Sent to"
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
            let phone = abContact?.phoneNumber

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

class MessageSeenByCell: UITableViewCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }
    
    override func layoutSubviews() {
        super.layoutSubviews()
   
        let labelSpacing: CGFloat = subtitleLabel.text?.isEmpty ?? true ? 0 : 4
        if vStack.spacing != labelSpacing {
            vStack.spacing = labelSpacing
        }
    }
    
    override func prepareForReuse() {
        avatar.prepareForReuse()
        accessoryView = nil
        nameLabel.text = ""
        timeLabel.text = ""
    }
    
    override var isUserInteractionEnabled: Bool {
        didSet {
            if isUserInteractionEnabled {
                nameLabel.textColor = .label
            } else {
                nameLabel.textColor = .systemGray
            }
        }
    }
    
    func configure(_ receipt: ChatGroupMessageReceipt, using avatarStore: AvatarStore) {
        avatar.configure(with: receipt.userId, using: avatarStore)
        nameLabel.text = receipt.contactName
        subtitleLabel.text = receipt.phoneNumber
//        timeLabel.text = receipt.timestamp.chatTimestamp()
    }
    
    private func setup() {
        contentView.addSubview(mainRow)
        mainRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor).isActive = true
        mainRow.topAnchor.constraint(equalTo: contentView.topAnchor).isActive = true
        mainRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor).isActive = true
        mainRow.bottomAnchor.constraint(equalTo: contentView.bottomAnchor).isActive = true
    }

    private lazy var mainRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ avatar, vStack, timeLabel ])
        view.layoutMargins = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
        view.isLayoutMarginsRelativeArrangement = true
        view.axis = .horizontal
        view.alignment = .center
        view.spacing = 10
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        profilePictureSizeConstraint = avatar.heightAnchor.constraint(equalToConstant: profilePictureSize)
        profilePictureSizeConstraint.isActive = true
        avatar.heightAnchor.constraint(equalTo: avatar.widthAnchor).isActive = true
        
        return view
    }()

    private lazy var avatar: AvatarView = {
        let view = AvatarView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var profilePictureSizeConstraint: NSLayoutConstraint!

    var profilePictureSize: CGFloat = 30 {
        didSet {
            profilePictureSizeConstraint.constant = profilePictureSize
        }
    }

    private lazy var vStack: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ nameLabel, subtitleLabel ])
        view.axis = .vertical
        view.spacing = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        return view
    }()

    let nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let subtitleLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    let timeLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return label
    }()
}

struct ChatGroupMessageReceipt: Hashable, Equatable {
    enum ReceiptType: Int {
        case seen = 0
        case sentTo = 1
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
