//
//  XMPPContactSyncRequest.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 3/11/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import Foundation
import XMPPFramework

typealias HalloContact = XMPPContact

struct XMPPContact {
    private(set) var userid: String?
    private(set) var normalized: String?
    private(set) var registered: Bool = false
    private(set) var avatarid: AvatarID?
    var raw: String?
    var isDeletedContact: Bool = false

    /** Use to process protobuf server responses */
    init(_ pbContact: Server_Contact) {
        if pbContact.uid > 0 {
            userid = String(pbContact.uid)
        }
        if !pbContact.normalized.isEmpty {
            normalized = pbContact.normalized
        }
        registered = (pbContact.role == .friends && userid != nil)
        raw = pbContact.raw
        if !pbContact.avatarID.isEmpty {
            avatarid = pbContact.avatarID
        }
    }

    /**
     Initialize with address book contact's data.
     */
    init(_ abContact: ABContact) {
        raw = abContact.phoneNumber
        normalized = abContact.normalizedPhoneNumber
        userid = abContact.userId
    }

    private init(_ normalizedPhoneNumber: ABContact.NormalizedPhoneNumber) {
        self.normalized = normalizedPhoneNumber
    }

    static func deletedContact(with normalizedPhoneNumber: ABContact.NormalizedPhoneNumber) -> XMPPContact {
        var contact = XMPPContact(normalizedPhoneNumber)
        contact.isDeletedContact = true
        return contact
    }
}
