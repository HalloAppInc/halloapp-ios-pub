//
//  FeedModel.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/1/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import AVKit
import CocoaLumberjack
import Combine
import Foundation
import SwiftUI
import XMPPFramework

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

        self.feedDataItems = feedItemCore.getAll()
        self.feedCommentItems = feedCommentCore.getAll()
        
        /* enable videoes to play with sound even when the phone is set to ringer mode */
        do {
           try AVAudioSession.sharedInstance().setCategory(.playback)
        } catch(let error) {
            print(error.localizedDescription)
        }

        // when app resumes, xmpp reconnects, feed should try uploading any pending again
        self.cancellableSet.insert(
            self.xmppController.didConnect.sink { _ in
                DDLogInfo("Feed: Got event for didConnect")
                
                self.processExpires()
            })
        
        self.cancellableSet.insert(
            self.userData.didLogOff.sink {
                DDLogInfo("Unloading feed data. \(self.feedDataItems.count) posts. \(self.feedCommentItems.count) comments")
                
                self.feedCommentItems.removeAll()
                self.feedDataItems.removeAll()
            })
        
        /* getting new items, usually one */
        self.cancellableSet.insert(
            xmppController.didGetNewFeedItem.sink { [weak self] xmppMessage in
                if let items = xmppMessage.element(forName: "event")?.element(forName: "items") {
                    DDLogInfo("Feed: new item \(items)")
                    guard let self = self else { return }
                    self.processIncomingFeedItems(items)
                }
            })
        
        /* getting the entire list of items back */
        self.cancellableSet.insert(
            xmppController.didGetFeedItems.sink { [weak self] xmppIQ in
                if let items = xmppIQ.element(forName: "pubsub")?.element(forName: "items") {
                    DDLogInfo("Feed: fetched items \(items)")
                    guard let self = self else { return }
                    self.processIncomingFeedItems(items)
               }
            })
        
        /* retract item */
        self.cancellableSet.insert(
            xmppController.didGetRetractItem.sink { xmppMessage in
                DDLogInfo("Feed: Retract Item \(xmppMessage)")
                
                //todo: handle retracted items
            })
    }

    private func processIncomingFeedItems(_ itemsElement: XMLElement) {
        var feedPosts: [XMPPFeedPost] = []
        var comments: [XMPPComment] = []
        let items = itemsElement.elements(forName: "item")
        for item in items {
            guard let type = item.attribute(forName: "type")?.stringValue else {
                DDLogError("Invalid item: [\(item)]")
                continue
            }
            if type == "feedpost" {
                if let feedPost = XMPPFeedPost(itemElement: item) {
                    feedPosts.append(feedPost)
                }
            } else if type == "comment" {
                if let comment = XMPPComment(itemElement: item) {
                    comments.append(comment)
                }
            } else {
                DDLogError("Invalid item type: [\(type)]")
            }
        }

        let feedDataItems = feedPosts.map { FeedDataItem($0) }
        for item in feedDataItems.sorted(by: { $0.timestamp > $1.timestamp }) {
            self.pushItem(item: item)
        }

        // TODO: do bulk processing here
        let feedComments = comments.map { FeedComment($0) }
        for item in feedComments {
            self.insertComment(item: item)
        }
    }

    func getItemMedia(_ itemId: String) {
        if let feedItem = self.feedDataItems.first(where: { $0.itemId == itemId }) {
            if feedItem.media.isEmpty {
                feedItem.media = FeedMediaCore().get(feedItemId: itemId)

                DDLogDebug("FeedData/getItemMedia item=[\(itemId)] count=[\(feedItem.media.count)]")

                /* ideally we should have the images in core data by now */
                /* todo: scan for unloaded images during init */
                feedItem.loadMedia()
            }
        }
    }

    func calHeight(media: [FeedMedia]) -> Int? {
        guard !media.isEmpty else { return nil }

        var maxHeight: CGFloat = 0
        var width: CGFloat = 0

        media.forEach { media in
            if media.size.height > maxHeight {
                maxHeight = media.size.height
                width = media.size.width
            }
        }

        if maxHeight < 1 {
            return nil
        }

        let desiredAspectRatio: Float = 5/4 // 1.25 for portrait

        // can be customized for different devices
        let desiredViewWidth = Float(UIScreen.main.bounds.width) - 20 // account for padding on left and right

        let desiredTallness = desiredAspectRatio * desiredViewWidth

        let ratio = Float(maxHeight)/Float(width) // image ratio

        let actualTallness = ratio * desiredViewWidth

        let resultHeight = actualTallness >= desiredTallness ? desiredTallness : actualTallness + 10
        return Int(resultHeight.rounded())
    }

    func pushItem(item: FeedDataItem) {
        guard !self.feedDataItems.contains(where: { $0.itemId == item.itemId }) else { return }
        guard !self.feedItemCore.isPresent(itemId: item.itemId) else { return }

        item.mediaHeight = self.calHeight(media: item.media)
        self.feedDataItems.insert(item, at: 0)
        self.feedDataItems.sort {
            return $0.timestamp > $1.timestamp
        }

        self.feedItemCore.create(item: item)
        item.media.forEach { self.feedMediaCore.create(item: $0) }

        item.loadMedia()
    }

    func insertComment(item: FeedComment) {
        guard !self.feedCommentItems.contains(where: { $0.id == item.id }) else { return }

        self.feedCommentItems.insert(item, at: 0)

        if (item.username != self.userData.phone) {
            self.increaseFeedItemUnreadComments(feedItemId: item.feedItemId, by: 1)
        }

        self.feedCommentCore.create(item: item)
    }

    func increaseFeedItemUnreadComments(feedItemId: String, by number: Int) {
        guard let feedDataItem = self.feedDataItems.first(where: { $0.itemId == feedItemId }) else { return }
        feedDataItem.unreadComments += number
        self.feedItemCore.update(item: feedDataItem)
    }

    func markFeedItemUnreadComments(feedItemId: String) {
        guard let feedDataItem = self.feedDataItems.first(where: { $0.itemId == feedItemId }) else { return }
        if feedDataItem.unreadComments > 0 {
            feedDataItem.unreadComments = 0
            self.feedItemCore.update(item: feedDataItem)
        }
    }
    
    func post(text: String, media: [PendingMedia]) {
        let feedPost = XMPPFeedPost(text: text, media: media)
        let request = XMPPPostItemRequest(xmppFeedPost: feedPost) { (timestamp, error) in
            // Handle error!
            let feedItem = FeedDataItem(feedPost)
            if timestamp != nil {
                // TODO: probably not need to use server timestamp here?
                feedItem.timestamp = Date(timeIntervalSince1970: timestamp!)
            }
            feedItem.media = media.map{ FeedMedia($0, feedItemId: feedPost.id) }
            // TODO: save post to the local db before request finishes and allow to retry later.
            self.pushItem(item: feedItem)
            // TODO: write media data to db
        }
        
        AppContext.shared.xmppController.enqueue(request: request)
    }
    
    func post(comment text: String, to feedItem: FeedDataItem, replyingTo parentCommentId: String? = nil) {
        let xmppComment = XMPPComment(userPhoneNumber: feedItem.username, feedPostId: feedItem.itemId,
                                      parentCommentId: parentCommentId, text: text)
        let request = XMPPPostCommentRequest(xmppComment: xmppComment) { (timestamp, error) in
            // TODO: handle error!
            var feedComment = FeedComment(xmppComment)
            if timestamp != nil {
                // TODO: probably not need to use server timestamp here?
                feedComment.timestamp = Date(timeIntervalSince1970: timestamp!)
            }
            // TODO: comment should be saved to local db before it is posted.
            self.insertComment(item: feedComment)
        }
        
        AppContext.shared.xmppController.enqueue(request: request)
    }

    func feedDataItem(with itemId: String) -> FeedDataItem? {
        return self.feedDataItems.first(where: { $0.itemId == itemId })
    }
    
    func processExpires() {
        let current = Date().timeIntervalSince1970
        let month = Date.days(30)
        
        let feedItemCore = FeedItemCore()
    
        for (i, item) in feedDataItems.enumerated().reversed() {
            let diff = current - item.timestamp.timeIntervalSince1970
            if diff > month {
                if (item.username != self.userData.phone) {
                    // TODO: bulk delete
                    feedItemCore.delete(itemId: item.itemId)
                    feedDataItems.remove(at: i)
                }
            }
        }
    }
}
