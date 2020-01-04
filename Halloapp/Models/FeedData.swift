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
    @Published var feedCommentItems : [FeedCommentItem] = []
    
    var xmpp: XMPP
    var xmppController: XMPPController
    
    private var cancellableSet: Set<AnyCancellable> = []
    
    init(xmpp: XMPP) {
        
        self.xmpp = xmpp
        self.xmppController = self.xmpp.xmppController

        self.getAllData()
        
        self.getAllComments()

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
            
            xmppController.didGetNewFeedItem.sink(receiveValue: { value in
//
//                let textItem = Utils().parseFeedItem(value)
//
//                self.pushItem(item: textItem)

                let event = value.element(forName: "event")
                let (feedDataItems, feedCommentItems)  = Utils().parseFeedItems(event)
                 
                 for item in feedDataItems {
                     self.pushItem(item: item)
                 }
                
                for item in feedCommentItems {
                    self.insertComment(item: item)
                }

            })
       
        )
        
      
        /* getting the entire list of items back */
        cancellableSet.insert(
           
            xmppController.didGetFeedItems.sink(receiveValue: { value in
                
//                var textItem = Utils().parseFeedItems(value)
//
//                textItem.sort {
//                    $0.timestamp > $1.timestamp
//                }
//
//                for item in textItem {
//                    self.pushItem(item: item)
//                }

                let pubsub = value.element(forName: "pubsub")
                var (feedDataItems, feedCommentItems) = Utils().parseFeedItems(pubsub)

                feedDataItems.sort {
                    $0.timestamp > $1.timestamp
                }

                for item in feedDataItems {
                    self.pushItem(item: item)
                }
                
                for item in feedCommentItems {
                    self.insertComment(item: item)
                }

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
                
                let a = $0
                let b = $1
                
                var at = Int(a.timestamp)
                var bt = Int(b.timestamp)
                
                let current = Int(Date().timeIntervalSince1970)
            
                if current - at < 0 {
                    at = at/1000
                }
                
                if current - bt < 0 {
                    bt = bt/1000
                }
                
                return at > bt
            }
                        
            if (!self.isDataPresent(itemId: item.itemId)) {
                self.createData(item: item)
            }
            
            
        } else {
//            print("do no insert: \(item.text)")
        }
        
        
    }
    
    // Inserts the comments into the list and into CoreData.
    func insertComment(item: FeedCommentItem) {
       if let idx = self.feedCommentItems.firstIndex(where: {$0.commentItemId == item.commentItemId}) {
            print ("Failed to insert comment: \(item.commentItemId), \(self.feedCommentItems[idx].commentItemId)")
        } else {
            self.feedCommentItems.insert(item, at: 0)
            if (!self.isCommentPresent(commentId: item.commentItemId)) {
                self.createComment(item: item)
            } else {
                print ("Comment is already present in coredata with same id: \(item.commentItemId)")
            }
        }
    }
    
    // Publishes the post to the user's feed pubsub node.
    func postText(_ user: String, _ text: String, _ imageUrl: String) {
        print("postText: " + text)
        
        let text = XMLElement(name: "text", stringValue: text)
        let username = XMLElement(name: "username", stringValue: self.xmpp.userData.phone)
        let imageUrl = XMLElement(name: "imageUrl", stringValue: imageUrl)
        let userImageUrl = XMLElement(name: "userImageUrl", stringValue: "")
        let timestamp = XMLElement(name: "timestamp", stringValue: String(Date().timeIntervalSince1970))
        
        let childroot = XMLElement(name: "feedpost")
        let mainroot = XMLElement(name: "entry")
        
        childroot.addChild(username)
        childroot.addChild(userImageUrl)
        childroot.addChild(imageUrl)
        childroot.addChild(timestamp)
        childroot.addChild(text)
        
        mainroot.addChild(childroot)
        print ("Final pubsub payload: \(mainroot)")
        self.xmppController.xmppPubSub.publish(toNode: "feed-\(user)", entry: mainroot)
                
    }
    
    // Publishes the comment 'text' on post 'feedItemId' to the user 'postUser' feed pubsub node.
    func postComment(_ feedItemId: String, _ postUser: String, _ text: String) {
        print("postComment: " + text)
        
        let text = XMLElement(name: "text", stringValue: text)
        let feedItem = XMLElement(name: "feedItemId", stringValue: feedItemId)
        let username = XMLElement(name: "username", stringValue: self.xmpp.userData.phone)
        let userImageUrl = XMLElement(name: "userImageUrl", stringValue: "")
        let timestamp = XMLElement(name: "timestamp", stringValue: String(Date().timeIntervalSince1970))

        let mainroot = XMLElement(name: "entry")
        let childroot = XMLElement(name: "comment")
        
        childroot.addChild(username)
        childroot.addChild(userImageUrl)
        childroot.addChild(feedItem)
        childroot.addChild(timestamp)
        childroot.addChild(text)
    
        mainroot.addChild(childroot)
        print ("Final pubsub payload: \(mainroot)")
        self.xmppController.xmppPubSub.publish(toNode: "feed-\(postUser)", entry: mainroot)
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
    
    // Retrieves all the comments from the database.
    func getAllComments() {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        let managedContext = appDelegate.persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FeedComments")
        fetchRequest.sortDescriptors = [NSSortDescriptor.init(key: "timestamp", ascending: false)]
        do {
            let result = try managedContext.fetch(fetchRequest)
            for data in result as! [NSManagedObject] {
                let item = FeedCommentItem(commentItemId: data.value(forKey: "commentId") as! String,
                                           feedItemId: data.value(forKey: "feedItemId") as! String,
                                           parentCommentId: data.value(forKey: "parentCommentId") as! String,
                                           username: data.value(forKey: "username") as! String,
                                           userImageUrl: data.value(forKey: "userImageUrl") as! String,
                                           text: data.value(forKey: "text") as! String,
                                           timestamp: data.value(forKey: "timestamp") as! Double)
                self.feedCommentItems.insert(item, at: 0)
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
    
    // Inserts the comment item into the FeedComments entity of CoreData.
    func createComment(item: FeedCommentItem) {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        let managedContext = appDelegate.persistentContainer.viewContext
        let userEntity = NSEntityDescription.entity(forEntityName: "FeedComments", in: managedContext)!
        let obj = NSManagedObject(entity: userEntity, insertInto: managedContext)
        obj.setValue(item.commentItemId, forKeyPath: "commentId")
        obj.setValue(item.username, forKeyPath: "username")
        obj.setValue(item.userImageUrl, forKeyPath: "userImageUrl")
        obj.setValue(item.feedItemId, forKeyPath: "feedItemId")
        obj.setValue(item.parentCommentId, forKeyPath: "parentCommentId")
        obj.setValue(item.timestamp, forKeyPath: "timestamp")
        obj.setValue(item.text, forKeyPath: "text")
        
        do {
            try managedContext.save()
        } catch let error as NSError {
            print("could not save. \(error), \(error.userInfo)")
        }
    }
    
    // Check if a comment already exists in the FeedComments entity with the same commentId.
    func isCommentPresent(commentId: String) -> Bool {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            return false
        }
        let managedContext = appDelegate.persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FeedComments")
        fetchRequest.predicate = NSPredicate(format: "commentId == %@", commentId)
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

// FeedCommentItem object to hold all the properties of a comment item on a post.
class FeedCommentItem: Identifiable, Equatable {
    var id = UUID()
    var commentItemId: String
    var feedItemId: String
    var parentCommentId: String
    var username: String
    var userImageUrl: String
    var text: String
    var timestamp: Double = 0
    
    init(commentItemId: String = "",
         feedItemId: String = "",
         parentCommentId: String = "",
         username: String = "",
         userImageUrl: String = "",
         text: String = "",
         timestamp: Double = 0) {
        
        self.commentItemId = commentItemId
        self.feedItemId = feedItemId
        self.parentCommentId = parentCommentId
        self.username = username
        self.userImageUrl = userImageUrl
        self.text = text
        self.timestamp = timestamp
    }
    // Using commentItemId for now.
    static func == (lhs: FeedCommentItem, rhs: FeedCommentItem) -> Bool {
        return lhs.commentItemId == rhs.commentItemId
    }
    
}
