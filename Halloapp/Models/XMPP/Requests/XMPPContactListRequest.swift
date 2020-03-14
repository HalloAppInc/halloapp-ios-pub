//
//  XMPPContactListRequest.swift
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

    /**
     Construct xml element from instance data.

     Use to construct contact requests.
     */
    var xmppElement: XMPPElement {
        get {
            let contact = XMPPElement(name: "contact")
            if (self.userid != nil) {
                contact.addChild(XMPPElement(name: "userid", stringValue: self.userid))
            }
            if (self.raw != nil) {
                contact.addChild(XMPPElement(name: "raw", stringValue: self.raw))
            }
            if (self.normalized != nil) {
                contact.addChild(XMPPElement(name: "normalized", stringValue: self.normalized))
            }
            // "role" is never sent back to the server
            return contact
        }
    }
}

fileprivate let xmppNamespaceContacts = "halloapp:user:contacts"

class XMPPContactListRequest : XMPPRequest {
    enum RequestType: String {
        case set = "set"
        case add = "add"
        case delete = "delete"
    }

    typealias XMPPContactListRequestCompletion = ([XMPPContact]?, Error?) -> Void

    var completion: XMPPContactListRequestCompletion

    init(with contacts: [ABContact], operation: RequestType, completion: @escaping XMPPContactListRequestCompletion) {
        self.completion = completion
        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: XMPPIQDefaultTo), elementID: UUID().uuidString)
        iq.addChild({
            let contactList = XMPPElement(name: "contact_list", xmlns: xmppNamespaceContacts)
            contactList.addAttribute(withName: "type", stringValue: operation.rawValue)
            contactList.setChildren(contacts.compactMap{ XMPPContact($0).xmppElement })
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
