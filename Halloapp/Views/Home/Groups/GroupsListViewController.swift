//
//  GroupsListViewController.swift
//  HalloApp
//
//  Created by Tony Jiang on 1/12/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreData
import Intents
import SwiftUI
import UIKit

fileprivate struct Constants {
    static let AvatarSize: CGFloat = 56
    static let LastMsgFont = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize + 1) // 14
    static let LastMsgColor = UIColor.secondaryLabel
}

fileprivate enum ChatListViewSection {
    case main
}

class GroupsListViewController: UIViewController, NSFetchedResultsControllerDelegate {

    private static let cellReuseIdentifier = "ThreadListCell"
    private static let inviteFriendsReuseIdentifier = "GroupsListInviteFriendsCell"
    private let tableView = UITableView(frame: CGRect.zero, style: .grouped)
    
    private var fetchedResultsController: NSFetchedResultsController<ChatThread>?
    
    private var isVisible: Bool = false
    private var cancellableSet: Set<AnyCancellable> = []
    
    private var filteredChatsMembers: [ChatThread] = []
    private var filteredChatsTitles: [ChatThread] = []
    private var searchController: UISearchController!
    
    private var isSearchBarEmpty: Bool {
        return searchController.searchBar.text?.isEmpty ?? true
    }
    private var isFiltering: Bool {
        if searchController.isActive {
            navigationItem.rightBarButtonItem = nil
        } else {
            navigationItem.rightBarButtonItem = rightBarButtonItem
        }
        return searchController.isActive && !isSearchBarEmpty
    }
    private var groupIdToPresent: GroupID? = nil
        
    // MARK: Lifecycle
    
    init(title: String) {
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        DDLogInfo("GroupsListViewController/viewDidLoad")

        navigationItem.standardAppearance = .transparentAppearance
        navigationItem.standardAppearance?.backgroundColor = UIColor.feedBackground
        installLargeTitleUsingGothamFont()

        navigationItem.rightBarButtonItem = rightBarButtonItem
        
        definesPresentationContext = true
        
        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.definesPresentationContext = true
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.delegate = self

        searchController.searchBar.backgroundImage = UIImage()
        searchController.searchBar.tintColor = UIColor.primaryBlue
        searchController.searchBar.searchTextField.backgroundColor = .searchBarBg

        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.constrain(to: view)

        installEmptyView()
  
        tableView.register(GroupsListHeaderView.self, forHeaderFooterViewReuseIdentifier: "sectionHeader")
        tableView.register(ThreadListCell.self, forCellReuseIdentifier: GroupsListViewController.cellReuseIdentifier)
        tableView.delegate = self
        tableView.dataSource = self
        
        tableView.backgroundView = UIView() // fixes issue where bg color was off when pulled down from top
        tableView.backgroundColor = .primaryBg
        tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: -10, left: 0, bottom: 0, right: 0) // -10 to hide top padding on searchBar
                
        tableView.tableHeaderView = searchController.searchBar
        tableView.tableHeaderView?.layoutMargins = UIEdgeInsets(top: 0, left: 21, bottom: 0, right: 21) // requested to be 21
        
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60 // set a number close to default to prevent cells overlapping issue, can't be auto
        
        setupFetchedResultsController()
                
