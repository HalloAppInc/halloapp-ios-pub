//
//  GroupInfoViewController.swift
//  HalloApp
//
//  Created by Tony Jiang on 8/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import CoreData
import Foundation
import UIKit
import CoreMedia

fileprivate struct Constants {
    static let AvatarSize: CGFloat = 100
    static let PhotoIconSize: CGFloat = 40
    static let ActionRowHeight: CGFloat = 52
    static let HeaderHeight: CGFloat = 225
    static let FooterHeight: CGFloat = 100
    static let MaxFontPointSize: CGFloat = 28
}

class GroupInfoViewController: UIViewController, NSFetchedResultsControllerDelegate {

    private var groupID: GroupID
    private var chatGroup: Group?
    private var isAdmin: Bool = false
    private var isMember: Bool = false

    private let tableView = UITableView(frame: CGRect.zero, style: .insetGrouped)
    private let backgroundCellReuseIdentifier = "BackgroundViewCell"
    private let actionCellReuseIdentifier = "ActionViewCell"
    private let cellReuseIdentifier = "ContactViewCell"
    private let statCellReuseIdentifier = "StatViewCell"
    private let descriptionCellReuseIdentifier = "DescriptionViewCell"

    private var fetchedResultsController: NSFetchedResultsController<GroupMember>?
    private var dataSource: GroupInfoDataSource?

    private var showAllContacts: Bool = false
    private var initialNumContactsToShow: Int = 12

    private var showInviteLink: Bool {
        return isAdmin
    }

    private var cancellableSet: Set<AnyCancellable> = []

    init(for groupID: GroupID) {
        DDLogDebug("GroupInfoViewController/init/\(groupID)")
        self.groupID = groupID
        super.init(nibName: nil, bundle: nil)
        self.hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        DDLogInfo("GroupInfoViewController/viewDidLoad")

        navigationItem.title = Localizations.chatGroupInfoTitle
 
        tableView.separatorStyle = .none
        tableView.backgroundColor = UIColor.primaryBg
        tableView.register(BackgroundTableViewCell.self, forCellReuseIdentifier: backgroundCellReuseIdentifier)
        tableView.register(ActionTableViewCell.self, forCellReuseIdentifier: actionCellReuseIdentifier)
        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: cellReuseIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: statCellReuseIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: descriptionCellReuseIdentifier)

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 50

        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.constrain(to: view)

        tableView.delegate = self

        dataSource = GroupInfoDataSource(tableView: tableView) { [weak self] (tableView, indexPath, row) in
            guard let self = self else { return UITableViewCell() }
            if indexPath.section == 0 {
                switch row {
                case .descriptionRow:
                    guard let chatGroup = self.chatGroup else { break }
                    let cell = tableView.dequeueReusableCell(withIdentifier: self.descriptionCellReuseIdentifier, for: indexPath)
                    cell.textLabel?.numberOfLines = 0
                    cell.textLabel?.font = UIFont.systemFont(forTextStyle: .body, maximumPointSize: Constants.MaxFontPointSize)
                    if let desc = chatGroup.desc, !desc.isEmpty {
                        if let font = cell.textLabel?.font, let color = cell.textLabel?.textColor {
                            let ham = HAMarkdown(font: font, color: color)
                            cell.textLabel?.attributedText = ham.parse(desc)
                        }
                    } else {
                        cell.textLabel?.textColor = .secondaryLabel
                        cell.textLabel?.text = Localizations.groupAddDescription
                    }
                    cell.heightAnchor.constraint(equalToConstant: Constants.ActionRowHeight).isActive = true
                    return cell
                default: break
                }
            } else if indexPath.section == 1 {
                switch row {
                case .backgroundRow:
                    guard let cell = tableView.dequeueReusableCell(withIdentifier: self.backgroundCellReuseIdentifier, for: indexPath) as? BackgroundTableViewCell else { break }
                    guard let chatGroup = self.chatGroup else { break }
                    let isDefaultBackground = chatGroup.background == 0
                    let text = isDefaultBackground ? Localizations.chatGroupInfoBgDefaultLabel : Localizations.chatGroupInfoBgColorLabel
                    let backgroundColor = ChatData.getThemeBackgroundColor(for: chatGroup.background)
                    cell.configure(label: text, color: backgroundColor)
                    return cell
                default: break
                }
            } else if indexPath.section == 2 {
                switch row {
                case .contactRow(let contactRow):
                    switch contactRow {
                    case .addMembers:
                        guard let cell = tableView.dequeueReusableCell(withIdentifier: self.actionCellReuseIdentifier, for: indexPath) as? ActionTableViewCell else { break }
                        guard let image = UIImage(named: "GroupsAddMembers")?.withRenderingMode(.alwaysTemplate) else { break }
                        cell.color = .primaryBlue
                        cell.configure(icon: image, label: Localizations.chatGroupInfoAddMembers)
                        return cell
                    case .inviteToGroup:
                        guard let cell = tableView.dequeueReusableCell(withIdentifier: self.actionCellReuseIdentifier, for: indexPath) as? ActionTableViewCell else { break }
                        guard let image = UIImage(named: "ShareLink")?.withRenderingMode(.alwaysTemplate) else { break }
                        cell.color = .primaryBlue
                        cell.configure(icon: image, label: Localizations.groupInfoInviteToGroupViaLink)
                        return cell
                    case .contact(let memberUserID):
                        guard let cell = tableView.dequeueReusableCell(withIdentifier: self.cellReuseIdentifier, for: indexPath) as? ContactTableViewCell else { break }
                        cell.configure(groupID: self.groupID, memberUserID: memberUserID)
                        return cell
                    case .more:
                        guard let cell = tableView.dequeueReusableCell(withIdentifier: self.actionCellReuseIdentifier, for: indexPath) as? ActionTableViewCell else { break }
                        guard let image = UIImage(systemName: "chevron.down")?.withRenderingMode(.alwaysTemplate) else { break }
                        cell.configure(icon: image, label: Localizations.buttonMore)
                        cell.imageBgColor = .clear
                        return cell
                    }
                default:
                    break
                }
            } else if indexPath.section == 3 {
                switch row {
                case .historyStatsRow:
                    let cell = tableView.dequeueReusableCell(withIdentifier: self.statCellReuseIdentifier, for: indexPath)
                    cell.textLabel?.numberOfLines = 0
                    cell.textLabel?.font = UIFont.systemFont(forTextStyle: .body, maximumPointSize: Constants.MaxFontPointSize)
                    cell.textLabel?.text = self.generateHistoryStatsString()
                    cell.heightAnchor.constraint(equalToConstant: Constants.ActionRowHeight).isActive = true
                    return cell
                default: break
                }
            }
            return UITableViewCell()
        }

