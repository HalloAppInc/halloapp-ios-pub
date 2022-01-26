//
//  DestinationViewController.swift
//  Shared Extension
//
//  Copyright © 2021 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import Intents
import UIKit
import Social

private extension Localizations {
    static var title: String {
        NSLocalizedString("share.destination.title", value: "HalloApp", comment: "Destination screen title")
    }

    static var home: String {
        NSLocalizedString("share.destination.home", value: "Home", comment: "Share on the home feed label")
    }

    static var contacts: String {
        NSLocalizedString("share.destination.contacts", value: "Recent Contacts", comment: "Contacts category label")
    }

    static var groups: String {
        NSLocalizedString("share.destination.groups", value: "Your Groups", comment: "Groups category label")
    }

    static var newPost: String {
        NSLocalizedString("share.destination.new", value: "New Post", comment: "Share on the home feed selection cell")
    }
}

class ShareDestinationViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    private let contacts: [ABContact]
    private let allGroups: [GroupListSyncItem]
    private var groups: [GroupListSyncItem]
    private var filteredContacts: [ABContact] = []
    private var filteredGroups: [GroupListSyncItem] = []
    private var searchController: UISearchController!
    private var selected: [ShareDestination] = []
    private var cancellableSet: Set<AnyCancellable> = []
    private var hasMoreGroups: Bool = true

    private var isFiltering: Bool {
        return searchController.isActive && !(searchController.searchBar.text?.isEmpty ?? true)
    }

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.allowsMultipleSelection = true
        tableView.backgroundColor = .primaryBg
        tableView.rowHeight = 50
        tableView.register(DestinationCell.self, forCellReuseIdentifier: DestinationCell.reuseIdentifier)
        tableView.keyboardDismissMode = .onDrag
        tableView.contentInset = UIEdgeInsets(top: -10, left: 0, bottom: 0, right: 0) // -10 to hide top padding on searchBar
        tableView.delegate = self
        tableView.dataSource = self

        return tableView
    } ()

    private lazy var selectionRow: ShareDestinationRowView = {
        let rowView = ShareDestinationRowView() { [weak self] index in
            guard let self = self else { return }

            self.selected.remove(at: index)
            self.updateNextBtn()
            self.updateSelectionRow()
            self.tableView.reloadData()
        }

        return rowView
    } ()

    private lazy var selectionRowHeightConstraint: NSLayoutConstraint = {
        selectionRow.heightAnchor.constraint(equalToConstant: 0)
    } ()

    private lazy var bottomConstraint: NSLayoutConstraint = {
        selectionRow.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    } ()
    
    init() {
        var chatTimestamps: [UserID : Date] = [:]
        ChatListSyncItem.load().forEach {
            chatTimestamps[$0.userId] = $0.timestamp ?? Date.distantPast
        }

        contacts = ShareExtensionContext.shared.contactStore.allRegisteredContacts(sorted: false).sorted {
            var timestamp0 = Date.distantPast
            var timestamp1 = Date.distantPast

            if let userId = $0.userId, let time = chatTimestamps[userId] {
                timestamp0 = time
            }

            if let userId = $1.userId, let time = chatTimestamps[userId] {
                timestamp1 = time
            }

            if timestamp0 == timestamp1 {
                return $0.sort > $1.sort
            }

            return timestamp0 > timestamp1
        }
        allGroups = GroupListSyncItem.load().sorted {
            ($0.lastActivityTimestamp ?? Date.distantPast) > ($1.lastActivityTimestamp ?? Date.distantPast)
        }

        hasMoreGroups = allGroups.count > 6
        groups = hasMoreGroups ? [GroupListSyncItem](allGroups[..<6]) : allGroups

        super.init(nibName: nil, bundle: nil)

        DDLogInfo("ShareDestinationViewController/init loaded \(groups.count) groups and \(contacts.count) contacts")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.title = Localizations.title
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelAciton))

        setupSearch()

        view.backgroundColor = .primaryBg
        view.addSubview(tableView)
        view.addSubview(selectionRow)

        tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        tableView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        tableView.bottomAnchor.constraint(equalTo: selectionRow.topAnchor).isActive = true
        selectionRow.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        selectionRow.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        selectionRowHeightConstraint.isActive = true
        bottomConstraint.isActive = true
        
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

        handleKeyboardUpdates()
    }

    private func handleKeyboardUpdates() {
        cancellableSet.insert(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification).sink { [weak self] notification in
            guard let self = self else { return }
            self.animateWithKeyboard(notification: notification) {
                self.bottomConstraint.constant = -$0
            }
        })

        cancellableSet.insert(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification).sink { [weak self] notification in
            guard let self = self else { return }
            self.animateWithKeyboard(notification: notification) { _ in
                self.bottomConstraint.constant = 0
            }
        })
    }

    private func animateWithKeyboard(notification: Notification, animations: @escaping (CGFloat) -> Void) {
        let durationKey = UIResponder.keyboardAnimationDurationUserInfoKey
        guard let duration = notification.userInfo?[durationKey] as? Double else { return }

        let frameKey = UIResponder.keyboardFrameEndUserInfoKey
        guard let keyboardFrameValue = notification.userInfo?[frameKey] as? NSValue else { return }

        let curveKey = UIResponder.keyboardAnimationCurveUserInfoKey
        guard let curveValue = notification.userInfo?[curveKey] as? Int else { return }
        guard let curve = UIView.AnimationCurve(rawValue: curveValue) else { return }

        let animator = UIViewPropertyAnimator(duration: duration, curve: curve) {
            animations(keyboardFrameValue.cgRectValue.height)
            self.view?.layoutIfNeeded()
        }

        animator.startAnimation()
    }

    private func updateNextBtn() {
        if selected.count > 0 {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: Localizations.buttonNext, style: .done, target: self, action: #selector(nextAction))
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    private func updateSelectionRow() {
        if selected.count > 0 && selectionRowHeightConstraint.constant == 0 {
            UIView.animate(withDuration: 0.3, animations: {
                self.selectionRowHeightConstraint.constant = 100
                self.selectionRow.layoutIfNeeded()
            }) { _ in
                self.selectionRow.update(with: self.selected)
            }
        } else if selected.count == 0 && selectionRowHeightConstraint.constant > 0 {
            selectionRow.update(with: self.selected)

            UIView.animate(withDuration: 0.3) {
                self.selectionRowHeightConstraint.constant = 0
                self.selectionRow.layoutIfNeeded()
            }
        } else {
            selectionRow.update(with: self.selected)
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

    private func setupSearch() {
        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.definesPresentationContext = true
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.delegate = self

        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
    }

    // MARK: Data Source

    func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
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
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 1:
            return Localizations.groups
        case 2:
            return Localizations.contacts
        default:
            return nil
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DestinationCell.reuseIdentifier, for: indexPath) as! DestinationCell

        guard let destination = destinationForRow(at: indexPath) else { return cell }
        let isSelected = selected.contains { $0 == destination }

        switch destination {
        case .feed:
            cell.configureHome(isSelected: isSelected) {
                // TODO
            }
        case .group(let group):
            cell.configure(group, isSelected: isSelected)
        case .contact(let contact):
            cell.configure(contact, isSelected: isSelected)
        }

        return cell
    }

    // MARK: UITableViewDelegate

    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        guard let destination = destinationForRow(at: indexPath) else { return nil }

        if let idx = selected.firstIndex(where: { $0 == destination }) {
            selected.remove(at: idx)
        } else {
            selected.append(destination)
        }

        updateNextBtn()
        updateSelectionRow()
        searchController.searchBar.text = ""
        searchController.isActive = false
        tableView.reloadData()

        return nil
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        if section == 1 && !isFiltering && hasMoreGroups {
            let container = UIView()

            let moreGroupsButton = UIButton(type: .custom)
            moreGroupsButton.translatesAutoresizingMaskIntoConstraints = false
            moreGroupsButton.setTitle("Show more...", for: .normal)
            moreGroupsButton.setTitleColor(.primaryBlue, for: .normal)
            moreGroupsButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
            moreGroupsButton.addTarget(self, action: #selector(moreGroupsAction), for: .touchUpInside)

            container.addSubview(moreGroupsButton)
            NSLayoutConstraint.activate([
                moreGroupsButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
                moreGroupsButton.topAnchor.constraint(equalTo: container.topAnchor),
                moreGroupsButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
            ])

            return container
        }

        return nil
    }

    @objc func moreGroupsAction() {
        groups = allGroups
        hasMoreGroups = false
        tableView.reloadData()
    }
}

// MARK: UISearchBarDelegate
extension ShareDestinationViewController: UISearchBarDelegate {
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        DispatchQueue.main.async { [weak self] in
            self?.tableView.reloadData()
            self?.tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .middle, animated: true)
        }
    }
}