        // When the user was on this view
        cancellableSet.insert(
            MainAppContext.shared.didTapNotification.sink { [weak self] (metadata) in
                guard let self = self else { return }
                self.processNotification(metadata: metadata)
            }
        )
        cancellableSet.insert(
            MainAppContext.shared.chatData.didGetAGroupEvent.sink { [weak self] (groupId) in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    if self.groupIdToPresent == groupId {
                        DDLogDebug("GroupsListViewController/presentGroup \(groupId)")
                        self.openFeed(forGroupId: groupId)
                        self.groupIdToPresent = nil
                    }
                }
        })

        // When the user was not on this view, and HomeView sends user to here
        if let metadata = NotificationMetadata.fromUserDefaults() {
            processNotification(metadata: metadata)
        }

        cancellableSet.insert(
            MainAppContext.shared.groupFeedFromGroupTabPresentRequest.sink { [weak self] (groupID) in
                guard let self = self else { return }
                guard let groupID = groupID else { return }
                self.navigationController?.popToRootViewController(animated: false)
                let vc = GroupFeedViewController(groupId: groupID)
                vc.delegate = self
                self.navigationController?.pushViewController(vc, animated: false)
            }
        )
    }
    
    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("GroupsListViewController/viewWillAppear")
        super.viewWillAppear(animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        DDLogInfo("GroupsListViewController/viewWillDisappear")
        super.viewWillDisappear(animated)
        isVisible = false
    }

    private lazy var rightBarButtonItem: UIBarButtonItem = {
        let image = UIImage(named: "NavCreateGroup", in: nil, with: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))?.withTintColor(UIColor.primaryBlue, renderingMode: .alwaysOriginal)
        image?.accessibilityLabel = Localizations.chatCreateNewGroup
        let button = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(openNewGroupAction))
        return button
    }()

    // MARK: NUX

    private lazy var overlayContainer: OverlayContainer = {
        let overlayContainer = OverlayContainer()
        overlayContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayContainer)
        overlayContainer.constrain(to: view)
        return overlayContainer
    }()

    private lazy var emptyView: UIView = {
        let image = UIImage(named: "ChatEmpty")?.withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: image)
        imageView.tintColor = UIColor.label.withAlphaComponent(0.2)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.text = Localizations.nuxGroupsListEmpty
        label.textAlignment = .center
        label.textColor = .secondaryLabel

        let stackView = UIStackView(arrangedSubviews: [imageView, label])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 12

        return stackView
    }()

    private func installEmptyView() {
        view.addSubview(emptyView)

        emptyView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.6).isActive = true
        emptyView.constrain([.centerX, .centerY], to: view)
    }

    private func updateEmptyView() {
        let isEmpty = (fetchedResultsController?.sections?.first?.numberOfObjects ?? 0) == 0
        emptyView.alpha = isEmpty ? 1 : 0
    }

    // MARK: Invite friends

    @objc
    private func startInviteFriendsFlow() {
        guard ContactStore.contactsAccessAuthorized else {
            let inviteVC = InvitePermissionDeniedViewController()
            present(UINavigationController(rootViewController: inviteVC), animated: true)
            return
        }
        InviteManager.shared.requestInvitesIfNecessary()
        let inviteVC = InviteViewController(manager: InviteManager.shared, dismissAction: { [weak self] in self?.dismiss(animated: true, completion: nil) })
        let navController = UINavigationController(rootViewController: inviteVC)
        present(navController, animated: true)
    }
    
    // MARK: Fetched Results Controller
    
    public var fetchRequest: NSFetchRequest<ChatThread> {
        let fetchRequest = NSFetchRequest<ChatThread>(entityName: "ChatThread")
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: "lastFeedTimestamp", ascending: false),
            NSSortDescriptor(key: "lastMsgTimestamp", ascending: false),
            NSSortDescriptor(key: "title", ascending: true)
        ]
        fetchRequest.predicate = NSPredicate(format: "groupId != nil")
        return fetchRequest
    }

    private var trackPerRowFRCChanges = false

    private var reloadTableViewInDidChangeContent = false

    private func setupFetchedResultsController() {
        fetchedResultsController = createFetchedResultsController()
        do {
            try fetchedResultsController?.performFetch()
            updateEmptyView()
        } catch {
            fatalError("Failed to fetch thread items \(error)")
        }
    }

    private func createFetchedResultsController() -> NSFetchedResultsController<ChatThread> {
        // Setup fetched results controller the old way because it allows granular control over UI update operations.
        let fetchedResultsController = NSFetchedResultsController<ChatThread>(fetchRequest: fetchRequest,
                                                                              managedObjectContext: MainAppContext.shared.chatData.viewContext,
                                                                              sectionNameKeyPath: nil,
                                                                              cacheName: nil)
        fetchedResultsController.delegate = self
        return fetchedResultsController
    }

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        reloadTableViewInDidChangeContent = false
        trackPerRowFRCChanges = self.view.window != nil && UIApplication.shared.applicationState == .active
        DDLogDebug("GroupsListView/frc/will-change perRowChanges=[\(trackPerRowFRCChanges)]")
        
        if trackPerRowFRCChanges {
            tableView.beginUpdates()
        }

        updateEmptyView()
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            guard let indexPath = newIndexPath, let chatThread = anObject as? ChatThread else { break }
            DDLogDebug("GroupsListView/frc/insert [\(chatThread.type):\(chatThread.groupId ?? chatThread.lastMsgId ?? "")] at [\(indexPath)]")
            if trackPerRowFRCChanges && !isFiltering {
                tableView.insertRows(at: [ indexPath ], with: .automatic)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .delete:
            guard let indexPath = indexPath, let chatThread = anObject as? ChatThread else { break }
            DDLogDebug("GroupsListView/frc/delete [\(chatThread.type):\(chatThread.groupId ?? chatThread.lastMsgId ?? "")] at [\(indexPath)]")
      
            if trackPerRowFRCChanges && !isFiltering {
                tableView.deleteRows(at: [ indexPath ], with: .left)
            } else {
                reloadTableViewInDidChangeContent = true
            }
            
        case .move:
            guard let fromIndexPath = indexPath, let toIndexPath = newIndexPath, let chatThread = anObject as? ChatThread else { break }
            DDLogDebug("GroupsListView/frc/move [\(chatThread.type):\(chatThread.groupId ?? chatThread.lastMsgId ?? "")] from [\(fromIndexPath)] to [\(toIndexPath)]")
            if trackPerRowFRCChanges && !isFiltering {
                tableView.moveRow(at: fromIndexPath, to: toIndexPath)
            } else {
                reloadTableViewInDidChangeContent = true
            }
        case .update:
            guard let indexPath = indexPath, let chatThread = anObject as? ChatThread else { return }
            DDLogDebug("GroupsListView/frc/update [\(chatThread.type):\(chatThread.groupId ?? chatThread.lastMsgId ?? "")] at [\(indexPath)]")

            if trackPerRowFRCChanges && !isFiltering {
                tableView.reloadRows(at: [indexPath], with: .automatic)
            } else {
                reloadTableViewInDidChangeContent = true
            }
        default:
            break
        }

        updateEmptyView()
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DDLogDebug("GroupsListView/frc/did-change perRowChanges=[\(trackPerRowFRCChanges)]  reload=[\(reloadTableViewInDidChangeContent)]")
        if trackPerRowFRCChanges {
            tableView.endUpdates()
        }
        if reloadTableViewInDidChangeContent || isFiltering {
            tableView.reloadData()
        }

        updateEmptyView()
    }
    
    // MARK: Actions
    
    @objc private func openNewGroupAction() {
        openNewGroup()
    }

    // MARK: Helpers
    
    func isScrolledFromTop(by fromTop: CGFloat) -> Bool {
        return tableView.contentOffset.y < fromTop
    }

    // MARK: Tap Notification
    
    private func processNotification(metadata: NotificationMetadata) {
        guard metadata.isGroupNotification else {
            return
        }
        
        // If the user tapped on a notification, move to group feed
        DDLogInfo("GroupsListViewController/processNotification/open group feed [\(metadata.groupId ?? "")]")

        navigationController?.popToRootViewController(animated: false)
        
        switch metadata.contentType {
        case .groupFeedPost, .groupFeedComment:
            if let groupId = metadata.groupId, let _ = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
                let vc = GroupFeedViewController(groupId: groupId)
                vc.delegate = self
                self.navigationController?.pushViewController(vc, animated: false)
            }
            break
        case .groupAdd:
            if let groupId = metadata.groupId {
                if let _ = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
                    openFeed(forGroupId: groupId)
                } else {
                    // for offline groupAdd notifications, the app needs some time to get and create the new group when the user
                    // taps on the notification so we just wait for the group event here.
                    DispatchQueue.main.async{
                        self.groupIdToPresent = groupId
                    }
                }
            }
            metadata.removeFromUserDefaults()
            break
        case .groupChatMessage:
            metadata.removeFromUserDefaults()
            break
        default:
            break
        }
        
