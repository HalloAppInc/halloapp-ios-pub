//
//  CountController.swift
//  Core
//
//  Created by Chris Leonavicius on 8/23/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import CoreData

open class CountController<ResultType>: NSObject, NSFetchedResultsControllerDelegate where ResultType : NSFetchRequestResult {

    private let fetchedResultsController: NSFetchedResultsController<ResultType>

    public let count = CurrentValueSubject<Int, Never>(0)

    public init(fetchRequest: NSFetchRequest<ResultType>, managedObjectContext context: NSManagedObjectContext) {
        fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: context, sectionNameKeyPath: nil, cacheName: nil)
        super.init()
        fetchedResultsController.delegate = self

        do {
            try fetchedResultsController.performFetch()
        } catch {
            DDLogError("CountController/failed to perform initial fetch")
        }

        updateCount()
    }

    public func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        updateCount()
    }

    // public so external callers can force a refresh
    public func updateCount() {
        count.send(fetchedResultsController.sections?.first?.numberOfObjects ?? 0)
    }
}
