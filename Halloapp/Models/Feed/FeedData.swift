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
    @Published var isConnecting: Bool = true
        
    private var userData: UserData
    private var xmppController: XMPPController
    private var cancellableSet: Set<AnyCancellable> = []
    
    private let feedItemCore = FeedItemCore()
    private let feedCommentCore = FeedCommentCore()
    private let feedMediaCore = FeedMediaCore()

    init(xmpp: XMPP, userData: UserData) {
        self.xmppController = xmpp.xmppController
        self.userData = userData

//        self.feedMedia.append(contentsOf: FeedMediaCore().getAll())
//        print("count: \(self.feedMedia.count)")
        
        self.pushAllItems(items: feedItemCore.getAll())
        
        self.feedCommentItems = feedCommentCore.getAll()
        
        self.cancellableSet.insert(
            self.xmppController.isConnecting.sink(receiveValue: { value in
                self.isConnecting = true
            })
        )
        
        // when app resumes, xmpp reconnects, feed should try uploading any pending again
        self.cancellableSet.insert(
            self.xmppController.didConnect.sink(receiveValue: { value in

                self.isConnecting = false
                
                self.userData.log("Feed: Got event for didConnect")
                
                DispatchQueue.global(qos: .default).async {
                    ImageServer().processPending()
                }

                // should try to load images again if there are unfinished ones
//                for item in self.feedDataItems {
//                    item.loadMedia()
//                }
                
                self.processExpires()
            })
        )
        
        self.cancellableSet.insert(
            self.userData.didLogOff.sink(receiveValue: {
                
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
                self.userData.log("Feed: New Item \(value)")
                
                if let id = value.elementID {
                    self.userData.log("Feed: Sending ACK")
                    Utils().sendAck(xmppStream: self.xmppController.xmppStream, id: id, from: self.userData.phone)
                } else {
                    self.userData.log("Feed: Not sending ACK")
                }
                
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
                                
//                self.xmpp.userData.log("got items: \(value)")

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
    
    func getItemMedia(_ itemId: String) {
        let idx = self.feedDataItems.firstIndex(where: {$0.itemId == itemId})
        if idx != nil {
            if self.feedDataItems[idx!].media.count == 0 {
                self.feedDataItems[idx!].media = FeedMediaCore().get(feedItemId: itemId)

                /* ideally we should have the images in core data by now */
                /* todo: scan for unloaded images during init */
                self.feedDataItems[idx!].loadMedia()
            }
        }
    }
    
    func setItemCellHeight(_ itemId: String, _ cellHeight: Int) {
       let idx = self.feedDataItems.firstIndex(where: {$0.itemId == itemId})
       if idx != nil {
           
            self.feedDataItems[idx!].cellHeight = cellHeight
        
            DispatchQueue.global(qos: .default).async {
                self.feedItemCore.updateCellHeight(item: self.feedDataItems[idx!])
            }
       }
    }

    func calHeight(media: [FeedMedia]) -> Int {
         
        var resultHeight = 0
        
         var maxHeight = 0
         var width = 0
         
         for med in media {
             if med.height > maxHeight {
                 maxHeight = med.height
                 width = med.width
             }
         }
         
         if maxHeight < 1 {
             return 0
         }
         
         let desiredAspectRatio: Float = 5/4 // 1.25 for portrait
         
         // can be customized for different devices
         let desiredViewWidth = Float(UIScreen.main.bounds.width) - 20 // account for padding on left and right
         
         let desiredTallness = desiredAspectRatio * desiredViewWidth
         
         let ratio = Float(maxHeight)/Float(width) // image ratio

         let actualTallness = ratio * desiredViewWidth

         if actualTallness >= desiredTallness {
             resultHeight = Int(CGFloat(desiredTallness))
         } else {
             resultHeight = Int(CGFloat(actualTallness + 10))
         }
         
        return resultHeight
     }
    
    func pushAllItems(items: [FeedDataItem]) {

        if self.feedDataItems.count > 0 {
            return
        }
        
        self.feedDataItems = items
            
        self.feedDataItems.sort {
            return Int($0.timestamp) > Int($1.timestamp)
        }

        /* backwards compatibility for items that were missed or did not have mediaHeight yet */
        for item in self.feedDataItems {
            if item.mediaHeight == -1 {
                self.userData.log("Missing mediaHeight - \(item.itemId)")
                
                let tempMedia = feedMediaCore.getInfo(feedItemId: item.itemId)
                
                item.mediaHeight = self.calHeight(media: tempMedia)

                DispatchQueue.global(qos: .default).async {
                    self.feedItemCore.updateMediaHeight(item: item)
                }
            }
        }
        
//        for item in self.feedDataItems {
//
//            item.media = self.feedMediaCore.get(feedItemId: item.itemId)
//
//            item.media.sort {
//                return $0.order < $1.order
//            }
//
//            item.comments = self.feedCommentCore.get(feedItemId: item.itemId)
//
//            item.loadMedia()
//
//        }
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
                        
            DispatchQueue.global(qos: .default).async {
                
                item.mediaHeight = self.calHeight(media: item.media)
                
                print("new item mediaHeight: \(item.mediaHeight)")
                print("cellHeight: \(item.cellHeight)")
                
                self.feedItemCore.create(item: item)
                
                for med in item.media {
                    feedMediaCore.create(item: med)
                }
            }
            
            // load media for new items
            item.loadMedia()
        } else {
            // redundant, in case feedItem got into coredata but the feedMedia did not, as in the case of older posts
            for med in item.media {
                DispatchQueue.global(qos: .default).async {
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
        
            if (item.username != self.userData.phone) {
                self.increaseFeedItemUnreadComments(comment: item, num: 1)
            }
        
            DispatchQueue.global(qos: .default).async {
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
        
        DispatchQueue.global(qos: .default).async {
            if (self.feedDataItems.count > idx!) {
                self.feedItemCore.update(item: self.feedDataItems[idx!])
            }
        }
    }
        
    func markFeedItemUnreadComments(feedItemId: String) {
        let idx = self.feedDataItems.firstIndex(where: {$0.itemId == feedItemId})
        
        if idx == nil {
            return
        } else {
            if (self.feedDataItems[idx!].unreadComments > 0) {
                self.feedDataItems[idx!].unreadComments = 0

                DispatchQueue.global(qos: .default).async {
                    self.feedItemCore.update(item: self.feedDataItems[idx!])
                }
            }
        }
    }
    
    func postItem(_ user: String, _ text: String, _ media: [FeedMedia]) {
        let text = XMLElement(name: "text", stringValue: text)
        
        let username = XMLElement(name: "username", stringValue: self.userData.phone)
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
                
                if med.key != "" {
                    medEl.addAttribute(withName: "key", stringValue: String(med.key))
                    medEl.addAttribute(withName: "sha256hash", stringValue: String(med.sha256hash))
                }
                 
                mediaEl.addChild(medEl)
            }
            
            childroot.addChild(mediaEl)
        }

        childroot.addChild(username)
        childroot.addChild(userImageUrl)
        childroot.addChild(text)
        
        mainroot.addChild(childroot)
        
        self.userData.log("Feed: postItem - \(mainroot)")
        
        let id = UUID().uuidString
        self.xmppController.xmppPubSub.publish(toNode: "feed-\(user)", entry: mainroot, withItemID: id)
    }
    
    // Publishes the post to the user's feed pubsub node.
    func postTextOld(_ user: String, _ text: String, _ media: [FeedMedia]) {
        let text = XMLElement(name: "text", stringValue: text)
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
        
        childroot.addChild(text)
        
        mainroot.addChild(childroot)
        
        self.userData.log("Feed: PostText \(mainroot)")
        
        let id = UUID().uuidString
        self.xmppController.xmppPubSub.publish(toNode: "feed-\(user)", entry: mainroot, withItemID: id)
    }
    
    // Publishes the comment 'text' on post 'feedItemId' to the user 'postUser' feed pubsub node.
    func postComment(_ feedItemId: String, _ postUser: String, _ text: String, _ parentCommentId: String) {
        print("postComment: " + text)
        
        let text = XMLElement(name: "text", stringValue: text)
        let feedItem = XMLElement(name: "feedItemId", stringValue: feedItemId)
        let parentCommentId = XMLElement(name: "parentCommentId", stringValue: parentCommentId)
        let username = XMLElement(name: "username", stringValue: self.userData.phone)
        let userImageUrl = XMLElement(name: "userImageUrl", stringValue: "")

        let mainroot = XMLElement(name: "entry")
        let childroot = XMLElement(name: "comment")
        
        childroot.addChild(username)
        childroot.addChild(userImageUrl)
        childroot.addChild(feedItem)
        childroot.addChild(parentCommentId)

        childroot.addChild(text)
        
        mainroot.addChild(childroot)

        var log = "\r\n Final pubsub payload (postComment(): \(mainroot)"
        log += "\r\n"
        print(log)
        self.userData.logging += log
        
        
        let id = UUID().uuidString
        self.xmppController.xmppPubSub.publish(toNode: "feed-\(postUser)", entry: mainroot, withItemID: id)
    }
    
    func sendMessage(text: String) {
        print("sendMessage: " + text)
        let user = XMPPJID(string: "4155553695@s.halloapp.net")
        let msg = XMPPMessage(type: "chat", to: user)
        msg.addBody(text)
        self.xmppController.xmppStream.send(msg)
    }

    func processExpires() {
        let current = Int(Date().timeIntervalSince1970)
        
        let month = 60*60*24*30
        
        let feedItemCore = FeedItemCore()
    
        for (i, item) in feedDataItems.enumerated().reversed() {
            let diff = current - Int(item.timestamp)
            
            if (diff > month) {

                if (item.username != self.userData.phone) {
                    feedItemCore.delete(itemId: item.itemId)
                    feedDataItems.remove(at: i)
                }
            }
        }
    }
}
