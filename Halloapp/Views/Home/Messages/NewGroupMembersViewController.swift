//
//  HalloApp
//
//  Created by Tony Jiang on 4/29/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import CoreData
import Foundation
import UIKit
import SwiftUI

protocol NewGroupMembersViewControllerDelegate: AnyObject {
    func newGroupMembersViewController(_ inputView: NewGroupMembersViewController, selected: [UserID])
}

class NewGroupMembersViewController: UITableViewController, NSFetchedResultsControllerDelegate {
    
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

    private var selectedMembers: [UserID] = []
    
    private var alreadyHaveMembers: Bool = false
    private var currentMembers: [UserID] = []
    
    init(currentMembers: [UserID] = []) {
        self.currentMembers = currentMembers
        self.alreadyHaveMembers = self.currentMembers.count > 0 ? true : false
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        DDLogInfo("NewGroupMembersViewController/viewDidLoad")

        if alreadyHaveMembers {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Add", style: .plain, target: self, action: #selector(addAction))
        } else {
            self.navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(cancelAction))
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Next", style: .plain, target: self, action: #selector(nextAction))
        }
        self.navigationItem.rightBarButtonItem?.tintColor = UIColor.systemBlue
        self.navigationItem.rightBarButtonItem?.isEnabled = selectedMembers.count > 0 ? true : false
        
        self.navigationItem.title = "Add Members"
        self.navigationItem.standardAppearance = .transparentAppearance
        self.navigationItem.standardAppearance?.backgroundColor = UIColor.systemGray6

        let backButton = UIBarButtonItem(title: "Back", style: .plain, target: nil, action: nil)
        navigationItem.backBarButtonItem = backButton

        
        self.tableView.separatorStyle = .none
        self.tableView.backgroundColor = UIColor.systemGray6
        self.tableView.register(NewGroupMembersViewCell.self, forCellReuseIdentifier: cellReuseIdentifier)
        
        searchController = UISearchController(searchResultsController: nil)
        searchController.delegate = self
        searchController.searchResultsUpdater = self
        searchController.searchBar.autocapitalizationType = .none
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.definesPresentationContext = true
        
        self.navigationItem.searchController = searchController
        self.navigationItem.hidesSearchBarWhenScrolling = false
        
        
        let newGroupMembersHeaderView = NewGroupMembersHeaderView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.size.width, height: 0))
        //        headerView.configure(withPost: feedPost)
        //        headerView.textLabel.delegate = self
        //        headerView.profilePictureButton.addTarget(self, action: #selector(showUserFeedForPostAuthor), for: .touchUpInside)
        
        newGroupMembersHeaderView.delegate = self
        tableView.tableHeaderView = newGroupMembersHeaderView
        
        self.setupFetchedResultsController()
        
        
        
    }

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

    // MARK: UITableView Delegates

    override func numberOfSections(in tableView: UITableView) -> Int {
        return self.fetchedResultsController?.sections?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sections = self.fetchedResultsController?.sections else { return 0 }
        if isFiltering {
          return filteredContacts.count
        }
        return sections[section].numberOfObjects
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier, for: indexPath) as! NewGroupMembersViewCell

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

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
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

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
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

    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let cell = tableView.cellForRow(at: indexPath) as? NewGroupMembersViewCell else { return }
