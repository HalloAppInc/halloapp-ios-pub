//
//  PrivacyPermissionDeniedController.swift
//  HalloApp
//
//  Created by Nandini Shetty on 7/3/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import UIKit

class PrivacyPermissionDeniedController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .feedBackground
        title = Localizations.titlePrivacy
        let updateContactsPermissionView = UpdateContactsPermissionView()
        updateContactsPermissionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(updateContactsPermissionView)
        updateContactsPermissionView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8).isActive = true
        updateContactsPermissionView.constrain([.centerX, .centerY], to: view)
    }
}
