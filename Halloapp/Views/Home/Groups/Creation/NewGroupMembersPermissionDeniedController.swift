//
//  NewGroupMembersPermissionDeniedController.swift
//  HalloApp
//
//  Created by Nandini Shetty on 7/2/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import UIKit

class NewGroupMembersPermissionDeniedController: UIViewController {

    private var alreadyHaveMembers: Bool = false
    private var currentMembers: [UserID] = []
    
    init(currentMembers: [UserID] = []) {
        self.currentMembers = currentMembers
        self.alreadyHaveMembers = self.currentMembers.count > 0 ? true : false
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .feedBackground
        if alreadyHaveMembers {
            navigationItem.title = Localizations.titleSelectGroupMembers
        } else {
            navigationItem.title = Localizations.titleSelectGroupMembersCreateGroup
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(cancelAction))
        }
        let updateContactsPermissionsView = UpdateContactsPermissionView()
        view.addSubview(updateContactsPermissionsView)
        updateContactsPermissionsView.translatesAutoresizingMaskIntoConstraints = false
        updateContactsPermissionsView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8).isActive = true
        updateContactsPermissionsView.constrain([.centerX, .centerY], to: view)
    }
    
    // MARK: Top Nav Button Actions

    @objc private func cancelAction() {
        dismiss(animated: true)
    }
}
