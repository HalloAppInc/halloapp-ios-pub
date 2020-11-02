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
    static let HeaderHeight: CGFloat = 255
    static let FooterHeight: CGFloat = 250
}

class GroupInfoViewController: UITableViewController, NSFetchedResultsControllerDelegate {

    private var groupId: GroupID
    private var chatGroup: ChatGroup?
    private var isAdmin: Bool = false
    
    private var fetchedResultsController: NSFetchedResultsController<ChatGroupMember>?

    let cellReuseIdentifier = "GroupMembersViewCell"
    
    init(for groupId: GroupID) {
        DDLogDebug("GroupInfoViewController/init/\(groupId)")
        self.groupId = groupId
//        self.chatGroup = MainAppContext.shared.chatData.chatGroup(groupId: groupId)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        DDLogInfo("GroupInfoViewController/viewDidLoad")

        navigationItem.title = "Group Info"
        navigationItem.standardAppearance = .transparentAppearance
        navigationItem.standardAppearance?.backgroundColor = UIColor.feedBackground

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

    @objc private func editAction() {
        guard let chatGroup = chatGroup else { return }
        let controller = EditGroupViewController(chatGroup: chatGroup)
        navigationController?.pushViewController(controller, animated: true)
    }
    
    @objc private func openEditAvatarOptions() {
        let actionSheet = UIAlertController(title: "Group Photo", message: nil, preferredStyle: .actionSheet)
        actionSheet.view.tintColor = UIColor.systemBlue
        
        actionSheet.addAction(UIAlertAction(title: "Take or Choose Photo", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.presentPhotoLibraryPicker()
        })
        
//        actionSheet.addAction(UIAlertAction(title: "Delete Photo", style: .destructive) { _ in
//
//        })
        
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

        guard isAdmin else {
            deselectRow()
            return
        }
        guard let chatGroupMember = fetchedResultsController?.object(at: indexPath),
              chatGroupMember.userId != MainAppContext.shared.userData.userId else
        {
            deselectRow()
            return
        }
        
        let userName = MainAppContext.shared.contactStore.fullName(for: chatGroupMember.userId)
        let selectedMembers = [chatGroupMember.userId]
        
        let actionSheet = UIAlertController(title: "\(userName)", message: nil, preferredStyle: .actionSheet)
        actionSheet.view.tintColor = UIColor.systemBlue
        
        if chatGroupMember.type == .admin {
            actionSheet.addAction(UIAlertAction(title: "Demote", style: .destructive) { [weak self] _ in
                guard let self = self else { return }
                
                MainAppContext.shared.service.modifyGroup(groupID: self.groupId, with: selectedMembers, groupAction: ChatGroupAction.modifyAdmins, action: ChatGroupMemberAction.demote) { result in
                    //            guard let self = self else { return }
                }
            })
        } else {
            actionSheet.addAction(UIAlertAction(title: "Make Group Admin", style: .default) { [weak self] _ in
                guard let self = self else { return }
                
                MainAppContext.shared.service.modifyGroup(groupID: self.groupId, with: selectedMembers, groupAction: ChatGroupAction.modifyAdmins, action: ChatGroupMemberAction.promote) { result in
                    //            guard let self = self else { return }
                }
            })
        }
        actionSheet.addAction(UIAlertAction(title: "Remove From Group", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            
            MainAppContext.shared.service.modifyGroup(groupID: self.groupId, with: selectedMembers, groupAction: ChatGroupAction.modifyMembers, action: ChatGroupMemberAction.remove) { [weak self] result in
                guard let self = self else { return }
                self.refreshGroupInfo()
            }
            
        })
        
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        present(actionSheet, animated: true) {
            deselectRow()
        }
    }
    
    // MARK: Helpers
    
    func checkIfMember() {
        let footerView = self.tableView.tableFooterView as! GroupInfoFooterView
                
        if let chatGroupMember = MainAppContext.shared.chatData.chatGroupMember(groupId: groupId, memberUserId: MainAppContext.shared.userData.userId) {
            if chatGroupMember.type == .admin {
                isAdmin = true
                footerView.setIsAdmin(true)
                footerView.setIsMember(true)
            } else if chatGroupMember.type == .member {
                isAdmin = false
                footerView.setIsAdmin(false)
                footerView.setIsMember(true)
            }
        } else {
            isAdmin = false
            footerView.setIsAdmin(false)
            footerView.setIsMember(false)
        }
    }
    
    private func presentPhotoLibraryPicker() {
        let pickerController = MediaPickerViewController(filter: .image, multiselect: false, camera: true) { [weak self] controller, media, cancel in
            guard let self = self else { return }

            if cancel || media.count == 0 {
                controller.dismiss(animated: true)
            } else {
                let edit = MediaEditViewController(cropToCircle: true, mediaToEdit: media, selected: 0) { controller, media, index, cancel in
                    controller.dismiss(animated: true)

                    if !cancel && media.count > 0 {
                        
                        guard let image = media[0].image else { return }
                        
                        guard let resizedImage = image.fastResized(to: CGSize(width: AvatarStore.avatarSize, height: AvatarStore.avatarSize)) else {
                            DDLogError("EditGroupViewController/resizeImage error resize failed")
                            return
                        }

                        let data = resizedImage.jpegData(compressionQuality: CGFloat(UserData.compressionQuality))!
                        
                        MainAppContext.shared.chatData.changeGroupAvatar(groupID: self.groupId, data: data) { result in
            
                            switch result {
                            case .success:
                                DispatchQueue.main.async() {
//                                    self.avatarView.configure(groupId: self.groupId, using: MainAppContext.shared.avatarStore)
                                    controller.dismiss(animated: true)
                                }
                            case .failure(let error):
                                DDLogError("GroupInfoViewController/createAction/error \(error)")
                            }
                        }
                        
                        self.dismiss(animated: true)
                    }
                }
                
                edit.modalPresentationStyle = .fullScreen
                controller.present(edit, animated: true)
            }
        }
        
        self.present(UINavigationController(rootViewController: pickerController), animated: true)
    }

    private func refreshGroupInfo() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
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

    public func configure(chatGroup: ChatGroup?) {
        guard let chatGroup = chatGroup else { return }
        groupNameTextView.text = chatGroup.name
        membersLabel.text = "MEMBERS (\(String(chatGroup.members?.count ?? 0)))"
        
        avatarView.configure(groupId: chatGroup.groupId, using: MainAppContext.shared.avatarStore)
    }
    
    private func setup() {
        addSubview(vStack)
        vStack.constrain(to: self)
    }
    
    private lazy var vStack: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        
        let view = UIStackView(arrangedSubviews: [ avatarRow, groupNameLabelRow, groupNameTextView, spacer, membersLabelRow ])

        view.axis = .vertical
        view.spacing = 0
        view.setCustomSpacing(20, after: avatarRow)
        
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
        let icon = UIImageView()
        let image = UIImage(named: "ProfileHeaderCamera")
        icon.image = image?.imageResized(to: CGSize(width: 20, height: 20)).withRenderingMode(.alwaysTemplate)
        
        icon.contentMode = .center
        icon.tintColor = UIColor.secondarySystemGroupedBackground
        icon.backgroundColor = UIColor.systemBlue
        icon.layer.masksToBounds = false
        icon.layer.cornerRadius = Constants.PhotoIconSize/2
        icon.clipsToBounds = true
        icon.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(groupAvatarAction(_:)))
        icon.isUserInteractionEnabled = true
        icon.addGestureRecognizer(tapGesture)
        