        setupFetchedResultsController()
        reloadData(animated: false)

        cancellableSet.insert(MainAppContext.shared.chatData.didGetAGroupEvent.sink { [weak self] (groupID) in
            guard let self = self else { return }
            guard self.groupID == groupID else { return }
            self.refreshGroupInfo() // for refreshing group name
            self.reloadData(animated: false) // for refreshing group description and background
        })
    }

    override func viewDidLayoutSubviews() {

        // set header in viewDidLayoutSubviews because tableView does not have the correct size yet in viewDidLoad
        let groupInfoHeaderView = GroupInfoHeaderView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.size.width, height: Constants.HeaderHeight))
        groupInfoHeaderView.delegate = self
        groupInfoHeaderView.configure(chatGroup: chatGroup)
        tableView.tableHeaderView = groupInfoHeaderView

        // set footer in viewDidLayoutSubviews because tableView does not have the correct size yet in viewDidLoad
        let groupInfoFooterView = GroupInfoFooterView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.size.width, height: Constants.FooterHeight))
        groupInfoFooterView.delegate = self
        tableView.tableFooterView = groupInfoFooterView

        checkIfMember()
    }

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("GroupInfoViewController/viewWillAppear")

        chatGroup = MainAppContext.shared.chatData.chatGroup(groupId: groupID, in: MainAppContext.shared.chatData.viewContext)
        if let tableHeaderView = tableView.tableHeaderView as? GroupInfoHeaderView {
            tableHeaderView.configure(chatGroup: chatGroup)
        }
        super.viewWillAppear(animated)
        MainAppContext.shared.chatData.syncGroupIfNeeded(for: groupID)
    }

    deinit {
        DDLogDebug("GroupInfoViewController/deinit ")
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        DDLogDebug("GroupInfoViewController/traitCollectionDidChange")

        for cell in tableView.visibleCells {
            cell.contentView.layer.backgroundColor = UIColor.secondarySystemGroupedBackground.cgColor
        }
    }

    // MARK: Fetch Results Controller

    public var fetchRequest: NSFetchRequest<GroupMember> {
        get {
            let fetchRequest = NSFetchRequest<GroupMember>(entityName: "GroupMember")
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \ChatGroupMember.typeValue, ascending: true)
            ]
            fetchRequest.predicate = NSPredicate(format: "groupID = %@", groupID)
            return fetchRequest
        }
    }

    private func setupFetchedResultsController() {
        self.fetchedResultsController = self.newFetchedResultsController()
        do {
            try self.fetchedResultsController?.performFetch()
        } catch {
            fatalError("Failed to fetch group members \(error)")
        }
    }

    private func newFetchedResultsController() -> NSFetchedResultsController<GroupMember> {
        let fetchedResultsController = NSFetchedResultsController<GroupMember>(fetchRequest: self.fetchRequest, managedObjectContext: MainAppContext.shared.mainDataStore.viewContext,
                                                                            sectionNameKeyPath: nil, cacheName: nil)
        fetchedResultsController.delegate = self
        return fetchedResultsController
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        reloadData()
        checkIfMember()
    }

    private func sortByFullName(this: GroupMember, that: GroupMember) -> Bool {
        let thisName = MainAppContext.shared.contactStore.fullName(for: this.userID, in: MainAppContext.shared.contactStore.viewContext)
        let thatName = MainAppContext.shared.contactStore.fullName(for: that.userID, in: MainAppContext.shared.contactStore.viewContext)
        return thisName < thatName
    }

    private func reloadData(animated: Bool = true) {
        DispatchQueue.main.async { [weak self] in
            self?.reloadDataInMainQueue(animated: animated)
        }
    }

    private func reloadDataInMainQueue(animated: Bool = true) {
        /* description section */
        var descriptionRows = [Row]()
        let description = chatGroup?.desc ?? ""
        descriptionRows.append(Row.descriptionRow(DescriptionRow.description(description: description)))

        /* background section */
        var backgroundRows = [Row]()
        let selectedBackground = Int(chatGroup?.background ?? 0)
        backgroundRows.append(Row.backgroundRow(BackgroundRow.background(selectedBackground: selectedBackground)))

        /* contacts section */
        var allGroupMembers: [GroupMember] = []

        // user (Me) first, admins second, members who are contacts, members not contacts, all alphabetical
        var yourself: [GroupMember] = []
        var contactsWhoAreAdmins: [GroupMember] = []
        var contactsInAddressBook: [GroupMember] = []
        var contactsNotInAddressBook: [GroupMember] = []
        
        if let objects = fetchedResultsController?.fetchedObjects {
            let contactsViewContext = MainAppContext.shared.contactStore.viewContext
            for groupMember in objects {
                if groupMember.userID == MainAppContext.shared.userData.userId {
                    yourself.append(groupMember)
                } else if groupMember.type == .admin {
                    contactsWhoAreAdmins.append(groupMember)
                } else if MainAppContext.shared.contactStore.isContactInAddressBook(userId: groupMember.userID, in: contactsViewContext) {
                    contactsInAddressBook.append(groupMember)
                } else {
                    contactsNotInAddressBook.append(groupMember)
                }
            }
        }

        contactsWhoAreAdmins.sort(by: sortByFullName)
        contactsInAddressBook.sort(by: sortByFullName)
        contactsNotInAddressBook.sort(by: sortByFullName)

        allGroupMembers.append(contentsOf: Array(yourself))
        allGroupMembers.append(contentsOf: Array(contactsWhoAreAdmins))
        allGroupMembers.append(contentsOf: Array(contactsInAddressBook))
        allGroupMembers.append(contentsOf: Array(contactsNotInAddressBook))

        var allContactRowContacts = [ContactRow]()
        allContactRowContacts.append(contentsOf: allGroupMembers.map { ContactRow.contact($0.userID) })

        var allContactRows = [Row]()
        allContactRows.append(contentsOf: allContactRowContacts.map { Row.contactRow($0) })

        var contactRows = [Row]()

        if isAdmin {
            contactRows.append(Row.contactRow(ContactRow.addMembers))
            contactRows.append(Row.contactRow(ContactRow.inviteToGroup))
        }

        if !showAllContacts && (allContactRows.count > initialNumContactsToShow) {
            contactRows.append(contentsOf: Array(allContactRows.prefix(initialNumContactsToShow - 2))) // show 10
            contactRows.append(Row.contactRow(ContactRow.more))
        } else {
            contactRows.append(contentsOf: Array(allContactRows))
        }

        var historyStatsRows = [Row]()
        historyStatsRows.append(.historyStatsRow(.stats))

        /* apply snapshot */
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        let numContacts = allContactRows.count
        snapshot.appendSections([ .description, .background, .contacts(numContacts: numContacts) ])
        snapshot.appendItems(descriptionRows, toSection: .description)
        snapshot.appendItems(backgroundRows, toSection: .background)
        snapshot.appendItems(contactRows, toSection: .contacts(numContacts: numContacts))
        if ServerProperties.isInternalUser {
            snapshot.appendSections([.historyStats])
            snapshot.appendItems(historyStatsRows, toSection: .historyStats)
        }

        dataSource?.defaultRowAnimation = .fade

        if #available(iOS 15.0, *) {
            dataSource?.applySnapshotUsingReloadData(snapshot)
        } else {
            dataSource?.apply(snapshot, animatingDifferences: animated)
        }
    }

    private func generateHistoryStatsString() -> String {
        guard let chatGroup = chatGroup else {
            return ""
        }
        let groupFeedHistoryDecryption = AppContext.shared.cryptoData.fetchGroupFeedHistoryDecryption(groupID: chatGroup.id, in: AppContext.shared.cryptoData.viewContext)
        let numExpected = groupFeedHistoryDecryption?.numExpected ?? 0
        let numDecrypted = groupFeedHistoryDecryption?.numDecrypted ?? 0
        return String(numDecrypted) + " / " + String(numExpected)
    }

    // MARK: Actions

    @objc private func openEditAvatarOptions() {
        let viewContext = MainAppContext.shared.chatData.viewContext
        guard MainAppContext.shared.chatData.chatGroupMember(groupId: groupID, memberUserId: MainAppContext.shared.userData.userId, in: viewContext) != nil else { return }
        let avatarData = MainAppContext.shared.avatarStore.groupAvatarData(for: groupID)

        let actionSheet = UIAlertController(title: Localizations.chatGroupPhotoTitle, message: nil, preferredStyle: .actionSheet)
        actionSheet.view.tintColor = UIColor.systemBlue

        if !avatarData.isEmpty {
            actionSheet.addAction(UIAlertAction(title: Localizations.viewPhoto, style: .default) { [weak self] _ in
                self?.presentAvatar()
            })
        }
        
        actionSheet.addAction(UIAlertAction(title: Localizations.chatGroupTakeOrChoosePhoto, style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.presentPhotoLibraryPicker()
        })

        if !avatarData.isEmpty {
            actionSheet.addAction(UIAlertAction(title: Localizations.deletePhoto, style: .destructive) { [weak self] _ in
                self?.changeAvatar(data: nil)
            })
        }

        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))

        present(actionSheet, animated: true)
    }

    @objc private func editNameAction() {
        guard let chatGroup = chatGroup else { return }
        guard isMember else { return }
        let controller = EditGroupViewController(chatGroup: chatGroup)
        controller.delegate = self
        present(UINavigationController(rootViewController: controller), animated: true)
    }

    @objc private func changeBackgroundAction() {
        guard let group = chatGroup else { return }
        guard isMember else { return }
        let vc = GroupBackgroundViewController(chatGroup: group)
        vc.delegate = self
        present(UINavigationController(rootViewController: vc), animated: true)
    }

    @objc private func shareAction() {
        let controller = GroupInviteViewController(for: groupID)
        navigationController?.pushViewController(controller, animated: true)
    }

    func openAddMembers() {
        var currentMembers: [UserID] = []
        if let objects = fetchedResultsController?.fetchedObjects {
            for groupMember in objects {
                currentMembers.append(groupMember.userID)
            }
        }
        guard ContactStore.contactsAccessAuthorized else {
            let vController = NewGroupMembersPermissionDeniedController(currentMembers: currentMembers)
            navigationController?.pushViewController(vController, animated: true)
            return
        }
        let vController = NewGroupMembersViewController(isNewCreationFlow: false,
                                                        currentMembers: currentMembers,
                                                        groupID: groupID) { [weak self, groupID] (_, didComplete, selectedMembers) in
            if didComplete {
                MainAppContext.shared.service.modifyGroup(groupID: groupID,
                                                          with: selectedMembers,
                                                          groupAction: .modifyMembers,
                                                          action: .add) { [weak self] _ in
                    self?.refreshGroupInfo()
                }
            }
        }
        self.navigationController?.pushViewController(vController, animated: true)
    }

    func openEditDesc() {
        guard let chatGroup = chatGroup else { return }
        guard isMember else { return }
        let controller = EditGroupDescViewController(chatGroup: chatGroup)
        controller.delegate = self
        present(UINavigationController(rootViewController: controller), animated: true)
    }

    func openBackground() {
        guard let group = chatGroup else { return }
        guard isMember else { return }
        let vc = GroupBackgroundViewController(chatGroup: group)
        vc.delegate = self
        present(UINavigationController(rootViewController: vc), animated: true)
    }

    private func showAllContactsTapped() {
        showAllContacts = true
        reloadData(animated: false) // animation causes jumpiness for long lists for some reason
    }

    // MARK: Helpers

    func checkIfMember() {
        guard let headerView = tableView.tableHeaderView as? GroupInfoHeaderView else { return }
        guard let footerView = tableView.tableFooterView as? GroupInfoFooterView else { return }
        var haveAdminPermissionChanged: Bool = false
        let viewContext = MainAppContext.shared.chatData.viewContext

        if let chatGroupMember = MainAppContext.shared.chatData.chatGroupMember(groupId: groupID, memberUserId: MainAppContext.shared.userData.userId, in: viewContext) {
            if chatGroupMember.type == .admin {
                if !isAdmin { haveAdminPermissionChanged = true }
                isAdmin = true
                isMember = true
                headerView.setIsMember(true)
                footerView.setIsMember(true)
            } else if chatGroupMember.type == .member {
                if isAdmin { haveAdminPermissionChanged = true }
                isAdmin = false
                isMember = true
                headerView.setIsMember(true)
                footerView.setIsMember(true)
            }
        } else {
            if isAdmin { haveAdminPermissionChanged = true }
            isAdmin = false
            isMember = false
            headerView.setIsMember(false)
            footerView.setIsMember(false)
        }

        if haveAdminPermissionChanged {
            reloadData(animated: false)
        }
    }

    private func presentPhotoLibraryPicker() {
        let pickerController = MediaPickerViewController(config: .image) { [weak self] controller, _, _, media, cancel in
            guard let self = self else { return }

            if cancel || media.count == 0 {
                controller.dismiss(animated: true)
            } else {
                let edit = MediaEditViewController(cropRegion: .square, mediaToEdit: media, selected: 0) { controller, media, index, cancel in
                    controller.dismiss(animated: true)

                    if !cancel && media.count > 0 {
                        if media[0].ready.value {
                            guard let image = media[0].image else { return }
                            self.changeAvatar(image: image)
                        } else {
                            self.cancellableSet.insert(
                                media[0].ready.sink { [weak self] ready in
                                    guard let self = self else { return }
                                    guard ready else { return }
                                    guard let image = media[0].image else { return }
                                    self.changeAvatar(image: image)
                                }
                            )
                        }

                        controller.dismiss(animated: true)
                        self.dismiss(animated: true)
                    }
                }.withNavigationController()

                controller.present(edit, animated: true)
            }
        }

        self.present(UINavigationController(rootViewController: pickerController), animated: true)
    }

    private func presentAvatar() {
        guard let avatarStore = MainAppContext.shared.avatarStore else {
            return
        }
        
        let avatarData = avatarStore.groupAvatarData(for: groupID)
        
        let imagePublisher = avatarData.imageDidChange
            .prepend(avatarData.image)
            .map { image in
                (URL?.none, image, image?.size ?? .zero)
            }.eraseToAnyPublisher()

        let mediaController = MediaExplorerController(imagePublisher: imagePublisher, progress: nil)
        mediaController.delegate = self

        avatarData.loadImage(using: avatarStore)
        
        present(mediaController, animated: true)
    }
    
    private func changeAvatar(image: UIImage) {
        guard let resizedImage = image.fastResized(to: AvatarStore.thumbnailSize) else {
            DDLogError("GroupInfoViewController/resizeImage error resize failed")
            return
        }

        let data = resizedImage.jpegData(compressionQuality: CGFloat(UserData.compressionQuality))!

        changeAvatar(data: data)
    }

    private func changeAvatar(data: Data?) {
        MainAppContext.shared.chatData.changeGroupAvatar(groupID: self.groupID, data: data) { result in
            switch result {
            case .success:
                DispatchQueue.main.async() { [weak self] in
                    guard let self = self else { return }

                    // configure again as avatar listens to cached object that's evicted if app goes into background
                    if let tableHeaderView = self.tableView.tableHeaderView as? GroupInfoHeaderView {
                        tableHeaderView.configure(chatGroup: self.chatGroup)
                    }
                }
            case .failure(let error):
                DDLogError("GroupInfoViewController/changeAvatar/error \(error)")
            }
        }
    }

    private func refreshGroupInfo() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self = self else { return }
            self.chatGroup = MainAppContext.shared.chatData.chatGroup(groupId: self.groupID, in: MainAppContext.shared.chatData.viewContext)
            if let tableHeaderView = self.tableView.tableHeaderView as? GroupInfoHeaderView {
                tableHeaderView.configure(chatGroup: self.chatGroup)
            }
        }
    }
}

