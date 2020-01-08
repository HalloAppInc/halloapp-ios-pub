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

extension Array {

    func chunked(by distance: Int) -> [[Element]] {
        let indicesSequence = stride(from: startIndex, to: endIndex, by: distance)
        let array: [[Element]] = indicesSequence.map {
            let newIndex = $0.advanced(by: distance) > endIndex ? endIndex : $0.advanced(by: distance)
            //let newIndex = self.index($0, offsetBy: distance, limitedBy: self.endIndex) ?? self.endIndex // also works
            return Array(self[$0 ..< newIndex])
        }
        return array
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
    var isWhiteListed: Bool = false
    var isNormalized: Bool = false
    var timeLastChecked: Double
    
    var isMatched: Bool = false // not saved in Core Data, used only for checking
}

class Contacts: ObservableObject {
    
    @Published var contacts: [CNContact] = []
    @Published var error: Error? = nil
    
    @Published var normalizedContacts: [NormContact] = []
    @Published var idsToNormalize: [BatchId] = []
    @Published var idsToWhiteList: [BatchId] = []
    
    var allPhonesString = ""
    var contactHash = ""
    
    var xmpp: XMPP
    var xmppController: XMPPController
    
    private var cancellableSet: Set<AnyCancellable> = []
    
    var store = CNContactStore()
    
    private var sentPreemptiveNormalize = false
    
    func getOwnAffiliations() {
        
        let affiliations = XMLElement(name: "affiliations")
        affiliations.addAttribute(withName: "node", stringValue: "contacts-\(self.xmpp.userData.phone)")

        let pubsub = XMLElement(name: "pubsub")
        pubsub.addAttribute(withName: "xmlns", stringValue: "http://jabber.org/protocol/pubsub#owner")
        pubsub.addChild(affiliations)

        let iq = XMLElement(name: "iq")
        iq.addAttribute(withName: "type", stringValue: "get")
        iq.addAttribute(withName: "from", stringValue: "\(self.xmpp.userData.phone)@s.halloapp.net/iphone")
        iq.addAttribute(withName: "to", stringValue: "pubsub.s.halloapp.net")
        iq.addAttribute(withName: "id", stringValue: "own aff")
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
        iq.addAttribute(withName: "from", stringValue: "\(self.xmpp.userData.phone)@s.halloapp.net/iphone")
        iq.addAttribute(withName: "to", stringValue: "pubsub.s.halloapp.net")
        iq.addAttribute(withName: "id", stringValue: "all aff")
        iq.addChild(pubsub)

        self.xmppController.xmppStream.send(iq)
    }
    
    func getName(phone: String) -> String {
        
        if phone == self.xmpp.userData.phone {
            return "Me"
        }
        
        let idx = self.normalizedContacts.firstIndex(where: {($0.normPhone != "" ? $0.normPhone : $0.phone) == phone})
        
        if (idx == nil) {
            return "Unknown"
        } else {
            return self.normalizedContacts[idx!].name
        }
    }
    
    
        
