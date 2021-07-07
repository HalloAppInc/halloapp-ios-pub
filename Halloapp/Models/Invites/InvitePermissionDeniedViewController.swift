//
//  InvitePermissionDeniedViewController.swift
//  HalloApp
//
//  Created by Nandini Shetty on 7/6/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import UIKit

class InvitePermissionDeniedViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = Localizations.inviteTitle
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(cancelAction))
        view.backgroundColor = .feedBackground
        let updateContactsPermissionView = UpdateContactsPermissionView()
        updateContactsPermissionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(updateContactsPermissionView)
        updateContactsPermissionView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8).isActive = true
        updateContactsPermissionView.constrain([.centerX, .centerY], to: view)
    }

    // MARK: Top Nav Button Actions

    @objc private func cancelAction() {
        dismiss(animated: true)
    }
}