extension GroupInfoViewController: MediaExplorerTransitionDelegate {
    func getTransitionView(atPostion index: Int) -> UIView? {
        return (self.tableView.tableHeaderView as? GroupInfoHeaderView)?.avatarView
    }
    
    func scrollMediaToVisible(atPostion index: Int) {
        return
    }
    
    func currentTimeForVideo(atPostion index: Int) -> CMTime? {
        return nil
    }

    func shouldTransitionScaleToFit() -> Bool {
        return true
    }
}

// MARK: UITableView Delegates
extension GroupInfoViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 40
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: tableView.frame.size.width, height: 40))
        let label = UILabel(frame: CGRect(x: 0, y: 7, width: tableView.frame.size.width, height: 40))
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = UIColor.secondaryLabel
        if section == 0 {
            label.text = Localizations.groupDescriptionLabel.uppercased()
        } else if section == 1 {
            label.text = Localizations.groupBackgroundLabel.uppercased()
        } else if section == 2 {
            label.text = Localizations.groupMembersLabel.uppercased() + " (\(String(self.chatGroup?.members?.count ?? 0)))"
        } else if section == 3 {
            label.text = "History Decryption Stats"
        }
        view.addSubview(label)
        return view
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let row = dataSource?.itemIdentifier(for: indexPath) else {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }

        func deselectRow() {
            tableView.deselectRow(at: indexPath, animated: true)
        }

        if indexPath.section == 0 {
            openEditDesc()
            deselectRow()
        } else if indexPath.section == 1 {
            openBackground()
            deselectRow()
        } else if indexPath.section == 2 {
            switch row {
            case .contactRow(let contactRow):
                switch contactRow {
                case .addMembers:
                    if isAdmin {
                        openAddMembers()
                    }
                    deselectRow()
                case .inviteToGroup:
                    if isAdmin {
                        shareAction()
                    }
                    deselectRow()
                case .contact(let memberUserID):
                    let viewContext = MainAppContext.shared.chatData.viewContext
                    guard let member = MainAppContext.shared.chatData.chatGroupMember(groupId: groupID, memberUserId: memberUserID, in: viewContext) else {
                        return deselectRow()
                    }
                    guard memberUserID != MainAppContext.shared.userData.userId else {
                        return deselectRow()
                    }
      
                    let userName = MainAppContext.shared.contactStore.fullName(for: memberUserID, in: MainAppContext.shared.contactStore.viewContext)
                    let contactsViewContext = MainAppContext.shared.contactStore.viewContext
                    let isContactInAddressBook = MainAppContext.shared.contactStore.isContactInAddressBook(userId: memberUserID, in: contactsViewContext)
                    let selectedMembers = [memberUserID]

                    let actionSheet = UIAlertController(title: "\(userName)", message: nil, preferredStyle: .actionSheet)
                    actionSheet.view.tintColor = UIColor.systemBlue

                    actionSheet.addAction(UIAlertAction(title: Localizations.chatGroupInfoViewProfile, style: .default) { [weak self] _ in
                        guard let self = self else { return }

                        let userViewController = UserFeedViewController(userId: memberUserID)
                        self.navigationController?.pushViewController(userViewController, animated: true)
                    })
                    
                    if isContactInAddressBook {
                        actionSheet.addAction(UIAlertAction(title: Localizations.chatGroupInfoMessageUser, style: .default) { [weak self] _ in
                            guard let self = self else { return }
                            if ServerProperties.newChatUI {
                                let vc = ChatViewControllerNew(for: memberUserID)
                                self.navigationController?.pushViewController(vc, animated: true)
                            } else {
                                let vc = ChatViewController(for: memberUserID)
                                self.navigationController?.pushViewController(vc, animated: true)
                            }
                        })
                    }

                    if isAdmin {
                        if member.type == .admin {
                            actionSheet.addAction(UIAlertAction(title: Localizations.chatGroupInfoDismissAsAdmin, style: .destructive) { [weak self] _ in
                                guard let self = self else { return }

                                MainAppContext.shared.service.modifyGroup(groupID: self.groupID, with: selectedMembers, groupAction: ChatGroupAction.modifyAdmins, action: ChatGroupMemberAction.demote) { result in }
                            })
                        } else {
                            actionSheet.addAction(UIAlertAction(title: Localizations.chatGroupInfoMakeGroupAdmin, style: .default) { [weak self] _ in
                                guard let self = self else { return }

                                MainAppContext.shared.service.modifyGroup(groupID: self.groupID, with: selectedMembers, groupAction: ChatGroupAction.modifyAdmins, action: ChatGroupMemberAction.promote) { result in }
                            })
                        }
                        actionSheet.addAction(UIAlertAction(title: Localizations.chatGroupInfoRemoveFromGroup, style: .destructive) { [weak self] _ in
                            guard let self = self else { return }

                            MainAppContext.shared.service.modifyGroup(groupID: self.groupID, with: selectedMembers, groupAction: ChatGroupAction.modifyMembers, action: ChatGroupMemberAction.remove) { [weak self] result in
                                guard let self = self else { return }
                                self.refreshGroupInfo()
                            }

                        })
                    }

                    actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
                    present(actionSheet, animated: true) {
                        deselectRow()
                    }
                case .more:
                    tableView.deselectRow(at: indexPath, animated: false)
                    showAllContactsTapped()
                }
            default:
                break
            }
        }
    }

}