// MARK: UISearchResultsUpdating
extension ShareDestinationViewController: UISearchResultsUpdating {

    func updateSearchResults(for searchController: UISearchController) {
        guard let searchText = searchController.searchBar.text?.trimmingCharacters(in: CharacterSet.whitespaces), !searchText.isEmpty else { return }
        let searchItems = searchText.lowercased().components(separatedBy: " ")

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
    }
}

fileprivate class DestinationCell: UITableViewCell {
    static var reuseIdentifier: String {
        return String(describing: DestinationCell.self)
    }

    private var cancellable: AnyCancellable?
    private var more: (() -> Void)?
    private lazy var homeView: UIView = {
        let imageView = UIImageView(image: Self.homeIcon)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .avatarHomeIcon
        imageView.contentMode = .scaleAspectFit

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .avatarHomeBg
        container.layer.cornerRadius = 6
        container.clipsToBounds = true
        container.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        container.isHidden = true

        container.addSubview(imageView)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 34),
            container.heightAnchor.constraint(equalTo: container.widthAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 24),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor),
            imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }()
    private var avatar: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        imageView.isHidden = true

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 34),
            imageView.heightAnchor.constraint(equalToConstant: 34),
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
        label.isHidden = true

        return label
    }()
    private lazy var moreButton: UIButton = {
        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(Self.more, for: .normal)
        button.tintColor = .primaryBlue
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        button.addTarget(self, action: #selector(moreAction), for: .touchUpInside)
        button.isHidden = true

        return button
    }()
    private lazy var selectedView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = Self.checkmarkUnchecked
        imageView.tintColor = Self.colorUnchecked
        imageView.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        return imageView
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func prepareForReuse() {
        cancellable?.cancel()
        homeView.isHidden = true
        avatar.isHidden = true
        subtitle.isHidden = true
        moreButton.isHidden = true
    }

    private func setup() {
        selectionStyle = .none

        let labels = UIStackView(arrangedSubviews: [ title, subtitle ])
        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.axis = .vertical
        labels.distribution = .fill
        labels.spacing = 3

        let stack = UIStackView(arrangedSubviews: [homeView, avatar, labels, moreButton, selectedView])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fill
        stack.spacing = 10

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: 16),
            stack.rightAnchor.constraint(equalTo: contentView.rightAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    @objc func moreAction() {
        if let more = more {
            more()
        }
    }

    public func configureHome(isSelected: Bool, more: @escaping () -> Void) {
        self.more = more

        title.text = Localizations.home
        homeView.isHidden = false
        subtitle.isHidden = false
//        moreButton.isHidden = false

        switch ShareExtensionContext.shared.privacySettings.activeType {
        case .all:
            subtitle.text = Localizations.feedPrivacyShareWithAllContacts
        case .blacklist:
            subtitle.text = Localizations.feedPrivacyShareWithContactsExcept
        case .whitelist:
            subtitle.text = Localizations.feedPrivacyShareWithSelected
        default:
            subtitle.isHidden = true
        }

        configureSelected(isSelected)
    }

    public func configure(_ group: GroupListSyncItem, isSelected: Bool) {
        title.text = group.name
        avatar.isHidden = false
        avatar.layer.cornerRadius = 6

        loadAvatar(group: group.id)
        configureSelected(isSelected)
    }

    public func configure(_ contact: ABContact, isSelected: Bool) {
        title.text = contact.fullName
        subtitle.isHidden = false
        subtitle.text = contact.phoneNumber
        avatar.isHidden = false
        avatar.layer.cornerRadius = 17

        if let id = contact.userId {
            loadAvatar(user: id)
        } else {
            avatar.image = AvatarView.defaultImage
        }

        configureSelected(isSelected)
    }

    private func configureSelected(_ isSelected: Bool) {
        selectedView.image = isSelected ? Self.checkmarkChecked : Self.checkmarkUnchecked
        selectedView.tintColor = isSelected ? Self.colorChecked : Self.colorUnchecked
    }

    private func loadAvatar(group id: GroupID) {
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
        let userAvatar = ShareExtensionContext.shared.avatarStore.userAvatar(forUserId: id)

        if let image = userAvatar.image {
            avatar.image = image
        } else {
            avatar.image = AvatarView.defaultImage

            if !userAvatar.isEmpty {
                userAvatar.loadImage(using: ShareExtensionContext.shared.avatarStore)
            }
        }

        cancellable = userAvatar.imageDidChange.sink { [weak self] image in
            guard let self = self else { return }

            if let image = image {
                self.avatar.image = image
            } else {
                self.avatar.image = AvatarView.defaultImage
            }
        }
    }

    static var homeIcon: UIImage {
        UIImage(named: "HomeFill")!.withRenderingMode(.alwaysTemplate)
    }

    private static var more: UIImage {
        UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21))!.withRenderingMode(.alwaysTemplate)
    }

    private static var checkmarkUnchecked: UIImage {
        UIImage(systemName: "circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21))!.withRenderingMode(.alwaysTemplate)
    }

    private static var checkmarkChecked: UIImage {
        UIImage(systemName: "checkmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 21))!.withRenderingMode(.alwaysTemplate)
    }

    private static var colorChecked: UIColor {
        .primaryBlue
    }

    private static var colorUnchecked: UIColor {
        .primaryBlackWhite.withAlphaComponent(0.2)
    }
}
