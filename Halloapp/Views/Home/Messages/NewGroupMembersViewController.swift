//
//  HalloApp
//
//  Created by Tony Jiang on 4/29/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import CoreData
import UIKit

protocol NewGroupMembersViewControllerDelegate: AnyObject {
    func newGroupMembersViewController(_ inputView: NewGroupMembersViewController, selected: [UserID])
}

class NewGroupMembersViewController: UIViewController, NSFetchedResultsControllerDelegate {
    
    weak var delegate: NewGroupMembersViewControllerDelegate?
    
    let cellReuseIdentifier = "NewGroupMembersViewCell"
    
    private var fetchedResultsController: NSFetchedResultsController<ABContact>?

    private var searchController: UISearchController!
   
    var isSearchBarEmpty: Bool {
      return searchController.searchBar.text?.isEmpty ?? true
    }
    var isFiltering: Bool {
      return searchController.isActive && !isSearchBarEmpty
    }
    private var filteredContacts: [ABContact] = []
    
    private var trackedContacts: [String:TrackedContact] = [:]

    private var selectedMembers: [UserID] = [] {
        didSet {
            if selectedMembers.count == 0 {
                memberAvatarsRow.isHidden = true
            } else {
                memberAvatarsRow.isHidden = false
            }
        }
    }
    
    private var alreadyHaveMembers: Bool = false
    private var currentMembers: [UserID] = []
    
//    init(currentMembers: [UserID] = []) {
//        self.currentMembers = currentMembers
//        self.alreadyHaveMembers = self.currentMembers.count > 0 ? true : false
//        super.init(style: .plain)
//    }

    init(currentMembers: [UserID] = []) {
        self.currentMembers = currentMembers
        self.alreadyHaveMembers = self.currentMembers.count > 0 ? true : false
        super.init(nibName: nil, bundle: nil)
    }
        
    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        DDLogInfo("NewGroupMembersViewController/viewDidLoad")

        if alreadyHaveMembers {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Add", style: .plain, target: self, action: #selector(addAction))
        } else {
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(cancelAction))
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: Localizations.buttonNext, style: .plain, target: self, action: #selector(nextAction))
        }
        navigationItem.rightBarButtonItem?.tintColor = UIColor.systemBlue