fileprivate enum Section: Hashable {
    case description
    case background
    case historyStats
    case contacts(numContacts: Int) // numContacts needed for snapshot to notice changes and update section header title
}

fileprivate enum Row: Hashable, Equatable {
    case descriptionRow(DescriptionRow)
    case backgroundRow(BackgroundRow)
    case contactRow(ContactRow)
    case historyStatsRow(HistoryStatsRow)

    var descriptionRow: DescriptionRow? {
        switch self {
        case .descriptionRow(let descriptionRow): return descriptionRow
        default: return nil
        }
    }

    var backgroundRow: BackgroundRow? {
        switch self {
        case .backgroundRow(let backgroundRow): return backgroundRow
        default: return nil
        }
    }

    var contactRow: ContactRow? {
        switch self {
        case .contactRow(let contactRow): return contactRow
        default: return nil
        }
    }

    var statsRow: HistoryStatsRow? {
        switch self {
        case .historyStatsRow(let statsRow): return statsRow
        default: return nil
        }
    }
}

fileprivate enum DescriptionRow: Hashable, Equatable {
    case description (description: String)
}

fileprivate enum BackgroundRow: Hashable, Equatable {
    case background (selectedBackground: Int)
}

fileprivate enum HistoryStatsRow: Hashable, Equatable {
    case stats
}

