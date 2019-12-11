//
//  FeedModel.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/1/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Foundation
import SwiftUI
import Combine

import XMPPFramework

class FeedData: ObservableObject {
    
    @Published var feedDataItems : [FeedDataItem] = []
    
    var xmpp: XMPP
    var xmppController: XMPPController
    
    private var cancellableSet: Set<AnyCancellable> = []
    
    init(xmpp: XMPP) {
        
        self.xmpp = xmpp
        self.xmppController = self.xmpp.xmppController

        self.getAllData()

//        self.feedDataItems = [
//            FeedDataItem(username: "Robert",
//                          imageUrl: "https://cdn.pixabay.com/photo/2015/12/01/20/28/road-1072823_960_720.jpg",
//                          userImageUrl: "https://cdn.pixabay.com/photo/2016/11/18/19/07/happy-1836445_1280.jpg",
//                          text: ""),
//            FeedDataItem(username: "Jessica",
//                          imageUrl: "https://cdn.pixabay.com/photo/2019/09/24/01/05/flower-4499972_640.jpg",
//                          userImageUrl: "https://cdn.pixabay.com/photo/2018/01/25/14/12/nature-3106213_1280.jpg",
//                          text: ""),
//            FeedDataItem(username: "Timothy",
//                          imageUrl: "https://cdn.pixabay.com/photo/2019/09/21/06/59/dog-4493182_640.jpg",
//                          userImageUrl: "https://cdn.pixabay.com/photo/2012/05/29/00/43/car-49278_1280.jpg",
//                          text: ""),
//            FeedDataItem(username: "Ashley",
//                          imageUrl: "https://cdn.pixabay.com/photo/2019/09/25/15/12/chapel-4503926_640.jpg",
//                          userImageUrl: "https://cdn.pixabay.com/photo/2016/11/23/17/25/beach-1853939_1280.jpg",
//                          text: "")
//        ]

//        self.feedDataItems.forEach({
//            let c = $0.objectWillChange.sink(receiveValue: {
//                self.firstItemId = self.feedDataItems[0].id.uuidString
//                self.objectWillChange.send()
//
//            })
//
//            self.cancellableSet.insert(c)
//        })
        
        
        /* getting feed items */
        cancellableSet.insert(
            
            xmppController.didChangeFeedItem.sink(receiveValue: { value in
 
                let textItem = Utils().parseFeedItem(value)
                
                self.pushItem(item: textItem)
                
                // self.createData(item: item)

            })
       
        )
        
      
        /* getting the entire list of items back */
        cancellableSet.insert(
           
            xmppController.didGetItems.sink(receiveValue: { value in
                
                var textItem = Utils().parseListItems(value)
               
                textItem.sort {
                    $0.timestamp > $1.timestamp
                }
                
                for item in textItem {
                    self.pushItem(item: item)
                }
                
               // self.createData(item: item)

           })

        )
        
    }
    
    
    func pushItem(item: FeedDataItem) {
        
        let idx = self.feedDataItems.firstIndex(where: {$0.itemId == item.itemId})
        
        if (idx == nil) {
            
            let c = item.didChange.sink(receiveValue: {
                self.objectWillChange.send()
                self.updateImageData(itemId: item.itemId, image: item.image)
            })
            self.cancellableSet.insert(c)
            
            if item.imageUrl != "" && item.image.size.width == 0 {
                item.loadImage()
            }

            // note: 15 items is the max before there's a slight UI (in milliseconds) slowdown in rendering the view
            self.feedDataItems.insert(item, at: 0)
            
            self.feedDataItems.sort {
                $0.timestamp > $1.timestamp
            }
                        
            if (!self.isDataPresent(itemId: item.itemId)) {
                self.createData(item: item)
            }
            
            
        } else {
//            print("do no insert: \(item.text)")
        }
        
        
    }
    
    
    func postText(_ user: String, _ text: String, _ imageUrl: String) {
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
    
    
    func sendMessage(text: String) {
        print("sendMessage: " + text)
        let user = XMPPJID(string: "4155553695@s.halloapp.net")
        let msg = XMPPMessage(type: "chat", to: user)
        msg.addBody(text)
        self.xmppController.xmppStream.send(msg)


      /* storing private data */
        
//        let item = XMLElement(name: "item", stringValue: "Rebecca")

//        let wrapper = XMLElement(name: "list")
//        wrapper.addAttribute(withName: "xmlns", stringValue: "feed:disallow")
////        wrapper.addChild(item)
//
//        let query = XMLElement(name: "query")
//        query.addAttribute(withName: "xmlns", stringValue: "jabber:iq:private")
//        query.addChild(wrapper)
//
//        let iq = XMLElement(name: "iq")
//        iq.addAttribute(withName: "type", stringValue: "set")
//        iq.addAttribute(withName: "id", stringValue: "1")
//        iq.addChild(query)
//        print("sending: \(iq)")
//        self.xmppController.xmppStream.send(iq)
        
        
        // get private data
//        let wrapper = XMLElement(name: "list")
//        wrapper.addAttribute(withName: "xmlns", stringValue: "feed:disallow")
//
//        let query = XMLElement(name: "query")
//        query.addAttribute(withName: "xmlns", stringValue: "jabber:iq:private")
//
//        query.addChild(wrapper)
//
//        let iq = XMLElement(name: "iq")
//        iq.addAttribute(withName: "type", stringValue: "get")
//        iq.addAttribute(withName: "id", stringValue: "1")
//        iq.addChild(query)
//        print("sending: \(iq)")
//        self.xmppController.xmppStream.send(iq)

        // let user2 = XMPPJID(string: "14154121848@s.halloapp.net")
        // self.xmppController.xmppRoster.addUser(user2!, withNickname: nil)
        
//        if let user2 = XMPPJID(string: "14154121848@s.halloapp.net")
//        {
//            self.xmppController.xmppRoster.addUser(user2)
//        }
        
        
    }
    
//   func getRoster() {
//        print("getRoster")
//        let user = XMPPJID(string: "14088922686@s.halloapp.net")
//
//        self.xmppController.xmppStream.send(msg)
//    }
    
//    func addEntryToRoster(id: String) {
//
//    }
    
    
    
 
    func createData(item: FeedDataItem) {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        let managedContext = appDelegate.persistentContainer.viewContext
        
        let userEntity = NSEntityDescription.entity(forEntityName: "FeedCore", in: managedContext)!
        
        let obj = NSManagedObject(entity: userEntity, insertInto: managedContext)
        obj.setValue(item.itemId, forKeyPath: "itemId")
        obj.setValue(item.username, forKeyPath: "username")
        obj.setValue(item.userImageUrl, forKeyPath: "userImageUrl")
        obj.setValue(item.imageUrl, forKeyPath: "imageUrl")
        obj.setValue(item.timestamp, forKeyPath: "timestamp")
        obj.setValue(item.text, forKeyPath: "text")
        
        
        do {
            try managedContext.save()
        } catch let error as NSError {
            print("could not save. \(error), \(error.userInfo)")
        }
    }
    

    func updateImageData(itemId: String, image: UIImage) {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        
        let managedContext = appDelegate.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FeedCore")
        fetchRequest.predicate = NSPredicate(format: "itemId == %@", itemId)
        
        do {
            let result = try managedContext.fetch(fetchRequest)
            
            let obj = result[0] as! NSManagedObject
            
            let data = image.jpegData(compressionQuality: 1.0)
            
            if data != nil {
                obj.setValue(data, forKeyPath: "imageBlob")
            }
            
        
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
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FeedCore")
        
        fetchRequest.sortDescriptors = [NSSortDescriptor.init(key: "timestamp", ascending: false)]
        
        do {
            let result = try managedContext.fetch(fetchRequest)
            
            for data in result as! [NSManagedObject] {
                let item = FeedDataItem(
                    itemId: data.value(forKey: "itemId") as! String,
                    username: data.value(forKey: "username") as! String,
                    imageUrl: data.value(forKey: "imageUrl") as! String,
                    userImageUrl: data.value(forKey: "userImageUrl") as! String,
                    text: (data.value(forKey: "text") as? String) ?? "",
                    timestamp: data.value(forKey: "timestamp") as! Double
                )
                
                if let imageData = data.value(forKey: "imageBlob") as? Data {
                    if let imageData2 = UIImage(data: imageData) {
                        item.image = imageData2
                    }
                }
                
                self.pushItem(item: item)

            }
            
        } catch  {
            print("failed")
        }
    }
    
    func isDataPresent(itemId: String) -> Bool {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            return false
        }
        
        let managedContext = appDelegate.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FeedCore")
        
        fetchRequest.predicate = NSPredicate(format: "itemId == %@", itemId)
        
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


class FeedDataItem: Identifiable, ObservableObject, Equatable {
    
    var id = UUID()
    
    var itemId: String
    
    var username: String
    var userImageUrl: String
    
    var text: String
    
    var timestamp: Double = 0
    
    @Published var userImage: UIImage = UIImage()
    
    var imageUrl: String
    
    @Published var image: UIImage = UIImage()
    
    @ObservedObject var imageLoader: ImageLoader = ImageLoader()
    @ObservedObject var userImageLoader: ImageLoader = ImageLoader()
    
    var didChange = PassthroughSubject<Void, Never>()
    private var cancellableSet: Set<AnyCancellable> = []
    
    init(   itemId: String = "",
            username: String = "",
            imageUrl: String = "",
            userImageUrl: String = "",
            text: String = "",
            timestamp: Double = 0) {
        
        self.itemId = itemId
        self.username = username
        self.userImageUrl = userImageUrl
        self.imageUrl = imageUrl
        self.text = text
        self.timestamp = timestamp
    }
    
    static func == (lhs: FeedDataItem, rhs: FeedDataItem) -> Bool {
        return lhs.id == rhs.id
    }
    
    func loadImage() {
        if (self.imageUrl != "") {
            imageLoader = ImageLoader(urlString: self.imageUrl)
            cancellableSet.insert(
                imageLoader.didChange.sink(receiveValue: { [weak self] _ in
                    guard let self = self else { return }
                    self.image = UIImage(data: self.imageLoader.data) ?? UIImage()
                    
                    self.didChange.send()
                    
                })
            )
        }
    }
    
    func loadUserImage() {
        if (self.userImageUrl != "") {
            userImageLoader = ImageLoader(urlString: self.userImageUrl)
            cancellableSet.insert(
                userImageLoader.didChange.sink(receiveValue: { [weak self] _ in
                    guard let self = self else { return }
                    self.userImage = UIImage(data: self.userImageLoader.data) ?? UIImage()
                    
                    self.didChange.send()
                })
            )
        }
    }
    
}