    func pushAllItems(items: [NormContact]) {
        
        self.normalizedContacts = items
        
        self.normalizedContacts.sort {
            $0.name < $1.name
        }

    }
    
    
    func pushItem(item: NormContact) {
        
        let idx = self.normalizedContacts.firstIndex(where: {$0.phone == item.phone})
        
        if (idx == nil) {
 
            self.normalizedContacts.append(item)
            
            self.normalizedContacts.sort {
                $0.name < $1.name
            }
            
            
            if (!self.isDataPresent(phone: item.phone)) {
                self.createData(item: item)
            }
            
        } else {
//            print("do no insert: \(item.text)")
        }
        
    }

    
    init(xmpp: XMPP) {
//        print("contacts init")
                
        self.xmpp = xmpp
        self.xmppController = self.xmpp.xmppController
        
        
        self.getAllData()
        
        
        store.requestAccess(for: .contacts, completionHandler: { (granted, error) in
            
            if (granted) {
                self.fetch()
            } else {
                // should display something to inform user of changing it in settings
            }
            
        })
        
        
        cancellableSet.insert(
         
            xmppController.didGetAllAffiliations.sink(receiveValue: { iq in

                DispatchQueue.global(qos: .background).async {
                    
                    var localNormalizedContacts: [NormContact] = self.normalizedContacts
                    
                    var affList = Utils().parseAffList(iq)
                    
                    print("Aff: \(affList)")
              
                    for (conIndex, con) in localNormalizedContacts.enumerated() {
                        
                        let targetUser = con.normPhone != "" ? con.normPhone : con.phone
                        let index = affList.firstIndex { $0 == targetUser }
                        
                        if !con.isConnected {
                            
                            /* connect to the other user */
                            if (index != nil) {
                                localNormalizedContacts[conIndex].isConnected = true
                                localNormalizedContacts[conIndex].timeLastChecked = Date().timeIntervalSince1970
                                DispatchQueue.main.async {
                                    self.updateData(item: localNormalizedContacts[conIndex])
                                }

                                self.xmppController.xmppPubSub.subscribe(toNode: "feed-\(targetUser)")
                                self.xmppController.xmppPubSub.retrieveItems(fromNode: "feed-\(targetUser)") // get newly connected user's past feed items
                                
                                /*  redundant whitelisting but useful if the user is new and has > 1k contacts as this will whitelist
                                    these users first
                                 */
                                Utils().sendAff(xmppStream: self.xmppController.xmppStream, node: "contacts-\(self.xmpp.userData.phone)", from: "\(self.xmpp.userData.phone)", user: targetUser, role: "member")
                                Utils().sendAff(xmppStream: self.xmppController.xmppStream, node: "feed-\(self.xmpp.userData.phone)", from: "\(self.xmpp.userData.phone)", user: targetUser, role: "member")
                            
                                self.notifyUser(targetUser)
                                
                            }
                            
                        } else {
                            
                            /* other user have removed you */
                            if (index == nil) {

                                localNormalizedContacts[conIndex].isConnected = false
                                localNormalizedContacts[conIndex].timeLastChecked = Date().timeIntervalSince1970
                                DispatchQueue.main.async {
                                    self.updateData(item: localNormalizedContacts[conIndex])
                                }
                                
                                self.xmppController.xmppPubSub.unsubscribe(fromNode: "feed-\(targetUser)")
                                self.xmppController.xmppPubSub.unsubscribe(fromNode: "contacts-\(targetUser)")
                            }
                            
                        }
                        
                        if (index != nil) {
                            affList.remove(at: index!)
                        }
                    }
                
                    
                    let unprocessed = localNormalizedContacts.filter() { !$0.isNormalized || !$0.isWhiteListed }

                    if unprocessed.count > 0 {
                        print("Unprocessed: \(unprocessed.count)")
                        
                        /*
                            if processing hasn't finished yet, do one extra check on the affiliations so the user
                            doesn't have to wait too long to get connected, if there are still leftover users on the affList
                         */
                        if (unprocessed.count > 0 && !self.sentPreemptiveNormalize && affList.count > 0) {
               
                            var idsArr: [BatchId] = []
                            let label = "batchNorm-9999"
                            
                            for aff in affList {
                                let index = localNormalizedContacts.firstIndex { aff.contains($0.phone) }
                                if (index != nil) {
                                    
                                    var bId = BatchId()
                                    bId.phone = localNormalizedContacts[index!].phone
                                    bId.batch = label
                        
                                    idsArr.append(bId)
                                    DispatchQueue.main.async {
                                        self.idsToNormalize.append(bId)
                                    }
                                }
                            }
                            
                            if (idsArr.count > 0) {
                                
                                Utils().sendRawContacts(
                                    xmppStream: self.xmppController.xmppStream,
                                    user: "\(self.xmpp.userData.phone)",
                                    rawContacts: idsArr,
                                    id: label)
                                
                                
                                DispatchQueue.main.async {
                                    self.sentPreemptiveNormalize = true
                                }
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                    self.getAllAffiliations()
                                }
                                
                            }
                            
                        }
                    }
                    
                        
                    /* get all the items  */
//                    let connected = localNormalizedContacts.filter() { $0.isConnected }
//        
//                    connected.forEach {
//                        let targetUser = $0.normPhone != "" ? $0.normPhone : $0.phone
//                        self.xmppController.xmppPubSub.retrieveItems(fromNode: "feed-\(targetUser)")
//                    }
//                    
//                    
//                    /* get your own items */
//                    self.xmppController.xmppPubSub.retrieveItems(fromNode: "feed-\(self.xmpp.userData.phone)")
                    
    //                self.xmppController.xmppPubSub.retrieveItems(fromNode: "contacts-\(self.xmpp.userData.phone)")
                    
                    
                    /* only do cleanup duty when everything else has been done */
                    if (unprocessed.count == 0) {
                    
    //                    print("Clean Up")
                        
                        /* edge case: currently used only for removing extra affiliations */
                        self.getOwnAffiliations()
                        
                        /*
                            edge case: currently only used for removing subscriptions that user does not have the contact for anymore
                            ie. user have contact A connected, then user removes app and remove contact A, after reinstalling app, user
                            will not have contact A anymore but is still subscribed
                         */
                        self.xmppController.xmppPubSub.retrieveSubscriptions()
                        
                    }
                    
                    DispatchQueue.main.async {
                        self.normalizedContacts = localNormalizedContacts
                    }
                    
                }
                
            })
        )
        
        
        cancellableSet.insert(
         
            xmppController.didGetNewContactsItem.sink(receiveValue: { iq in
                // basically a refresh
                self.getAllAffiliations()
                
                // todo: should also delete everything from list, ie remove users from subscriber lists
                
            })

        )
        
