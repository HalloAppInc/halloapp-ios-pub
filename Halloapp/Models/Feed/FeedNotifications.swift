//
//  FeedNotifications.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/22/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import CoreData
import Foundation
import Core

class FeedNotifications: NSObject, NSFetchedResultsControllerDelegate {

    private let fetchedResultsController: NSFetchedResultsController<FeedNotification>

    init(_ managedObjectContext: NSManagedObjectContext) {
        let fetchRequest: NSFetchRequest<FeedNotification> = FeedNotification.fetchRequest()
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedNotification.timestamp, ascending: false) ]
        fetchedResultsController = NSFetchedResultsController<FeedNotification>(fetchRequest: fetchRequest, managedObjectContext: managedObjectContext, sectionNameKeyPath: nil, cacheName: nil)
        super.init()
        fetchedResultsController.delegate = self
        do {
            try fetchedResultsController.performFetch()
        } catch {
            Log.e("FeedNotifications/fetch/error [\(error)]")
            fatalError("Failed to fetch feed notifications.")
        }
    }

    // MARK: Unread Count

    let unreadCountDidChange = PassthroughSubject<Int, Never>()
    private(set) var unreadCount: Int = 0 {
        didSet {
            self.unreadCountDidChange.send(unreadCount)
        }
    }

    private func reloadUnreadCount() {
        let managedObjectContext = self.fetchedResultsController.managedObjectContext
        let fetchRequest: NSFetchRequest<FeedNotification> = FeedNotification.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "read = %@", NSExpression(forConstantValue: false))
        do {
            self.unreadCount = try managedObjectContext.count(for: fetchRequest)
        }
        catch {
            Log.e("FeedNotifications/fetch/error [\(error)]")
            fatalError("Failed to fetch feed notifications.")
        }
    }

    // MARK: NSFetchedResultsControllerDelegate

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        self.reloadUnreadCount()
    }

}
