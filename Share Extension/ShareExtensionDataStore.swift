//
//  ShareExtensionDataStore.swift
//  Share Extension
//
//  Created by Alan Luo on 7/27/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import CoreData
import UIKit
import XMPPFramework

class ShareExtensionDataStore: SharedDataStore {
    public typealias ShareExtenstionFeedPostRequestCompletion = (Result<FeedPostID, Error>) -> Void
    
    func post(text: String, media: [PendingMedia], using xmppController: XMPPController, completion: @escaping ShareExtenstionFeedPostRequestCompletion) {
        let postId: FeedPostID = UUID().uuidString
        DDLogInfo("SharedDataStore/post/create new feedpost with [\(postId)]")
        
        let managedObjectContext = persistentContainer.viewContext
        
        let feedPost = NSEntityDescription.insertNewObject(forEntityName: SharedFeedPost.entity().name!, into: managedObjectContext) as! SharedFeedPost
        feedPost.id = postId
        feedPost.text = text
        feedPost.timestamp = Date()
        feedPost.userId = AppContext.shared.userData.userId
        feedPost.status = .none
        
        for (index, item) in media.enumerated() {
            self.save(item, index: index, to: .post(feedPost), using: managedObjectContext)
        }
        
        save(managedObjectContext)
        
        let request = XMPPPostItemRequest(feedItem: feedPost, feedOwnerId: feedPost.userId) { (result) in
            switch result {
            case .success(let timestamp):
                if let timestamp = timestamp {
                    feedPost.timestamp = timestamp
                    feedPost.status = .sent
                    self.save(managedObjectContext)
                } else {
                    DDLogError("SharedDataStore/post/send/error timestamp is nil")
                }

                completion(.success(feedPost.id))

            case .failure(let error):
                DDLogError("SharedDataStore/post/send/error: \(error)")
                completion(.failure(error))
            }
        }
        
        xmppController.enqueue(request: request)
    }
    
    public typealias ShareExtenstionMessageRequestCompletion = (Result<String, Error>) -> Void
    
    func sned(to userId: UserID, text: String, media: [PendingMedia], using xmppController: XMPPController, completion: @escaping ShareExtenstionMessageRequestCompletion) {
        let xmppChatMessage = XMPPChatMessage(toUserId: userId, text: text, media: media, feedPostId: nil, feedPostMediaIndex: 0)
        
        DDLogInfo("SharedDataStore/send/create new message with [\(xmppChatMessage.id)]")
        
        let managedObjectContext = persistentContainer.viewContext
        
        let chatMessage = NSEntityDescription.insertNewObject(forEntityName: SharedChatMessage.entity().name!, into: managedObjectContext) as! SharedChatMessage
        chatMessage.id = xmppChatMessage.id
        chatMessage.toUserId = userId
        chatMessage.fromUserId = AppContext.shared.userData.userId
        chatMessage.text = text
        chatMessage.status = .sent
        chatMessage.timestamp = Date()
        
        for (index, item) in media.enumerated() {
            self.save(item, index: index, to: .message(chatMessage), using: managedObjectContext)
        }
        
        save(managedObjectContext)
        
        xmppController.xmppStream.send(xmppChatMessage.xmppElement)
        
        // TODO: Find a way to detect send error
        
        completion(.success(xmppChatMessage.id))
    }
}
