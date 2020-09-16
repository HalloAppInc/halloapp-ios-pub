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
import SwiftUI

class GroupInfoViewController: UITableViewController, NSFetchedResultsControllerDelegate {

    private var groupId: GroupID
    private var chatGroup: ChatGroup?
    private var isAdmin: Bool = false
    
    private var fetchedResultsController: NSFetchedResultsController<ChatGroupMember>?

    let cellReuseIdentifier = "GroupMembersViewCell"
    
    init(for groupId: GroupID) {
        DDLogDebug("GroupInfoViewController/init/\(groupId)")
        self.groupId = groupId
        self.chatGroup = MainAppContext.shared.chatData.chatGroup(groupId: groupId)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        DDLogInfo("GroupInfoViewController/viewDidLoad")

        self.navigationItem.title = "Group Info"

        self.navigationItem.standardAppearance = .transparentAppearance
        self.navigationItem.standardAppearance?.backgroundColor = UIColor.systemGray6

        self.tableView.separatorStyle = .none
        self.tableView.backgroundColor = UIColor.systemGray6
        self.tableView.register(GroupMemberViewCell.self, forCellReuseIdentifier: cellReuseIdentifier)
        
        let groupInfoHeaderView = GroupInfoHeaderView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.size.width, height: 35))
        //        headerView.configure(withPost: feedPost)
        //        headerView.textLabel.delegate = self
        //        headerView.profilePictureButton.addTarget(self, action: #selector(showUserFeedForPostAuthor), for: .touchUpInside)
        groupInfoHeaderView.delegate = self
        groupInfoHeaderView.isHidden = true
        tableView.tableHeaderView = groupInfoHeaderView
        
//        if let chatGroupMember = MainAppContext.shared.chatData.chatGroupMember(groupId: groupId, memberUserId: MainAppContext.shared.userData.userId) {
//            if chatGroupMember.type == .admin {
//                isAdmin = true
//                groupInfoHeaderView.isHidden = false
//            }
//        }
        
        let groupInfoFooterView = GroupInfoFooterView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.size.width, height: 35))
        groupInfoFooterView.delegate = self
        tableView.tableFooterView = groupInfoFooterView
        
        checkIfMember()
        
        self.setupFetchedResultsController()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("GroupInfoViewController/viewWillAppear")
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
            print("member: \(member.typeValue)")
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
    
    
    // MARK: UITableView Delegates

    override func numberOfSections(in tableView: UITableView) -> Int {
        return self.fetchedResultsController?.sections?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sections = self.fetchedResultsController?.sections else { return 0 }
        return sections[section].numberOfObjects
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier, for: indexPath) as! GroupMemberViewCell
        if let chatGroupMember = fetchedResultsController?.object(at: indexPath) {
            cell.configure(with: chatGroupMember)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard isAdmin else { return }
        guard let chatGroupMember = fetchedResultsController?.object(at: indexPath) else { return }
        guard chatGroupMember.userId != MainAppContext.shared.userData.userId else { return }
        
        let userName = MainAppContext.shared.contactStore.fullName(for: chatGroupMember.userId)
        let selectedMembers = [chatGroupMember.userId]
        
        let actionSheet = UIAlertController(title: "\(userName)", message: nil, preferredStyle: .actionSheet)

        if chatGroupMember.type == .admin {
            actionSheet.addAction(UIAlertAction(title: "Demote", style: .destructive) { [weak self] _ in
                guard let self = self else { return }
                
                MainAppContext.shared.service.modifyGroup(groupID: self.groupId, with: selectedMembers, groupAction: ChatGroupAction.modifyAdmins, action: ChatGroupMemberAction.demote) { result in
                    //            guard let self = self else { return }
                }
            })
        } else {
            actionSheet.addAction(UIAlertAction(title: "Promote to admin", style: .default) { [weak self] _ in
                guard let self = self else { return }
                
                MainAppContext.shared.service.modifyGroup(groupID: self.groupId, with: selectedMembers, groupAction: ChatGroupAction.modifyAdmins, action: ChatGroupMemberAction.promote) { result in
                    //            guard let self = self else { return }
                }
            })
        }
        actionSheet.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            
            MainAppContext.shared.service.modifyGroup(groupID: self.groupId, with: selectedMembers, groupAction: ChatGroupAction.modifyMembers, action: ChatGroupMemberAction.remove) { result in
                //            guard let self = self else { return }
            }
            
        })
        
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        self.present(actionSheet, animated: true)
    }
    
    func checkIfMember() {

        let headerView = self.tableView.tableHeaderView as! GroupInfoHeaderView
        let footerView = self.tableView.tableFooterView as! GroupInfoFooterView
                
        if let chatGroupMember = MainAppContext.shared.chatData.chatGroupMember(groupId: groupId, memberUserId: MainAppContext.shared.userData.userId) {
            if chatGroupMember.type == .admin {
                isAdmin = true
                headerView.isHidden = false
                footerView.setIsMember(true)
            } else if chatGroupMember.type == .member {
                isAdmin = false
                headerView.isHidden = true
                footerView.setIsMember(true)
            }
        } else {
            isAdmin = false
            headerView.isHidden = true
            footerView.setIsMember(false)
        }
        
    }
    
}


