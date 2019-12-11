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
    var batch: String = ""
}

struct NormContact: Identifiable {
    var id = UUID()
    
    var name: String
    var phone: String
    var isConnected: Bool = false
    var isWhiteListed: Bool = false
    var timeLastChecked: Double
    
    var isMatched: Bool = false // not saved in Core Data, used only for checking
}

class Contacts: ObservableObject {
    
    @Published var contacts: [CNContact] = []
    @Published var error: Error? = nil
    
    @Published var normalizedContacts: [NormContact] = []
    @Published var idsToWhiteList: [BatchId] = []
    
    var allPhonesString = ""
    var contactHash = ""
    
    var xmpp: XMPP
    var xmppController: XMPPController
    
    private var cancellableSet: Set<AnyCancellable> = []
    
    var store = CNContactStore()
    
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
        
        let idx = self.normalizedContacts.firstIndex(where: {$0.phone == phone})
        
        if (idx == nil) {
            return "Unknown"
        } else {
            return self.normalizedContacts[idx!].name
        }
    }
    
    func pushItem(item: NormContact) {
        
        let idx = self.normalizedContacts.firstIndex(where: {$0.phone == item.phone})
        
        if (idx == nil) {
 
            self.normalizedContacts.append(item)
            
            self.normalizedContacts.sort {
                $0.name > $1.name
            }
            
            
            if (!self.isDataPresent(phone: item.phone)) {
                self.createData(item: item)
            }
            
        } else {
//            print("do no insert: \(item.text)")
        }
        
        
    }
    

    
    init(xmpp: XMPP) {
        
        print("contacts init")
        
        self.xmpp = xmpp
        self.xmppController = self.xmpp.xmppController
        
        self.getAllData()
        
        store.requestAccess(for: .contacts, completionHandler: { (granted, error) in
            
            if (granted) {
//                Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { (_) in
                    self.fetch()
//                }
            } else {
                // should display something to inform user of changing it in settings
            }
            
        })
        
        
        cancellableSet.insert(
         
            xmppController.didGetAllAffiliations.sink(receiveValue: { iq in

                /* reconcile contacts with others contacts */
                let affList = Utils().parseAffList(iq)
                
                print("got affiliations: \(affList)")
                
                for (conIndex, con) in self.normalizedContacts.enumerated() {
                    
                    let index = affList.firstIndex { $0 == con.phone }
                    
                    if !con.isConnected {
                        
                        /* connect to the other user */
                        if (index != nil) {
                            self.normalizedContacts[conIndex].isConnected = true
                            self.normalizedContacts[conIndex].timeLastChecked = Date().timeIntervalSince1970
                            
                            self.updateData(item: self.normalizedContacts[conIndex])
                            self.normalizedContacts[conIndex].isConnected = true
                            self.normalizedContacts[conIndex].timeLastChecked = Date().timeIntervalSince1970
                            
                            self.xmppController.xmppPubSub.subscribe(toNode: "feed-\(con.phone)")
                            
                            /* do this first so the other user does not have to wait */
                            Utils().sendAff(xmppStream: self.xmppController.xmppStream, node: "contacts-\(self.xmpp.userData.phone)", from: "\(self.xmpp.userData.phone)", user: con.phone, role: "member")
                            Utils().sendAff(xmppStream: self.xmppController.xmppStream, node: "feed-\(self.xmpp.userData.phone)", from: "\(self.xmpp.userData.phone)", user: con.phone, role: "member")
                        
                        }
                        
                    } else {
                        
                        /* other user have removed you */
                        if (index == nil) {

                            self.normalizedContacts[conIndex].isConnected = false
                            self.normalizedContacts[conIndex].timeLastChecked = Date().timeIntervalSince1970
                            self.updateData(item: self.normalizedContacts[conIndex])
                            
                            self.xmppController.xmppPubSub.unsubscribe(fromNode: "feed-\(con.phone)")
                            self.xmppController.xmppPubSub.unsubscribe(fromNode: "contacts-\(con.phone)")
                        }
                        
                    }
                    
                }

                
                
                /* get all the items  */
                let connected = self.normalizedContacts.filter() { $0.isConnected }
                connected.forEach {
                    self.xmppController.xmppPubSub.retrieveItems(fromNode: "feed-\($0.phone)")
                }
                
                /* get your own items */
                self.xmppController.xmppPubSub.retrieveItems(fromNode: "feed-\(self.xmpp.userData.phone)")
                
            })

        )
        

        cancellableSet.insert(
         
            xmppController.didGetIq.sink(receiveValue: { iq in

                if let idParts = iq.elementID?.components(separatedBy: "-") {
                    if (idParts[0] == "batchAff") {
 
                        print("got \(iq.elementID!)")
                        
                        let connected = self.idsToWhiteList.filter() { $0.batch == iq.elementID! }
                        
                        print("count: \(connected.count)")
                        
                        connected.forEach { con in
                            
                            let index = self.normalizedContacts.firstIndex { $0.phone == con.phone }
                            
                            if index != nil {

                                print("whitelisted: \(con.phone)")
                                
                                self.idsToWhiteList.removeAll(where: { $0.phone == con.phone } )
                                
                                self.normalizedContacts[index!].isWhiteListed = true
                                self.updateData(item: self.normalizedContacts[index!])
                                
                            }
                            
                            
                        }
                        
                    }
                }


                
            })

        )
        
        cancellableSet.insert(
         
            xmppController.didSubscribeToContact.sink(receiveValue: { phone in

                /* do this first so that new users don't have to wait too long to get a feed */
                self.xmppController.xmppPubSub.subscribe(toNode: "feed-\(phone)") // contact's feed
                self.xmppController.xmppPubSub.retrieveItems(fromNode: "feed-\(phone)") // get contact's feed items
                
                let index = self.normalizedContacts.firstIndex { $0.phone == phone }
                
                if index != nil {
                    self.normalizedContacts[index!].isConnected = true
                    
                    self.normalizedContacts[index!].timeLastChecked = Date().timeIntervalSince1970
                    
                    self.updateData(item: self.normalizedContacts[index!])
                    
                }
                
            })

        )
        
        cancellableSet.insert(
         
            xmppController.didNotSubscribeToContact.sink(receiveValue: { phone in

                let index = self.normalizedContacts.firstIndex { $0.phone == phone }
                
                if index != nil {
                    
                    self.normalizedContacts[index!].isConnected = false
                    self.normalizedContacts[index!].timeLastChecked = Date().timeIntervalSince1970
                    self.updateData(item: self.normalizedContacts[index!])
                    
                }
                
            })

        )

    }


    func postActive(_ user: String, _ text: String, _ imageUrl: String) {
        print("postText: " + text)
        
        let text = XMLElement(name: "text", stringValue: text)
        let username = XMLElement(name: "username", stringValue: self.xmpp.userData.phone)
        let imageUrl = XMLElement(name: "imageUrl", stringValue: imageUrl)
        let userImageUrl = XMLElement(name: "userImageUrl", stringValue: "")
        let timestamp = XMLElement(name: "timestamp", stringValue: String(Date().timeIntervalSince1970))

        let root = XMLElement(name: "entry")
        
        root.addChild(username)
        root.addChild(userImageUrl)
        root.addChild(imageUrl)
        root.addChild(timestamp)
        root.addChild(text)
        
        self.xmppController.xmppPubSub.publish(toNode: "feed-\(user)", entry: root)
                
    }
    
    
    func fetch() {
        print("fetch contacts")
        
        DispatchQueue.global(qos: .background).async {
           
            var localContacts: [CNContact] = []
            
            let keysToFetch = [CNContactGivenNameKey as CNKeyDescriptor,
                               CNContactFamilyNameKey as CNKeyDescriptor,
                               CNContactImageDataAvailableKey as CNKeyDescriptor,
                               CNContactImageDataKey as CNKeyDescriptor,
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
                    let containerResults = try self.store.unifiedContacts(matching: fetchPredicate, keysToFetch: keysToFetch)
                    localContacts.append(contentsOf: containerResults)
                } catch {
                    print("Error fetching results for container")
                }
            }
                  
        
            DispatchQueue.main.async {
        
                self.allPhonesString = ""
                let characterSet = CharacterSet(charactersIn: "01234567890")
                
                self.idsToWhiteList.removeAll()

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

                        let idx = self.normalizedContacts.firstIndex(where: {$0.phone == pn})

                        if (idx == nil) {

                            self.pushItem(item: NormContact(
                                    name: c.name,
                                    phone: pn,
                                    isConnected: false,
                                    isWhiteListed: false,
                                    timeLastChecked: Date().timeIntervalSince1970,
                                    isMatched: true
                                )
                            )

                            print("new whitelist \(pn)")
                            self.idsToWhiteList.append(BatchId(phone: pn))
                            
                        } else {

                            self.normalizedContacts[idx!].isMatched = true

                            // see if contact has updated info
                            if self.normalizedContacts[idx!].name != c.name {
                                self.normalizedContacts[idx!].name = c.name
                                self.updateData(item: self.normalizedContacts[idx!])
                            }

                            // if contact is not connected, check
                            if !self.normalizedContacts[idx!].isConnected {
                                if (!self.normalizedContacts[idx!].isWhiteListed) {
                                    print("old whitelist \(self.normalizedContacts[idx!].phone)")
                                    self.idsToWhiteList.append(BatchId(phone: pn))
                                }
                            }
                        }
                    }
                }
                
                
