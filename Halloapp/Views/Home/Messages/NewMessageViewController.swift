//
//  NewMessageViewController.swift
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

fileprivate struct Constants {
    static let cellReuseIdentifier = "NewMessageViewCell"
}

protocol NewMessageViewControllerDelegate: AnyObject {
    func newMessageViewController(_ newMessageViewController: NewMessageViewController, chatWithUserId: String)
}

fileprivate class ContactsSearchResultsController: UITableViewController {

    var contacts: [ABContact] = [] {
        didSet {
            if self.isViewLoaded {
                self.tableView.reloadData()
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.backgroundColor = .feedBackground
        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: Constants.cellReuseIdentifier)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return contacts.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Constants.cellReuseIdentifier, for: indexPath) as! ContactTableViewCell
        cell.configure(with: contacts[indexPath.row])
        return cell
    }
}



class NewMessageViewController: UITableViewController, NSFetchedResultsControllerDelegate {

    weak var delegate: NewMessageViewControllerDelegate?

    private var fetchedResultsController: NSFetchedResultsController<ABContact>!

    private var searchController: UISearchController!
    private var searchResultsController: ContactsSearchResultsController!

    private var trackedContacts: [String: TrackedContact] = [:]

    init() {
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        DDLogInfo("NewMessageViewController/viewDidLoad")

        navigationItem.title = "New Chat"
        navigationItem.standardAppearance = .opaqueAppearance
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(cancelAction))

        setupFetchedResultsController()

        tableView.backgroundColor = .feedBackground
        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: Constants.cellReuseIdentifier)
        
        searchResultsController = ContactsSearchResultsController(style: .plain)
        searchController = UISearchController(searchResultsController: searchResultsController)
        searchController.delegate = self
        searchController.searchResultsUpdater = self
        searchController.searchBar.autocapitalizationType = .none
        searchController.definesPresentationContext = true
        
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        
        let newMessageHeaderView = NewMessageHeaderView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.size.width, height: 35))
        newMessageHeaderView.isHidden = true
        if ServerProperties.isInternalUser || ServerProperties.isGroupsEnabled {
            newMessageHeaderView.isHidden = false
        }
        newMessageHeaderView.delegate = self
        tableView.tableHeaderView = newMessageHeaderView
    }

    // MARK: Appearance

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("NewMessageViewController/viewWillAppear")
        super.viewWillAppear(animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        DDLogInfo("NewMessageViewController/viewDidAppear")
        super.viewDidAppear(animated)
    }

    deinit {
        DDLogDebug("NewMessageViewController/deinit ")
    }

    // MARK: Top Nav Button Actions

    @objc private func cancelAction() {
        dismiss(animated: true)
    }

    // MARK: Customization

    private var fetchRequest: NSFetchRequest<ABContact> {
        let fetchRequest = NSFetchRequest<ABContact>(entityName: "ABContact")
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \ABContact.fullName, ascending: true)
        ]
        fetchRequest.predicate = NSPredicate(format: "statusValue = %d OR (statusValue = %d AND userId != nil)", ABContact.Status.in.rawValue, ABContact.Status.out.rawValue)
        return fetchRequest
    }

    // MARK: Fetched Results Controller

    private var trackPerRowFRCChanges = false

    private func setupFetchedResultsController() {
        fetchedResultsController = newFetchedResultsController()
        do {
            try fetchedResultsController.performFetch()
        } catch {
            fatalError("Failed to fetch feed items \(error)")
        }
    }

    private func newFetchedResultsController() -> NSFetchedResultsController<ABContact> {
        // Setup fetched results controller the old way because it allows granular control over UI update operations.
        let fetchedResultsController = NSFetchedResultsController<ABContact>(fetchRequest: fetchRequest,
                                                                             managedObjectContext: AppContext.shared.contactStore.viewContext,
                                                                             sectionNameKeyPath: nil,
                                                                             cacheName: nil)
        fetchedResultsController.delegate = self
        return fetchedResultsController
    }

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        trackPerRowFRCChanges = view.window != nil && UIApplication.shared.applicationState == .active
        DDLogDebug("NewMessageView/frc/will-change perRowChanges=[\(trackPerRowFRCChanges)]")
        if trackPerRowFRCChanges {
            tableView.beginUpdates()
        }
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            guard let indexPath = newIndexPath, let abContact = anObject as? ABContact else { break }
            DDLogDebug("NewMessageView/frc/insert [\(abContact)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                tableView.insertRows(at: [ indexPath ], with: .automatic)
            }

        case .delete:
            guard let indexPath = indexPath, let abContact = anObject as? ABContact else { break }
            DDLogDebug("NewMessageView/frc/delete [\(abContact)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                tableView.deleteRows(at: [ indexPath ], with: .automatic)
            }

        case .move:
            guard let fromIndexPath = indexPath, let toIndexPath = newIndexPath, let abContact = anObject as? ABContact else { break }
            DDLogDebug("NewMessageView/frc/move [\(abContact)] from [\(fromIndexPath)] to [\(toIndexPath)]")
            if trackPerRowFRCChanges {
                tableView.moveRow(at: fromIndexPath, to: toIndexPath)
            }

        case .update:
            guard let indexPath = indexPath, let abContact = anObject as? ABContact else { return }
            DDLogDebug("NewMessageView/frc/update [\(abContact)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                tableView.reloadRows(at: [ indexPath ], with: .automatic)
            }

        default:
            break
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DDLogDebug("NewMessageView/frc/did-change perRowChanges=[\(trackPerRowFRCChanges)]")
        if trackPerRowFRCChanges {
            tableView.endUpdates()
        } else {
            tableView.reloadData()
        }
    }

    // MARK: UITableView Delegates

    override func numberOfSections(in tableView: UITableView) -> Int {
        return fetchedResultsController.sections?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sections = fetchedResultsController?.sections else {
            return 0
        }
        return sections[section].numberOfObjects
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Constants.cellReuseIdentifier, for: indexPath) as! ContactTableViewCell
        cell.configure(with: fetchedResultsController.object(at: indexPath))
        return cell
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        var contact: ABContact
        if tableView == self.tableView {
            contact = fetchedResultsController.object(at: indexPath)
        } else {
            contact = searchResultsController.contacts[indexPath.row]
        }
        guard !isDuplicate(contact) else {
            return 0
        }
        return UITableView.automaticDimension
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        var contact: ABContact
        if tableView == self.tableView {
            contact = fetchedResultsController.object(at: indexPath)
        } else {
            contact = searchResultsController.contacts[indexPath.row]
        }
        if isDuplicate(contact) {
            cell.isHidden = true
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let delegate = delegate else {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }

        var userId: UserID?
        if tableView == self.tableView {
            userId = fetchedResultsController.object(at: indexPath).userId
        } else {
            userId = searchResultsController.contacts[indexPath.row].userId
        }

        if let userId = userId {
            if searchController.isActive {
                searchController.dismiss(animated: false) {
                    delegate.newMessageViewController(self, chatWithUserId: userId)
                }
            } else {
                delegate.newMessageViewController(self, chatWithUserId: userId)

            }
        } else {
            tableView.deselectRow(at: indexPath, animated: true)
        }
    }

    func isDuplicate(_ abContact: ABContact) -> Bool {
        guard let identifier = abContact.identifier else {
            return false
        }
        guard let normalizedPhoneNumber = abContact.normalizedPhoneNumber else {
            return false
        }
        if trackedContacts[identifier] == nil {
            var trackedContact = TrackedContact(with: abContact)
            for (_, con) in trackedContacts {
                if con.normalizedPhone == normalizedPhoneNumber {
                    trackedContact.isDuplicate = true
                    break
                }
            }
            trackedContacts[identifier] = trackedContact
        }
        return trackedContacts[identifier]?.isDuplicate ?? false
    }

}