        cancellableSet.insert(
         
            xmppController.didGetSubscriptions.sink(receiveValue: { iq in

                DispatchQueue.global(qos: .background).async {
                    
                    let list = Utils().parseSubsForExtras(iq)
    //                print("parsed subscriptions: \(list)")
                                    
                    for sub in list {
                        
                        if (sub == self.xmpp.userData.phone) {
                            continue
                        }
                        
                        let index = self.normalizedContacts.firstIndex { $0.phone == sub }
                        
                        if index == nil {
                            print("remove extra subscription: \(sub)")
                            
                            self.xmppController.xmppPubSub.unsubscribe(fromNode: "feed-\(sub)")
                            self.xmppController.xmppPubSub.unsubscribe(fromNode: "contacts-\(sub)")

                        }

                    }
                    
                }
            
            })

        )
        
        cancellableSet.insert(
         
            xmppController.didGetOwnAffiliations.sink(receiveValue: { iq in

                DispatchQueue.global(qos: .background).async {
                
                    let affList = Utils().parseOwnAffList(iq)
    //                print("got own affiliations: \(affList)")
                    
                    for aff in affList {
                    
                        let index = self.normalizedContacts.firstIndex {
                            ($0.normPhone != "" ? $0.normPhone : $0.phone) == aff
                        }
                        
                        if index == nil {
                            print("remove extra whitelist: \(aff)")
                            Utils().sendAff(xmppStream: self.xmppController.xmppStream, node: "feed-\(self.xmpp.userData.phone)", from: "\(self.xmpp.userData.phone)", user: aff, role: "none")
                            Utils().sendAff(xmppStream: self.xmppController.xmppStream, node: "contacts-\(self.xmpp.userData.phone)", from: "\(self.xmpp.userData.phone)", user: aff, role: "none")

                        }

                    }
                    
                }
            
            })

        )
        
