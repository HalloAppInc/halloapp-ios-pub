//
//  FeedActivityObserver.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/22/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreData
import Foundation

class FeedActivityObserver: NSObject, NSFetchedResultsControllerDelegate {

    private let fetchedResultsController: NSFetchedResultsController<FeedActivity>

    init(_ managedObjectContext: NSManagedObjectContext) {
        let fetchRequest: NSFetchRequest<FeedActivity> = FeedActivity.fetchRequest()
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedActivity.timestamp, ascending: false) ]
        fetchedResultsController = NSFetchedResultsController<FeedActivity>(fetchRequest: fetchRequest, managedObjectContext: managedObjectContext, sectionNameKeyPath: nil, cacheName: nil)
        super.init()
        fetchedResultsController.delegate = self
        do {
            try fetchedResultsController.performFetch()
        } catch {
            DDLogError("FeedActivityObserver/fetch/error [\(error)]")
            fatalError("Failed to fetch post activities.")
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
        let fetchRequest: NSFetchRequest<FeedActivity> = FeedActivity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "read = %@", NSExpression(forConstantValue: false))
        do {
            self.unreadCount = try managedObjectContext.count(for: fetchRequest)
        }
        catch {
            DDLogError("FeedActivityObserver/fetch/error [\(error)]")
            fatalError("Failed to fetch post activities.")
        }
    }

    // MARK: NSFetchedResultsControllerDelegate

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        self.reloadUnreadCount()
    }

}