//        self.navigationItem.rightBarButtonItem?.isEnabled = selectedMembers.count > 0 ? true : false
        
        navigationItem.title = Localizations.chatSelectGroupMembersTitle

        tableView.backgroundColor = .feedBackground
        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: cellReuseIdentifier)
        
        searchController = UISearchController(searchResultsController: nil)
        searchController.delegate = self
        searchController.searchResultsUpdater = self
        searchController.searchBar.autocapitalizationType = .none
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.definesPresentationContext = true
        
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        
        searchController.searchBar.searchTextField.layer.cornerRadius = 20
        searchController.searchBar.searchTextField.layer.masksToBounds = true
        
        searchController.searchBar.setSearchFieldBackgroundImage(UIImage(), for: .normal)
        searchController.searchBar.backgroundColor = .feedBackground
        searchController.searchBar.searchTextField.backgroundColor = .secondarySystemGroupedBackground

        tableView.tableHeaderView = nil

        view.addSubview(mainView)
        view.backgroundColor = UIColor.feedBackground
        mainView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        mainView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        mainView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        mainView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        
        setupFetchedResultsController()
    }

    private lazy var mainView: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        
        let view = UIStackView(arrangedSubviews: [ tableView, memberAvatarsRow ])
        view.axis = .vertical
  
        view.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private lazy var memberAvatarsRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ groupMemberAvatars ])
        view.axis = .horizontal

        view.layoutMargins = UIEdgeInsets(top: 15, left: 0, bottom: 10, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 100).isActive = true
        
        let subView = UIView(frame: view.bounds)
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        subView.backgroundColor = UIColor.feedBackground
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(subView, at: 0)
        
        let topBorder = UIView(frame: view.bounds)
        topBorder.frame.size.height = 1
        topBorder.backgroundColor = UIColor.secondarySystemGroupedBackground
        topBorder.autoresizingMask = [.flexibleWidth]
        view.insertSubview(topBorder, at: 1)
        
        view.isHidden = true
        
        return view
    }()
    
    private lazy var groupMemberAvatars: GroupMemberAvatars = {
        let view = GroupMemberAvatars()
        view.delegate = self
        return view
    }()
    
    private lazy var tableView: UITableView = {
        let view = UITableView()
        
        view.backgroundColor = .feedBackground
        view.register(ContactTableViewCell.self, forCellReuseIdentifier: cellReuseIdentifier)
        view.delegate = self
        view.dataSource = self
        
        view.tableFooterView = UIView()
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    // MARK: Appearance

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("NewGroupMembersViewController/viewWillAppear")
        super.viewWillAppear(animated)
//        self.tableView.reloadData()
    }

    override func viewDidAppear(_ animated: Bool) {
        DDLogInfo("NewGroupMembersViewController/viewDidAppear")
        super.viewDidAppear(animated)
    }

    deinit {
        DDLogDebug("NewGroupMembersViewController/deinit ")
    }

    // MARK: Top Nav Button Actions

    @objc private func cancelAction() {
        self.dismiss(animated: true)
    }
    
    @objc private func nextAction() {
        let controller = CreateGroupViewController(selectedMembers: selectedMembers)
        self.navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func addAction() {
        self.navigationController?.popViewController(animated: true)
        self.delegate?.newGroupMembersViewController(self, selected: selectedMembers)
    }
    
    
    // MARK: Customization

    public var fetchRequest: NSFetchRequest<ABContact> {
        get {
            let fetchRequest = NSFetchRequest<ABContact>(entityName: "ABContact")
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \ABContact.fullName, ascending: true)
            ]
            fetchRequest.predicate = NSPredicate(format: "statusValue = %d OR (statusValue = %d AND userId != nil)", ABContact.Status.in.rawValue, ABContact.Status.out.rawValue)
            return fetchRequest
        }
    }

    // MARK: Fetched Results Controller

    private var trackPerRowFRCChanges = false

    private var reloadTableViewInDidChangeContent = false

    private func setupFetchedResultsController() {
        self.fetchedResultsController = self.newFetchedResultsController()
        do {
            try self.fetchedResultsController?.performFetch()
        } catch {
            fatalError("Failed to fetch feed items \(error)")
        }
    }

    private func newFetchedResultsController() -> NSFetchedResultsController<ABContact> {
        // Setup fetched results controller the old way because it allows granular control over UI update operations.
        let fetchedResultsController = NSFetchedResultsController<ABContact>(fetchRequest: self.fetchRequest, managedObjectContext: AppContext.shared.contactStore.viewContext,
                                                                            sectionNameKeyPath: nil, cacheName: nil)
        fetchedResultsController.delegate = self
        return fetchedResultsController
    }

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        reloadTableViewInDidChangeContent = false
        trackPerRowFRCChanges = self.view.window != nil && UIApplication.shared.applicationState == .active
        DDLogDebug("NewGroupMembersView/frc/will-change perRowChanges=[\(trackPerRowFRCChanges)]")
        if trackPerRowFRCChanges {
            self.tableView.beginUpdates()
        }
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            guard let indexPath = newIndexPath, let abContact = anObject as? ABContact else { break }
            DDLogDebug("NewGroupMembersView/frc/insert [\(abContact)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                self.tableView.insertRows(at: [ indexPath ], with: .automatic)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .delete:
            guard let indexPath = indexPath, let abContact = anObject as? ABContact else { break }
            DDLogDebug("NewGroupMembersView/frc/delete [\(abContact)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                self.tableView.deleteRows(at: [ indexPath ], with: .automatic)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .move:
            guard let fromIndexPath = indexPath, let toIndexPath = newIndexPath, let abContact = anObject as? ABContact else { break }
            DDLogDebug("NewGroupMembersView/frc/move [\(abContact)] from [\(fromIndexPath)] to [\(toIndexPath)]")
            if trackPerRowFRCChanges {
                self.tableView.moveRow(at: fromIndexPath, to: toIndexPath)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .update:
            guard let indexPath = indexPath, let abContact = anObject as? ABContact else { return }
            DDLogDebug("NewGroupMembersView/frc/update [\(abContact)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                self.tableView.reloadRows(at: [ indexPath ], with: .automatic)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        default:
            break
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DDLogDebug("NewGroupMembersView/frc/did-change perRowChanges=[\(trackPerRowFRCChanges)]  reload=[\(reloadTableViewInDidChangeContent)]")
        if trackPerRowFRCChanges {
            self.tableView.endUpdates()
        } else if reloadTableViewInDidChangeContent {
            self.tableView.reloadData()
        }
    }
        
    func isDuplicate(_ abContact: ABContact) -> Bool {
        guard let identifier = abContact.identifier else { return false }
        guard let phoneNumber = abContact.phoneNumber else { return false }
        guard let normalizedPhoneNumber = abContact.normalizedPhoneNumber else { return false }
        let id = "\(identifier)-\(phoneNumber)" // account for contacts that have multiple registered numbers
        if trackedContacts[id] == nil {
            var trackedContact = TrackedContact(with: abContact)
            if trackedContacts.keys.first(where: { trackedContacts[$0]?.normalizedPhone == normalizedPhoneNumber }) != nil {
                trackedContact.isDuplicate = true
            }
            trackedContacts[id] = trackedContact
        }
        return trackedContacts[id]?.isDuplicate ?? false
    }
}

// MARK: UITableView Delegates
extension NewGroupMembersViewController: UITableViewDelegate, UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return self.fetchedResultsController?.sections?.count ?? 0
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sections = self.fetchedResultsController?.sections else { return 0 }
        if isFiltering {
          return filteredContacts.count
        }
        return sections[section].numberOfObjects
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier, for: indexPath) as! ContactTableViewCell

        let abContact: ABContact?
        
        if isFiltering {
            abContact = filteredContacts[indexPath.row]
        } else {
            abContact = fetchedResultsController?.object(at: indexPath)
        }

        if let abContact = abContact {
            if let userId = abContact.userId {
                cell.configure(with: abContact)
                let isSelected = selectedMembers.contains(userId)
                cell.setContact(selected: isSelected, animated: true)
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        var contact: ABContact?
        
        if isFiltering {
            contact = filteredContacts[indexPath.row]
        } else {
            contact = fetchedResultsController?.object(at: indexPath)
        }
        if let contact = contact, self.isDuplicate(contact) {
            return 0
        }
        
        guard let userId = contact?.userId else { return 0 }
        if currentMembers.contains(userId) {
            return 0
        }
        
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        var contact: ABContact?

        if isFiltering {
            contact = filteredContacts[indexPath.row]
        } else {
            contact = fetchedResultsController?.object(at: indexPath)
        }
        if let contact = contact, self.isDuplicate(contact) {
            cell.isHidden = true
        }
        
        guard let userId = contact?.userId else { return }
        if currentMembers.contains(userId) {
            cell.isHidden = true
        }
    }

    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let cell = tableView.cellForRow(at: indexPath) as? ContactTableViewCell else { return }
//        guard let contact = fetchedResultsController?.object(at: indexPath) else { return }
        let abContact: ABContact?
        if isFiltering {
            abContact = filteredContacts[indexPath.row]
        } else {
            abContact = fetchedResultsController?.object(at: indexPath)
        }
        
        guard let contact = abContact else { return }
        
        var isSelected = false
        guard let userId = contact.userId else { return }
        if !selectedMembers.contains(userId) {
            
            guard selectedMembers.count + currentMembers.count < ServerProperties.maxGroupSize else {
                let alert = UIAlertController(title: "", message: "The max group size is \(ServerProperties.maxGroupSize)", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
                self.present(alert, animated: true)
                return
            }
            
            selectedMembers.append(userId)
            groupMemberAvatars.insert(with: [userId])
            isSelected = true
        } else {
            selectedMembers.removeAll(where: {$0 == userId})
            groupMemberAvatars.removeUser(userId)
        }
        cell.setContact(selected: isSelected, animated: true)
        tableView.deselectRow(at: indexPath, animated: true)
//        navigationItem.rightBarButtonItem?.isEnabled = selectedMembers.count > 0 ? true : false

        searchController.isActive = false
        searchController.searchBar.text = ""
    }
}

extension NewGroupMembersViewController: UISearchControllerDelegate {

    func willPresentSearchController(_ searchController: UISearchController) {
        if let resultsController = searchController.searchResultsController as? UITableViewController {
            resultsController.tableView.delegate = self
        }
    }
}

extension NewGroupMembersViewController: UISearchResultsUpdating {
    
    func updateSearchResults(for searchController: UISearchController) {
        guard let allContacts = fetchedResultsController?.fetchedObjects else { return }
        let strippedString = searchController.searchBar.text!.trimmingCharacters(in: CharacterSet.whitespaces)
        let searchItems = strippedString.components(separatedBy: " ")

        let andPredicates: [NSPredicate] = searchItems.map { (searchString) in
            NSComparisonPredicate(leftExpression: NSExpression(forKeyPath: "searchTokens"),
                                  rightExpression: NSExpression(forConstantValue: searchString),
                                  modifier: .any,
                                  type: .contains,
                                  options: [.caseInsensitive, .diacriticInsensitive])
        }

        let finalCompoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: andPredicates)

        filteredContacts = allContacts.filter { finalCompoundPredicate.evaluate(with: $0) }
        tableView.reloadData()
    }
}

extension NewGroupMembersViewController: GroupMemberAvatarsDelegate {
    
    func groupMemberAvatarsDelegate(_ view: GroupMemberAvatars, selectedUser: String) {
        
        selectedMembers.removeAll(where: { $0 == selectedUser })
        
        tableView.reloadData()
        
    }
}

fileprivate struct TrackedContact {
    let normalizedPhone: String?
    var isDuplicate: Bool = false

    init(with abContact: ABContact) {
        normalizedPhone = abContact.normalizedPhoneNumber
    }
}

private extension ContactTableViewCell {

    func configure(with abContact: ABContact) {
        options.insert(.hasCheckmark)

        nameLabel.text = abContact.fullName
        subtitleLabel.text = abContact.phoneNumber

        if let userId = abContact.userId {
            contactImage.configure(with: userId, using: MainAppContext.shared.avatarStore)
        }

    }
}

private extension Localizations {
    
    static var chatSelectGroupMembersTitle: String {
        NSLocalizedString("chat.select.group.members.title", value: "Select Members", comment: "Title of screen where user chooses members to add to either a new group or an existing one")
    }
    
}