fileprivate enum ContactRow: Hashable, Equatable {
    case addMembers
    case inviteToGroup
    case contact(String)
    case more

    var contact: UserID? {
        switch self {
        case .contact(let groupMemberID): return groupMemberID
        default: return nil
        }
    }
}

fileprivate class GroupInfoDataSource: UITableViewDiffableDataSource<Section, Row> { }

// MARK: GroupInfoHeaderView Delegates
extension GroupInfoViewController: GroupInfoHeaderViewDelegate {

    func groupInfoHeaderViewAvatar(_ groupInfoHeaderView: GroupInfoHeaderView) {
        openEditAvatarOptions()
    }

    func groupInfoHeaderViewEdit(_ groupInfoHeaderView: GroupInfoHeaderView) {
        editNameAction()
    }
}

// MARK: GroupInfoFooterView Delegates
extension GroupInfoViewController: GroupInfoFooterViewDelegate {

    func groupInfoFooterView(_ groupInfoFooterView: GroupInfoFooterView) {
        guard let group = chatGroup else { return }

        let actionSheet = UIAlertController(title: nil, message: Localizations.leaveGroupConfirmation(groupName: group.name), preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: Localizations.chatGroupInfoLeaveGroup, style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            MainAppContext.shared.service.leaveGroup(groupID: self.groupID) { result in }
         })
         actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
         self.present(actionSheet, animated: true)
    }
}

