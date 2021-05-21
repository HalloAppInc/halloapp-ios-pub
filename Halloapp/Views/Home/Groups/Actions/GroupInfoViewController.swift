//
//  GroupInfoViewController.swift
//  HalloApp
//
//  Created by Tony Jiang on 8/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import CoreData
import Foundation
import UIKit

fileprivate struct Constants {
    static let AvatarSize: CGFloat = 100
    static let PhotoIconSize: CGFloat = 40
    static let HeaderHeight: CGFloat = 350
    static let FooterHeight: CGFloat = 250
}

class GroupInfoViewController: UITableViewController, NSFetchedResultsControllerDelegate {

    private var groupId: GroupID
    private var chatGroup: ChatGroup?
    private var isAdmin: Bool = false

    private var fetchedResultsController: NSFetchedResultsController<ChatGroupMember>?

    let cellReuseIdentifier = "GroupMembersViewCell"

    private var cancellableSet: Set<AnyCancellable> = []

    init(for groupId: GroupID) {
        DDLogDebug("GroupInfoViewController/init/\(groupId)")
        self.groupId = groupId
//        self.chatGroup = MainAppContext.shared.chatData.chatGroup(groupId: groupId)
        super.init(style: .insetGrouped)
        self.hidesBottomBarWhenPushed = true
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        DDLogInfo("GroupInfoViewController/viewDidLoad")

        navigationItem.title = Localizations.chatGroupInfoTitle
        navigationItem.standardAppearance = .transparentAppearance
        navigationItem.standardAppearance?.backgroundColor = UIColor.feedBackground
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: Localizations.buttonShare, style: .done, target: self, action: #selector(shareAction))
        navigationItem.rightBarButtonItem?.tintColor = UIColor.systemBlue

        tableView.separatorStyle = .singleLine
        tableView.backgroundColor = UIColor.feedBackground
        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: cellReuseIdentifier)
        
