//
//  DestinationViewController.swift
//  Shared Extension
//
//  Copyright © 2021 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import Intents
import UIKit
import Social

private extension Localizations {
    static var title: String {
        NSLocalizedString("share.destination.title", value: "HalloApp", comment: "Destination screen title")
    }

    static var home: String {
        NSLocalizedString("share.destination.home", value: "My Friends", comment: "Share on the home feed label with all my friends")
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

    static var moreGroups: String {
        NSLocalizedString("share.destination.more", value: "Show more...", comment: "Show more groups in the share group selection")
    }

    static func missing(group name: String) -> String {
        let format = NSLocalizedString("share.destination.missing.group", value: "Missing group %@", comment: "Alert title when a direct to group sharing is missing")
        return String.localizedStringWithFormat(format, name)
    }

    static func missing(contact name: String) -> String {
        let format = NSLocalizedString("share.destination.missing.group", value: "Missing contact %@", comment: "Alert title when a direct to contact sharing is missing")
        return String.localizedStringWithFormat(format, name)
    }
}

fileprivate enum DestinationSection {
    case main, groups, chats
}

class ShareDestinationViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    private let chats: [ChatListSyncItem]
    private let allGroups: [GroupListSyncItem]
    private var groups: [GroupListSyncItem]
    private var feedPrivacyTypes: [PrivacyListType]
    private var filteredChats: [ChatListSyncItem] = []
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
            self.onSelectionChange(destinations: self.selected)
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
        allGroups = GroupListSyncItem.load().sorted {
            ($0.lastActivityTimestamp ?? Date.distantPast) > ($1.lastActivityTimestamp ?? Date.distantPast)
        }

        chats = ChatListSyncItem.load().sorted {
            ($0.timestamp ?? Date.distantPast) > ($1.timestamp ?? Date.distantPast)
        }

        hasMoreGroups = allGroups.count > 6
        groups = hasMoreGroups ? [GroupListSyncItem](allGroups[..<6]) : allGroups

        feedPrivacyTypes = [PrivacyListType.all, PrivacyListType.whitelist]
        super.init(nibName: nil, bundle: nil)

