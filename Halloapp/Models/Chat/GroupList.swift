//
//  GroupList.swift
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreData
import Foundation

public class GroupList: NSObject, NSFetchedResultsControllerDelegate {

    private var fetchedResultsController: NSFetchedResultsController<ChatGroup>?
    private var userId: UserID?

    public func listenForChanges(using context: NSManagedObjectContext, userId: UserID) {
        self.userId = userId

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

    private func chatThread(for id: GroupID, in context: NSManagedObjectContext) -> ChatThread? {
        let request = ChatThread.fetchRequest()
        request.predicate = NSPredicate(format: "groupId == %@", id)


        do {
            return try context.fetch(request).first
        }
        catch {
            DDLogError("group-list/chatThread/fetch/error  [\(error)]")
        }

        return nil
    }

    private func sync() {
        guard let userId = userId else { return }
        guard let controller = fetchedResultsController else { return }

        let groups = (controller.fetchedObjects ?? [])
            .filter { $0.members?.first { $0.userId == userId } != nil }
            .map { (group: ChatGroup) -> GroupListItem in
                let users = group.members?.map { $0.userId } ?? [UserID]()
                let thread = chatThread(for: group.groupId, in: controller.managedObjectContext)

                return GroupListItem(
                    id: group.groupId,
                    name: group.name,
                    users: users,
                    lastActivityTimestamp: thread?.lastFeedTimestamp ?? thread?.lastMsgTimestamp
                )
            }

        GroupListItem.save(groups)
    }
}
