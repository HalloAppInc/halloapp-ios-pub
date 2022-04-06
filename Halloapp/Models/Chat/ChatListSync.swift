//
//  ChatListSync.swift
//  HalloApp
//
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import CoreData
import Foundation

public class ChatListSync: NSObject, NSFetchedResultsControllerDelegate {

    private var fetchedResultsController: NSFetchedResultsController<CommonThread>?
    private let sync = PassthroughSubject<Void, Never>()
    private var syncCancellable: AnyCancellable?
    private let syncQueue = DispatchQueue(label: "com.halloapp.chat-list-sync")

    public func listenForChanges(using context: NSManagedObjectContext) {
        syncCancellable = sync.debounce(for: .seconds(0.5), scheduler: syncQueue).sink { [weak self] in
            guard let fetchedResultsController = self?.fetchedResultsController else {
                return
            }
            fetchedResultsController.managedObjectContext.perform {
                let threads = (fetchedResultsController.fetchedObjects ?? [])

                ChatListSyncItem.save(threads.compactMap {
                    guard let userId = $0.userID else { return nil }
                    return ChatListSyncItem(userId: userId, timestamp: $0.lastMsgTimestamp)
                })
            }
        }

        fetchedResultsController = makeFetchedResultsController(using: context)
        fetchedResultsController?.delegate = self
        try? fetchedResultsController?.performFetch()
        sync.send()
    }

    private func makeFetchedResultsController(using context: NSManagedObjectContext) -> NSFetchedResultsController<CommonThread> {
        let request = NSFetchRequest<CommonThread>(entityName: "CommonThread")
        request.sortDescriptors = [
            NSSortDescriptor(key: "lastTimestamp", ascending: false),
            NSSortDescriptor(key: "title", ascending: true)
        ]

        // TODO: Should this use type field instead?
        request.predicate = NSPredicate(format: "userID != nil")

        return NSFetchedResultsController(fetchRequest: request, managedObjectContext: context, sectionNameKeyPath: nil, cacheName: nil)
    }

    public func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        sync.send()
    }
}
