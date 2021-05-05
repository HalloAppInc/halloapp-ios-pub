//
//  GroupList.swift
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import CoreData
import Foundation

public class GroupList: NSObject, NSFetchedResultsControllerDelegate {

    private var fetchedResultsController: NSFetchedResultsController<ChatGroup>?

    public func listenForChanges(using context: NSManagedObjectContext) {
        fetchedResultsController = makeFetchedResultsController(using: context)
        fetchedResultsController?.delegate = self
        try? fetchedResultsController?.performFetch()
        sync()
    }

    private func makeFetchedResultsController(using context: NSManagedObjectContext) -> NSFetchedResultsController<ChatGroup> {
        let request: NSFetchRequest<ChatGroup> = ChatGroup.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "name", ascending: true),
        ]
        request.predicate = NSPredicate(format: "groupId != nil")

        return NSFetchedResultsController(fetchRequest: request, managedObjectContext: context, sectionNameKeyPath: nil, cacheName: nil)
    }

    public func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        sync()
    }

    private func sync() {
        if let groups = fetchedResultsController?.fetchedObjects {
            return GroupListItem.save(groups.map {
                let users = $0.members?.map { $0.userId } ?? [UserID]()
                return GroupListItem(id: $0.groupId, name: $0.name, users: users)
            })
        }
    }
}