        let groupInfoHeaderView = GroupInfoHeaderView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.size.width, height: Constants.HeaderHeight))
        groupInfoHeaderView.delegate = self
        groupInfoHeaderView.configure(chatGroup: chatGroup)
        tableView.tableHeaderView = groupInfoHeaderView
        
        let groupInfoFooterView = GroupInfoFooterView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.size.width, height: Constants.FooterHeight))
        groupInfoFooterView.delegate = self
        tableView.tableFooterView = groupInfoFooterView

        checkIfMember()

        setupFetchedResultsController()
    }

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("GroupInfoViewController/viewWillAppear")

        chatGroup = MainAppContext.shared.chatData.chatGroup(groupId: groupId)
        if let tableHeaderView = tableView.tableHeaderView as? GroupInfoHeaderView {
            tableHeaderView.configure(chatGroup: chatGroup)
        }

        super.viewWillAppear(animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        DDLogInfo("GroupInfoViewController/viewDidAppear")
        super.viewDidAppear(animated)
        self.tabBarController?.hideTabBar()
    }

    deinit {
        DDLogDebug("GroupInfoViewController/deinit ")
    }

    // MARK: Fetch Results Controller

    public var fetchRequest: NSFetchRequest<ChatGroupMember> {
        get {
            let fetchRequest = NSFetchRequest<ChatGroupMember>(entityName: "ChatGroupMember")
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \ChatGroupMember.typeValue, ascending: true)
            ]
            fetchRequest.predicate = NSPredicate(format: "groupId = %@", groupId)
            return fetchRequest
        }
    }

    private var trackPerRowFRCChanges = false

    private var reloadTableViewInDidChangeContent = false

    private func setupFetchedResultsController() {
        self.fetchedResultsController = self.newFetchedResultsController()
        do {
            try self.fetchedResultsController?.performFetch()
        } catch {
            fatalError("Failed to fetch group members \(error)")
        }
    }

    private func newFetchedResultsController() -> NSFetchedResultsController<ChatGroupMember> {
        // Setup fetched results controller the old way because it allows granular control over UI update operations.
        let fetchedResultsController = NSFetchedResultsController<ChatGroupMember>(fetchRequest: self.fetchRequest, managedObjectContext: MainAppContext.shared.chatData.viewContext,
                                                                            sectionNameKeyPath: nil, cacheName: nil)
        fetchedResultsController.delegate = self
        return fetchedResultsController
    }

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        reloadTableViewInDidChangeContent = false
        trackPerRowFRCChanges = self.view.window != nil && UIApplication.shared.applicationState == .active
        DDLogDebug("GroupInfoViewController/frc/will-change perRowChanges=[\(trackPerRowFRCChanges)]")
        if trackPerRowFRCChanges {
            self.tableView.beginUpdates()
        }
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .update:
            guard let indexPath = indexPath, let member = anObject as? ChatGroupMember else { return }
            DDLogDebug("GroupInfoViewController/frc/update [\(member)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                tableView.reloadRows(at: [ indexPath ], with: .automatic)
            } else {
                reloadTableViewInDidChangeContent = true
            }
        case .insert:
            guard let indexPath = newIndexPath, let member = anObject as? ChatGroupMember else { break }
            DDLogDebug("GroupInfoViewController/frc/insert [\(member)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                tableView.insertRows(at: [ indexPath ], with: .automatic)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .move:
            guard let fromIndexPath = indexPath, let toIndexPath = newIndexPath, let member = anObject as? ChatGroupMember else { break }
            DDLogDebug("GroupInfoViewController/frc/move [\(member)] from [\(fromIndexPath)] to [\(toIndexPath)]")
            if trackPerRowFRCChanges {
                tableView.moveRow(at: fromIndexPath, to: toIndexPath)
                DispatchQueue.main.async {
                    self.tableView.reloadRows(at: [ toIndexPath ], with: .automatic)
                }

            } else {
                reloadTableViewInDidChangeContent = true
            }
        case .delete:
            guard let indexPath = indexPath, let member = anObject as? ChatGroupMember else { break }
            DDLogDebug("GroupInfoViewController/frc/delete [\(member)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                tableView.deleteRows(at: [ indexPath ], with: .automatic)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        default:
            break
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DDLogDebug("GroupInfoViewController/frc/did-change perRowChanges=[\(trackPerRowFRCChanges)]  reload=[\(reloadTableViewInDidChangeContent)]")
        if trackPerRowFRCChanges {
            tableView.endUpdates()
        } else if reloadTableViewInDidChangeContent {
            tableView.reloadData()
        }
        checkIfMember()
    }

    // MARK: Actions

    @objc private func shareAction() {
        let controller = GroupInviteViewController(for: groupId)
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func editAction() {
        guard let chatGroup = chatGroup else { return }
        let controller = EditGroupViewController(chatGroup: chatGroup)
        controller.delegate = self
        present(UINavigationController(rootViewController: controller), animated: true)
    }

    @objc private func changeBackgroundAction() {
        guard let group = chatGroup else { return }
        let vc = GroupBackgroundViewController(chatGroup: group)
        vc.delegate = self
        present(UINavigationController(rootViewController: vc), animated: true)
    }

    @objc private func openEditAvatarOptions() {
        let actionSheet = UIAlertController(title: Localizations.chatGroupPhotoTitle, message: nil, preferredStyle: .actionSheet)
        actionSheet.view.tintColor = UIColor.systemBlue

        actionSheet.addAction(UIAlertAction(title: Localizations.chatGroupTakeOrChoosePhoto, style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.presentPhotoLibraryPicker()
        })

        actionSheet.addAction(UIAlertAction(title: "Delete Photo", style: .destructive) { _ in
            MainAppContext.shared.chatData.deleteGroupPhoto(groupID: self.groupId) { result in
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
                    DDLogError("GroupInfoViewController/createAction/error \(error)")
                }
            }

        })

        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        present(actionSheet, animated: true)
    }

    // MARK: UITableView Delegates

    override func numberOfSections(in tableView: UITableView) -> Int {
        return self.fetchedResultsController?.sections?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sections = self.fetchedResultsController?.sections else { return 0 }
        return sections[section].numberOfObjects
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier, for: indexPath) as! ContactTableViewCell
        if let chatGroupMember = fetchedResultsController?.object(at: indexPath) {
            cell.configure(with: chatGroupMember)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        func deselectRow() {
            tableView.deselectRow(at: indexPath, animated: true)
        }

//        guard isAdmin else {
//            deselectRow()
//            return
//        }
        guard let chatGroupMember = fetchedResultsController?.object(at: indexPath),
              chatGroupMember.userId != MainAppContext.shared.userData.userId else
        {
            deselectRow()
            return
        }
        
        let userName = MainAppContext.shared.contactStore.fullName(for: chatGroupMember.userId)
        let isUserAContact = MainAppContext.shared.contactStore.isContactInAddressBook(userId: chatGroupMember.userId)
        let selectedMembers = [chatGroupMember.userId]
        
        let actionSheet = UIAlertController(title: "\(userName)", message: nil, preferredStyle: .actionSheet)
        actionSheet.view.tintColor = UIColor.systemBlue
        
        actionSheet.addAction(UIAlertAction(title: Localizations.chatGroupInfoViewProfile, style: .default) { [weak self] _ in
            guard let self = self else { return }

            let userViewController = UserFeedViewController(userId: chatGroupMember.userId)
            self.navigationController?.pushViewController(userViewController, animated: true)
        })

        if isUserAContact {
            actionSheet.addAction(UIAlertAction(title: Localizations.chatGroupInfoMessageUser, style: .default) { [weak self] _ in
                guard let self = self else { return }

                self.navigationController?.pushViewController(ChatViewController(for: chatGroupMember.userId), animated: true)
            })
        }

        if isAdmin {
            if chatGroupMember.type == .admin {
                actionSheet.addAction(UIAlertAction(title: Localizations.chatGroupInfoDismissAsAdmin, style: .destructive) { [weak self] _ in
                    guard let self = self else { return }

                    MainAppContext.shared.service.modifyGroup(groupID: self.groupId, with: selectedMembers, groupAction: ChatGroupAction.modifyAdmins, action: ChatGroupMemberAction.demote) { result in }
                })
            } else {
                actionSheet.addAction(UIAlertAction(title: Localizations.chatGroupInfoMakeGroupAdmin, style: .default) { [weak self] _ in
                    guard let self = self else { return }

                    MainAppContext.shared.service.modifyGroup(groupID: self.groupId, with: selectedMembers, groupAction: ChatGroupAction.modifyAdmins, action: ChatGroupMemberAction.promote) { result in }
                })
            }
            actionSheet.addAction(UIAlertAction(title: Localizations.chatGroupInfoRemoveFromGroup, style: .destructive) { [weak self] _ in
                guard let self = self else { return }

                MainAppContext.shared.service.modifyGroup(groupID: self.groupId, with: selectedMembers, groupAction: ChatGroupAction.modifyMembers, action: ChatGroupMemberAction.remove) { [weak self] result in
                    guard let self = self else { return }
                    self.refreshGroupInfo()
                }

            })
        }

        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        present(actionSheet, animated: true) {
            deselectRow()
        }
    }

    // MARK: Helpers

    func checkIfMember() {
        let headerView = self.tableView.tableHeaderView as! GroupInfoHeaderView
        let footerView = self.tableView.tableFooterView as! GroupInfoFooterView
        navigationItem.rightBarButtonItem?.isEnabled = false
        navigationItem.rightBarButtonItem?.tintColor = UIColor.clear

        if let chatGroupMember = MainAppContext.shared.chatData.chatGroupMember(groupId: groupId, memberUserId: MainAppContext.shared.userData.userId) {
            if chatGroupMember.type == .admin {
                isAdmin = true
                headerView.setIsAdmin(true)
                footerView.setIsMember(true)

                if ServerProperties.isInternalUser && ServerProperties.isGroupInviteLinksEnabled {
                    navigationItem.rightBarButtonItem?.isEnabled = true
                    navigationItem.rightBarButtonItem?.tintColor = UIColor.primaryBlue
                }

            } else if chatGroupMember.type == .member {
                isAdmin = false
                headerView.setIsAdmin(false)
                footerView.setIsMember(true)
            }
        } else {
            isAdmin = false
            headerView.setIsAdmin(false)
            footerView.setIsMember(false)
        }
    }

    private func presentPhotoLibraryPicker() {
        let pickerController = MediaPickerViewController(filter: .image, multiselect: false, camera: true) { [weak self] controller, media, cancel in
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
                }

                edit.modalPresentationStyle = .fullScreen
                controller.present(edit, animated: true)
            }
        }

        self.present(UINavigationController(rootViewController: pickerController), animated: true)
    }

    private func changeAvatar(image: UIImage) {

        var me = String(MainAppContext.shared.userData.userId)
        var currentMembers: [UserID] = []
        if let objects = fetchedResultsController?.fetchedObjects {
            for groupMember in objects {
                currentMembers.append(groupMember.userId)
            }
        }
        print(currentMembers.contains(me))
        if (currentMembers.contains(me)) {
            guard let resizedImage = image.fastResized(to: CGSize(width: AvatarStore.avatarSize, height: AvatarStore.avatarSize)) else {
                DDLogError("GroupInfoViewController/resizeImage error resize failed")
                return
            }

            let data = resizedImage.jpegData(compressionQuality: CGFloat(UserData.compressionQuality))!

            MainAppContext.shared.chatData.changeGroupAvatar(groupID: self.groupId, data: data) { result in
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
                    DDLogError("GroupInfoViewController/createAction/error \(error)")
                }
            }
        }
    }

    private func refreshGroupInfo() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self = self else { return }
            self.chatGroup = MainAppContext.shared.chatData.chatGroup(groupId: self.groupId)
            if let tableHeaderView = self.tableView.tableHeaderView as? GroupInfoHeaderView {
                tableHeaderView.configure(chatGroup: self.chatGroup)
            }
        }
    }
}