        DDLogInfo("ShareDestinationViewController/init loaded \(groups.count) groups and \(chats.count) chats")
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

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            selectionRow.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            selectionRow.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            selectionRowHeightConstraint,
            bottomConstraint,
        ])
        
        if let intent = extensionContext?.intent as? INSendMessageIntent {
            guard let rawConversationID = intent.conversationIdentifier else { return }
            guard let conversationID = ConversationID(rawConversationID) else { return }
            
            if conversationID.conversationType == .chat {
                guard let chat = chats.first(where: { chat in
                    chat.userId == conversationID.id
                }) else {
                    DDLogError("ShareDestinationViewController/intent/error missing contact userId=[\(conversationID.id)]")

                    let title = Localizations.missing(contact: intent.speakableGroupName?.spokenPhrase ?? "")
                    let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .default))
                    present(alert, animated: true)

                    return
                }

                let destination = ShareDestination.chat(chat)
                navigationController?.pushViewController(ShareComposerViewController(destinations: [destination]) { [weak self] destinations in
                    self?.onSelectionChange(destinations: destinations)
                }, animated: false)
            } else if conversationID.conversationType == .group {
                guard let group = allGroups.first(where: { group in
                    group.id == conversationID.id
                }) else {
                    DDLogError("ShareDestinationViewController/intent/error missing group id=[\(conversationID.id)]")

                    let title = Localizations.missing(group: intent.speakableGroupName?.spokenPhrase ?? "")
                    let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .default))
                    present(alert, animated: true)

                    return
                }

                let destination = ShareDestination.group(group)
                navigationController?.pushViewController(ShareComposerViewController(destinations: [destination]) { [weak self] destinations in
                    self?.onSelectionChange(destinations: destinations)
                }, animated: false)
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
                let bottomContentInset = 100 - self.view.safeAreaInsets.bottom
                self.tableView.contentInset.bottom = bottomContentInset
                self.tableView.verticalScrollIndicatorInsets.bottom = bottomContentInset
                self.selectionRow.layoutIfNeeded()
            }) { _ in
                self.selectionRow.update(with: self.selected)
            }
        } else if selected.count == 0 && selectionRowHeightConstraint.constant > 0 {
            selectionRow.update(with: self.selected)

            UIView.animate(withDuration: 0.3) {
                self.selectionRowHeightConstraint.constant = 0
                self.tableView.contentInset.bottom = 0
                self.tableView.verticalScrollIndicatorInsets.bottom = 0
                self.selectionRow.layoutIfNeeded()
            }
        } else {
            selectionRow.update(with: self.selected)
        }
    }

    @objc func cancelAciton() {
        DDLogInfo("ShareDestinationViewController/cancel")

        ImageServer.shared.clearAllTasks(keepFiles: false)
        ShareDataLoader.shared.reset()

        ShareExtensionContext.shared.coreService.disconnect()
        extensionContext?.cancelRequest(withError: ShareError.cancel)
    }

    @objc private func nextAction() {
        guard selected.count > 0 else { return }
        navigationController?.pushViewController(ShareComposerViewController(destinations: selected) { [weak self] destinations in
            self?.onSelectionChange(destinations: destinations)
        }, animated: true)
    }

    private func onSelectionChange(destinations: [ShareDestination]) {
        selected = destinations
        updateNextBtn()
        updateSelectionRow()
        tableView.reloadData()
    }

    private func destinationForRow(at indexPath: IndexPath) -> ShareDestination? {
        switch sectionAt(index: indexPath.section) {
        case .main:
            return .feed(feedPrivacyTypes[indexPath.row])
        case .groups:
            return .group(isFiltering ? filteredGroups[indexPath.row] : groups[indexPath.row])
        case .chats:
            return .chat(isFiltering ? filteredChats[indexPath.row] : chats[indexPath.row])
        case .none:
            return nil
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

    private func sectionAt(index: Int) -> DestinationSection? {
        if isFiltering {
            if index == 0 && filteredGroups.count > 0 {
                return .groups
            }

            if index == 0 && filteredChats.count >  0 {
                return .chats
            }

            if index == 1 && filteredChats.count >  0 {
                return .chats
            }
        } else {
            if index == 0 {
                return .main
            }

            if index == 1 && groups.count > 0 {
                return .groups
            }

            if index == 1 && chats.count >  0 {
                return .chats
            }

            if index == 2 && chats.count >  0 {
                return .chats
            }
        }

        return nil
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        var count = 0

        if !isFiltering {
            count += 1 // main section
        }

        if isFiltering, filteredGroups.count > 0 {
            count += 1
        } else if !isFiltering, groups.count > 0 {
            count += 1
        }

        if isFiltering, filteredChats.count > 0 {
            count += 1
        } else if !isFiltering, chats.count > 0 {
            count += 1
        }

        return count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sectionAt(index: section) {
        case .main:
            return 2
        case .groups:
            return isFiltering ? filteredGroups.count : groups.count
        case .chats:
            return isFiltering ? filteredChats.count : chats.count
        case .none:
            return 0
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch sectionAt(index: section) {
        case .groups:
            return Localizations.groups
        case .chats:
            return Localizations.contacts
        case .none, .main:
            return nil
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DestinationCell.reuseIdentifier, for: indexPath) as! DestinationCell

        guard let destination = destinationForRow(at: indexPath) else { return cell }
        let isSelected = selected.contains { $0 == destination }
        switch destination {
        case .feed(let privacyListType):
            switch privacyListType {
            case .all:
                cell.configureHome(isSelected: isSelected) {
                    // TODO
                }
            case .whitelist:
                cell.configureFavorites(isSelected: isSelected) {
                    // TODO
                }
            default:
                break
            }
            
        case .group(let group):
            cell.configure(group, isSelected: isSelected)
        case .chat(let chat):
            cell.configure(chat, isSelected: isSelected)
        }

        return cell
    }

    // MARK: UITableViewDelegate

    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        guard let destination = destinationForRow(at: indexPath) else { return nil }

        searchController.searchBar.text = ""
        searchController.isActive = false

        if let idx = selected.firstIndex(where: { $0 == destination }) {
            selected.remove(at: idx)
        } else {
            selected.append(destination)
        }

        // Home and Favorites need to be mutually exclusive
        switch destination {
        case .feed(let privacyListType):
            switch privacyListType {
            case .all:
                selected.removeAll(where: {$0 == .feed(.whitelist)})
            case .whitelist:
                selected.removeAll(where: {$0 == .feed(.all)})
            default:
                break
            }
        default:
            break
        }

        onSelectionChange(destinations: selected)

        return nil
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        if sectionAt(index: section) == .groups && !isFiltering && hasMoreGroups {
            let container = UIView()

            let moreGroupsButton = UIButton(type: .custom)
            moreGroupsButton.translatesAutoresizingMaskIntoConstraints = false
            moreGroupsButton.setTitle(Localizations.moreGroups, for: .normal)
            moreGroupsButton.setTitleColor(.primaryBlue, for: .normal)
            moreGroupsButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
            moreGroupsButton.addTarget(self, action: #selector(moreGroupsAction), for: .touchUpInside)

            container.addSubview(moreGroupsButton)
            NSLayoutConstraint.activate([
                moreGroupsButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
                moreGroupsButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
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
        guard let searchText = searchController.searchBar.text?.trimmingCharacters(in: CharacterSet.whitespaces), !searchText.isEmpty else {
            tableView.reloadData()
            return
        }
        let searchItems = searchText.lowercased().components(separatedBy: " ")

        filteredGroups = allGroups.filter {
            let name = $0.name.lowercased()

            for item in searchItems {
                if name.contains(item) {
                    return true
                }
            }

            return false
        }

        filteredChats = chats.filter {
            let name = $0.displayName.lowercased()
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

    private lazy var favoritesView: UIView = {
        let imageView = UIImageView(image: Self.favoritesIcon)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .white
        imageView.contentMode = .scaleAspectFit

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .favoritesBg
        container.layer.cornerRadius = 6
        container.clipsToBounds = true
        container.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        container.isHidden = true

        container.addSubview(imageView)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 34),
            container.heightAnchor.constraint(equalTo: container.widthAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 34),
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
        super.prepareForReuse()
        
        cancellable?.cancel()
        homeView.isHidden = true
        favoritesView.isHidden = true
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

        let stack = UIStackView(arrangedSubviews: [homeView, favoritesView, avatar, labels, moreButton, selectedView])
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
        subtitle.text = Localizations.feedPrivacyShareWithAllContacts
        homeView.isHidden = false
        subtitle.isHidden = false
//        moreButton.isHidden = false

        configureSelected(isSelected)
        if isSelected {
            ShareExtensionContext.shared.privacySettings.activeType = .all
        }
    }

    public func configureFavorites(isSelected: Bool, more: @escaping () -> Void) {
        self.more = more

        title.text = Localizations.favoritesTitle
        subtitle.text = Localizations.feedPrivacyShareWithSelected
        favoritesView.isHidden = false
        subtitle.isHidden = false
//        moreButton.isHidden = false

        configureSelected(isSelected)
        if isSelected {
            ShareExtensionContext.shared.privacySettings.activeType = .whitelist
        }
    }

    public func configure(_ group: GroupListSyncItem, isSelected: Bool) {
        title.text = group.name
        avatar.isHidden = false
        avatar.layer.cornerRadius = 6

        loadAvatar(group: group.id)
        configureSelected(isSelected)
    }

    public func configure(_ chat: ChatListSyncItem, isSelected: Bool) {
        title.text = chat.displayName
        subtitle.isHidden = false
        subtitle.text = chat.phoneNumber ?? ""
        avatar.isHidden = false
        avatar.layer.cornerRadius = 17

        loadAvatar(user: chat.userId)

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
                userAvatar.loadThumbnailImage(using: ShareExtensionContext.shared.avatarStore)
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
        UIImage(named: "PrivacySettingMyContacts")!.withRenderingMode(.alwaysTemplate)
    }

    static var favoritesIcon: UIImage {
       UIImage(named: "PrivacySettingFavoritesWithBackground")!.withRenderingMode(.alwaysOriginal)
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
