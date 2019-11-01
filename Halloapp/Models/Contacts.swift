//
//  ContactStore.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/11/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Contacts
import SwiftUI
import os
import CryptoKit

import Foundation
import Combine

import XMPPFramework

// CryptoKit.Digest utils
extension Digest {
    var bytes: [UInt8] { Array(makeIterator()) }
    var data: Data { Data(bytes) }

    var hexStr: String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }
}

struct NormContact: Identifiable {
    var id = UUID()
    var name: String
    var phone: String
}

class Contacts: ObservableObject {
    
    @Published var contacts: [CNContact] = []
    @Published var error: Error? = nil
    
    @Published var normalizedContacts: [NormContact] = []
    
    var allPhonesString = ""
    var contactHash = ""
    
    var xmpp: XMPP
    var xmppController: XMPPController
    
    private var cancellableSet: Set<AnyCancellable> = []
    
    init(xmpp: XMPP) {
        print("init Contacts")
        self.xmpp = xmpp
        self.xmppController = self.xmpp.xmppController
        
        self.fetch()
        
        cancellableSet.insert(
         
            xmppController.didChangeMessage.sink(receiveValue: { value in

                print("got something")
                
            })

        )

    }

    
    func addAffiliates(user: String) {
        
        let item = XMLElement(name: "affiliation")
        item.addAttribute(withName: "jid", stringValue: "14088922686@s.halloapp.net")
        item.addAttribute(withName: "affiliation", stringValue: "owner")

        let item2 = XMLElement(name: "affiliation")
        item2.addAttribute(withName: "jid", stringValue: "14154121848@s.halloapp.net")
        item2.addAttribute(withName: "affiliation", stringValue: "member")
        
        let affiliations = XMLElement(name: "affiliations")
        affiliations.addAttribute(withName: "node", stringValue: "1111")
        affiliations.addChild(item)
        affiliations.addChild(item2)

        let pubsub = XMLElement(name: "pubsub")
        pubsub.addAttribute(withName: "xmlns", stringValue: "http://jabber.org/protocol/pubsub#owner")
        pubsub.addChild(affiliations)

        let iq = XMLElement(name: "iq")
        iq.addAttribute(withName: "type", stringValue: "set")
        iq.addAttribute(withName: "from", stringValue: "14088922686@s.halloapp.net/iphone")
        iq.addAttribute(withName: "to", stringValue: "pubsub.s.halloapp.net")
        iq.addAttribute(withName: "id", stringValue: "1")
        iq.addChild(pubsub)
        
        xmppController.xmppStream.send(iq)
    }
    
    func fetch() {

        do {
            let store = CNContactStore()
            let keysToFetch = [CNContactGivenNameKey as CNKeyDescriptor,
                               CNContactFamilyNameKey as CNKeyDescriptor,
                               CNContactImageDataAvailableKey as CNKeyDescriptor,
                               CNContactImageDataKey as CNKeyDescriptor,
                               CNContactPhoneNumbersKey as CNKeyDescriptor]
            
            os_log("Fetching contacts: now")
            let containerId = store.defaultContainerIdentifier()
            let predicate = CNContact.predicateForContactsInContainer(withIdentifier: containerId)
            let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keysToFetch)
            os_log("Fetching contacts: succesfull with count = %d", contacts.count)
            self.contacts = contacts
            
            self.allPhonesString = ""
            self.normalizedContacts.removeAll()
            
            for c in self.contacts {
                c.phoneNumbers.forEach {
                    let characterSet = CharacterSet(charactersIn: "01234567890")
                    let pn = String($0.value.stringValue.unicodeScalars.filter(characterSet.contains))
                    self.normalizedContacts.append(NormContact(name: c.name, phone: pn))
                    
                    self.allPhonesString = self.allPhonesString + pn
                }
            }
            
            self.normalizedContacts.forEach {
                print($0.phone)
            }
            
            
            // self.xmppController.createNodes(node: "xxx")
            
            
            // not used yet
            guard let data = self.allPhonesString.data(using: .utf8) else { return }
            let digest = SHA256.hash(data: data)
            print(digest.hexStr)
            
            
        } catch {
            os_log("Fetching contacts: failed with %@", error.localizedDescription)
            self.error = error
        }
    }
}

extension CNContact: Identifiable {
    var name: String {
        return [givenName, familyName].filter{ $0.count > 0}.joined(separator: " ")
    }
}