extension GroupInfoViewController: GroupInfoHeaderViewDelegate {

    func groupInfoHeaderViewAvatar(_ groupInfoHeaderView: GroupInfoHeaderView) {
        openEditAvatarOptions()
    }

    func groupInfoHeaderViewEdit(_ groupInfoHeaderView: GroupInfoHeaderView) {
        editAction()
    }

    func groupInfoHeaderViewChangeBackground(_ groupInfoHeaderView: GroupInfoHeaderView) {
        changeBackgroundAction()
    }

    func groupInfoHeaderViewAddMember(_ groupInfoFooterView: GroupInfoHeaderView) {
        var currentMembers: [UserID] = []
        if let objects = fetchedResultsController?.fetchedObjects {
            for groupMember in objects {
                currentMembers.append(groupMember.userId)
            }
        }

        let vController = NewGroupMembersViewController(currentMembers: currentMembers)
        vController.delegate = self
        self.navigationController?.pushViewController(vController, animated: true)
    }
}

extension GroupInfoViewController: GroupInfoFooterViewDelegate {

    func groupInfoFooterViewAddMember(_ groupInfoFooterView: GroupInfoFooterView) {
        var currentMembers: [UserID] = []
        if let objects = fetchedResultsController?.fetchedObjects {
            for groupMember in objects {
                currentMembers.append(groupMember.userId)
            }
        }

        let vController = NewGroupMembersViewController(currentMembers: currentMembers)
        vController.delegate = self
        self.navigationController?.pushViewController(vController, animated: true)
    }
    
