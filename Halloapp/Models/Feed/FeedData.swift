//
//  FeedModel.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/1/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Foundation
import SwiftUI
import XMPPFramework
import AVKit

class FeedData: ObservableObject {
    @Published var feedDataItems : [FeedDataItem] = []
    @Published var feedCommentItems : [FeedComment] = []

    private var userData: UserData
    private var xmppController: XMPPController
    private var cancellableSet: Set<AnyCancellable> = []
    
    private let feedItemCore = FeedItemCore()
    private let feedCommentCore = FeedCommentCore()
    private let feedMediaCore = FeedMediaCore()

    init(xmppController: XMPPController, userData: UserData) {
        self.xmppController = xmppController
        self.userData = userData
        
        self.pushAllItems(items: feedItemCore.getAll())
        
        self.feedCommentItems = feedCommentCore.getAll()
        
        /* enable videoes to play with sound even when the phone is set to ringer mode */
        do {
           try AVAudioSession.sharedInstance().setCategory(.playback)
        } catch(let error) {
            print(error.localizedDescription)
        }

        // when app resumes, xmpp reconnects, feed should try uploading any pending again
        self.cancellableSet.insert(
            self.xmppController.didConnect.sink(receiveValue: { value in
                DDLogInfo("Feed: Got event for didConnect")
                
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
                
                DDLogInfo("wiping feed data")
                
                self.feedCommentItems.removeAll()
                self.feedDataItems.removeAll()
                DDLogInfo("feedDataItemss Count: \(self.feedDataItems.count)")
            })
        )
        
        /* getting new items, usually one */
        cancellableSet.insert(
            
            xmppController.didGetNewFeedItem.sink(receiveValue: { value in
                DDLogInfo("Feed: New Item \(value)")
                
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
                                
//                DDLogInfo("got items: \(value)")

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
        
        /* retract item */
        cancellableSet.insert(
            xmppController.didGetRetractItem.sink(receiveValue: { value in
                DDLogInfo("Feed: Retract Item \(value)")
                
                //todo: handle retracted items
            })
        )
    }
    
    func getItemMedia(_ itemId: String) {
        if let idx = self.feedDataItems.firstIndex(where: {$0.itemId == itemId}) {
            if self.feedDataItems[idx].media.count == 0 {
                self.feedDataItems[idx].media = FeedMediaCore().get(feedItemId: itemId)

                print("now \(self.feedDataItems[idx].media.count)")
                
                /* ideally we should have the images in core data by now */
                /* todo: scan for unloaded images during init */
                self.feedDataItems[idx].loadMedia()
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
        
    }

    func pushItem(item: FeedDataItem) {
        
        let idx = self.feedDataItems.firstIndex(where: {$0.itemId == item.itemId})
        
        if idx == nil && !self.feedItemCore.isPresent(itemId: item.itemId) {
               
            item.mediaHeight = self.calHeight(media: item.media)
            
            self.feedDataItems.insert(item, at: 0)
            
            self.feedDataItems.sort {
                return Int($0.timestamp) > Int($1.timestamp)
            }

            DispatchQueue.global(qos: .userInitiated).async {
                self.feedItemCore.create(item: item)
                for med in item.media {
                    self.feedMediaCore.create(item: med)
                }
            }
            
            print("pushing item: \(item.itemId)")
            item.loadMedia()
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
    
        let itemId: String = UUID().uuidString
        
        let request = XMPPPostItemRequest(user: user,
                                          text: text,
                                          media: media,
                                          itemId: itemId,
                                          completion: { timestamp, error in
            
            let feedItem = FeedDataItem()
            feedItem.itemId = itemId
            
            feedItem.text = text
            feedItem.username = user
                                            
            for med in media {

                let copyMed: FeedMedia = FeedMedia()
                copyMed.feedItemId = itemId
                copyMed.order = med.order
                copyMed.type = med.type
                copyMed.width = med.width
                copyMed.height = med.height
                copyMed.key = med.key
                copyMed.sha256hash = med.sha256hash
                copyMed.url = med.url

                feedItem.media.append(copyMed)
            }
            
            // default a current timestamp for now in case the latest server hasn't been released
            feedItem.timestamp = Date().timeIntervalSince1970
                                            
            if let serverTimestamp = timestamp {
                if serverTimestamp > 0 {
                    feedItem.timestamp = serverTimestamp
                }
            }
                            
            self.pushItem(item: feedItem)
        })
        
        AppContext.shared.xmppController.enqueue(request: request)
    }
    

    func post(comment text: String, to feedItem: FeedDataItem, replyingTo parentCommentID: String? = nil) {
        let commentItemId: String = UUID().uuidString
        
        let request = XMPPPostCommentRequest(feedUser: feedItem.username,
                                             feedItemId: feedItem.itemId,
                                             parentCommentId: parentCommentID,
                                             text: text,
                                             commentItemId: commentItemId,
                                             completion: { timestamp, error in
            
            var feedComment = FeedComment(id: commentItemId)
            feedComment.feedItemId = feedItem.itemId
            feedComment.parentCommentId = parentCommentID ?? ""
            feedComment.username = self.userData.phone
            feedComment.text = text
            
            // default a current timestamp for now in case the latest server hasn't been released
            feedComment.timestamp = Date().timeIntervalSince1970
                                            
            if let serverTimestamp = timestamp {
                if serverTimestamp > 0 {
                    feedComment.timestamp = serverTimestamp
                }
            }
             
            self.insertComment(item: feedComment)
        })
        
        AppContext.shared.xmppController.enqueue(request: request)
    }

    func feedDataItem(with itemId: String) -> FeedDataItem? {
        return self.feedDataItems.first(where: { $0.itemId == itemId })
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
