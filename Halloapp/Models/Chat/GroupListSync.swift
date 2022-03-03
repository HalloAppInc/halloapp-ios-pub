//
//  GroupListSync.swift
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import CoreData
import Foundation

public class GroupListSync: NSObject, NSFetchedResultsControllerDelegate {

    private var fetchedResultsController: NSFetchedResultsController<ChatGroup>?
    private var userId: UserID?
    private let sync = PassthroughSubject<Void, Never>()
    private var syncCancellable: AnyCancellable?
    private let syncQueue = DispatchQueue(label: "com.halloapp.group-list-sync")

    public func listenForChanges(using context: NSManagedObjectContext, userId: UserID) {
        syncCancellable = sync.debounce(for: .seconds(0.5), scheduler: syncQueue).sink { [weak self] in
            guard let self = self, let fetchedResultsController = self.fetchedResultsController, let userId = self.userId else {
                return
            }
            fetchedResultsController.managedObjectContext.perform {
                let groups = (fetchedResultsController.fetchedObjects ?? [])
                    .filter { $0.members?.first { $0.userId == userId } != nil }
                    .map { (group: ChatGroup) -> GroupListSyncItem in
                        let users = group.members?.map { $0.userId } ?? [UserID]()
                        let thread = self.chatThread(for: group.groupId, in: fetchedResultsController.managedObjectContext)

                        return GroupListSyncItem(
                            id: group.groupId,
                            name: group.name,
                            users: users,
                            lastActivityTimestamp: thread?.lastFeedTimestamp ?? thread?.lastMsgTimestamp
                        )
                    }

                GroupListSyncItem.save(groups)
            }
        }

        self.userId = userId

        fetchedResultsController = makeFetchedResultsController(using: context)
        fetchedResultsController?.delegate = self
        try? fetchedResultsController?.performFetch()
        sync.send()
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
        sync.send()
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
}
