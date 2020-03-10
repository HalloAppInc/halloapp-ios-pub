import Combine
import CommonCrypto
import Contacts
import CryptoKit
import CryptoSwift
import Dispatch
import Foundation
import os
import SwiftUI
import XMPPFramework

class Contacts: ObservableObject {
    @Published var connectedContacts: [NormContact] = []

    private let defaultNumChunks: Int = 1000
    private let contactsQueue = DispatchQueue(label: "com.halloapp.contacts.serial", qos: DispatchQoS.default)
    private var contacts: [NormContact] = []
    private var idsToNormalize: [BatchId] = []
    private var idsToWhiteListContacts: [BatchId] = []
    private var idsToWhiteListFeed: [BatchId] = []
    private var cancellableSet: Set<AnyCancellable> = []

    private var userData: UserData
    private var xmppController: XMPPController
    private let store = CNContactStore()
    private let contactsCD = ContactsCD()

    init(xmppController: XMPPController, userData: UserData) {
        self.xmppController = xmppController
        self.userData = userData
        
        self.pushAllItems(items: self.contactsCD.getAll())
        
        self.connectedContacts = self.contacts.filter { $0.isConnected }

        // when app resumes, xmpp reconnects, contacts should check again
        self.cancellableSet.insert(
            self.xmppController.didConnect.sink(receiveValue: { value in
                
                self.userData.log("Contacts: Got event for didConnect")
//                self.fetch()

                self.store.requestAccess(for: .contacts, completionHandler: { (granted, error) in
                    
                    if (granted) {
                        self.fetch()
                    } else {
                        // should display something to inform user of changing it in settings
                    }
                    
                })
                
                
                let current = Int(Date().timeIntervalSince1970)
                
                let oneday = 60*60*24*1
                
                let diff = current - self.userData.loggingTimestamp
                                
                if (diff > oneday) {
                    self.userData.loggingTimestamp = Int(Date().timeIntervalSince1970)
                    self.userData.logging = ""
                }
            })
        )
        
        self.cancellableSet.insert(
         
            self.userData.didLogOff.sink(receiveValue: {
                self.userData.log("Contacts: got didLogOff")
                
                self.connectedContacts.removeAll()
                self.contacts.removeAll()
                self.idsToNormalize.removeAll()
                self.idsToWhiteListContacts.removeAll()
                self.idsToWhiteListFeed.removeAll()
            })
        )
        
        self.cancellableSet.insert(
            self.userData.didResyncContacts.sink(receiveValue: { value in
                
                self.userData.log("Resync Contacts")
                
                self.contacts.removeAll()
                self.connectedContacts = self.contacts.filter { $0.isConnected }
                
                self.fetch()
            })
        )
        
        cancellableSet.insert(
         
            xmppController.didGetAllAffiliations.sink(receiveValue: { iq in

                self.contactsQueue.async {
                    
                    var numChanges: Int = 0
                    
                    let affList = Utils().parseAffList(iq)
                    
                    self.userData.log("Contacts: Aff List - \(affList)")

                    for (conIndex, con) in self.contacts.enumerated() {
                        
                        let targetUser = con.normPhone != "" ? con.normPhone : con.phone
                        let index = affList.firstIndex { $0 == targetUser }
                        
                        if !con.isConnected {
                            
                            /* connect to the other user */
                            if (index != nil) {
                                self.contacts[conIndex].isConnected = true
                                numChanges += 1
                                
                                let updateItem = self.contacts[conIndex]
                                self.contactsQueue.async {
                                    self.contactsCD.update(item: updateItem)
                                }
                                
                                self.xmppController.xmppPubSub.subscribe(toNode: "feed-\(targetUser)")
                                self.xmppController.xmppPubSub.retrieveItems(fromNode: "feed-\(targetUser)") // get newly connected user's past feed items
                                
                                self.notifyUser(user: targetUser, type: "add")
                                
                            }
                            
                        } else {
                            
                            /* other user have removed you */
                            if (index == nil) {

                                self.contacts[conIndex].isConnected = false
                                
                                numChanges += 1
                                let updateItem = self.contacts[conIndex]
                                
                                self.contactsQueue.async {
                                    self.contactsCD.update(item: updateItem)
                                }
                                
                                self.xmppController.xmppPubSub.unsubscribe(fromNode: "feed-\(targetUser)")
                            }
                            
                        }
                    }

                    if numChanges > 0 {
                        self.userData.log("Contacts: there are changes, update the connected users list")
                        
                        DispatchQueue.main.async {

                            var isConnected = self.contacts.filter { $0.isConnected }
                            isConnected.sort {
                                $0.name < $1.name
                            }
                            self.connectedContacts = isConnected
                        }
                    }
                    
//                    self.userData.log("Connected Contacts: ")
//                    self.userData.log("\(self.contacts.filter { $0.isConnected })")
                    
                    self.userData.log("Fetch all items")
                    
                    let connected = self.contacts.filter() { $0.isConnected }

                    connected.forEach {
                        let targetUser = $0.normPhone != "" ? $0.normPhone : $0.phone
                        
                        /* extra redundancy - repair past corrupted data if there are any */
                        self.xmppController.xmppPubSub.subscribe(toNode: "feed-\(targetUser)")
                        Utils().sendAff(xmppStream: self.xmppController.xmppStream, node: "feed-\(self.userData.phone)", from: "\(self.userData.phone)", user: targetUser, role: "member")
                        Utils().sendAff(xmppStream: self.xmppController.xmppStream, node: "contacts-\(self.userData.phone)", from: "\(self.userData.phone)", user: targetUser, role: "publish-only")

//                        self.xmppController.xmppPubSub.retrieveItems(fromNode: "feed-\(targetUser)")
                    }

                    /* get your own items */
//                    self.xmppController.xmppPubSub.retrieveItems(fromNode: "feed-\(self.userData.phone)")
                    
                    /* only do cleanup duty when everything else has been done */
//                    print("Contacts Clean Up")
                    
                    /* remove extra affiliations  */
                    self.getWhitelist(node: "contacts", id: "whitelisted-on-contacts")
                    
                    /* for informational purposes */
                    self.getWhitelist(node: "feed", id: "whitelisted-on-feed")
                    
                    /* remove extra subscriptions */
                    self.xmppController.xmppPubSub.retrieveSubscriptions()
                }
            })
        )
        
        
        cancellableSet.insert(
         
            xmppController.didGetNewContactsItem.sink(receiveValue: { iq in
                
                if let id = iq.elementID {
                    self.userData.log("Feed: Sending ACK for Add/Remove")
                    Utils().sendAck(xmppStream: self.xmppController.xmppStream, id: id, from: self.userData.phone)
                } else {
                    self.userData.log("Feed: Not sending ACK for Add/Remove")
                }
                
                // basically a refresh
                self.getAllAffiliations()
                
                // todo: should also delete everything from list, ie remove users from subscriber lists
                
            })
        )
        
        cancellableSet.insert(
         
            xmppController.didGetSubscriptions.sink(receiveValue: { iq in
                
                self.contactsQueue.async {
                    
                    let list = Utils().parseSubsForExtras(iq)
                    
                    self.userData.log("Contacts: Subscriptions - \(list.count)")
                    self.userData.log("\(list)")
                    
                    for sub in list {
                        
                        if (sub == self.userData.phone) {
                            continue
                        }
                        
                        let processed = self.contacts.filter {
                            $0.isProcessed
                        }
                        
                        let index = processed.firstIndex {
                            ($0.normPhone != "" ? $0.normPhone : $0.phone) == sub
                        }
                        
                        if index == nil {
                            self.userData.log("Remove extra subscription: \(sub)")
                            
                            self.xmppController.xmppPubSub.unsubscribe(fromNode: "feed-\(sub)")
                            
                            self.notifyUser(user: sub, type: "remove")
                        }
                    }
                }
            })
        )
        
        cancellableSet.insert(
         
            xmppController.didGetOwnAffiliations.sink(receiveValue: { iq in
                
                self.contactsQueue.async {
                
                    let affList = Utils().parseOwnAffList(iq)
             
                    if iq.elementID == "whitelisted-on-contacts" {
                        self.userData.log("whitelisted-on-contacts: \(affList.count)")
                        self.userData.devLog("\(affList)")
                    } else {
                        self.userData.log("whitelisted-on-feed: \(affList.count)")
                        self.userData.devLog("\(affList)")
                        return
                    }
                    
                    for aff in affList {
                    
                        let index = self.contacts.firstIndex {
                            ($0.normPhone != "" ? $0.normPhone : $0.phone) == aff
                        }
                        
                        if index == nil {
                            self.userData.log("remove extra whitelist: \(aff)")
                            
                            Utils().sendAff(xmppStream: self.xmppController.xmppStream, node: "feed-\(self.userData.phone)", from: "\(self.userData.phone)", user: aff, role: "none")
                            Utils().sendAff(xmppStream: self.xmppController.xmppStream, node: "contacts-\(self.userData.phone)", from: "\(self.userData.phone)", user: aff, role: "none")
                        
                        }
                    }
                }
            })
        )
        
        /* norm batch */
        cancellableSet.insert(

            xmppController.didGetNormBatch.sink(receiveValue: { iq in

                self.contactsQueue.async {
                    if let idParts = iq.elementID?.components(separatedBy: "-") {
                       if (idParts[0] == "batchNorm") {

                            let normList = Utils().parseRawContacts(iq)
                        
                            self.userData.log("Contacts: Norm Batch - \(iq.elementID!) num: \(normList.count) numIdsToNormalize: \(self.idsToNormalize.count)")
                            self.userData.log("\(iq)")
                        
                            var whiteList: [BatchId] = []
                            
                            for norm in normList {
                                
                                let index = self.contacts.firstIndex { $0.phone == norm.phone }
                                
                                if index != nil {

                                    self.idsToNormalize.removeAll(where: { $0.phone == norm.phone } )
                                    
                                    if (norm.normalizedPhone != "") {
                                        self.contacts[index!].normPhone = norm.normalizedPhone
                                    }

                                    self.contactsQueue.async {
                                        self.contactsCD.update(item: self.contacts[index!])
                                    }
                           
                                    /* after normalizing, send it in to whitelist */
                                    var item = BatchId()
                                    item.phone = norm.normalizedPhone != "" ? norm.normalizedPhone : norm.phone
                                    
                                    whiteList.append(item)
                                    
                                }
                                   
                            }
                    
          
                            self.idsToWhiteListContacts.append(contentsOf: whiteList)
                            self.idsToWhiteListFeed.append(contentsOf: whiteList)
                       }
                    }

                    /* all normalizations are done, proceed to whitelisting */
                    if self.idsToNormalize.count == 0 {
                        self.userData.log("Finish Normaliziation -> start whitelisting contacts: \(self.idsToWhiteListContacts.count)")
                        
                        self.processWhiteListContactsChunks()
                    }
                }
            })
        )
        
        /* contacts aff batch */
        cancellableSet.insert(
         
            xmppController.didGetAffContactsBatch.sink(receiveValue: { iq in

                self.contactsQueue.async {
                    if let idParts = iq.elementID?.components(separatedBy: "-") {
                        
                        if (idParts[0] == "batchAff") {

                            let connected = self.idsToWhiteListContacts.filter() { $0.batch == iq.elementID! }

                            self.userData.log("Aff Batch Contacts: \(iq.elementID!) num: \(connected.count) numIdsToWhiteList: \(self.idsToWhiteListContacts.count)")
                            
                            connected.forEach { con in
                                
                                let index = self.contacts.firstIndex {
                                    return ($0.normPhone != "" ? $0.normPhone : $0.phone) == con.phone
                                }
                                
                                if index != nil {

                                    self.idsToWhiteListContacts.removeAll(where: { $0.phone == con.phone } )
                                    
                                    self.contactsQueue.async {
                                        self.contactsCD.update(item: self.contacts[index!])
                                    }
                                }
                            }
                        }
                    }
                    
                    /* all contact whitelisting are done, proceed to whitelisting feed */
                    if self.idsToWhiteListContacts.count == 0 {
                        self.userData.log("Finish whitelisting contacts -> start whitelisting Feed")

                        self.processWhiteListFeedChunks()
                    }
                }
            })
        )
        
        /* feed aff batch */
        cancellableSet.insert(
         
            xmppController.didGetAffFeedBatch.sink(receiveValue: { iq in

                self.contactsQueue.async {
                    if let idParts = iq.elementID?.components(separatedBy: "-") {
                        if (idParts[0] == "batchAffFeed") {
     
                            let connected = self.idsToWhiteListFeed.filter() { $0.batch == iq.elementID! }
     
                            self.userData.log("Aff Batch Feed: \(iq.elementID!) num: \(connected.count) numIdsToWhiteList: \(self.idsToWhiteListFeed.count)")

                            connected.forEach { con in
                                
                                let index = self.contacts.firstIndex {
                                    
                                    if (!$0.isProcessed) {
                                        return ($0.normPhone != "" ? $0.normPhone : $0.phone) == con.phone
                                    } else {
                                        return false
                                    }
                                    
                                }
                                
                                if index != nil {

    //                                print("whitelisted: \(con.phone)")
                                    
                                    self.idsToWhiteListFeed.removeAll(where: { $0.phone == con.phone } )
                                    
                                    self.contacts[index!].isProcessed = true
                                    
                                    self.contactsQueue.async {
                                        self.contactsCD.update(item: self.contacts[index!])
                                    }
                                }
                            }
                        }
                    }
                    
                    /* all feed whitelisting are done, proceed to getAllAffiliations */
                    if self.idsToWhiteListFeed.count == 0 {
                        self.userData.log("Finish whitelisting feed, now getAllAffiliations")

                        
                        self.getAllAffiliations()
                    }
                }
            })
        )

        
        /* might be redundant to remove first, but just in case */
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name.CNContactStoreDidChange,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(addressBookDidChange),
            name: NSNotification.Name.CNContactStoreDidChange,
            object: nil)
        
    }

    func getWhitelist(node: String, id: String) {
        
        let affiliations = XMLElement(name: "affiliations")
        affiliations.addAttribute(withName: "node", stringValue: "\(node)-\(self.userData.phone)")

        let pubsub = XMLElement(name: "pubsub")
        pubsub.addAttribute(withName: "xmlns", stringValue: "http://jabber.org/protocol/pubsub#owner")
        pubsub.addChild(affiliations)

        let iq = XMLElement(name: "iq")
        iq.addAttribute(withName: "type", stringValue: "get")
        iq.addAttribute(withName: "from", stringValue: "\(self.userData.phone)@s.halloapp.net/iphone")
        iq.addAttribute(withName: "to", stringValue: "pubsub.s.halloapp.net")
        iq.addAttribute(withName: "id", stringValue: id)
        iq.addChild(pubsub)

        self.xmppController.xmppStream.send(iq)
    }
    
    func getAllAffiliations() {
        let affiliations = XMLElement(name: "affiliations")

        let pubsub = XMLElement(name: "pubsub")
        pubsub.addAttribute(withName: "xmlns", stringValue: "http://jabber.org/protocol/pubsub")
        pubsub.addChild(affiliations)

        let iq = XMLElement(name: "iq")
        iq.addAttribute(withName: "type", stringValue: "get")
        iq.addAttribute(withName: "from", stringValue: "\(self.userData.phone)@s.halloapp.net/iphone")
        iq.addAttribute(withName: "to", stringValue: "pubsub.s.halloapp.net")
        iq.addAttribute(withName: "id", stringValue: "all aff")
        iq.addChild(pubsub)

        self.xmppController.xmppStream.send(iq)
    }
    
    func getName(phone: String) -> String {
        
        if phone == self.userData.phone {
            return "Me"
        }
        
        let idx = self.contacts.firstIndex(where: {($0.normPhone != "" ? $0.normPhone : $0.phone) == phone})
        
        if (idx == nil) {
            return phone // Modified it only for temporary use.
        } else {
            return self.contacts[idx!].name
        }
    }
        
    func pushAllItems(items: [NormContact]) {
        
        self.contacts = items
        
        self.contacts.sort {
            $0.name < $1.name
        }

    }

    func pushItem(item: NormContact) {
        
        let idx = self.contacts.firstIndex(where: {$0.phone == item.phone})
        
        if (idx == nil) {
 
            self.contacts.append(item)
            
            self.contactsQueue.async {
                self.contactsCD.create(item: item)
            }
            
            
        } else {
//            print("do no insert: \(item.text)")
        }
        
    }

    @objc func addressBookDidChange(notification: NSNotification) {

        print("notification: \(notification)")
            
        /* for some reason, notifications get fired twice so we remove it after the first */
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name.CNContactStoreDidChange,
            object: nil
        )
        
        self.fetch()
        
        /*
         after we remove the observer we need to add it back so we can observe the next time,
         but we delay for 2 seconds or else an immediate observer will actually catch the 2nd firing
         note: 2nd firing could actually be an iOS issue
         */
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.addressBookDidChange),
                name: NSNotification.Name.CNContactStoreDidChange,
                object: nil)
        }
        

    }

    func notifyUser(user: String, type: String) {
        
        print("notifyUser: \(user) - \(type)")
        
        let text = XMLElement(name: "type", stringValue: type)
        let username = XMLElement(name: "user", stringValue: self.userData.phone)
        let timestamp = XMLElement(name: "timestamp", stringValue: String(Date().timeIntervalSince1970))

        let root = XMLElement(name: "entry")
        
        root.addChild(username)
        root.addChild(timestamp)
        root.addChild(text)
        
        self.xmppController.xmppPubSub.publish(toNode: "contacts-\(user)", entry: root)
        
    }

    func fetch() {
        
        self.contactsQueue.async {

            let timestamp = Date()
            print("Contacts fetch begin")
           
            var addressBookContacts: [CNContact] = []
            
            let keysToFetch = [CNContactGivenNameKey as CNKeyDescriptor,
                               CNContactFamilyNameKey as CNKeyDescriptor,
                               CNContactOrganizationNameKey as CNKeyDescriptor,
                               CNContactPhoneNumbersKey as CNKeyDescriptor]
            
            /* get all the containers in the address book */
            var allContainers: [CNContainer] = []
            
            do {
                allContainers = try self.store.containers(matching: nil)
            } catch {
                print("Error fetching containers")
            }

            /* get address book contacts */
            for container in allContainers {
                let fetchPredicate = CNContact.predicateForContactsInContainer(withIdentifier: container.identifier)

                do {
                    /* note: if for some reason you have one contact with 4000 phone numbers inside of it, this
                       call will crash silently without throwing, furthermore, opening that contact up on an iPhone
                       will crash the phone also (iPhone 11 pro - ios 13.3)
                       2000 phone numbers work fine
                     */
                    let containerResults = try self.store.unifiedContacts(matching: fetchPredicate, keysToFetch: keysToFetch)

                    addressBookContacts.append(contentsOf: containerResults)
                } catch {
                    print("Error fetching results for container")
                }
            }
            
            var addressBookContactsStrArr: [String] = []
            
            var numChangesToExistingContacts: Int = 0
            
            let characterSet = CharacterSet(charactersIn: "01234567890")
            

            /* find any new or changed numbers from the address book */
            for abContact in addressBookContacts {

                /* for users with TrueCaller installed, it'll have a SPAM contact that has a lot of phone numbers */
                if (abContact.name == "SPAM") {
                    continue
                }

                for abContactPhoneNumber in abContact.phoneNumbers {

                    let phoneNumber = String(abContactPhoneNumber.value.stringValue.unicodeScalars.filter(characterSet.contains))

                    /* skip user's him/herself */
                    if (phoneNumber == self.userData.phone) {
                        continue
                    }

                    /* skip invalid numbers */
                    if (phoneNumber.count < 5) {
                        continue
                    }

                    addressBookContactsStrArr.append(phoneNumber)
                    
                    let idx = self.contacts.firstIndex(where: {$0.phone == phoneNumber})

                    if (idx == nil) { // can't find contact
                        
                        let item = NormContact(
                                phone: phoneNumber,
                                normPhone: "",
                                name: abContact.name,
                                isConnected: false,
                                isProcessed: false
                            )
                    
                        self.contacts.append(item)
                      
                        let updateItem = item
                        self.contactsQueue.async {
                            self.contactsCD.create(item: updateItem)
                        }
                        
                        self.idsToNormalize.append(BatchId(phone: phoneNumber))
                        
                    } else { // found contact
                        
                        /*
                            see if contact has updated info,
                            gotcha: we do allow contacts with no name, just phone number
                        */
                        if self.contacts[idx!].name != abContact.name {
       
                            self.contacts[idx!].name = abContact.name
                            
                            numChangesToExistingContacts += 1
                            
                            let updateItem = self.contacts[idx!]
                            self.contactsQueue.async {
                                self.contactsCD.update(item: updateItem)
                            }
                        }

                        if (!self.contacts[idx!].isProcessed) {
                            self.idsToNormalize.append(BatchId(phone: phoneNumber))
                        }
                        
                    }
                }
            }

            /* remove any contacts that is not in the address book anymore */
            let numContactRemovals = self.removeExtraContacts(addressBookContactsStrArr: addressBookContactsStrArr)
            
            /* name changes, etc */
            if numChangesToExistingContacts > 0 || numContactRemovals > 0 {
                var isConnected = self.contacts.filter { $0.isConnected }
                isConnected.sort {
                    $0.name < $1.name
                }
                DispatchQueue.main.async {
                    self.connectedContacts = isConnected
                }
            }


            if self.idsToNormalize.count > 0 {
                self.userData.log("Start normalization of: \(self.idsToNormalize.count)")

                self.processNormalizeChunks(self.idsToNormalize)
            } else {
                self.getAllAffiliations()
            }

            print("Contacts fetch end. time: \(Date().timeIntervalSince(timestamp))")
        }
    }
    
    func processNormalizeChunks(_ fromList: [BatchId]) {
        
        if (fromList.count == 0) { return }
        
        var list = fromList
        
        let numChunk = self.defaultNumChunks
        let listChunked = list.chunked(by: numChunk)
        
        for (index, idsArr) in listChunked.enumerated() {
                                    
            let label = "batchNorm-\(index)"
            
            for (_, id) in idsArr.enumerated() {
                
                let idx = list.firstIndex(where: {$0.phone == id.phone})
                
                if (idx != nil) {
                    list[idx!].batch = label
                }
                
            }
            
            self.contactsQueue.async() {
                
                Utils().sendRawContacts(
                    xmppStream: self.xmppController.xmppStream,
                    user: "\(self.userData.phone)",
                    rawContacts: idsArr,
                    id: label)
                
            }
            
        }
        
        self.userData.log("Chunking normalization: \(self.idsToNormalize.count)")
        
    }

    func processWhiteListContactsChunks() {
        
        let numChunk = self.defaultNumChunks
        let idsToWhiteListChunked = self.idsToWhiteListContacts.chunked(by: numChunk)
        
        for (index, idsArr) in idsToWhiteListChunked.enumerated() {
            
//            timeCounter += Double(index) + 1.0
            
            let labelContacts = "batchAff-\(index)"
            
            for (_, id) in idsArr.enumerated() {
                
                let idx = self.idsToWhiteListContacts.firstIndex(where: {$0.phone == id.phone})
                
                if (idx != nil) {
                    self.idsToWhiteListContacts[idx!].batch = labelContacts
                }
            }
            
            
            self.contactsQueue.async() {
        
                Utils().sendAffBatch(
                    xmppStream: self.xmppController.xmppStream,
                    node: "contacts-\(self.userData.phone)",
                    from: "\(self.userData.phone)",
                    users: idsArr,
                    role: "publish-only",
                    id: labelContacts)
                
            }
                
        }
        
    }

    func processWhiteListFeedChunks() {
        
        let numChunk = self.defaultNumChunks
        let idsToWhiteListFeedChunked = self.idsToWhiteListFeed.chunked(by: numChunk)
    
        for (index, idsArr) in idsToWhiteListFeedChunked.enumerated() {
            
            let labelFeed = "batchAffFeed-\(index)"
            
            for (_, id) in idsArr.enumerated() {
                
                let idx = self.idsToWhiteListFeed.firstIndex(where: {$0.phone == id.phone})
                
                if (idx != nil) {
                    self.idsToWhiteListFeed[idx!].batch = labelFeed
                }
            }
            
            
            self.contactsQueue.async() {
                        
                Utils().sendAffBatch(
                    xmppStream: self.xmppController.xmppStream,
                    node: "feed-\(self.userData.phone)",
                    from: "\(self.userData.phone)",
                    users: idsArr,
                    role: "member",
                    id: labelFeed)
            }
                
        }
        
    }
    
    func removeExtraContacts(addressBookContactsStrArr: [String]) -> Int {

        var notFound: [NormContact] = []
        
//        var log = "address book string: \(addressBookContactsStrArr)"
//        log += "\r\n"
//        print(log)
//        self.userData.logging += log
        
        for con in self.contacts {
            
            /* do not use normalized numbers because we are matching contacts to addressBookContacts, which keys off the original number */
            let idx = addressBookContactsStrArr.firstIndex(where: {$0 == con.phone})
            
            /* contact not in addressBook */
            if (idx == nil) {
                let item = NormContact(
                    phone: con.phone,
                    normPhone: con.normPhone,
                    name: con.name,
                    isConnected: con.isConnected,
                    isProcessed: con.isProcessed
                )
                notFound.append(item)
            }
        }
        

        /* find everything that's not found, and send deletes to Core and everywhere else */
        if (notFound.count > 0) {
            var log = "not found in addressBook: \(notFound)"
            log += "\r\n"
            print(log)
            self.userData.logging += log
            
            notFound.forEach { con in
                                      
                /* Note: do not try to remove the affiliations or unsubscribe yet as those nodes could be using a normalized number (or not),
                 * and if we have duplicates in our contacts (ie. 1-415, 415) it could remove them by accident
                 */
                
                self.contacts.removeAll(where: { $0.phone == con.phone } )
                
                let updateItem = con
                self.contactsQueue.async {
                    self.contactsCD.delete(item: updateItem)
                }
                
            }
        }
        
        return notFound.count

    }
}


extension CNContact: Identifiable {
    var name: String {
        var derivedName = ""
        derivedName = [givenName, familyName].filter{ $0.count > 0 }.joined(separator: " ")
        if derivedName == "" {
            derivedName = organizationName
        }
        return derivedName
//        return [givenName, familyName].filter{ $0.count > 0 }.joined(separator: " ")
    }
}


struct BatchId: Identifiable {
    var id = UUID()
    var phone: String = ""
    var normalizedPhone: String = ""
    var name: String = ""
    var batch: String = ""
}

struct NormContact: Identifiable {
    var id = UUID()
    var phone: String
    var normPhone: String = ""
    var name: String
    var isConnected: Bool = false
    var isProcessed: Bool = false
}