        return icon
    }()

    
    private lazy var groupNameLabelRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [groupNameLabel])
        view.axis = .horizontal
        
        view.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 3, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        
        return view
    }()
    
    private lazy var groupNameLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 11)
        label.text = "GROUP NAME"
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
    private lazy var groupNameTextView: UITextView = {
        let view = UITextView()
        view.isScrollEnabled = false
        view.isEditable = false
        view.isSelectable = false
        
        view.backgroundColor = .secondarySystemGroupedBackground
        
        view.textContainerInset = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 10)
        
        view.font = UIFont.preferredFont(forTextStyle: .body)
   
        view.translatesAutoresizingMaskIntoConstraints = false
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(editAction(_:)))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)
        
        return view
    }()
    
    private lazy var membersLabelRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ membersLabel ])
        
        view.axis = .horizontal
        view.spacing = 20

        view.layoutMargins = UIEdgeInsets(top: 10, left: 20, bottom: 3, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private lazy var membersLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabel
        
        label.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
      
        label.translatesAutoresizingMaskIntoConstraints = false
        
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
    func groupInfoFooterViewAddMember(_ groupInfoFooterView: GroupInfoFooterView)
    func groupInfoFooterView(_ groupInfoFooterView: GroupInfoFooterView)
}

class GroupInfoFooterView: UIView {

    weak var delegate: GroupInfoFooterViewDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    public func setIsAdmin(_ isAdmin: Bool) {
        addMembersRow.isHidden = isAdmin ? false : true
    }
    
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
        
        let view = UIStackView(arrangedSubviews: [ addMembersRow, fixedSpacerRow, leaveGroupRow, spacer ])
        view.axis = .vertical
//        view.spacing = 0
        
        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()
    
    
    private lazy var addMembersRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ addMembersLabel ])

        view.axis = .horizontal
        view.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        let subView = UIView(frame: view.bounds)
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        subView.backgroundColor = .secondarySystemGroupedBackground
        view.insertSubview(subView, at: 0)
        
        let topBorder = UIView(frame: CGRect(x: 20, y: 0, width: view.bounds.size.width, height: 1))
        topBorder.backgroundColor = UIColor.feedBackground
        topBorder.autoresizingMask = [.flexibleWidth]
        view.insertSubview(topBorder, at: 1)
        
        view.isHidden = true
        
        return view
    }()
    
    private lazy var addMembersLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = .gothamFont(forTextStyle: .headline, weight: .regular)
        label.textColor = .systemBlue
        label.textAlignment = .left
        label.text = "Add members"
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(openAddGroupMemberView(_:)))
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(tapGesture)

        return label
    }()
    
    private lazy var fixedSpacerRow: UIView = {

        let view = UIView()
        view.backgroundColor = UIColor.feedBackground
        
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 50).isActive = true
        
        
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
        view.insertSubview(subView, at: 0)
        
        return view
    }()
    
    private lazy var leaveGroupLabel: UILabel = {
        let label = UILabel()
        label.font = .gothamFont(forTextStyle: .body, weight: .regular)
        label.textColor = .systemRed
        label.textAlignment = .left
        label.text = "Leave group"
        
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
        label.text = "You are not a member of this group"
        label.isHidden = true
        
        return label
    }()

    
    @objc func openAddGroupMemberView (_ sender: UITapGestureRecognizer) {
        self.delegate?.groupInfoFooterViewAddMember(self)
    }
    
    @objc func leaveGroupAction (_ sender: UITapGestureRecognizer) {
        self.delegate?.groupInfoFooterView(self)
    }

}

private extension ContactTableViewCell {

    func configure(with chatGroupMember: ChatGroupMember) {
        profilePictureSize = 40
        nameLabel.text = MainAppContext.shared.contactStore.fullName(for: chatGroupMember.userId)
        accessoryLabel.text = chatGroupMember.type == .admin ? "Admin" : ""
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
