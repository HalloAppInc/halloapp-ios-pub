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

        self.navigationItem.title = "New Chat"

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
        
        searchController.definesPresentationContext = true
        
        self.navigationItem.searchController = searchController
        self.navigationItem.hidesSearchBarWhenScrolling = false
        
        let newMessageHeaderView = NewMessageHeaderView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.size.width, height: 35))
        newMessageHeaderView.isHidden = true
        
        //        headerView.configure(withPost: feedPost)
        //        headerView.textLabel.delegate = self
        //        headerView.profilePictureButton.addTarget(self, action: #selector(showUserFeedForPostAuthor), for: .touchUpInside)
        
        if ServerProperties.isInternalUser || ServerProperties.isGroupsEnabled {
            newMessageHeaderView.isHidden = false
        }
        
        newMessageHeaderView.delegate = self
        tableView.tableHeaderView = newMessageHeaderView
        
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
        self.id = abContact.identifier
        self.normalizedPhone = abContact.normalizedPhoneNumber
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
        self.addSubview(vStack)

        vStack.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor).isActive = true
        vStack.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor).isActive = true
        vStack.topAnchor.constraint(equalTo: self.layoutMarginsGuide.topAnchor).isActive = true
        vStack.bottomAnchor.constraint(equalTo: self.layoutMarginsGuide.bottomAnchor).isActive = true
    }
    
    @objc func openNewGroupView (_ sender: UITapGestureRecognizer) {
        self.delegate?.newMessageHeaderView(self)
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

        isHidden = false
        contactImageView.prepareForReuse()
    }

    public func configure(with abContact: ABContact) {
        nameLabel.text = abContact.fullName
        lastMessageLabel.text = abContact.phoneNumber

        if let userId = abContact.userId {
            contactImageView.configure(with: userId, using: MainAppContext.shared.avatarStore)
        }
    }

    private lazy var contactImageView: AvatarView = {
        let imageView = AvatarView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
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
        let vStack = UIStackView(arrangedSubviews: [ nameLabel, lastMessageLabel ])
        vStack.translatesAutoresizingMaskIntoConstraints = false
        vStack.alignment = .leading
        vStack.axis = .vertical
        vStack.spacing = 4

        contentView.addSubview(contactImageView)
        contentView.addSubview(vStack)

        contentView.addConstraints([
            contactImageView.widthAnchor.constraint(equalToConstant: 40),
            contactImageView.heightAnchor.constraint(equalTo: contactImageView.widthAnchor),
            contactImageView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            contactImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            vStack.leadingAnchor.constraint(equalToSystemSpacingAfter: contactImageView.trailingAnchor, multiplier: 2),
            vStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            vStack.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
            vStack.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor)
        ])

        // Priority is lower than "required" because cell's height might be 0 (duplicate contacts).
        contentView.addConstraint({
            let constraint = contactImageView.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor)
            constraint.priority = .defaultHigh
            return constraint
            }())
        contentView.addConstraint({
            let constraint = vStack.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor)
            constraint.priority = .defaultHigh
            return constraint
            }())

        backgroundColor = .clear
    }
}
