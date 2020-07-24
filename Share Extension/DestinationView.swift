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

class DestinationViewController: UITableViewController {
    static let defaultCellReuseIdentifier = "default-cell"
    static let contactCellReuseIdentifier = "contact-cell"
    
    private let avatarStore: AvatarStore
    private let contacts: [ABContact]
    
    public var delegate: ShareDestinationDelegate?
    
    override init(style: UITableView.Style) {
        avatarStore = AvatarStore()
        contacts = ShareExtensionContext.shared.contactStore.allRegisteredContacts(sorted: true)
        
        super.init(style: style)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.navigationItem.title = "Send To"
        self.tableView.backgroundColor = .clear
        
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.defaultCellReuseIdentifier)
        self.tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: Self.contactCellReuseIdentifier)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        /*
         SLComposeServiceViewController is a relatively small view to show the contact list.
         We need to extend the sheet size for a better user experience.
         SLComposeServiceViewController observes changes to preferredContentSize of each view,
         and animates sheet size changes as necessary.
         */
        let frame = self.view.frame
        let newSize:CGSize = CGSize(width:frame.size.width, height:frame.size.height * 2)
        self.preferredContentSize = newSize
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return 1
        } else {
            return contacts.count
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return "Post"
        } else {
            return "Contacts"
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.defaultCellReuseIdentifier, for: indexPath)
            cell.textLabel?.text = "Post"
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: Self.contactCellReuseIdentifier, for: indexPath) as! ContactTableViewCell
            cell.configure(with: contacts[indexPath.row].userId!, name: contacts[indexPath.row].fullName!, using: avatarStore)
            cell.isUserInteractionEnabled = false // Disable contacts for the first version
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