//        metadata.removeFromUserDefaults()
    }

    private func openFeed(forGroupId groupId: GroupID) {
        let vc = GroupFeedViewController(groupId: groupId)
        vc.delegate = self
        navigationController?.pushViewController(vc, animated: true)
    }

    private func openNewGroup() {
        guard ContactStore.contactsAccessAuthorized else {
            present(UINavigationController(rootViewController: NewGroupMembersPermissionDeniedController()), animated: true)
            return
        }
        let viewController = NewGroupMembersViewController(currentMembers: [])
        viewController.delegate = self
        present(UINavigationController(rootViewController: viewController), animated: true)
    }
}

extension GroupsListViewController: UIViewControllerScrollsToTop {
    func scrollToTop(animated: Bool) {
        let indexPath = IndexPath(row: 0, section: 0)
        guard indexPath.section < tableView.numberOfSections else { return }
        guard indexPath.row < tableView.numberOfRows(inSection: indexPath.section) else { return }
        tableView.scrollToRow(at: indexPath, at: .middle, animated: animated)
    }
}

extension GroupsListViewController: FeedCollectionViewControllerDelegate {
    func feedCollectionViewController(_ controller: FeedCollectionViewController, userActioned: Bool) {
        searchController.isActive = false
        DispatchQueue.main.async {
            self.scrollToTop(animated: false)
        }
    }
}