protocol GroupInfoHeaderViewDelegate: AnyObject {
    func groupInfoHeaderViewAvatar(_ groupInfoHeaderView: GroupInfoHeaderView)
    func groupInfoHeaderViewEdit(_ groupInfoHeaderView: GroupInfoHeaderView)
}

class GroupInfoHeaderView: UIView {

    weak var delegate: GroupInfoHeaderViewDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    public func configure(chatGroup: Group?) {
        guard let chatGroup = chatGroup else { return }
        let ham = HAMarkdown(font: groupNameText.font, color: groupNameText.textColor)
        groupNameText.attributedText = ham.parse(chatGroup.name)
        avatarView.configure(groupId: chatGroup.id, squareSize: Constants.AvatarSize, using: MainAppContext.shared.avatarStore)
    }

    public func setIsMember(_ isMember: Bool) {
        photoIcon.isHidden = isMember ? false : true
    }

    private func setup() {
        addSubview(vStack)
        vStack.constrain(to: self)
    }

    private lazy var vStack: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [ avatarRow, groupNameLabelRow, groupNameTextRow, spacer])

        view.axis = .vertical
        view.spacing = 0
        view.setCustomSpacing(20, after: avatarRow)

        view.layoutMargins = UIEdgeInsets(top: 0, left: 17, bottom: 0, right: 17)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var avatarRow: UIStackView = {
        let leftSpacer = UIView()
        leftSpacer.translatesAutoresizingMaskIntoConstraints = false

        let rightSpacer = UIView()
        rightSpacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [ leftSpacer, avatarBox, rightSpacer ])

        view.axis = .horizontal
        view.distribution = .equalCentering

        view.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    private lazy var avatarBox: UIView = {
        let viewWidth = Constants.AvatarSize + 40
        let viewHeight = Constants.AvatarSize
        let view = UIView()

        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: viewWidth).isActive = true
        view.heightAnchor.constraint(equalToConstant: viewHeight).isActive = true

        view.addSubview(avatarView)

        avatarView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        avatarView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true

        photoIcon.frame = CGRect(x: 0 - Constants.PhotoIconSize, y: viewHeight - Constants.PhotoIconSize, width: Constants.PhotoIconSize, height: Constants.PhotoIconSize)
        view.addSubview(photoIcon)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(groupAvatarAction(_:)))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)

        return view
    }()

    public lazy var avatarView: AvatarView = {
        let view = AvatarView()

        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: Constants.AvatarSize).isActive = true
        view.heightAnchor.constraint(equalToConstant: Constants.AvatarSize).isActive = true
        return view
    }()

    private lazy var photoIcon: UIImageView = {
        let view = UIImageView()
        let image = UIImage(named: "ProfileHeaderCamera")
        view.image = image?.imageResized(to: CGSize(width: 20, height: 20)).withRenderingMode(.alwaysTemplate)

        view.contentMode = .center
        view.tintColor = UIColor.secondarySystemGroupedBackground
        view.backgroundColor = UIColor.systemBlue
        view.layer.masksToBounds = false
        view.layer.cornerRadius = Constants.PhotoIconSize/2
        view.clipsToBounds = true
        view.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]

        return view
    }()

    private lazy var groupNameLabelRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [groupNameLabel])
        view.axis = .horizontal

        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 5, right: 0)
        view.isLayoutMarginsRelativeArrangement = true

        return view
    }()
    
    private lazy var groupNameLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 12)
        label.text = Localizations.chatGroupNameLabel.uppercased()
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    private lazy var groupNameTextRow: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [ groupNameText ])

        view.layoutMargins = UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 15)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: Constants.ActionRowHeight).isActive = true

        let subView = UIView(frame: view.bounds)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        subView.backgroundColor = .secondarySystemGroupedBackground
        subView.layer.cornerRadius = 10
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        view.insertSubview(subView, at: 0)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(editAction(_:)))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)

        return view
    }()

    private lazy var groupNameText: UILabel = {
        let label = UILabel()
        label.font = .systemFont(forTextStyle: .body, maximumPointSize: Constants.MaxFontPointSize)
        label.textAlignment = .left
        return label
    }()

    @objc func groupAvatarAction (_ sender: UITapGestureRecognizer) {
        delegate?.groupInfoHeaderViewAvatar(self)
    }

    @objc func editAction (_ sender: UITapGestureRecognizer) {
        delegate?.groupInfoHeaderViewEdit(self)
    }
}

