//
//  NewMessageViewController.swift
//  HalloApp
//
//  Created by Tony Jiang on 4/29/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import CoreData
import UIKit

protocol NewChatViewControllerDelegate: AnyObject {
    func newChatViewController(_ newChatViewController: NewChatViewController, didSelect userId: UserID)
}

class NewChatTableViewController: ContactPickerViewController<ABContact> {

    // MARK: ContactPickerViewController

    override func configure(cell: ContactTableViewCell, with contact: ABContact) {
        cell.configure(with: contact)
    }

    // MARK: NewChatTableViewController

    fileprivate func didSelectContact(with userId: UserID) {
        // Subclasses to implement.
    }

    // MARK: UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let contact = dataSource.itemIdentifier(for: indexPath),
              let userId = contact.userId else
        {
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }

        didSelectContact(with: userId)
    }

}

class NewChatViewController: NewChatTableViewController {

    weak var delegate: NewChatViewControllerDelegate?

    private var fetchedResultsController: NSFetchedResultsController<ABContact>!

    private var searchController: UISearchController!

    init(delegate: NewChatViewControllerDelegate) {
        self.delegate = delegate
        super.init(contacts: [])
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(delegate:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        DDLogInfo("NewMessageViewController/viewDidLoad")

        navigationItem.title = "New Chat"
        navigationItem.standardAppearance = .opaqueAppearance
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(cancelAction))

        tableView.backgroundColor = .feedBackground

        let fetchRequest: NSFetchRequest<ABContact> = ABContact.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "statusValue = %d OR (statusValue = %d AND userId != nil)",
                                             ABContact.Status.in.rawValue, ABContact.Status.out.rawValue)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \ABContact.sort, ascending: true) ]
        fetchedResultsController = NSFetchedResultsController<ABContact>(fetchRequest: fetchRequest,
                                                                         managedObjectContext: AppContext.shared.contactStore.viewContext,
                                                                         sectionNameKeyPath: nil,
                                                                         cacheName: nil)
        fetchedResultsController.delegate = self
        do {
            try fetchedResultsController.performFetch()
            reloadContacts()
        } catch {
            fatalError("Failed to fetch contacts. \(error)")
        }

        let searchResultsController = NewChatSearchResultsController(delegate: self)
        searchController = UISearchController(searchResultsController: searchResultsController)
        searchController.searchResultsUpdater = self
        searchController.searchBar.autocapitalizationType = .none
        searchController.definesPresentationContext = true
        
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        
        if ServerProperties.isInternalUser || ServerProperties.isGroupsEnabled {
            let headerView = TableHeaderView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.size.width, height: 44))
            headerView.button.addTarget(self, action: #selector(createNewGroup), for: .touchUpInside)
            tableView.tableHeaderView = headerView
        }
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        guard let headerView = tableView.tableHeaderView else { return }
        let size = headerView.systemLayoutSizeFitting(CGSize(width: tableView.frame.width, height: CGFloat.greatestFiniteMagnitude),
                                                      withHorizontalFittingPriority: .required,
                                                      verticalFittingPriority: .fittingSizeLevel)
        if headerView.frame.height != size.height {
            headerView.frame.size = size
            tableView.tableHeaderView = headerView
        }
    }

    // MARK: Top Nav Button Actions

    @objc private func cancelAction() {
        dismiss(animated: true)
    }

    @objc private func createNewGroup() {
        navigationController?.pushViewController(NewGroupMembersViewController(), animated: true)
    }

    private func reloadContacts() {
        var deduplicatedContacts: [ABContact] = []
        var contactIdentifiers = Set<String>()
        for contact in fetchedResultsController.fetchedObjects ?? [] {
            guard let identifier = contact.identifier,
                  let phoneNumber = contact.normalizedPhoneNumber else
            {
                deduplicatedContacts.append(contact)
                continue
            }
            let id = "\(identifier)-\(phoneNumber)"
            guard !contactIdentifiers.contains(id) else {
                continue
            }
            contactIdentifiers.insert(id)
            deduplicatedContacts.append(contact)
        }
        contacts = deduplicatedContacts
    }

    // MARK: NewChatTableViewController

    override func didSelectContact(with userId: UserID) {
        delegate?.newChatViewController(self, didSelect: userId)
    }
}

extension NewChatViewController: NSFetchedResultsControllerDelegate {

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        reloadContacts()
    }
}

extension NewChatViewController: NewChatSearchResultsControllerDelegate {

    fileprivate func newChatSearchResultsController(_ controller: NewChatSearchResultsController, didSelect userId: UserID) {
        if searchController.isActive {
            searchController.dismiss(animated: false) {
                self.didSelectContact(with: userId)
            }
        } else {
            didSelectContact(with: userId)
        }
    }
}

private protocol NewChatSearchResultsControllerDelegate: AnyObject {

    func newChatSearchResultsController(_ controller: NewChatSearchResultsController, didSelect userId: UserID)
}

private class NewChatSearchResultsController: NewChatTableViewController {

    weak var delegate: NewChatSearchResultsControllerDelegate?

    init(delegate: NewChatSearchResultsControllerDelegate) {
        self.delegate = delegate
        super.init(contacts: [])
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(delegate:)")
    }

    // MARK: ContactPickerViewController

    override class var showSections: Bool { false }

    // MARK: NewChatTableViewController

    override func didSelectContact(with userId: UserID) {
        delegate?.newChatSearchResultsController(self, didSelect: userId)
    }
}

private class TableHeaderView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private(set) var button: UIButton!

    private func setup() {
        preservesSuperviewLayoutMargins = true

        button = UIButton(type: .system)
        button.titleLabel?.font = .gothamFont(forTextStyle: .headline, weight: .medium)
        button.setTitle("New Group", for: .normal)
        button.tintColor = .systemBlue
        button.contentHorizontalAlignment = .leading
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: layoutMargins.left, bottom: 8, right: layoutMargins.right)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        addSubview(button)
        button.constrain(to: self)
    }

    override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
        button.contentEdgeInsets.left = layoutMargins.left
        button.contentEdgeInsets.right = layoutMargins.right
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
