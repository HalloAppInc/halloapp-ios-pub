//
//  Findable.swift
//  Core
//
//  Created by Chris Leonavicius on 10/5/23.
//  Copyright © 2023 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import CoreData

public protocol FindableManagedObject: NSManagedObject {

    associatedtype ManagedObjectType: NSManagedObject = Self
}

extension FindableManagedObject {

    public static func find(predicate: NSPredicate, in context: NSManagedObjectContext) -> [ManagedObjectType] {
        let fetchRequest = NSFetchRequest<ManagedObjectType>()
        fetchRequest.entity = entity()
        fetchRequest.predicate = predicate
        do {
            return try context.fetch(fetchRequest)
        } catch {
            DDLogError("\(String(describing: self))/find/Failed with predicate \(predicate): \(error)")
            return []
        }
    }

    public static func findFirst(predicate: NSPredicate, in context: NSManagedObjectContext) -> ManagedObjectType? {
        let fetchRequest = NSFetchRequest<ManagedObjectType>()
        fetchRequest.entity = entity()
        fetchRequest.predicate = predicate
        fetchRequest.fetchLimit = 1
        do {
            return try context.fetch(fetchRequest).first
        } catch {
            DDLogError("\(String(describing: self))/findFirst/Failed with predicate \(predicate): \(error)")
            return nil
        }
    }
}