        /* norm batch */
        cancellableSet.insert(

            xmppController.didGetNormBatch.sink(receiveValue: { iq in

                if let idParts = iq.elementID?.components(separatedBy: "-") {
                   if (idParts[0] == "batchNorm") {

                        let normList = Utils().parseRawContacts(iq)
                    
                        var whiteList: [BatchId] = []
                        var batchLabel = "batchAff-unknown"
                        var batchFeedLabel = "batchAffFeed-unknown"
                    
                        if let batchNum = Int(idParts[1]) {
                            let num = batchNum + 9000
                            batchLabel = "batchAff-\(String(num))"
                            batchFeedLabel = "batchAffFeed-\(String(num))"
                        }
                        
                        for norm in normList {
                            
                            let index = self.normalizedContacts.firstIndex { $0.phone == norm.phone }

                            if index != nil {

//                                    print("normalized: \(norm.phone)")
            
                                self.idsToNormalize.removeAll(where: { $0.phone == norm.phone } )
                                
                                if (norm.normalizedPhone != "") {
                                    self.normalizedContacts[index!].normPhone = norm.normalizedPhone
                                }

                                self.normalizedContacts[index!].isNormalized = true
                                self.updateData(item: self.normalizedContacts[index!])
                       

                                /* after normalizing, send it in to whitelist */
                                var item = BatchId()
                                item.phone = norm.normalizedPhone != "" ? norm.normalizedPhone : norm.phone
                                item.batch = batchLabel
                                whiteList.append(item)
                                
                            }
                               
                        }
                    
                        Utils().sendAffBatch(
                            xmppStream: self.xmppController.xmppStream,
                            node: "contacts-\(self.xmpp.userData.phone)",
                            from: "\(self.xmpp.userData.phone)",
                            users: whiteList,
                            role: "member",
                            id: batchLabel)

                        Utils().sendAffBatch(
                            xmppStream: self.xmppController.xmppStream,
                            node: "feed-\(self.xmpp.userData.phone)",
                            from: "\(self.xmpp.userData.phone)",
                            users: whiteList,
                            role: "member",
                            id: batchFeedLabel)
                    

                        self.idsToWhiteList.append(contentsOf: whiteList)

                       
                   }
                }
                

            })

        )
        
        
        /* aff batch */
        cancellableSet.insert(
         
            xmppController.didGetAffBatch.sink(receiveValue: { iq in

                
                    
                if let idParts = iq.elementID?.components(separatedBy: "-") {
                    if (idParts[0] == "batchAff") {
 
                        print("got \(iq.elementID!)")
                        
                        let connected = self.idsToWhiteList.filter() { $0.batch == iq.elementID! }
                        
                        print("count: \(connected.count)")
//                        print("list: \(self.idsToWhiteList)")
                        
                        connected.forEach { con in
                            
                            let index = self.normalizedContacts.firstIndex {
                                
                                if (!$0.isWhiteListed) {
                                    return ($0.normPhone != "" ? $0.normPhone : $0.phone) == con.phone
                                } else {
                                    return false
                                }
                                
                            }
                            
                            if index != nil {

//                                print("whitelisted: \(con.phone)")
                                
                                self.idsToWhiteList.removeAll(where: { $0.phone == con.phone } )
                                
                                self.normalizedContacts[index!].isWhiteListed = true
                                
                 
                                self.updateData(item: self.normalizedContacts[index!])
                   

                            }
                            
                            
                        }
                        
                        
                    }
                    

                }
                
            })

        )
        
        /* unused */
//        cancellableSet.insert(
//
//            xmppController.didSubscribeToContact.sink(receiveValue: { phone in
//
//                /* do this first so that new users don't have to wait too long to get a feed */
//                self.xmppController.xmppPubSub.subscribe(toNode: "feed-\(phone)") // contact's feed
//                self.xmppController.xmppPubSub.retrieveItems(fromNode: "feed-\(phone)") // get contact's feed items
//
//                let index = self.normalizedContacts.firstIndex { $0.phone == phone }
//
//                if index != nil {
//                    self.normalizedContacts[index!].isConnected = true
//
//                    self.normalizedContacts[index!].timeLastChecked = Date().timeIntervalSince1970
//
//                    self.updateData(item: self.normalizedContacts[index!])
//
//                }
//
//            })
//
//        )
        