// MARK: Table Header Delegate
extension GroupsListViewController: GroupsListHeaderViewDelegate {
    func groupsListHeaderView(_ groupsListHeaderView: GroupsListHeaderView) {
        openNewGroup()
    }
}

// MARK: UITableView Delegates
extension GroupsListViewController: UITableViewDelegate, UITableViewDataSource {
    
    func chatThread(at indexPath: IndexPath) -> ChatThread? {
        
        if isFiltering {
            if (indexPath.section == 0 && filteredChatsTitles.count > 0) {
                return filteredChatsTitles[indexPath.row]
            } else {
                return filteredChatsMembers[indexPath.row]
            }
        }
        
        guard let fetchedObjects = fetchedResultsController?.fetchedObjects, indexPath.row < fetchedObjects.count else {
            return nil
        }
        return fetchedObjects[indexPath.row]
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: "sectionHeader") as! GroupsListHeaderView
        view.delegate = self
        return view
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return section == 1 ? CGFloat.leastNormalMagnitude : 25
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        
        if isFiltering {
            if (filteredChatsTitles.count > 0 && filteredChatsMembers.count > 0) {
                return 2
            } else {
                return 1
            }
        }
        
        return fetchedResultsController?.sections?.count ?? 0
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        if isFiltering {
            if (section == 0 && filteredChatsTitles.count > 0) {
                return filteredChatsTitles.count
            } else {
                return filteredChatsMembers.count
            }
        }
        
        guard let sections = fetchedResultsController?.sections else { return 0 }
        return sections[section].numberOfObjects + 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let chatThread = chatThread(at: indexPath) else {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.isHidden = true
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: GroupsListViewController.cellReuseIdentifier, for: indexPath) as! ThreadListCell

        cell.configureAvatarSize(Constants.AvatarSize)
        cell.configureForGroupsList(with: chatThread, squareSize: Constants.AvatarSize)
  
        if isFiltering {
            let strippedString = searchController.searchBar.text!.trimmingCharacters(in: CharacterSet.whitespaces)
            let searchItems = strippedString.components(separatedBy: " ")
            cell.highlightTitle(searchItems)
        }
        
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let chatThread = chatThread(at: indexPath) else {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
        guard let groupId = chatThread.groupId else { return }

        openFeed(forGroupId: groupId)

        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let chatThread = self.chatThread(at: indexPath) else { return UISwipeActionsConfiguration(actions: []) }
        guard let groupId = chatThread.groupId else { return UISwipeActionsConfiguration(actions: []) }
        
        let moreInfoAction = UIContextualAction(style: .normal, title: "") { [weak self] (_, _, completionHandler) in
            guard let self = self else { return }
            let vc = GroupInfoViewController(for: groupId)
            self.navigationController?.pushViewController(vc, animated: true)
            completionHandler(true)
        }
        moreInfoAction.backgroundColor = .primaryBlue
        moreInfoAction.image = UIImage(systemName: "ellipsis")

        let removeAction = UIContextualAction(style: .destructive, title: Localizations.buttonRemove) { [weak self] (_, _, completionHandler) in
            guard let self = self else { return }
            let actionSheet = UIAlertController(title: chatThread.title, message: Localizations.groupsListRemoveMessage, preferredStyle: .actionSheet)
            actionSheet.addAction(UIAlertAction(title: Localizations.buttonRemove, style: .destructive) { [weak self] action in
                guard let self = self else { return }
                MainAppContext.shared.chatData.deleteChatGroup(groupId: groupId)
                if self.isFiltering {
                    if (indexPath.section == 0 && self.filteredChatsTitles.count > 0) {
                        self.filteredChatsTitles.remove(at: indexPath.row)
                    } else {
                        self.filteredChatsMembers.remove(at: indexPath.row)
                    }
                }
            })
            actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
            self.present(actionSheet, animated: true)
            completionHandler(true)
        }

        if MainAppContext.shared.chatData.chatGroupMember(groupId: groupId, memberUserId: MainAppContext.shared.userData.userId) != nil {
            return UISwipeActionsConfiguration(actions: [moreInfoAction])
        } else {
            return UISwipeActionsConfiguration(actions: [removeAction])
        }
    }

