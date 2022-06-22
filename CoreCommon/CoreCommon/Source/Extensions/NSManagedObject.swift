//
//  NSManagedObject.swift
//  CoreCommon
//
//  Created by Chris Leonavicius on 6/21/22.
//

import CocoaLumberjackSwift
import CoreData

extension NSManagedObject {

    /*
     This can be safely called on an NSManagedObject from any queue.
     */
    public func `in`(context otherContext: NSManagedObjectContext) -> Self? {
        do {
            if objectID.isTemporaryID {
                try managedObjectContext?.obtainPermanentIDs(for: [self])
            }
            return otherContext.object(with: objectID) as? Self
        } catch {
            DDLogError("Error accessing object in alternate context: \(error)")
            return nil
        }
    }
}