extension GroupInfoViewController: GroupInfoHeaderViewDelegate {
    func groupInfoHeaderView(_ groupInfoHeaderView: GroupInfoHeaderView) {
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
    func groupInfoFooterView(_ groupInfoFooterView: GroupInfoFooterView) {
        guard let group = chatGroup else { return }

        let actionSheet = UIAlertController(title: nil, message: "Leave \"\(group.name)\"?", preferredStyle: .actionSheet)
         actionSheet.addAction(UIAlertAction(title: "Yes", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            MainAppContext.shared.service.leaveGroup(groupID: self.groupId) { result in }
         })
         actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
         self.present(actionSheet, animated: true)
    }
}

extension GroupInfoViewController: NewGroupMembersViewControllerDelegate {
    func newGroupMembersViewController(_ viewController: NewGroupMembersViewController, selected selectedMembers: [UserID]) {
        MainAppContext.shared.service.modifyGroup(groupID: groupId, with: selectedMembers, groupAction: ChatGroupAction.modifyMembers, action: ChatGroupMemberAction.add) { result in
//            guard let self = self else { return }
        }
    }
}

protocol GroupInfoHeaderViewDelegate: AnyObject {
    func groupInfoHeaderView(_ groupInfoHeaderView: GroupInfoHeaderView)
}

class GroupInfoHeaderView: UIView {

    weak var delegate: GroupInfoHeaderViewDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    private func setup() {
        self.preservesSuperviewLayoutMargins = true

        vStack.addArrangedSubview(textLabel)
        self.addSubview(vStack)

        vStack.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor).isActive = true
        vStack.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor).isActive = true
        vStack.topAnchor.constraint(equalTo: self.layoutMarginsGuide.topAnchor).isActive = true
        vStack.bottomAnchor.constraint(equalTo: self.layoutMarginsGuide.bottomAnchor).isActive = true
    }
    
    private let vStack: UIStackView = {
        let vStack = UIStackView()
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis = .vertical
        return vStack
    }()
    
    private lazy var textLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.textColor = .systemBlue
        label.textAlignment = .right
        label.text = "Add Members"
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.openAddGroupMemberView(_:)))
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(tapGesture)

        return label
    }()


    @objc func openAddGroupMemberView (_ sender: UITapGestureRecognizer) {
        self.delegate?.groupInfoHeaderView(self)
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
        textLabel.isHidden = isMember ? false : true
        notAMemberLabel.isHidden = isMember ? true : false
    }
    
    private func setup() {
        self.preservesSuperviewLayoutMargins = true

        self.addSubview(vStack)

        vStack.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor).isActive = true
        vStack.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor).isActive = true
        vStack.topAnchor.constraint(equalTo: self.layoutMarginsGuide.topAnchor).isActive = true
        vStack.bottomAnchor.constraint(equalTo: self.layoutMarginsGuide.bottomAnchor).isActive = true
    }
    
    private lazy var vStack: UIStackView = {
        let vStack = UIStackView(arrangedSubviews: [ self.textLabel, self.notAMemberLabel ])
        vStack.axis = .vertical
        vStack.translatesAutoresizingMaskIntoConstraints = false
        return vStack
    }()
    
    private lazy var textLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.textColor = .systemBlue
        label.textAlignment = .right
        label.text = "Leave Group"
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.openAddGroupMemberView(_:)))
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(tapGesture)

        return label
    }()

    private lazy var notAMemberLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.textAlignment = .right
        label.text = "You are not a member of this group"
        label.isHidden = true
        
        return label
    }()

    @objc func openAddGroupMemberView (_ sender: UITapGestureRecognizer) {
        self.delegate?.groupInfoFooterView(self)
    }
}

fileprivate class GroupMemberViewCell: UITableViewCell {
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func prepareForReuse() {
        super.prepareForReuse()
        isHidden = false
        nameLabel.text = ""
        roleLabel.text = ""
        contactImageView.prepareForReuse()
    }
    
    public func configure(with chatGroupMember: ChatGroupMember) {
        nameLabel.text = MainAppContext.shared.contactStore.fullName(for: chatGroupMember.userId)
        roleLabel.text = chatGroupMember.type == .admin ? "Admin" : ""
        contactImageView.configure(with: chatGroupMember.userId, using: MainAppContext.shared.avatarStore)
    }

    private func setup() {
        backgroundColor = .clear
        
        let vStack = UIStackView(arrangedSubviews: [nameLabel, lastMessageLabel])
        vStack.axis = .vertical
        vStack.spacing = 2
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let imageSize: CGFloat = 40.0
        contactImageView.widthAnchor.constraint(equalToConstant: imageSize).isActive = true
        contactImageView.heightAnchor.constraint(equalTo: contactImageView.widthAnchor).isActive = true

        let hStack = UIStackView(arrangedSubviews: [ contactImageView, vStack, roleLabel])
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.axis = .horizontal
        hStack.spacing = 10

        contentView.addSubview(hStack)
        
        // Priority is lower than "required" because cell's height might be 0 (duplicate contacts).
        contentView.addConstraint({
            let constraint = hStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor)
            constraint.priority = .defaultHigh
            return constraint
            }())
        hStack.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        hStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor).isActive = true
        hStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor).isActive = true
    }
    
    private lazy var contactImageView: AvatarView = {
        return AvatarView()
    }()

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var lastMessageLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var roleLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return label
    }()
    
        
   
}
