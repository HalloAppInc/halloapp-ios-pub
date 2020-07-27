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
            DDLogInfo("SharedDataStore/post/add new media with [\(item.url!)]")
            
            let feedMedia = NSEntityDescription.insertNewObject(forEntityName: SharedMedia.entity().name!, into: managedObjectContext) as! SharedMedia
            feedMedia.type = item.type
            feedMedia.url = item.url!
            feedMedia.size = item.size!
            feedMedia.key = item.key!
            feedMedia.sha256 = item.sha256!
            feedMedia.order = Int16(index)
            feedMedia.post = feedPost
            
            let mediaFilename = UUID().uuidString
            let destinationFileURL = Self.fileURL(forFileName: mediaFilename, withFileType: feedMedia.type)
            feedMedia.relativeFilePath = destinationFileURL.lastPathComponent
            
            do {
                try FileManager.default.createDirectory(at: Self.dataDirectoryURL, withIntermediateDirectories: true, attributes: nil)
                try FileManager.default.copyItem(at: item.fileURL!, to: destinationFileURL)
            } catch {
                DDLogError("SharedDataStore/post/copy-media/error [\(error)]")
            }
        }
        
        save(managedObjectContext)
        
        let request = XMPPPostItemRequest(feedItem: feedPost, feedOwnerId: feedPost.userId) { (timestamp, error) in
            if error != nil {
                DDLogError("SharedDataStore/post/send/error: \(String(describing: error))")
                completion(.failure(error!))
            } else {
                if let timestamp = timestamp {
                    feedPost.timestamp = timestamp
                    feedPost.status = .sent
                    self.save(managedObjectContext)
                } else {
                    DDLogError("SharedDataStore/post/send/error timestamp is nil")
                }
                
                completion(.success(feedPost.id))
            }
        }
        
        xmppController.enqueue(request: request)
    }
    
    
}
