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

        navigationItem.title = Localizations.chatNewMessageTitle
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
        
        
        let headerView = TableHeaderView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.size.width, height: 44))
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(createNewGroup))
        headerView.isUserInteractionEnabled = true
        headerView.addGestureRecognizer(tapGesture)
        
        tableView.tableHeaderView = headerView
        
    }

    // MARK: ContactPickerViewController

    override func makeSearchResultsController() -> ContactPickerViewController<ABContact> {
        return NewChatSearchResultsController(delegate: self)
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

    override class var isSearchResultsController: Bool { true }

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
        fatalError("Use init(delegate:)")
    }

    private(set) var button: UIButton!

    private func setup() {
        preservesSuperviewLayoutMargins = true
        backgroundColor = UIColor.secondarySystemGroupedBackground
        
        let groupIcon = UIImageView()
        groupIcon.image = AvatarView.defaultGroupImage
        groupIcon.contentMode = .scaleAspectFit
        groupIcon.tintColor = UIColor.systemBlue
        
        groupIcon.layer.masksToBounds = false
        groupIcon.layer.cornerRadius = 30/2
        groupIcon.clipsToBounds = true
     
        groupIcon.translatesAutoresizingMaskIntoConstraints = false
        groupIcon.widthAnchor.constraint(equalToConstant: 30).isActive = true
        groupIcon.heightAnchor.constraint(equalToConstant: 30).isActive = true
        
        button = UIButton(type: .system)
        button.isUserInteractionEnabled = false
        button.titleLabel?.font = .gothamFont(forTextStyle: .headline, weight: .medium)
        button.setTitle(Localizations.chatCreateNewGroup, for: .normal)
        button.tintColor = .systemBlue
        button.contentHorizontalAlignment = .leading
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: layoutMargins.right)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(groupIcon)
        addSubview(button)
        
        groupIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20).isActive = true
        groupIcon.topAnchor.constraint(equalTo: topAnchor, constant: 7).isActive = true
        
        button.leadingAnchor.constraint(equalTo: groupIcon.trailingAnchor).isActive = true
        button.topAnchor.constraint(equalTo: topAnchor).isActive = true
        button.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        button.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
    }

    override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
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

private extension Localizations {

    static var chatNewMessageTitle: String {
        NSLocalizedString("chat.new.message.title", value: "New Message", comment: "Title for new message screen where user chooses who to message")
    }

}