        /* unused */
//        cancellableSet.insert(
//
//            xmppController.didNotSubscribeToContact.sink(receiveValue: { phone in
//
//                let index = self.normalizedContacts.firstIndex { $0.phone == phone }
//
//                if index != nil {
//
//                    self.normalizedContacts[index!].isConnected = false
//                    self.normalizedContacts[index!].timeLastChecked = Date().timeIntervalSince1970
//                    self.updateData(item: self.normalizedContacts[index!])
//
//                }
//
//            })
//
//        )
        
        
        
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
    
    
    func notifyUser(_ user: String) {
        
        print("notifyUser: \(user)")
        
        let text = XMLElement(name: "type", stringValue: "newUser")
        let username = XMLElement(name: "user", stringValue: self.xmpp.userData.phone)
        let timestamp = XMLElement(name: "timestamp", stringValue: String(Date().timeIntervalSince1970))

        let root = XMLElement(name: "entry")
        
        root.addChild(username)
        root.addChild(timestamp)
        root.addChild(text)
        
        self.xmppController.xmppPubSub.publish(toNode: "contacts-\(user)", entry: root)
    }
    
    
    func fetch() {
        
        DispatchQueue.global(qos: .background).async {
           
            var localContacts: [CNContact] = []
            
            let keysToFetch = [CNContactGivenNameKey as CNKeyDescriptor,
                               CNContactFamilyNameKey as CNKeyDescriptor,
                               CNContactPhoneNumbersKey as CNKeyDescriptor]
            
            // Get all the containers
            var allContainers: [CNContainer] = []
            
            do {
                allContainers = try self.store.containers(matching: nil)
            } catch {
                print("Error fetching containers")
            }

            for container in allContainers {
                let fetchPredicate = CNContact.predicateForContactsInContainer(withIdentifier: container.identifier)

                do {
                    /* note: if for some reason you have one contact with 4000 phone numbers inside of it, this
                       call will crash silently without throwing, furthermore, opening that contact up on an iPhone
                       will crash the phone also (iPhone 11 pro - ios 13.3)
                       2000 phone numbers work fine
                     */
                    let containerResults = try self.store.unifiedContacts(matching: fetchPredicate, keysToFetch: keysToFetch)

                    localContacts.append(contentsOf: containerResults)
                } catch {
                    print("Error fetching results for container")
                }
            }

            print("Address Book: \(localContacts.count)")
            
//            sleep(20)
            
            var localNormalizedContacts = self.normalizedContacts
            
            self.allPhonesString = ""
            let characterSet = CharacterSet(charactersIn: "01234567890")
            
            var localIdsToNormalize: [BatchId] = []
            var localIdsToWhiteList: [BatchId] = []
            
            var localContactsStr: [String] = []
            

            for c in localContacts {

                /* for users with TrueCaller installed, it'll have a SPAM contact that has a lot of phone numbers */
                if (c.name == "SPAM") {
                    continue
                }

                for con in c.phoneNumbers {

                    let pn = String(con.value.stringValue.unicodeScalars.filter(characterSet.contains))

                    if (pn == self.xmpp.userData.phone) {
                        continue
                    }

                    if (pn.count < 5) {
                        continue
                    }

                    localContactsStr.append(pn)
                    
                    let idx = localNormalizedContacts.firstIndex(where: {$0.phone == pn})

                    if (idx == nil) { // can't find contact
                        
                        let item = NormContact(
                                phone: pn,
                                normPhone: "",
                                name: c.name,
                                isConnected: false,
                                isWhiteListed: false,
                                isNormalized: false,
                                timeLastChecked: Date().timeIntervalSince1970
                            )
                    
                        localNormalizedContacts.append(item)
                                                
                        DispatchQueue.main.async {
                            if (!self.isDataPresent(phone: item.phone)) {
                                self.createData(item: item)
                            }
                        }
                        
//                            print("new normalize \(pn)")
                        localIdsToNormalize.append(BatchId(phone: pn))
                        
                        
                    } else { // found contact
                        
                        /*
                            see if contact has updated info,
                            gotcha: we do allow contacts with no name, just phone number
                        */
                        if localNormalizedContacts[idx!].name != c.name {
       
                            localNormalizedContacts[idx!].name = c.name
                            
                            DispatchQueue.main.async {
                                self.updateData(item: localNormalizedContacts[idx!])
                            }
                        }


                        if (!self.normalizedContacts[idx!].isNormalized) {
//                                print("old normalize \(self.normalizedContacts[idx!].phone)")
                            localIdsToNormalize.append(BatchId(phone: pn))
                        } else {
                        
                            if (!localNormalizedContacts[idx!].isWhiteListed) {
//                                    print("old whitelist \(self.normalizedContacts[idx!].phone)")
                                                                  
                                let nPhone = localNormalizedContacts[idx!].normPhone != "" ? localNormalizedContacts[idx!].normPhone : localNormalizedContacts[idx!].phone
                                localIdsToWhiteList.append(BatchId(phone: nPhone))
                                
                                
                            }
                            
                        }
                        
   
                    }
                }
                
            }
             
            

            let timeAfterNormalizing = self.processNormalizeChunks(localIdsToNormalize)

            /*
                do an extra check AFTER all the normalizations are done
                if there are normalizations
             */
            if (timeAfterNormalizing > 0) {
                DispatchQueue.main.asyncAfter(deadline: .now() + (timeAfterNormalizing + 5)) {
                    self.getAllAffiliations()
                }
            }

            self.processWhiteListChunks(localIdsToWhiteList, timeAfterNormalizing)

            
            self.afterFetch(localContactsStr)
            
            localNormalizedContacts.sort {
                $0.name < $1.name
            }
                
            DispatchQueue.main.async {

                self.normalizedContacts = localNormalizedContacts
                
                /* always do one check first */
                self.getAllAffiliations()
                
            }
            
        }
                
    }
    
    
    func processNormalizeChunks(_ fromList: [BatchId]) -> Double {
        
        if (fromList.count < 1) { return 0.0 }
        
        var list = fromList
        
        let numChunk = 100
        let listChunked = list.chunked(by: numChunk)
        var timeCounter = 0.0
        
        for (index, idsArr) in listChunked.enumerated() {
            
            timeCounter += Double(index) + 2.0
            
            let label = "batchNorm-\(index)"
            
            for (_, id) in idsArr.enumerated() {
                
                let idx = list.firstIndex(where: {$0.phone == id.phone})
                
                if (idx != nil) {
                    list[idx!].batch = label
                }
                
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + timeCounter) {
                
                Utils().sendRawContacts(
                    xmppStream: self.xmppController.xmppStream,
                    user: "\(self.xmpp.userData.phone)",
                    rawContacts: idsArr,
                    id: label)
                
            }
            
        }
        
        DispatchQueue.main.async {
//            self.idsToNormalize.removeAll()
            self.idsToNormalize.append(contentsOf: list)
        }
        
        return timeCounter
    }
    
    
    func processWhiteListChunks(_ fromList: [BatchId], _ timeToStart: Double) {
        
        if (fromList.count < 1) { return}
        
        var list = fromList
        
        let numChunk = 100
        let idsToWhiteListChunked = list.chunked(by: numChunk)
        var timeCounter = timeToStart
        
        for (index, idsArr) in idsToWhiteListChunked.enumerated() {
            
            timeCounter += Double(index) + 2.0
            
            let labelContacts = "batchAff-\(index)"
            let labelFeed = "batchAffFeed-\(index)"
            
            for (_, id) in idsArr.enumerated() {
                
                let idx = list.firstIndex(where: {$0.phone == id.phone})
                
                if (idx != nil) {
                    list[idx!].batch = labelContacts
                }
                
            }
            

            DispatchQueue.main.asyncAfter(deadline: .now() + timeCounter) {
        
                Utils().sendAffBatch(
                    xmppStream: self.xmppController.xmppStream,
                    node: "contacts-\(self.xmpp.userData.phone)",
                    from: "\(self.xmpp.userData.phone)",
                    users: idsArr,
                    role: "member",
                    id: labelContacts)
                
                Utils().sendAffBatch(
                    xmppStream: self.xmppController.xmppStream,
                    node: "feed-\(self.xmpp.userData.phone)",
                    from: "\(self.xmpp.userData.phone)",
                    users: idsArr,
                    role: "member",
                    id: labelFeed)
            }
                
        }
        
        DispatchQueue.main.async {
//            self.idsToWhiteList.removeAll()
            self.idsToWhiteList.append(contentsOf: list)
        }
    }
    