    func groupInfoFooterView(_ groupInfoFooterView: GroupInfoFooterView) {
        guard let group = chatGroup else { return }

        let actionSheet = UIAlertController(title: nil, message: "Leave \"\(group.name)\"?", preferredStyle: .actionSheet)
         actionSheet.addAction(UIAlertAction(title: "Yes", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            MainAppContext.shared.service.leaveGroup(groupID: self.groupId) { result in }
         })
         actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
         self.present(actionSheet, animated: true)
    }
}

extension GroupInfoViewController: NewGroupMembersViewControllerDelegate {

    func newGroupMembersViewController(_ viewController: NewGroupMembersViewController, selected selectedMembers: [UserID]) {
        MainAppContext.shared.service.modifyGroup(groupID: groupId, with: selectedMembers, groupAction: ChatGroupAction.modifyMembers, action: ChatGroupMemberAction.add) { [weak self] result in
            guard let self = self else { return }
            
            self.refreshGroupInfo()
        }
    }
    
    func newGroupMembersViewController(_ viewController: NewGroupMembersViewController, didCreateGroup: GroupID) {}
}


protocol GroupInfoHeaderViewDelegate: AnyObject {
    func groupInfoHeaderViewAvatar(_ groupInfoHeaderView: GroupInfoHeaderView)
    func groupInfoHeaderViewEdit(_ groupInfoHeaderView: GroupInfoHeaderView)
    func groupInfoHeaderViewChangeBackground(_ groupInfoHeaderView: GroupInfoHeaderView)
    func groupInfoHeaderViewAddMember(_ groupInfoHeaderView: GroupInfoHeaderView)
}

