//
//  IdentifiableManagedObject.swift
//  Core
//
//  Created by Chris Leonavicius on 10/5/23.
//  Copyright © 2023 Hallo App, Inc. All rights reserved.
//

import CoreData

public protocol IdentifiableManagedObject: FindableManagedObject {

    static var identifierKeyPath: WritableKeyPath<ManagedObjectType, String?> { get }
}

extension IdentifiableManagedObject {

    public static func find(id: String, in context: NSManagedObjectContext) -> ManagedObjectType? {
        findFirst(predicate: NSPredicate(format: "%K = %@", NSExpression(forKeyPath: identifierKeyPath).keyPath, id), in: context)
    }

    public static func find<IDList: Sequence<String> & CVarArg>(ids: IDList, in context: NSManagedObjectContext) -> [ManagedObjectType] {
        find(predicate: NSPredicate(format: "%K in %@", NSExpression(forKeyPath: identifierKeyPath).keyPath, ids), in: context)
    }

    public static func findOrCreate(id: String, in context: NSManagedObjectContext) -> ManagedObjectType {
        var entity: ManagedObjectType

        if let existingEntity = find(id: id, in: context) {
            entity = existingEntity
        } else {
            entity = ManagedObjectType(context: context)
            entity[keyPath: identifierKeyPath] = id
        }

        return entity
    }
}