    func afterFetch(_ localContactsStr: [String]) {

        var unmatched: [NormContact] = []
        
        for con in self.normalizedContacts {
            
            /* do not use normPhone because here we are matching Core Data Store to our local storage, which keys off the orig number */
            let idx = localContactsStr.firstIndex(where: {$0 == con.phone})
            
            /* this item is unmatched */
            if (idx == nil) {
                let item = NormContact(
                    phone: con.phone,
                    normPhone: con.normPhone,
                    name: con.name,
                    isConnected: con.isConnected,
                    isWhiteListed: con.isWhiteListed,
                    isNormalized: con.isNormalized,
                    timeLastChecked: con.timeLastChecked,
                    isMatched: con.isMatched
                )
                unmatched.append(item)
            }
            
        }
        
        
        /* find everything that's not matched, and send deletes to Core and everywhere else */
        if (unmatched.count > 0) {
            print("Unmatched: \(unmatched)")
            
            unmatched.forEach { con in
                                      
                let targetUser = con.normPhone != "" ? con.normPhone : con.phone
                
                /* remove contact from whitelist */
                Utils().sendAff(xmppStream: self.xmppController.xmppStream, node: "feed-\(self.xmpp.userData.phone)", from: "\(self.xmpp.userData.phone)", user: targetUser, role: "none")
                Utils().sendAff(xmppStream: self.xmppController.xmppStream, node: "contacts-\(self.xmpp.userData.phone)", from: "\(self.xmpp.userData.phone)", user: targetUser, role: "none")

                /* unsubscribe to contact's lists */
                if (con.isConnected) {
                    self.xmppController.xmppPubSub.unsubscribe(fromNode: "feed-\(targetUser)")
                    self.xmppController.xmppPubSub.unsubscribe(fromNode: "contacts-\(targetUser)")
                }
                
                
                DispatchQueue.main.async {
                    self.deleteData(item: con)
                    self.normalizedContacts.removeAll(where: { $0.phone == con.phone } )
                }
                
            }
        }

        
        print("Contacts: \(self.normalizedContacts.count)")
        
    }
    
    
    func createData(item: NormContact) {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        let managedContext = appDelegate.persistentContainer.viewContext
        
        let userEntity = NSEntityDescription.entity(forEntityName: "ContactsCore", in: managedContext)!
        
        let obj = NSManagedObject(entity: userEntity, insertInto: managedContext)
        
        obj.setValue(item.phone, forKeyPath: "phone")
        obj.setValue(item.normPhone, forKeyPath: "normPhone")
        
        obj.setValue(item.name, forKeyPath: "name")
        
        obj.setValue(item.isConnected, forKeyPath: "isConnected")
        obj.setValue(item.isWhiteListed, forKeyPath: "isWhiteListed")
        obj.setValue(item.isNormalized, forKeyPath: "isNormalized")
        
        obj.setValue(item.timeLastChecked, forKeyPath: "timeLastChecked")
        
        do {
            try managedContext.save()
        } catch let error as NSError {
            print("could not save. \(error), \(error.userInfo)")
        }
    }
    