protocol GroupInfoFooterViewDelegate: AnyObject {
    func groupInfoFooterView(_ groupInfoFooterView: GroupInfoFooterView)
}

class GroupInfoFooterView: UIView {

    weak var delegate: GroupInfoFooterViewDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    public func setIsMember(_ isMember: Bool) {
        leaveGroupLabel.isHidden = isMember ? false : true
        notAMemberLabel.isHidden = isMember ? true : false
    }

    private func setup() {
        addSubview(vStack)
        vStack.constrain(to: self)
    }

    private lazy var vStack: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [ fixedSpacerRow, leaveGroupRow, spacer ])
        view.axis = .vertical

        view.layoutMargins = UIEdgeInsets(top: 0, left: 17, bottom: 0, right: 17)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    private lazy var fixedSpacerRow: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.primaryBg

        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 30).isActive = true

        return view
    }()

    private lazy var leaveGroupRow: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [ leaveGroupLabel, notAMemberLabel ])
        view.axis = .vertical

        view.layoutMargins = UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 15)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: Constants.ActionRowHeight).isActive = true

        let subView = UIView(frame: view.bounds)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        subView.backgroundColor = .secondarySystemGroupedBackground
        subView.layer.cornerRadius = 10
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        view.insertSubview(subView, at: 0)

        return view
    }()

    private lazy var leaveGroupLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(forTextStyle: .body, maximumPointSize: Constants.MaxFontPointSize)
        label.textColor = .systemRed
        label.textAlignment = .left
        label.text = Localizations.chatGroupInfoLeaveGroup

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(leaveGroupAction(_:)))
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(tapGesture)

        return label
    }()

    private lazy var notAMemberLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(forTextStyle: .body, maximumPointSize: 17)
        label.textColor = .secondaryLabel
        label.textAlignment = .left
        label.text = Localizations.chatGroupInfoNotAMemberLabel
        label.isHidden = true
        
        return label
    }()

    @objc func leaveGroupAction (_ sender: UITapGestureRecognizer) {
        self.delegate?.groupInfoFooterView(self)
    }

}

