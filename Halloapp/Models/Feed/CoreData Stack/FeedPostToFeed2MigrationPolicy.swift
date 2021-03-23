//
//  FeedPostToFeed2MigrationPolicy.swift
//  HalloApp
//
//  Created by Murali Balusu on 3/16/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation
import CoreData
import CocoaLumberjack

class FeedPostToFeed2MigrationPolicy: NSEntityMigrationPolicy {
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        guard let sourcePostId = sInstance.value(forKey: "id") as? String else {
            return
        }
        DDLogInfo("FeedPostToFeed2Migration, sourceId: \(sourcePostId), sourceInstance: \(sInstance)")
        let request = NSFetchRequest<NSManagedObject>(entityName: "FeedPost")
        request.predicate = NSPredicate(format: "id == %@", sourcePostId)
        let destPost = try manager.destinationContext.fetch(request)
        let feedPost: NSManagedObject
        if destPost == [] {
            feedPost = NSEntityDescription.insertNewObject(forEntityName: mapping.destinationEntityName!, into: manager.destinationContext)
            feedPost.setValue(sInstance.value(forKey: "groupId"), forKey: "groupId")
            feedPost.setValue(sInstance.value(forKey: "id"), forKey: "id")
            feedPost.setValue(sInstance.value(forKey: "statusValue"), forKey: "statusValue")
            feedPost.setValue(sInstance.value(forKey: "text"), forKey: "text")
            feedPost.setValue(sInstance.value(forKey: "timestamp"), forKey: "timestamp")
            feedPost.setValue(sInstance.value(forKey: "unreadCount"), forKey: "unreadCount")
            feedPost.setValue(sInstance.value(forKey: "userId"), forKey: "userId")
        } else {
            return
        }
        DDLogInfo("FeedPostToFeed2Migration/associate sourceId: \(sourcePostId), sourceInstance: \(sInstance)")
        manager.associate(sourceInstance: sInstance, withDestinationInstance: feedPost, for: mapping)
        return
    }
}