//                for n in 1...5000 {
//                    self.idsToWhiteList.append(BatchId(phone: String(n)))
//                }
                
                let numChunk = 50
                let idsToWhiteListChunked = self.idsToWhiteList.chunked(by: numChunk)
                var timeCounter = 0.0
                
                for (index, idsArr) in idsToWhiteListChunked.enumerated() {
                    
                    timeCounter += Double(index) + 2.0
                    DispatchQueue.main.asyncAfter(deadline: .now() + timeCounter) {

                        let labelContacts = "batchAff-\(index)"
                        let labelFeed = "batchAffFeed-\(index)"
                        
                        for (_, id) in idsArr.enumerated() {
                            
                            let idx = self.idsToWhiteList.firstIndex(where: {$0.phone == id.phone})
                            
                            if (idx != nil) {
                                self.idsToWhiteList[idx!].batch = labelContacts
                            }
                            
                        }
                        
                        
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

                self.getAllAffiliations()
                
                /* find everything that's not matched, and send deletes to Core and everywhere else */
                let unmatched = self.normalizedContacts.filter() { !$0.isMatched }
                               
                unmatched.forEach {
                                                
                    /* remove contact from whitelist */
                    Utils().sendAff(xmppStream: self.xmppController.xmppStream, node: "feed-\(self.xmpp.userData.phone)", from: "\(self.xmpp.userData.phone)", user: $0.phone, role: "none")
                    Utils().sendAff(xmppStream: self.xmppController.xmppStream, node: "contacts-\(self.xmpp.userData.phone)", from: "\(self.xmpp.userData.phone)", user: $0.phone, role: "none")

                    /* unsubscribe to contact's lists */
                    if ($0.isConnected) {
                        self.xmppController.xmppPubSub.unsubscribe(fromNode: "feed-\($0.phone)")
                        self.xmppController.xmppPubSub.unsubscribe(fromNode: "contacts-\($0.phone)")
                    }
                    
                    self.deleteData(item: $0)
                    
                }
                
                self.normalizedContacts.removeAll(where: { !$0.isMatched } )
                
                
                
                
                print("Contacts: \(self.normalizedContacts.count)")
                

            }
        
        }
                
    }
    
    func createData(item: NormContact) {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        let managedContext = appDelegate.persistentContainer.viewContext
        
        let userEntity = NSEntityDescription.entity(forEntityName: "ContactsCore", in: managedContext)!
        
        let obj = NSManagedObject(entity: userEntity, insertInto: managedContext)
        obj.setValue(item.name, forKeyPath: "name")
        obj.setValue(item.phone, forKeyPath: "phone")
        obj.setValue(item.timeLastChecked, forKeyPath: "timeLastChecked")
        obj.setValue(item.isConnected, forKeyPath: "isConnected")
        obj.setValue(item.isWhiteListed, forKeyPath: "isWhiteListed")
        
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
            objectUpdate.setValue(item.name, forKey: "name")
            objectUpdate.setValue(item.phone, forKey: "phone")
            objectUpdate.setValue(item.isConnected, forKey: "isConnected")
            objectUpdate.setValue(item.timeLastChecked, forKey: "timeLastChecked")
            objectUpdate.setValue(item.isWhiteListed, forKey: "isWhiteListed")
            
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
            
            for data in result as! [NSManagedObject] {
                var item = NormContact(
                    name: data.value(forKey: "name") as! String,
                    phone: data.value(forKey: "phone") as! String,
                    isConnected: data.value(forKey: "isConnected") as! Bool,
                    timeLastChecked: data.value(forKey: "timeLastChecked") as! Double
                )
                
                
                if let isListed = data.value(forKey: "isWhiteListed") as? Bool {
                    item.isWhiteListed = isListed
                }
                
                self.pushItem(item: item)

            }
            
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
    
    
}

extension CNContact: Identifiable {
    var name: String {
        return [givenName, familyName].filter{ $0.count > 0}.joined(separator: " ")
    }
}
