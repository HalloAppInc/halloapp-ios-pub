//
//  GroupsInCommonViewController.swift
//  HalloApp
//
//  Created by Han  on 2021/5/31.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import CoreData
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

class GroupsInCommonViewController: UIViewController, NSFetchedResultsControllerDelegate {

    private static let cellReuseIdentifier = "ThreadListCell"
    private static let inviteFriendsReuseIdentifier = "GroupsListInviteFriendsCell"
    private let tableView = UITableView(frame: CGRect.zero, style: .grouped)
    
    private var fetchedResultsController: NSFetchedResultsController<ChatThread>?
    
    private var isVisible: Bool = false
    private var cancellableSet: Set<AnyCancellable> = []
    
    private var filteredChats: [ChatThread] = []
    private var searchController: UISearchController!
    
    private var commonChats: [ChatThread] = []
    
    private var isSearchBarEmpty: Bool {
        return searchController.searchBar.text?.isEmpty ?? true
    }
    private var isFiltering: Bool {
        return searchController.isActive && !isSearchBarEmpty
    }
    private var groupIdToPresent: GroupID? = nil
    
    private var fromID : String?
    
    
    func updateCommonGroups() {
        guard let allChats = fetchedResultsController?.fetchedObjects else { return }
        
        commonChats = allChats.filter {
            var groupIdStr: GroupID? = nil
            if $0.type == .group {
                groupIdStr = $0.groupId
            } else {
                groupIdStr = MainAppContext.shared.contactStore.fullName(for: $0.chatWithUserId ?? "")
            }
            guard let Id = groupIdStr else { return false }
            let group = MainAppContext.shared.chatData.chatGroup(groupId: Id)
            let members = group!.members
            for i in members!{
                if (i.userId == self.fromID) {
                    return true
                }
            }
            
            return false
        }
    }
        
    // MARK: Lifecycle
    
    init(title: String) {
        super.init(nibName: nil, bundle: nil)
        var selfname: String
        selfname = MainAppContext.shared.contactStore.fullName(for: title)
        self.title = "With " + selfname
        self.fromID = title

    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        DDLogInfo("GroupsInCommonViewController/viewDidLoad")

        navigationItem.standardAppearance = .transparentAppearance
        navigationItem.standardAppearance?.backgroundColor = UIColor.feedBackground
        installLargeTitleUsingGothamFont()

        //navigationItem.rightBarButtonItem = rightBarButtonItem
        
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
  
        tableView.register(GroupsInCommonHeaderView.self, forHeaderFooterViewReuseIdentifier: "sectionHeader2")
        tableView.register(ThreadListCell.self, forCellReuseIdentifier: GroupsInCommonViewController.cellReuseIdentifier)
        tableView.delegate = self
        tableView.dataSource = self
        
        tableView.backgroundView = UIView() // fixes issue where bg color was off when pulled down from top
        tableView.backgroundColor = .primaryBg
        tableView.separatorStyle = .none
        tableView.contentInset = UIEdgeInsets(top: -10, left: 0, bottom: 0, right: 0) // -10 to hide top padding on searchBar
                
        tableView.tableHeaderView = searchController.searchBar
        tableView.tableHeaderView?.layoutMargins = UIEdgeInsets(top: 0, left: 21, bottom: 0, right: 21) // requested to be 21
        
        setupFetchedResultsController()
        
        //add filter
        updateCommonGroups()

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
                        DDLogDebug("GroupsInCommonViewController/presentGroup \(groupId)")
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
        DDLogInfo("GroupsInCommonViewController/viewWillAppear")
        super.viewWillAppear(animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
//        showNUXIfNecessary()
    }

    override func viewWillDisappear(_ animated: Bool) {
        DDLogInfo("GroupsInCommonViewController/viewWillDisappear")
        super.viewWillDisappear(animated)
        isVisible = false
    }

    private lazy var rightBarButtonItem: UIBarButtonItem = {
        let image = UIImage(named: "NavCreateGroup", in: nil, with: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))?.withTintColor(UIColor.primaryBlue, renderingMode: .alwaysOriginal)
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

    private func showNUXIfNecessary() {
        if MainAppContext.shared.nux.isIncomplete(.chatListIntro) {
            let popover = NUXPopover(Localizations.nuxChatIntroContent) { MainAppContext.shared.nux.didComplete(.chatListIntro) }
            overlayContainer.display(popover)
        }
    }

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
        DDLogDebug("GroupsInCommonView/frc/will-change perRowChanges=[\(trackPerRowFRCChanges)]")
        
        if trackPerRowFRCChanges {
            tableView.beginUpdates()
        }

        updateEmptyView()
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            guard let indexPath = newIndexPath, let chatThread = anObject as? ChatThread else { break }
            DDLogDebug("GroupsInCommonView/frc/insert [\(chatThread.type):\(chatThread.groupId ?? chatThread.lastMsgId ?? "")] at [\(indexPath)]")
            if trackPerRowFRCChanges && !isFiltering {
                tableView.insertRows(at: [ indexPath ], with: .automatic)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .delete:
            guard let indexPath = indexPath, let chatThread = anObject as? ChatThread else { break }
            DDLogDebug("GroupsInCommonView/frc/delete [\(chatThread.type):\(chatThread.groupId ?? chatThread.lastMsgId ?? "")] at [\(indexPath)]")
      
            if trackPerRowFRCChanges && !isFiltering {
                tableView.deleteRows(at: [ indexPath ], with: .left)
            } else {
                reloadTableViewInDidChangeContent = true
            }
            
        case .move:
            guard let fromIndexPath = indexPath, let toIndexPath = newIndexPath, let chatThread = anObject as? ChatThread else { break }
            DDLogDebug("GroupsInCommon/frc/move [\(chatThread.type):\(chatThread.groupId ?? chatThread.lastMsgId ?? "")] from [\(fromIndexPath)] to [\(toIndexPath)]")
            if trackPerRowFRCChanges && !isFiltering {
                tableView.moveRow(at: fromIndexPath, to: toIndexPath)
                reloadTableViewInDidChangeContent = true
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .update:
            guard let indexPath = indexPath, let chatThread = anObject as? ChatThread else { return }
            DDLogDebug("GroupsListView/frc/update [\(chatThread.type):\(chatThread.groupId ?? chatThread.lastMsgId ?? "")] at [\(indexPath)]")

            reloadTableViewInDidChangeContent = true
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
        let viewController = NewGroupMembersViewController(currentMembers: [])
        viewController.delegate = self
        present(UINavigationController(rootViewController: viewController), animated: true)
    }
}

extension GroupsInCommonViewController: UIViewControllerScrollsToTop {
    func scrollToTop(animated: Bool) {
        guard let firstSection = fetchedResultsController?.sections?.first else { return }
        guard firstSection.numberOfObjects > 0 else { return }
        tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .middle, animated: animated)
    }
}

extension GroupsInCommonViewController: FeedCollectionViewControllerDelegate {
    func feedCollectionViewController(_ controller: FeedCollectionViewController, userActioned: Bool) {
        searchController.isActive = false
        DispatchQueue.main.async {
            self.scrollToTop(animated: false)
        }
    }
}

// MARK: Table Header Delegate
extension GroupsInCommonViewController: GroupsInCommonHeaderViewDelegate {
    func groupsInCommonHeaderView(_ groupsInCommonHeaderView: GroupsInCommonHeaderView) {
        openNewGroup()
    }
}

// MARK: UITableView Delegates
extension GroupsInCommonViewController: UITableViewDelegate, UITableViewDataSource {
    
