//
//  XMPPContactSyncRequest.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 3/11/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import XMPPFramework

struct XMPPContact {
    private(set) var userid: String?
    private(set) var normalized: String?
    private(set) var registered: Bool = false
    var raw: String?
    var isDeletedContact: Bool = false

    /**
     Initialize with data from an xml element.

     Use to process server responses.
     */
    init?(_ xmlElement: XMLElement) {
        guard xmlElement.name == "contact" else {
            return nil
        }
        guard let childElements = xmlElement.children else {
            return nil
        }
        for childElement in childElements {
            guard let value = childElement.stringValue else {
                continue
            }
            if let name = childElement.name {
                if name == "userid" {
                    self.userid = value
                }
                if name == "normalized" {
                    self.normalized = value
                }
                if name == "role" {
                    self.registered = (value == "friends")
                }
                if name == "raw" {
                    self.raw = value
                }
            }
        }
    }

    /**
     Initialize with address book contact's data.
     */
    init(_ abContact: ABContact) {
        self.raw = abContact.phoneNumber
        self.normalized = abContact.normalizedPhoneNumber
        self.userid = abContact.userId
    }

    private init(_ normalizedPhoneNumber: ABContact.NormalizedPhoneNumber) {
        self.normalized = normalizedPhoneNumber
    }

    static func deletedContact(with normalizedPhoneNumber: ABContact.NormalizedPhoneNumber) -> XMPPContact {
        var contact = XMPPContact(normalizedPhoneNumber)
        contact.isDeletedContact = true
        return contact
    }

    /**
     Construct xml element from instance data.

     Use to construct contact requests.
     */
    var xmppElement: XMPPElement {
        get {
            let contact = XMPPElement(name: "contact")
            if (self.raw != nil) {
                contact.addChild(XMPPElement(name: "raw", stringValue: self.raw))
            }
            if (self.userid != nil) {
                contact.addChild(XMPPElement(name: "userid", stringValue: self.userid))
            }
            if (self.normalized != nil) {
                contact.addChild(XMPPElement(name: "normalized", stringValue: self.normalized))
            }
            if (self.isDeletedContact) {
                contact.addAttribute(withName: "type", stringValue: "delete")
            }
            return contact
        }
    }
}

fileprivate let xmppNamespaceContacts = "halloapp:user:contacts"

class XMPPContactSyncRequest : XMPPRequest {
    enum RequestType: String {
        case full = "full"
        case delta = "delta"
    }

    typealias XMPPContactListRequestCompletion = ([XMPPContact]?, Error?) -> Void

    var completion: XMPPContactListRequestCompletion

    init<T: Sequence>(with contacts: T, type: RequestType, syncID: String, batchIndex: Int? = nil, isLastBatch: Bool? = nil,
                      completion: @escaping XMPPContactListRequestCompletion) where T.Iterator.Element == XMPPContact {
        self.completion = completion
        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: XMPPIQDefaultTo), elementID: UUID().uuidString)
        iq.addChild({
            let contactList = XMPPElement(name: "contact_list", xmlns: xmppNamespaceContacts)
            contactList.addAttribute(withName: "type", stringValue: type.rawValue)
            contactList.addAttribute(withName: "syncid", stringValue: syncID)
            if batchIndex != nil {
                contactList.addAttribute(withName: "index", intValue: Int32(batchIndex!))
            }
            if isLastBatch != nil {
                contactList.addAttribute(withName: "last", boolValue: isLastBatch!)
            }
            contactList.setChildren(contacts.compactMap{ $0.xmppElement })
            return contactList
        }())
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        var contacts: [XMPPContact]?
        if let contactList = response.childElement {
            assert(contactList.name == "contact_list")
            contacts = contactList.elements(forName: "contact").compactMap{ XMPPContact($0) }
        }
        self.completion(contacts, nil)
    }

    override func didFail(with error: Error) {
        self.completion(nil, error)
    }
}