fileprivate class BackgroundTableViewCell: UITableViewCell {

    public func configure(label: String? = nil, color: UIColor) {
        if let label = label {
            backgroundSelectionLabel.text = label
        }
        backgroundSelectionImage.backgroundColor = color
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .secondarySystemGroupedBackground
        contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        contentView.addSubview(backgroundRow)
        backgroundRow.constrain(to: contentView)
    }

    private lazy var backgroundRow: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let view = UIStackView(arrangedSubviews: [ backgroundSelectionLabel, spacer, backgroundSelectionImage ])

        view.axis = .horizontal
        view.alignment = .center
        view.spacing = 20

        let subView = UIView(frame: view.bounds)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        subView.backgroundColor = .secondarySystemGroupedBackground
        subView.layer.cornerRadius = 10
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        view.insertSubview(subView, at: 0)

        view.layoutMargins = UIEdgeInsets(top: 5, left: 20, bottom: 5, right: 10)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    private lazy var backgroundSelectionLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(forTextStyle: .body, maximumPointSize: 28)
        label.textAlignment = .left
        return label
    }()

    private lazy var backgroundSelectionImage: UIView = {
        let view = UIView()

        let size:CGFloat = 40.0

        view.layer.cornerRadius = size / 2
        view.clipsToBounds = true

        view.layer.borderColor = UIColor.primaryBlackWhite.withAlphaComponent(0.2).cgColor
        view.layer.borderWidth = 1

        view.translatesAutoresizingMaskIntoConstraints = false

        view.widthAnchor.constraint(equalToConstant: size).isActive = true
        view.heightAnchor.constraint(equalToConstant: size).isActive = true
        return view
    }()
    
}

extension GroupInfoViewController: EditGroupViewControllerDelegate {
    func editGroupViewController(_ editGroupViewController: EditGroupViewController) {
        self.refreshGroupInfo()
    }
}

extension GroupInfoViewController: EditGroupDescViewControllerDelegate {
    func editGroupDescViewController(_ editGroupDescViewController: EditGroupDescViewController) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.reloadData()
        }
    }
}

extension GroupInfoViewController: GroupBackgroundViewControllerDelegate {
    func groupBackgroundViewController(_ groupBackgroundViewController: GroupBackgroundViewController) {
        self.refreshGroupInfo()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.reloadData()
        }
    }
}

private extension ContactTableViewCell {

    func configure(groupID: GroupID, memberUserID: UserID) {
        contactImage.configure(with: memberUserID, using: MainAppContext.shared.avatarStore)
        nameLabel.font = UIFont.systemFont(forTextStyle: .body, maximumPointSize: Constants.MaxFontPointSize)
        nameLabel.text = MainAppContext.shared.contactStore.fullName(for: memberUserID, in: MainAppContext.shared.contactStore.viewContext)
        if let member = MainAppContext.shared.chatData.chatGroupMember(groupId: groupID, memberUserId: memberUserID, in: MainAppContext.shared.chatData.viewContext) {
            accessoryLabel.text = member.type == .admin ? Localizations.chatGroupInfoAdminLabel : ""
        }
    }

}

fileprivate extension UIImage {
    func imageResized(to size: CGSize) -> UIImage {
        return UIGraphicsImageRenderer(size: size).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private extension Localizations {

    static var chatGroupInfoTitle: String {
        NSLocalizedString("chat.group.info.title", value: "Group Info", comment: "Title of screen that shows group information")
    }

    static var chatGroupInfoBgDefaultLabel: String {
        NSLocalizedString("chat.group.info.bg.default.label", value: "Default", comment: "Text label for default selection of group feed background color")
    }

    static var chatGroupInfoBgColorLabel: String {
        NSLocalizedString("chat.group.info.bg.color.label", value: "Color", comment: "Text label for a color selection of group feed background color")
    }

    static var chatGroupInfoAddMembers: String {
        NSLocalizedString("chat.group.info.add.members", value: "Add Members", comment: "Action label for adding members to a group")
    }
    
    static var groupInfoInviteToGroupViaLink: String {
        NSLocalizedString("group.info.invite.to.group.via.link", value: "Invite to Group via Link", comment: "Action label for inviting others to join the group via link")
    }

    static var chatGroupInfoAdminLabel: String {
        NSLocalizedString("chat.group.info.admin.label", value: "Admin", comment: "Label shown in the members list when member is an admin")
    }

    static var chatGroupInfoLeaveGroup: String {
        NSLocalizedString("chat.group.info.leave.group", value: "Leave group", comment: "Action label for leaving group")
    }

    static var chatGroupInfoNotAMemberLabel: String {
        NSLocalizedString("chat.group.info.not.a.member.label", value: "You are not a member of this group", comment: "Text label shown when the user is not a member of the group")
    }

    // action menu for group members

    static var chatGroupInfoViewProfile: String {
        NSLocalizedString("chat.group.info.view.profile", value: "View Profile", comment: "Text for menu option of viewing profile")
    }

    static var chatGroupInfoMessageUser: String {
        NSLocalizedString("chat.group.info.message.user", value: "Message", comment: "Text for menu option of messaging user")
    }

    static var chatGroupInfoDismissAsAdmin: String {
        NSLocalizedString("chat.group.info.demote", value: "Dismiss As Admin", comment: "Text for menu option of demoting a group member")
    }

    static var chatGroupInfoMakeGroupAdmin: String {
        NSLocalizedString("chat.group.info.make.group.admin", value: "Make Group Admin", comment: "Text for menu option of making a group member admin")
    }

    static var chatGroupInfoRemoveFromGroup: String {
        NSLocalizedString("chat.group.info.remove.from.group", value: "Remove From Group", comment: "Text for menu option of removing a group member")
    }

    static func leaveGroupConfirmation(groupName: String) -> String {
        let format = NSLocalizedString("chat.group.leave.group.confirmation", value: "Leave “%@”?", comment: "Confirmation message presented when leaving a group")
        return String(format: format, groupName)
    }
}
