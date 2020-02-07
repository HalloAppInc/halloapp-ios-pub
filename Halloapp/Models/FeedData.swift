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
    
    @Published var feedMedia : [FeedMedia] = []
    
    @Published var feedDataItems : [FeedDataItem] = []
    @Published var feedCommentItems : [FeedComment] = []
        
    var xmpp: XMPP
    var xmppController: XMPPController
    
    private var cancellableSet: Set<AnyCancellable> = []
    
    let feedItemCore = FeedItemCore()
    let feedCommentCore = FeedCommentCore()
    let feedMediaCore = FeedMediaCore()
    
    init(xmpp: XMPP) {
        
        self.xmpp = xmpp
        self.xmppController = self.xmpp.xmppController

//        self.feedMedia.append(contentsOf: FeedMediaCore().getAll())
//        print("count: \(self.feedMedia.count)")
        
        self.pushAllItems(items: feedItemCore.getAll())
        
        self.getAllComments()
        
        self.processExpires()

        DispatchQueue.global(qos: .background).async {
            ImageServer().processPending()
        }
        
        self.cancellableSet.insert(
         
            self.xmpp.userData.didLogOff.sink(receiveValue: {
                
                print("wiping feed data")
                
                self.feedMedia.removeAll()
                self.feedCommentItems.removeAll()
                self.feedDataItems.removeAll()
                print("feedDataItemss Count: \(self.feedDataItems.count)")
                
            })

        )
        
        /* getting new items, usually one */
        cancellableSet.insert(
            
            xmppController.didGetNewFeedItem.sink(receiveValue: { value in

                
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
                                
//                print("got items: \(value)")

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
    
    
    func pushAllItems(items: [FeedDataItem]) {

        if self.feedDataItems.count > 0 {
            return
        }
        
        self.feedDataItems = items
            
        self.feedDataItems.sort {
            return Int($0.timestamp) > Int($1.timestamp)
        }

        for item in self.feedDataItems {
            
//            item.media = self.feedMedia.filter { $0.feedItemId == item.itemId }
            item.media = self.feedMediaCore.get(feedItemId: item.itemId)
                    

            item.media.sort {
                return $0.order < $1.order
            }

            
            // support pre-build 8 image format
            if item.imageUrl != "" && item.media.count == 0 {
                
                let med: FeedMedia = FeedMedia()
                med.feedItemId = item.itemId
                med.order = 1
                med.type = "image"
                med.url = item.imageUrl
                
                item.media.append(med)
                
                DispatchQueue.global(qos: .background).async {
                    self.feedMediaCore.create(item: med)
                }
              
            }
            
            
            item.loadMedia()
            
        }
    
    }

    
    func pushItem(item: FeedDataItem) {
        
        let feedMediaCore = FeedMediaCore()
        
        let idx = self.feedDataItems.firstIndex(where: {$0.itemId == item.itemId})
        
        if !self.feedItemCore.isPresent(itemId: item.itemId) && idx == nil {
   
//        if (idx == nil) {
            
            self.feedDataItems.insert(item, at: 0)
            
            self.feedDataItems.sort {
                return Int($0.timestamp) > Int($1.timestamp)
            }
                        
            DispatchQueue.global(qos: .background).async {
                self.feedItemCore.create(item: item)
                
                for med in item.media {
                    feedMediaCore.create(item: med)
                }
            }
            
            item.loadMedia()
            
        } else {
            
            // redundant, in case feedItem got into coredata but the feedMedia did not, as in the case of older posts
            
            for med in item.media {
                
                DispatchQueue.global(qos: .background).async {
                
//                    med.feedItemId = item.itemId // can be removed after build 8

                    feedMediaCore.create(item: med)

                }
                
            }

        }
        
    }
    
    func insertComment(item: FeedComment) {
        let idx = self.feedCommentItems.firstIndex(where: {$0.id == item.id})

        if idx == nil {
            self.feedCommentItems.insert(item, at: 0)
        
            self.increaseFeedItemUnreadComments(comment: item, num: 1)
        
            DispatchQueue.global(qos: .background).async {
                self.feedCommentCore.create(item: item)
            }
        }

    }
    
    func increaseFeedItemUnreadComments(comment: FeedComment, num: Int) {
        
        let idx = self.feedDataItems.firstIndex(where: {$0.itemId == comment.feedItemId})
        
        if idx == nil {
            return
        } else {
            self.feedDataItems[idx!].unreadComments += num
        }
        
        
        DispatchQueue.global(qos: .background).async {
            if (self.feedDataItems.count > idx!) {
                self.feedItemCore.update(item: self.feedDataItems[idx!])
            }
        }
        
        
    }
    
    func markFeedItemUnreadComments(comment: FeedComment) {
        
        let idx = self.feedDataItems.firstIndex(where: {$0.itemId == comment.feedItemId})
        
        if idx == nil {
            return
        } else {
            if (self.feedDataItems[idx!].unreadComments > 0) {
                self.feedDataItems[idx!].unreadComments = 0

                DispatchQueue.global(qos: .background).async {
                    self.feedItemCore.update(item: self.feedDataItems[idx!])
                }
            }
        }
        
    }
    
    func postText2(_ user: String, _ text: String, _ media: [FeedMedia]) {
        
        print("postText2: " + text)
        
        let text = XMLElement(name: "text", stringValue: text)
        
        let username = XMLElement(name: "username", stringValue: self.xmpp.userData.phone)
        let userImageUrl = XMLElement(name: "userImageUrl", stringValue: "")
        
        let childroot = XMLElement(name: "feedpost")
        let mainroot = XMLElement(name: "entry")
        
        if media.count > 0 {
            let mediaEl = XMLElement(name: "media")
            
            for med in media {
                let medEl = XMLElement(name: "url", stringValue: med.url)
                medEl.addAttribute(withName: "type", stringValue: med.type)
                medEl.addAttribute(withName: "width", stringValue: String(med.width))
                medEl.addAttribute(withName: "height", stringValue: String(med.height))
                 
                mediaEl.addChild(medEl)
            }
            
            childroot.addChild(mediaEl)
        }

        childroot.addChild(username)
        childroot.addChild(userImageUrl)
        childroot.addChild(text)
        
        mainroot.addChild(childroot)
        
        print ("Final pubsub payload: \(mainroot)")
        let id = UUID().uuidString
        self.xmppController.xmppPubSub.publish(toNode: "feed-\(user)", entry: mainroot, withItemID: id)
                
    }
    
    // Publishes the post to the user's feed pubsub node.
    func postText(_ user: String, _ text: String, _ media: [FeedMedia]) {
        
        var url: String = ""
        var imageWidth: Int = 0
        var imageHeight: Int = 0
        
        if media.count > 0 {
            url = media[0].url
            imageWidth = media[0].width
            imageHeight = media[0].height
        }
        
        print("postText: " + text)
        
        let text = XMLElement(name: "text", stringValue: text)
        let username = XMLElement(name: "username", stringValue: self.xmpp.userData.phone)
        let imageUrl = XMLElement(name: "imageUrl", stringValue: url)
        
        imageUrl.addAttribute(withName: "width", stringValue: String(imageWidth))
        imageUrl.addAttribute(withName: "height", stringValue: String(imageHeight))
        
        let userImageUrl = XMLElement(name: "userImageUrl", stringValue: "")

        let childroot = XMLElement(name: "feedpost")
        let mainroot = XMLElement(name: "entry")
        
        if media.count > 0 {
            let mediaEl = XMLElement(name: "media")
            
            for med in media {
                let medEl = XMLElement(name: "url", stringValue: med.url)
                medEl.addAttribute(withName: "type", stringValue: med.type)
                medEl.addAttribute(withName: "width", stringValue: String(med.width))
                medEl.addAttribute(withName: "height", stringValue: String(med.height))
                 
                mediaEl.addChild(medEl)
            }
            
            childroot.addChild(mediaEl)
        }
        
        childroot.addChild(username)
        childroot.addChild(userImageUrl)
        childroot.addChild(imageUrl)
//        childroot.addChild(timestamp)
        childroot.addChild(text)
        
        
        mainroot.addChild(childroot)
        
        print ("Final pubsub payload: \(mainroot)")
        let id = UUID().uuidString
        self.xmppController.xmppPubSub.publish(toNode: "feed-\(user)", entry: mainroot, withItemID: id)
                
    }
    
    // Publishes the comment 'text' on post 'feedItemId' to the user 'postUser' feed pubsub node.
    func postComment(_ feedItemId: String, _ postUser: String, _ text: String, _ parentCommentId: String) {
        print("postComment: " + text)
        
        let text = XMLElement(name: "text", stringValue: text)
        let feedItem = XMLElement(name: "feedItemId", stringValue: feedItemId)
        let parentCommentId = XMLElement(name: "parentCommentId", stringValue: parentCommentId)
        let username = XMLElement(name: "username", stringValue: self.xmpp.userData.phone)
        let userImageUrl = XMLElement(name: "userImageUrl", stringValue: "")

        let mainroot = XMLElement(name: "entry")
        let childroot = XMLElement(name: "comment")
        
        childroot.addChild(username)
        childroot.addChild(userImageUrl)
        childroot.addChild(feedItem)
        childroot.addChild(parentCommentId)

        childroot.addChild(text)
        
        mainroot.addChild(childroot)
        print ("Final pubsub payload: \(mainroot)")
        let id = UUID().uuidString
        self.xmppController.xmppPubSub.publish(toNode: "feed-\(postUser)", entry: mainroot, withItemID: id)
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
    
    
    func processExpires() {
        
        let current = Int(Date().timeIntervalSince1970)
        
        let month = 60*60*24*30
        
        let feedItemCore = FeedItemCore()
    
        for (i, item) in feedDataItems.enumerated().reversed() {
            let diff = current - Int(item.timestamp)
            
            if (diff > month) {

                if (item.username != self.xmpp.userData.phone) {
                    feedItemCore.delete(itemId: item.itemId)
                    feedDataItems.remove(at: i)
                }
                
            }
            
        }
    }
    


    

    
    // Retrieves all the comments from the database.
    func getAllComments() {
        
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FeedComments")
        fetchRequest.sortDescriptors = [NSSortDescriptor.init(key: "timestamp", ascending: false)]
        do {
            let result = try managedContext.fetch(fetchRequest)
            for data in result as! [NSManagedObject] {
                let item = FeedComment(id: data.value(forKey: "commentId") as! String,
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
    
    

    

    
}


