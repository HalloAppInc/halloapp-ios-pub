//
//  InvitePeopleTableViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 7/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import CoreData
import UIKit

extension Localizations {
    static var alreadyHalloAppUser: String {
        NSLocalizedString("invite.already.halloapp.user",
                          value: "Already a HalloApp user",
                          comment: "Displayed below contact name in contact list that is displayed when inviting someone to HalloApp.")
    }
}

extension ABContact: IndexableContact {
    var collationName: String {
        indexName ?? "#"
    }
}

extension ABContact: SearchableContact { }
