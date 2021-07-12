//
//  DestinationViewController.swift
//  Shared Extension
//
//  Copyright © 2021 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import UIKit
import Social
import Intents

private extension Localizations {
    static var title: String {
        NSLocalizedString("share.destination.title", value: "HalloApp", comment: "Destination screen title")
    }

    static var home: String {
        NSLocalizedString("share.destination.home", value: "Home", comment: "Share on the home feed label")
    }

    static var contacts: String {
        NSLocalizedString("share.destination.contacts", value: "Contacts", comment: "Contacts category label")
    }

    static var groups: String {
        NSLocalizedString("share.destination.groups", value: "Groups", comment: "Groups category label")
    }
}

class ShareDestinationViewController: UITableViewController {
    private let contacts: [ABContact]
    private let groups: [GroupListItem]
    private var filteredContacts: [ABContact] = []
    private var filteredGroups: [GroupListItem] = []
    private var searchController: UISearchController!
    private var selected: [ShareDestination] = []

    private var isFiltering: Bool {
        return searchController.isActive && !(searchController.searchBar.text?.isEmpty ?? true)
    }
    
    init() {
        contacts = ShareExtensionContext.shared.contactStore.allRegisteredContacts(sorted: true)
        groups = GroupListItem.load()
        
        super.init(style: .insetGrouped)

        DDLogInfo("ShareDestinationViewController/init loaded \(groups.count) groups and \(contacts.count) contacts")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.title = Localizations.title
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelAciton))

        tableView.allowsMultipleSelection = true
        tableView.register(DestinationCell.self, forCellReuseIdentifier: DestinationCell.reuseIdentifier)

        setupSearch()
        
        if let intent = extensionContext?.intent as? INSendMessageIntent {
            guard let rawConversationID = intent.conversationIdentifier else { return }
            guard let conversationID = ConversationID(rawConversationID) else { return }
            
            if conversationID.conversationType == .chat {
                guard let contact = ShareExtensionContext.shared.contactStore.allRegisteredContacts(sorted: false).first(where: { contact in
                    contact.userId == conversationID.id
                }) else {
                    return
                }

                let destination = ShareDestination.contact(contact)
                navigationController?.pushViewController(ShareComposerViewController(destinations: [destination]), animated: false)
            } else if conversationID.conversationType == .group {
                guard let group = groups.first(where: { group in
                    group.id == conversationID.id
                }) else {
                    return
                }

                let destination = ShareDestination.group(group)
                navigationController?.pushViewController(ShareComposerViewController(destinations: [destination]), animated: false)
            }
        }
    }

    private func updateNextBtn() {
        if selected.count > 0 {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: Localizations.buttonNext, style: .done, target: self, action: #selector(nextAction))
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    @objc func cancelAciton() {
        DDLogInfo("ShareDestinationViewController/cancel")

        ShareExtensionContext.shared.coreService.disconnect()
        extensionContext?.cancelRequest(withError: ShareError.cancel)
    }

    @objc private func nextAction() {
        guard selected.count > 0 else { return }
        navigationController?.pushViewController(ShareComposerViewController(destinations: selected), animated: true)
    }

    private func destinationForRow(at indexPath: IndexPath) -> ShareDestination? {
        switch indexPath.section {
        case 0:
            return .feed
        case 1:
            return .group(isFiltering ? filteredGroups[indexPath.row] : groups[indexPath.row])
        case 2:
            return .contact(isFiltering ? filteredContacts[indexPath.row] : contacts[indexPath.row])
        default:
            return nil
        }
    }

    private func indexPath(for destination: ShareDestination) -> IndexPath? {
        switch destination {
        case .feed:
            return IndexPath(row: 0, section: 0)
        case .group(let item):
            if isFiltering {
                guard let idx = filteredGroups.firstIndex(where: { $0.id == item.id }) else { return nil }
                return IndexPath(row: idx, section: 1)
            } else {
                guard let idx = groups.firstIndex(where: { $0.id == item.id }) else { return nil }
                return IndexPath(row: idx, section: 1)
            }
        case .contact(let contact):
            if isFiltering {
                guard let idx = filteredContacts.firstIndex(where: { $0 == contact}) else { return nil }
                return IndexPath(row: idx, section: 2)
            } else {
                guard let idx = contacts.firstIndex(where: { $0 == contact}) else { return nil }
                return IndexPath(row: idx, section: 2)
            }
        }
    }

    private func reloadSelection() {
        for destination in selected {
            tableView.selectRow(at: indexPath(for: destination), animated: false, scrollPosition: .none)
        }
    }

    private func setupSearch() {
        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.definesPresentationContext = true
        searchController.hidesNavigationBarDuringPresentation = true
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.delegate = self

        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
    }

    // MARK: Data Source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0:
            return 1
        case 1:
            return isFiltering ? filteredGroups.count : groups.count
        case 2:
            return isFiltering ? filteredContacts.count : contacts.count
        default:
            return 0
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 1:
            return Localizations.groups
        case 2:
            return Localizations.contacts
        default:
            return nil
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DestinationCell.reuseIdentifier, for: indexPath) as! DestinationCell

        switch indexPath.section {
        case 0:
            cell.configure(Localizations.home)
        case 1:
            let group = isFiltering ? filteredGroups[indexPath.row] : groups[indexPath.row]
            cell.configure(group)
        case 2:
            let contact = isFiltering ? filteredContacts[indexPath.row] : contacts[indexPath.row]
            cell.configure(contact)
        default:
            break
        }

        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let destination = destinationForRow(at: indexPath) else { return }

        selected.append(destination)
        updateNextBtn()
    }

    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard let destination = destinationForRow(at: indexPath) else { return }
        guard let idx = selected.firstIndex(where: { $0 == destination }) else { return }

        selected.remove(at: idx)
        updateNextBtn()
    }
}