    func chatThread(at indexPath: IndexPath) -> ChatThread? {
        
        if isFiltering {
            return filteredChats[indexPath.row]
        }
        
        if (indexPath.row < commonChats.count) {
            return commonChats[indexPath.row]
        } else {
            return nil
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let view = tableView.dequeueReusableHeaderFooterView(withIdentifier: "sectionHeader2") as! GroupsInCommonHeaderView
        view.delegate = self
        return view
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 25
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        if isFiltering {
            return filteredChats.count
        }
        
        return commonChats.count
        //guard let sections = fetchedResultsController?.sections else { return 0 }
        //return sections[section].numberOfObjects + 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let chatThread = chatThread(at: indexPath) else {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.isHidden = true
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: GroupsInCommonViewController.cellReuseIdentifier, for: indexPath) as! ThreadListCell

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
                    self.filteredChats.remove(at: indexPath.row)
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
extension GroupsInCommonViewController: UISearchBarDelegate {
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        DispatchQueue.main.async {
            self.scrollToTop(animated: false)
        }
    }
}

// MARK: UISearchController Updating Delegates
extension GroupsInCommonViewController: UISearchResultsUpdating {
    
    func updateSearchResults(for searchController: UISearchController) {
        guard let allChats = fetchedResultsController?.fetchedObjects else { return }
        guard let searchBarText = searchController.searchBar.text else { return }
    
        let strippedString = searchBarText.trimmingCharacters(in: CharacterSet.whitespaces)
        
        let searchItems = strippedString.components(separatedBy: " ")
        
        filteredChats = allChats.filter {
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
        DDLogDebug("GroupsListViewController/updateSearchResults/filteredChats count \(filteredChats.count) for: \(searchBarText)")
        
        tableView.reloadData()
    }
}

extension GroupsInCommonViewController: NewGroupMembersViewControllerDelegate {
    func newGroupMembersViewController(_ viewController: NewGroupMembersViewController, selected: [UserID]) {}
    
    func newGroupMembersViewController(_ viewController: NewGroupMembersViewController, didCreateGroup: GroupID) {
        let vc = GroupFeedViewController(groupId: didCreateGroup)
        vc.delegate = self
        navigationController?.pushViewController(vc, animated: true)
    }
}

protocol GroupsInCommonHeaderViewDelegate: AnyObject {
    func groupsInCommonHeaderView(_ groupsInCommonHeaderView: GroupsInCommonHeaderView)
}

class GroupsInCommonHeaderView: UITableViewHeaderFooterView {
    weak var delegate: GroupsInCommonHeaderViewDelegate?
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    private func setup() {
        preservesSuperviewLayoutMargins = true

        vStack.addArrangedSubview(groupCommonLabel)
        addSubview(vStack)

        vStack.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 20)
        vStack.isLayoutMarginsRelativeArrangement = true
        
        vStack.topAnchor.constraint(equalTo: topAnchor).isActive = true
        vStack.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true

        let vStackBottomConstraint = vStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        vStackBottomConstraint.priority = UILayoutPriority(rawValue: 999)
        vStackBottomConstraint.isActive = true
    }
    
    private lazy var groupCommonLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 17)
        label.textColor = .systemGray
        label.textAlignment = .left
        //fix:localization
        label.text = "Groups In Common"
        return label
    }()

    private let vStack: UIStackView = {
        let view = UIStackView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .vertical
        return view
    }()

    @objc func openNewGroupView (_ sender: UITapGestureRecognizer) {
        self.delegate?.groupsInCommonHeaderView(self)
    }
}

private extension Localizations {

    static var groupsListRemoveMessage: String {
        NSLocalizedString("groups.list.remove.message", value: "Are you sure you want to remove this group and its content from your device?", comment: "Text shown when user is about to remove the group")
    }
    
}
