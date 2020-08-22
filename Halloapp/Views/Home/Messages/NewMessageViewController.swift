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

        self.tableView.separatorStyle = .none
        self.tableView.backgroundColor = UIColor.systemGray6
        self.tableView.register(NewMessageViewCell.self, forCellReuseIdentifier: Constants.cellReuseIdentifier)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return contacts.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Constants.cellReuseIdentifier, for: indexPath) as! NewMessageViewCell
        cell.configure(with: contacts[indexPath.row])
        return cell
    }
}

class NewMessageViewController: UITableViewController, NSFetchedResultsControllerDelegate {

    weak var delegate: NewMessageViewControllerDelegate?

    private var fetchedResultsController: NSFetchedResultsController<ABContact>?

    private var searchController: UISearchController!
    private var searchResultsController: ContactsSearchResultsController!

    private var trackedContacts: [String:TrackedContact] = [:]

    init() {
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        DDLogInfo("NewMessageViewController/viewDidLoad")

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(cancelAction))

        self.navigationItem.title = "New Message"

        self.navigationItem.standardAppearance = .transparentAppearance
        self.navigationItem.standardAppearance?.backgroundColor = UIColor.systemGray6

        self.tableView.separatorStyle = .none
        self.tableView.backgroundColor = UIColor.systemGray6
        self.tableView.register(NewMessageViewCell.self, forCellReuseIdentifier: Constants.cellReuseIdentifier)

        searchResultsController = ContactsSearchResultsController(style: .plain)
        searchController = UISearchController(searchResultsController: searchResultsController)
        searchController.delegate = self
        searchController.searchResultsUpdater = self
        searchController.searchBar.autocapitalizationType = .none
        self.navigationItem.searchController = searchController

        self.setupFetchedResultsController()
    }

    // MARK: Appearance

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("NewMessageViewController/viewWillAppear")
        super.viewWillAppear(animated)
//        self.tableView.reloadData()
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
        self.dismiss(animated: true)
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
        DDLogDebug("NewMessageView/frc/will-change perRowChanges=[\(trackPerRowFRCChanges)]")
        if trackPerRowFRCChanges {
            self.tableView.beginUpdates()
        }
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            guard let indexPath = newIndexPath, let abContact = anObject as? ABContact else { break }
            DDLogDebug("NewMessageView/frc/insert [\(abContact)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                self.tableView.insertRows(at: [ indexPath ], with: .automatic)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .delete:
            guard let indexPath = indexPath, let abContact = anObject as? ABContact else { break }
            DDLogDebug("NewMessageView/frc/delete [\(abContact)] at [\(indexPath)]")
            if trackPerRowFRCChanges {
                self.tableView.deleteRows(at: [ indexPath ], with: .automatic)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .move:
            guard let fromIndexPath = indexPath, let toIndexPath = newIndexPath, let abContact = anObject as? ABContact else { break }
            DDLogDebug("NewMessageView/frc/move [\(abContact)] from [\(fromIndexPath)] to [\(toIndexPath)]")
            if trackPerRowFRCChanges {
                self.tableView.moveRow(at: fromIndexPath, to: toIndexPath)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .update:
            guard let indexPath = indexPath, let abContact = anObject as? ABContact else { return }
            DDLogDebug("NewMessageView/frc/update [\(abContact)] at [\(indexPath)]")
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
        DDLogDebug("NewMessageView/frc/did-change perRowChanges=[\(trackPerRowFRCChanges)]  reload=[\(reloadTableViewInDidChangeContent)]")
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
        return sections[section].numberOfObjects
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Constants.cellReuseIdentifier, for: indexPath) as! NewMessageViewCell
        if let abContact = fetchedResultsController?.object(at: indexPath) {
            cell.configure(with: abContact)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        var contact: ABContact?
        if tableView == self.tableView {
            contact = self.fetchedResultsController?.object(at: indexPath)
        } else {
            contact = searchResultsController.contacts[indexPath.row]
        }
        if let contact = contact, self.isDuplicate(contact) {
            return 0
        }
        return UITableView.automaticDimension
    }

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        var contact: ABContact?
        if tableView == self.tableView {
            contact = self.fetchedResultsController?.object(at: indexPath)
        } else {
            contact = searchResultsController.contacts[indexPath.row]
        }
        if let contact = contact, self.isDuplicate(contact) {
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
            userId = fetchedResultsController?.object(at: indexPath).userId
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

fileprivate struct TrackedContact {
    let id: String?
    let normalizedPhone: String?
    var isDuplicate: Bool = false

    init(with abContact: ABContact) {
        self.id = abContact.identifier
        self.normalizedPhone = abContact.normalizedPhoneNumber
    }
}

fileprivate class NewMessageViewCell: UITableViewCell {
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

    private func setup() {
        let vStack = UIStackView(arrangedSubviews: [self.nameLabel, self.lastMessageLabel])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.axis = .vertical
        vStack.spacing = 2

        let imageSize: CGFloat = 40.0
        self.contactImageView.widthAnchor.constraint(equalToConstant: imageSize).isActive = true
        self.contactImageView.heightAnchor.constraint(equalTo: self.contactImageView.widthAnchor).isActive = true

        let hStack = UIStackView(arrangedSubviews: [ self.contactImageView, vStack ])
        hStack.translatesAutoresizingMaskIntoConstraints = false
        hStack.axis = .horizontal
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