class GroupInfoHeaderView: UIView {

    weak var delegate: GroupInfoHeaderViewDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    public func configure(chatGroup: ChatGroup?) {
        guard let chatGroup = chatGroup else { return }
        groupNameTextView.text = chatGroup.name
        membersLabel.text = "\(Localizations.chatGroupMembersLabel) (\(String(chatGroup.members?.count ?? 0)))"

        avatarView.configure(groupId: chatGroup.groupId, squareSize: Constants.AvatarSize, using: MainAppContext.shared.avatarStore)

        backgroundSelectionImage.backgroundColor = ChatData.getThemeBackgroundColor(for: chatGroup.background)
        if chatGroup.background == 0 {
            backgroundSelectionLabel.text = Localizations.chatGroupInfoBgDefaultLabel
        } else {
            backgroundSelectionLabel.text = Localizations.chatGroupInfoBgColorLabel
        }

        if !ServerProperties.isGroupBackgroundEnabled {
            backgroundLabel.isHidden = true
            backgroundLabelRow.isHidden = true
        }
    }

    public func setIsAdmin(_ isAdmin: Bool) {
        addMembersLabel.isHidden = isAdmin ? false : true
    }

    private func setup() {
        addSubview(vStack)
        vStack.constrain(to: self)
    }

    private lazy var vStack: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [ avatarRow, groupNameLabelRow, groupNameTextView, backgroundLabelRow, backgroundRow, membersLabelRow, spacer])

        view.axis = .vertical
        view.spacing = 0
        view.setCustomSpacing(20, after: avatarRow)
        view.setCustomSpacing(25, after: groupNameTextView)
        view.setCustomSpacing(25, after: backgroundRow)

        view.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
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

    private lazy var avatarView: AvatarView = {
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
        label.text = Localizations.chatGroupNameLabel
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    private lazy var groupNameTextView: UITextView = {
        let view = UITextView()
        view.isScrollEnabled = false
        view.isEditable = false
        view.isSelectable = false

        view.clipsToBounds = true
        view.layer.cornerRadius = 10

        view.backgroundColor = .secondarySystemGroupedBackground
        view.textContainerInset = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 10)
        view.font = UIFont.preferredFont(forTextStyle: .body)

        view.translatesAutoresizingMaskIntoConstraints = false

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(editAction(_:)))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)

        return view
    }()
    
    private lazy var backgroundLabelRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [backgroundLabel])
        view.axis = .horizontal

        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 5, right: 0)
        view.isLayoutMarginsRelativeArrangement = true

        return view
    }()
    
    private lazy var backgroundLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 12)
        label.text = Localizations.chatGroupBackgroundLabel
        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    private lazy var backgroundRow: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let view = UIStackView(arrangedSubviews: [ backgroundSelectionLabel, spacer, backgroundSelectionImage ])

        view.axis = .horizontal
        view.spacing = 20

        let subView = UIView(frame: view.bounds)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        subView.backgroundColor = .secondarySystemGroupedBackground
        subView.layer.cornerRadius = 10
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        view.insertSubview(subView, at: 0)

        view.layoutMargins = UIEdgeInsets(top: 5, left: 15, bottom: 5, right: 10)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(changeBackgroundAction(_:)))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)

        return view
    }()

    private lazy var backgroundSelectionLabel: UITextView = {
        let view = UITextView()
        view.isScrollEnabled = false
        view.isEditable = false
        view.isSelectable = false

        view.backgroundColor = .clear
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.text = Localizations.chatGroupInfoBgDefaultLabel

        view.translatesAutoresizingMaskIntoConstraints = false

        return view
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

    private lazy var membersLabelRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ membersLabel, addMembersLabel ])

        view.axis = .horizontal
        view.spacing = 20

        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 5, right: 0)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()
    
    private lazy var membersLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1

        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel

        label.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        label.translatesAutoresizingMaskIntoConstraints = false

        return label
    }()

    private lazy var addMembersLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = .systemFont(ofSize: 14)
        label.textColor = .systemBlue
        label.textAlignment = .left
        label.text = Localizations.chatGroupInfoAddMembers

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(openAddGroupMemberView(_:)))
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(tapGesture)

        label.isHidden = true

        return label
    }()

    @objc func groupAvatarAction (_ sender: UITapGestureRecognizer) {
        delegate?.groupInfoHeaderViewAvatar(self)
    }

    @objc func editAction (_ sender: UITapGestureRecognizer) {
        delegate?.groupInfoHeaderViewEdit(self)
    }

    @objc func changeBackgroundAction (_ sender: UITapGestureRecognizer) {
        delegate?.groupInfoHeaderViewChangeBackground(self)
    }

    @objc func openAddGroupMemberView (_ sender: UITapGestureRecognizer) {
        self.delegate?.groupInfoHeaderViewAddMember(self)
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

        view.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    private lazy var fixedSpacerRow: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.feedBackground

        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 30).isActive = true

        return view
    }()

    private lazy var leaveGroupRow: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let view = UIStackView(arrangedSubviews: [ leaveGroupLabel, notAMemberLabel ])
        view.axis = .vertical
        view.translatesAutoresizingMaskIntoConstraints = false

        view.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        view.isLayoutMarginsRelativeArrangement = true

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
        label.font = UIFont.preferredFont(forTextStyle: .body)
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
        label.font = UIFont.preferredFont(forTextStyle: .body)
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

extension GroupInfoViewController: EditGroupViewControllerDelegate {
    func editGroupViewController(_ editGroupViewController: EditGroupViewController) {
        self.refreshGroupInfo()
    }
}

extension GroupInfoViewController: GroupBackgroundViewControllerDelegate {
    func groupBackgroundViewController(_ groupBackgroundViewController: GroupBackgroundViewController) {
        self.refreshGroupInfo()
    }
}

private extension ContactTableViewCell {

    func configure(with chatGroupMember: ChatGroupMember) {
        profilePictureSize = 40
        nameLabel.text = MainAppContext.shared.contactStore.fullName(for: chatGroupMember.userId)
        accessoryLabel.text = chatGroupMember.type == .admin ? Localizations.chatGroupInfoAdminLabel : ""
        contactImage.configure(with: chatGroupMember.userId, using: MainAppContext.shared.avatarStore)
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
        NSLocalizedString("chat.group.info.add.members", value: "Add members", comment: "Action label for adding members to a group")
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
}