    // resign keyboard so the entire tableview can be seen
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        searchController.searchBar.resignFirstResponder()
    }

}

// MARK: UISearchController SearchBar Delegates
extension GroupsListViewController: UISearchBarDelegate {
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        DispatchQueue.main.async {
            self.scrollToTop(animated: false)
        }
    }
}

// MARK: UISearchController Updating Delegates
extension GroupsListViewController: UISearchResultsUpdating {
    
    func updateSearchResults(for searchController: UISearchController) {
        guard let allChats = fetchedResultsController?.fetchedObjects else { return }
        guard let searchBarText = searchController.searchBar.text else { return }
        let strippedString = searchBarText.trimmingCharacters(in: CharacterSet.whitespaces)
        
        let searchItems = strippedString.components(separatedBy: " ")
        
        filteredChatsTitles = allChats.filter {
            var titleText: String? = nil
            if $0.type == .group {
                titleText = $0.title
            } else {
                titleText = MainAppContext.shared.contactStore.fullName(for: $0.chatWithUserId ?? "")
            }

            guard let title = titleText else { return false }
        
            for item in searchItems {
                if title.lowercased().contains(item.lowercased()) {
                    return true
                }
            }
            return false
        }
        
        filteredChatsMembers = allChats.filter {
            var flag = false
            var groupIdStr: GroupID? = nil
            if $0.type == .group {
                groupIdStr = $0.groupId
            } else {
                groupIdStr = MainAppContext.shared.contactStore.fullName(for: $0.chatWithUserId ?? "")
            }

            guard let Id = groupIdStr else { return false }
            let group = MainAppContext.shared.chatData.chatGroup(groupId: Id)
            guard let members = group?.members else {return false}

            for member in members {
                let name = MainAppContext.shared.contactStore.fullName(for: member.userId)
                for item in searchItems {
                    if name.lowercased().contains(item.lowercased()) {
                        flag = true
                    }
                }
            }
            
            if (filteredChatsTitles.contains($0)) {
                flag = false
            }
            return flag
        }
        
        tableView.reloadData()
    }
}

extension GroupsListViewController: NewGroupMembersViewControllerDelegate {
    func newGroupMembersViewController(_ viewController: NewGroupMembersViewController, selected: [UserID]) {}
    
    func newGroupMembersViewController(_ viewController: NewGroupMembersViewController, didCreateGroup: GroupID) {
        let vc = GroupFeedViewController(groupId: didCreateGroup)
        vc.delegate = self
        navigationController?.pushViewController(vc, animated: true)
    }
}

protocol GroupsListHeaderViewDelegate: AnyObject {
    func groupsListHeaderView(_ groupsListHeaderView: GroupsListHeaderView)
}

class GroupsListHeaderView: UITableViewHeaderFooterView {
    weak var delegate: GroupsListHeaderViewDelegate?
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    private func setup() {
        preservesSuperviewLayoutMargins = true

        vStack.addArrangedSubview(createGroupLabel)
        addSubview(vStack)

        vStack.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 20)
        vStack.isLayoutMarginsRelativeArrangement = true
        
        vStack.topAnchor.constraint(equalTo: topAnchor).isActive = true
        vStack.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true

        let vStackBottomConstraint = vStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        vStackBottomConstraint.priority = UILayoutPriority(rawValue: 999)
        vStackBottomConstraint.isActive = true
    }
    
    private lazy var createGroupLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 17)
        label.textColor = .systemBlue
        label.textAlignment = .right
        label.text = Localizations.chatCreateNewGroup
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.openNewGroupView(_:)))
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(tapGesture)

        return label
    }()

    private let vStack: UIStackView = {
        let view = UIStackView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .vertical
        return view
    }()

    @objc func openNewGroupView (_ sender: UITapGestureRecognizer) {
        self.delegate?.groupsListHeaderView(self)
    }
}

private extension Localizations {

    static var groupsListRemoveMessage: String {
        NSLocalizedString("groups.list.remove.message", value: "Are you sure you want to remove this group and its content from your device?", comment: "Text shown when user is about to remove the group")
    }
    
}
