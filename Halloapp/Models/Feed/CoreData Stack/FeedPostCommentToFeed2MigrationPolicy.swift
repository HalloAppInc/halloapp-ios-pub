//
//  FeedPostCommentToFeed2MigrationPolicy.swift
//  HalloApp
//
//  Created by Murali Balusu on 3/23/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation
import CoreData
import CocoaLumberjackSwift

class FeedPostCommentToFeed2MigrationPolicy: NSEntityMigrationPolicy {

    override func createRelationships(forDestination dInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        try super.createRelationships(forDestination: dInstance, in: mapping, manager: manager)

        let sourceInstances = manager.sourceInstances(forEntityMappingName: mapping.name, destinationInstances: [dInstance])
        guard let sInstance = sourceInstances.first else {
            return
        }
        if let sPost = sInstance.value(forKey: "post") as? NSManagedObject {
            if let sPostId = sPost.value(forKey: "id") as? String {
                let request = NSFetchRequest<NSManagedObject>(entityName: "FeedPost")
                request.predicate = NSPredicate(format: "id == %@", sPostId)
                let matchingPosts = try manager.destinationContext.fetch(request)
                if let destPost = matchingPosts.first {
                    dInstance.setValue(destPost, forKey: "post")
                }
                DDLogInfo("FeedPostCommentToFeed2Migration/createRelationships/commentId: \(dInstance.value(forKey: "id")) postId: \(sPostId)")
            }
        }
    }
}
