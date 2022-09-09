//
//  GroupsInCommonViewController.swift
//  HalloApp
//
//  Created by Han  on 2021/5/31.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import CoreData
import SwiftUI
import UIKit

fileprivate struct Constants {
    static let AvatarSize: CGFloat = 56
}

class GroupsInCommonViewController: UIViewController, NSFetchedResultsControllerDelegate {

    private static let cellReuseIdentifier = "ThreadListCell"
    private let tableView = UITableView(frame: CGRect.zero, style: .grouped)
    
    private var fetchedResultsController: NSFetchedResultsController<CommonThread>?
    
    private var isVisible: Bool = false
    
    private var filteredChats: [CommonThread] = []
    private var searchController: UISearchController!
    
    private var commonChats: [CommonThread] = []
    
    private var isSearchBarEmpty: Bool {
        return searchController.searchBar.text?.isEmpty ?? true
    }
    private var isFiltering: Bool {
        return searchController.isActive && !isSearchBarEmpty
    }
    private var groupIdToPresent: GroupID? = nil
    
    private var userID : UserID
    
    func updateCommonGroups() {
        guard let allChats = fetchedResultsController?.fetchedObjects else { return }
        commonChats = allChats.filter {
            var groupIdStr: GroupID? = nil
            if ($0.type == .groupFeed || $0.type == .groupChat) {
                groupIdStr = $0.groupId
            } else {
                return false
            }
            guard let Id = groupIdStr else { return false }
            guard let managedObjectContext = $0.managedObjectContext else { return false }
            let group = MainAppContext.shared.chatData.chatGroup(groupId: Id, in: managedObjectContext)
            guard let members = group?.members else { return false}
            for member in members {
                if (member.userID == self.userID) {
                    return true
                }
            }
            return false
        }
    }
        
    @objc
    private func didTapDismiss() {
        dismiss(animated: true)
    }

    // MARK: Lifecycle
    
    init(userID: String) {
        self.userID = userID
        super.init(nibName: nil, bundle: nil)
        self.title = String(format: Localizations.groupsInCommonLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        DDLogInfo("GroupsInCommonViewController/viewDidLoad")

        navigationItem.leftBarButtonItem = .init(image: UIImage(named: "ReplyPanelClose"), style: .plain, target: self, action: #selector(didTapDismiss))

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
    }
    
    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("GroupsInCommonViewController/viewWillAppear")
        super.viewWillAppear(animated)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        DDLogInfo("GroupsInCommonViewController/viewWillDisappear")
        super.viewWillDisappear(animated)
        isVisible = false
    }

    // MARK: NUX

    private lazy var emptyView: UIView = {
        let image = UIImage(named: "ChatEmpty")?.withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: image)
        imageView.tintColor = UIColor.label.withAlphaComponent(0.2)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.text = Localizations.nuxGroupsInCommonListEmpty
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
    
    // MARK: Fetched Results Controller
    
    public var fetchRequest: NSFetchRequest<CommonThread> {
        let fetchRequest = NSFetchRequest<CommonThread>(entityName: "CommonThread")
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: "lastTimestamp", ascending: false),
            NSSortDescriptor(key: "title", ascending: true)
        ]
        fetchRequest.predicate = NSPredicate(format: "groupID != nil")
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

    private func createFetchedResultsController() -> NSFetchedResultsController<CommonThread> {
        // Setup fetched results controller the old way because it allows granular control over UI update operations.
        let fetchedResultsController = NSFetchedResultsController<CommonThread>(fetchRequest: fetchRequest,
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
            guard let indexPath = newIndexPath, let chatThread = anObject as? CommonThread else { break }
            DDLogDebug("GroupsInCommonView/frc/insert [\(chatThread.type):\(chatThread.groupId ?? chatThread.lastMsgId ?? "")] at [\(indexPath)]")
            if trackPerRowFRCChanges && !isFiltering {
                tableView.insertRows(at: [ indexPath ], with: .automatic)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .delete:
            guard let indexPath = indexPath, let chatThread = anObject as? CommonThread else { break }
            DDLogDebug("GroupsInCommonView/frc/delete [\(chatThread.type):\(chatThread.groupId ?? chatThread.lastMsgId ?? "")] at [\(indexPath)]")
      
            if trackPerRowFRCChanges && !isFiltering {
                tableView.deleteRows(at: [ indexPath ], with: .left)
            } else {
                reloadTableViewInDidChangeContent = true
            }
            
        case .move:
            guard let fromIndexPath = indexPath, let toIndexPath = newIndexPath, let chatThread = anObject as? CommonThread else { break }
            DDLogDebug("GroupsInCommon/frc/move [\(chatThread.type):\(chatThread.groupId ?? chatThread.lastMsgId ?? "")] from [\(fromIndexPath)] to [\(toIndexPath)]")
            if trackPerRowFRCChanges && !isFiltering {
                tableView.moveRow(at: fromIndexPath, to: toIndexPath)
                reloadTableViewInDidChangeContent = true
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .update:
            guard let indexPath = indexPath, let chatThread = anObject as? CommonThread else { return }
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

    // MARK: Helpers

    private func openFeed(forGroupId groupId: GroupID) {
        let vc = GroupFeedViewController(groupId: groupId)
        vc.delegate = self
        navigationController?.pushViewController(vc, animated: true)
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

// MARK: UITableView Delegates
extension GroupsInCommonViewController: UITableViewDelegate, UITableViewDataSource {
    
    func chatThread(at indexPath: IndexPath) -> CommonThread? {
        
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
        let allChats = commonChats
        guard let searchBarText = searchController.searchBar.text else { return }
    
        let strippedString = searchBarText.trimmingCharacters(in: CharacterSet.whitespaces)
        
        let searchItems = strippedString.components(separatedBy: " ")
        
        filteredChats = allChats.filter {
            var titleText: String? = nil
            if ($0.type == .groupFeed || $0.type == .groupChat) {
                titleText = $0.title
            } else {
                titleText = MainAppContext.shared.contactStore.fullName(for: $0.userID ?? "", in: MainAppContext.shared.contactStore.viewContext)
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

class GroupsInCommonHeaderView: UITableViewHeaderFooterView {
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    private func setup() {
        preservesSuperviewLayoutMargins = true
        addSubview(vStack)

        vStack.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 20)
        vStack.isLayoutMarginsRelativeArrangement = true
        
        vStack.topAnchor.constraint(equalTo: topAnchor).isActive = true
        vStack.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true

        let vStackBottomConstraint = vStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        vStackBottomConstraint.priority = UILayoutPriority(rawValue: 999)
        vStackBottomConstraint.isActive = true
    }
    
    private let vStack: UIStackView = {
        let view = UIStackView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.axis = .vertical
        return view
    }()

}

private extension Localizations {
    
    static var groupsInCommonLabel: String {
        NSLocalizedString("groups.common", value: "Groups In Common", comment: "A label to show that the groups below are groups in common")
    }
    static var withPersonLabel: String {
        NSLocalizedString("groups.title", value: "With %@", comment: "A label on the header to indicate which person I have groups in common with")
    }
    
}