    func updateData(item: NormContact) {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        
        let managedContext = appDelegate.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "ContactsCore")
        
        fetchRequest.predicate = NSPredicate(format: "phone == %@", item.phone)
        
        do {
            let result = try managedContext.fetch(fetchRequest)

            if (result.count < 1) {
                return
            }
            
            let objectUpdate = result[0] as! NSManagedObject
            objectUpdate.setValue(item.phone, forKey: "phone")
            objectUpdate.setValue(item.normPhone, forKey: "normPhone")
            objectUpdate.setValue(item.name, forKey: "name")
            
            objectUpdate.setValue(item.isConnected, forKey: "isConnected")
            objectUpdate.setValue(item.isWhiteListed, forKey: "isWhiteListed")
            objectUpdate.setValue(item.isNormalized, forKey: "isNormalized")
            objectUpdate.setValue(item.timeLastChecked, forKey: "timeLastChecked")
            
            do {
                try managedContext.save()
            } catch {
                print(error)
            }
            
        } catch  {
            print("failed")
        }
    }
    
    
    func deleteData(item: NormContact) {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        
        let managedContext = appDelegate.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "ContactsCore")
        
        fetchRequest.predicate = NSPredicate(format: "phone == %@", item.phone)
        
        do {
            let result = try managedContext.fetch(fetchRequest)

            if (result.count < 1) {
                return
            }
            
            let objectToDelete = result[0] as! NSManagedObject
            managedContext.delete(objectToDelete)
            
            do {
                try managedContext.save()
            } catch {
                print(error)
            }
            
        } catch  {
            print("failed")
        }
    }
    
    func getAllData() {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        
        let managedContext = appDelegate.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "ContactsCore")
        
        fetchRequest.sortDescriptors = [NSSortDescriptor.init(key: "name", ascending: false)]
        
        do {
            let result = try managedContext.fetch(fetchRequest)
            
            var contactsArr: [NormContact] = []
            
            for data in result as! [NSManagedObject] {
                var item = NormContact(
                    phone: data.value(forKey: "phone") as! String,
                    name: data.value(forKey: "name") as! String,
                    
                    isConnected: data.value(forKey: "isConnected") as! Bool,
                    timeLastChecked: data.value(forKey: "timeLastChecked") as! Double
                )
                
                if let normPhone = data.value(forKey: "normPhone") as? String {
                    item.normPhone = normPhone
                }
                
                if let isWhiteListed = data.value(forKey: "isWhiteListed") as? Bool {
                    item.isWhiteListed = isWhiteListed
                }

                if let isNormalized = data.value(forKey: "isNormalized") as? Bool {
                    item.isNormalized = isNormalized
                }
                
                contactsArr.append(item)

            }
            
            self.pushAllItems(items: contactsArr)
            
        } catch  {
            print("failed")
        }
    }
    
    func isDataPresent(phone: String) -> Bool {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            return false
        }
        
        let managedContext = appDelegate.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "ContactsCore")
        
        fetchRequest.predicate = NSPredicate(format: "phone == %@", phone)
        
        do {
            let result = try managedContext.fetch(fetchRequest)
            
            if (result.count > 0) {
                return true
            } else {

                return false
            }
            
        } catch  {
            print("failed")
        }
        
        return false
    }
    
    
    func getData(phone: String) -> Bool {
         
         guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
             return false
         }
         
         let managedContext = appDelegate.persistentContainer.viewContext
         
         let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "ContactsCore")
         
         fetchRequest.predicate = NSPredicate(format: "phone == %@", phone)
         
         do {
             let result = try managedContext.fetch(fetchRequest)
             
             for data in result as! [NSManagedObject] {
                 var item = NormContact(
                     phone: data.value(forKey: "phone") as! String,
                     name: data.value(forKey: "name") as! String,
                     
                     isConnected: data.value(forKey: "isConnected") as! Bool,
                     timeLastChecked: data.value(forKey: "timeLastChecked") as! Double
                 )
                 
                 if let normPhone = data.value(forKey: "normPhone") as? String {
                     item.normPhone = normPhone
                 }
                 
                 if let isWhiteListed = data.value(forKey: "isWhiteListed") as? Bool {
                     item.isWhiteListed = isWhiteListed
                 }

                 if let isNormalized = data.value(forKey: "isNormalized") as? Bool {
                     item.isNormalized = isNormalized
                 }
                 
             }
             
         } catch  {
             print("failed")
         }
         
         return false
     }
    
}

extension CNContact: Identifiable {
    var name: String {
        return [givenName, familyName].filter{ $0.count > 0}.joined(separator: " ")
    }
}