//        guard let contact = fetchedResultsController?.object(at: indexPath) else { return }
        let abContact: ABContact?
        cell.selectionStyle = .none
        
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
            isSelected = true
        } else {
            selectedMembers.removeAll(where: {$0 == userId})
        }
        cell.setContact(selected: isSelected, animated: true)
        tableView.deselectRow(at: indexPath, animated: true)
        navigationItem.rightBarButtonItem?.isEnabled = selectedMembers.count > 0 ? true : false

        searchController.isActive = false
        searchController.searchBar.text = ""
    }
    
    func isDuplicate(_ abContact: ABContact) -> Bool {
        var result = false
        guard let identifier = abContact.identifier else { return result }
        guard let normalizedPhoneNumber = abContact.normalizedPhoneNumber else { return result }
        if self.trackedContacts[identifier] == nil {
            var trackedContact = TrackedContact(with: abContact)
            for (_, con) in self.trackedContacts {
                if con.normalizedPhone == normalizedPhoneNumber {
                    trackedContact.isDuplicate = true
                    break
                }
            }
            self.trackedContacts[identifier] = trackedContact
        }
        guard let isDuplicate = self.trackedContacts[identifier]?.isDuplicate else { return result }
        result = isDuplicate
        return result
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

extension NewGroupMembersViewController: NewGroupMembersHeaderViewDelegate {
    func newGroupMembersHeaderView(_ newGroupMembersHeaderView: NewGroupMembersHeaderView) {
        //TODO: for removal of selected members
    }
}

fileprivate struct TrackedContact {
    let id: String?
    let normalizedPhone: String?
    var isDuplicate: Bool = false

    init(with abContact: ABContact) {
        self.id = abContact.identifier
        self.normalizedPhone = abContact.normalizedPhoneNumber
    }
}

protocol NewGroupMembersHeaderViewDelegate: AnyObject {
    func newGroupMembersHeaderView(_ newGroupMembersHeaderView: NewGroupMembersHeaderView)
}

class NewGroupMembersHeaderView: UIView {

    weak var delegate: NewGroupMembersHeaderViewDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private lazy var textLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.textColor = .systemBlue
        label.textAlignment = .right
        label.text = ""
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.openNewGroupView(_:)))
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(tapGesture)

        return label
    }()

    private let vStack: UIStackView = {
        let vStack = UIStackView()
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis = .vertical
        return vStack
    }()

    private func setup() {
        self.preservesSuperviewLayoutMargins = true

        vStack.addArrangedSubview(textLabel)
        self.addSubview(vStack)

        vStack.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor).isActive = true
        vStack.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor).isActive = true
        vStack.topAnchor.constraint(equalTo: self.layoutMarginsGuide.topAnchor).isActive = true
        vStack.bottomAnchor.constraint(equalTo: self.layoutMarginsGuide.bottomAnchor).isActive = true
    }
    
    @objc func openNewGroupView (_ sender: UITapGestureRecognizer) {
        self.delegate?.newGroupMembersHeaderView(self)
    }
}

fileprivate class NewGroupMembersViewCell: UITableViewCell {
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.isHidden = false

        contactImageView.prepareForReuse()
    }

    public func configure(with abContact: ABContact) {
        self.nameLabel.text = abContact.fullName
        self.lastMessageLabel.text = abContact.phoneNumber

        if let userId = abContact.userId {
            contactImageView.configure(with: userId, using: MainAppContext.shared.avatarStore)
        }
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
    
    private let checkMark: UIImageView = {
        let view = UIImageView(image: UIImage(systemName: "circle")?.withRenderingMode(.alwaysTemplate))
        view.translatesAutoresizingMaskIntoConstraints = false
        
        view.widthAnchor.constraint(equalToConstant: 28).isActive = true
        view.heightAnchor.constraint(equalTo: view.widthAnchor).isActive = true
        
        view.tintColor = .systemGray
        return view
    }()
    
    private(set) var isContactSelected: Bool = false

    func setContact(selected: Bool, animated: Bool = false) {
    
        
        guard selected != isContactSelected else { return }

        isContactSelected = selected

        let image = isContactSelected ? UIImage(systemName: "checkmark.circle.fill") : UIImage(systemName: "circle")
        
        checkMark.image = image?.withRenderingMode(.alwaysTemplate)
  
        checkMark.tintColor =  isContactSelected ? UIColor.systemBlue : UIColor.systemGray
        
        if animated {
            checkMark.layer.add({
                let transition = CATransition()
                transition.duration = 0.2
                transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                transition.type = .fade
                return transition
            }(), forKey: nil)
        }
    }
    
    private func setup() {
        let vStack = UIStackView(arrangedSubviews: [self.nameLabel, self.lastMessageLabel])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis = .vertical
        vStack.spacing = 2

        let imageSize: CGFloat = 40.0
        self.contactImageView.widthAnchor.constraint(equalToConstant: imageSize).isActive = true
        self.contactImageView.heightAnchor.constraint(equalTo: self.contactImageView.widthAnchor).isActive = true


        
        let hStack = UIStackView(arrangedSubviews: [ self.contactImageView, vStack, self.checkMark ])
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.axis = .horizontal
        hStack.alignment = .center
        hStack.spacing = 10
        
 
    
        self.contentView.addSubview(hStack)
        // Priority is lower than "required" because cell's height might be 0 (duplicate contacts).
        self.contentView.addConstraint({
            let constraint = hStack.topAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.topAnchor)
            constraint.priority = .defaultHigh
            return constraint
            }())
        hStack.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        hStack.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor).isActive = true
        hStack.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor).isActive = true

        self.backgroundColor = .clear
    }
}