// MARK: UISearchBarDelegate
extension ShareDestinationViewController: UISearchBarDelegate {
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        DispatchQueue.main.async { [weak self] in
            self?.tableView.reloadData()
            self?.reloadSelection()
            self?.tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .middle, animated: true)
        }
    }
}

// MARK: UISearchResultsUpdating
extension ShareDestinationViewController: UISearchResultsUpdating {

    func updateSearchResults(for searchController: UISearchController) {
        guard let searchText = searchController.searchBar.text?.lowercased() else { return }
        let searchItems = searchText.trimmingCharacters(in: CharacterSet.whitespaces).components(separatedBy: " ")

        filteredGroups = groups.filter {
            let name = $0.name.lowercased()

            for item in searchItems {
                if name.contains(item) {
                    return true
                }
            }

            return false
        }

        filteredContacts = contacts.filter {
            let name = $0.fullName?.lowercased() ?? ""
            let number = $0.phoneNumber ?? ""

            for item in searchItems {
                if name.contains(item) || number.contains(item) {
                    return true
                }
            }

            return false
        }

        tableView.reloadData()
        reloadSelection()
    }
}

fileprivate class DestinationCell: UITableViewCell {
    static var reuseIdentifier: String {
        return String(describing: DestinationCell.self)
    }

    private var cancellable: AnyCancellable?
    private var avatar: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 30),
            imageView.heightAnchor.constraint(equalToConstant: 30),
        ])

        return imageView
    }()
    private lazy var title: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    private lazy var subtitle: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        accessoryType = selected ? .checkmark : .none
    }

    private func setup() {
        selectionStyle = .none

        let labels = UIStackView(arrangedSubviews: [ title, subtitle ])
        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.axis = .vertical
        labels.distribution = .fill
        labels.spacing = 3

        let stack = UIStackView(arrangedSubviews: [avatar, labels])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fill
        stack.spacing = 10

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            stack.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: 16),
            stack.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -16),
        ])
    }

    public func configure(_ text: String) {
        cancellable?.cancel()

        title.text = text
        subtitle.isHidden = true
        avatar.isHidden = true
    }

    public func configure(_ group: GroupListItem) {
        title.text = group.name
        subtitle.isHidden = true
        avatar.isHidden = false
        avatar.layer.cornerRadius = 6

        loadAvatar(group: group.id)
    }

    public func configure(_ contact: ABContact) {
        title.text = contact.fullName
        subtitle.isHidden = false
        subtitle.text = contact.phoneNumber

        if let id = contact.userId {
            avatar.isHidden = false
            avatar.layer.cornerRadius = 15
            loadAvatar(user: id)
        } else {
            avatar.isHidden = true
        }
    }

    private func loadAvatar(group id: GroupID) {
        cancellable?.cancel()

        let avatarData = ShareExtensionContext.shared.avatarStore.groupAvatarData(for: id)

        if let image = avatarData.image {
            avatar.image = image
        } else {
            avatar.image = AvatarView.defaultGroupImage

            if !avatarData.isEmpty {
                avatarData.loadImage(using: ShareExtensionContext.shared.avatarStore)
            }
        }

        cancellable = avatarData.imageDidChange.sink { [weak self] image in
            guard let self = self else { return }

            if let image = image {
                self.avatar.image = image
            } else {
                self.avatar.image = AvatarView.defaultGroupImage
            }
        }
    }

    private func loadAvatar(user id: UserID) {
        cancellable?.cancel()

        let userAvatar = ShareExtensionContext.shared.avatarStore.userAvatar(forUserId: id)

        if let image = userAvatar.image {
            avatar.image = image
        } else {
            avatar.image = AvatarView.defaultGroupImage

            if !userAvatar.isEmpty {
                userAvatar.loadImage(using: ShareExtensionContext.shared.avatarStore)
            }
        }

        cancellable = userAvatar.imageDidChange.sink { [weak self] image in
            guard let self = self else { return }

            if let image = image {
                self.avatar.image = image
            } else {
                self.avatar.image = AvatarView.defaultGroupImage
            }
        }
    }
}
