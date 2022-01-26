//
//  ChatListSync.swift
//  HalloApp
//
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreData
import Foundation

public class ChatListSync: NSObject, NSFetchedResultsControllerDelegate {

    private var fetchedResultsController: NSFetchedResultsController<ChatThread>?
    private let sync = PassthroughSubject<Void, Never>()
    private var syncCancellable: AnyCancellable?
    private let syncQueue = DispatchQueue(label: "com.halloapp.chat-list-sync")

    public func listenForChanges(using context: NSManagedObjectContext) {
        syncCancellable = sync.debounce(for: .seconds(0.5), scheduler: syncQueue).sink { [weak self] in
            guard let self = self else { return }
            guard let controller = self.fetchedResultsController else { return }
            let threads = (controller.fetchedObjects ?? [])

            ChatListSyncItem.save(threads.compactMap {
                guard let userId = $0.chatWithUserId else { return nil }
                return ChatListSyncItem(userId: userId, timestamp: $0.lastMsgTimestamp)
            })
        }

        fetchedResultsController = makeFetchedResultsController(using: context)
        fetchedResultsController?.delegate = self
        try? fetchedResultsController?.performFetch()
        sync.send()
    }

    private func makeFetchedResultsController(using context: NSManagedObjectContext) -> NSFetchedResultsController<ChatThread> {
        let request = NSFetchRequest<ChatThread>(entityName: "ChatThread")
        request.sortDescriptors = [
            NSSortDescriptor(key: "lastMsgTimestamp", ascending: false),
            NSSortDescriptor(key: "title", ascending: true)
        ]

        request.predicate = NSPredicate(format: "chatWithUserId != nil")

        return NSFetchedResultsController(fetchRequest: request, managedObjectContext: context, sectionNameKeyPath: nil, cacheName: nil)
    }

    public func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        sync.send()
    }
}
