//
//  DestinationView.swift
//  Shared Extension
//
//  Created by Alan Luo on 7/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import UIKit


protocol ShareDestinationDelegate {
    func setDestination(to: ShareDestination)
}

fileprivate extension ContactTableViewCell {

    func configureWithContact(_ contact: ABContact, using avatarStore: AvatarStore) {
        contactImage.configure(with: contact.userId!, using: avatarStore)

        nameLabel.font = .preferredFont(forTextStyle: .body)
        nameLabel.text = contact.fullName!
    }
}

class DestinationViewController: UITableViewController {

    static let defaultCellReuseIdentifier = "default-cell"
    static let contactCellReuseIdentifier = "contact-cell"
    
    private let avatarStore: AvatarStore
    private let contacts: [ABContact]
    
    public var delegate: ShareDestinationDelegate?
    
    init(style: UITableView.Style, avatarStore: AvatarStore) {
        self.avatarStore = avatarStore
        contacts = ShareExtensionContext.shared.contactStore.allRegisteredContacts(sorted: true)

        super.init(style: style)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.title = "Send To"

        tableView.backgroundColor = .clear
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.defaultCellReuseIdentifier)
        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: Self.contactCellReuseIdentifier)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        /*
         SLComposeServiceViewController is a relatively small view to show the contact list.
         We need to extend the sheet size for a better user experience.
         SLComposeServiceViewController observes changes to preferredContentSize of each view,
         and animates sheet size changes as necessary.
         */
        preferredContentSize = CGSize(width: view.frame.width, height: view.frame.height * 2)
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 1 {
            return contacts.count
        }
        return 1
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 1 {
            return "Contacts"
        }
        return nil
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.defaultCellReuseIdentifier, for: indexPath)
            cell.textLabel?.text = "Post"
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.contactCellReuseIdentifier, for: indexPath) as! ContactTableViewCell
            cell.profilePictureSize = 25
            cell.configureWithContact(contacts[indexPath.row], using: avatarStore)
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let delegate = delegate else { return }
        
        if indexPath.section == 0 {
            delegate.setDestination(to: .post)
        } else {
            delegate.setDestination(to: .contact(contacts[indexPath.row].userId!, contacts[indexPath.row].fullName!))
        }
    }
}