extension NewMessageViewController: UISearchControllerDelegate {

    func willPresentSearchController(_ searchController: UISearchController) {
        if let resultsController = searchController.searchResultsController as? UITableViewController {
            resultsController.tableView.delegate = self
        }
    }
}

extension NewMessageViewController: UISearchResultsUpdating {

    func updateSearchResults(for searchController: UISearchController) {
        guard let resultsController = searchController.searchResultsController as? ContactsSearchResultsController else { return }
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
        resultsController.contacts = allContacts.filter { finalCompoundPredicate.evaluate(with: $0) }
    }
}

extension NewMessageViewController: NewMessageHeaderViewDelegate {
    func newMessageHeaderView(_ newMessageHeaderView: NewMessageHeaderView) {
        self.navigationController?.pushViewController(NewGroupMembersViewController(), animated: true)
    }
}

fileprivate struct TrackedContact {
    let id: String?
    let normalizedPhone: String?
    var isDuplicate: Bool = false

    init(with abContact: ABContact) {
        id = abContact.identifier
        normalizedPhone = abContact.normalizedPhoneNumber
    }
}

protocol NewMessageHeaderViewDelegate: AnyObject {
    func newMessageHeaderView(_ newMessageHeaderView: NewMessageHeaderView)
}

class NewMessageHeaderView: UIView {

    weak var delegate: NewMessageHeaderViewDelegate?
    
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
        label.text = "New Group"
        
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
        addSubview(vStack)

        vStack.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor).isActive = true
        vStack.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor).isActive = true
        vStack.topAnchor.constraint(equalTo: self.layoutMarginsGuide.topAnchor).isActive = true
        vStack.bottomAnchor.constraint(equalTo: self.layoutMarginsGuide.bottomAnchor).isActive = true
    }
    
    @objc func openNewGroupView (_ sender: UITapGestureRecognizer) {
        self.delegate?.newMessageHeaderView(self)
    }
}

private extension ContactTableViewCell {

    func configure(with abContact: ABContact) {
        nameLabel.text = abContact.fullName
        subtitleLabel.text = abContact.phoneNumber
        if let userId = abContact.userId {
            contactImage.configure(with: userId, using: MainAppContext.shared.avatarStore)
        }
    }
}
