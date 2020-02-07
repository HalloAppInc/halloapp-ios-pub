//
//  FeedCommentCore.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/3/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import SwiftUI
import Combine
import CoreData

class FeedCommentCore {

    func create(item: FeedComment) {
        
        let managedContext = CoreDataManager.sharedManager.bgContext
        
        managedContext.perform {

            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "FeedComments")
            fetchRequest.predicate = NSPredicate(format: "commentId == %@", item.id)
            
            do {

                let result = try managedContext.fetch(fetchRequest)
                
                if (result.count > 0) {
                    return
                }
                
                let userEntity = NSEntityDescription.entity(forEntityName: "FeedComments", in: managedContext)!
                let obj = NSManagedObject(entity: userEntity, insertInto: managedContext)
                obj.setValue(item.id, forKeyPath: "commentId")
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
                
            } catch  {
                print("failed")
            }
            
        }
    }
    
}
