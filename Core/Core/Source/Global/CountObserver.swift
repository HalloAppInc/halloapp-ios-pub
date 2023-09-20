//
//  CountObserver.swift
//  Core
//
//  Created by Chris Leonavicius on 1/13/23.
//  Copyright © 2023 Hallo App, Inc. All rights reserved.
//

import Combine
import CoreData

public class CountObserver<T: NSManagedObject>: NSObject, NSFetchedResultsControllerDelegate {

    private let fetchedResultsController: NSFetchedResultsController<T>

    public var countDidChange: ((Int) -> Void)?

    public var count: Int {
        return fetchedResultsController.fetchedObjects?.count ?? 0
    }

    public init(context: NSManagedObjectContext, predicate: NSPredicate, countDidChange: ((Int) -> Void)? = nil) {
        self.countDidChange = countDidChange

        let fetchRequest = NSFetchRequest<T>()
        fetchRequest.entity = T.entity()
        fetchRequest.includesPendingChanges = false
        fetchRequest.includesPropertyValues = false
        fetchRequest.predicate = predicate
        fetchRequest.returnsObjectsAsFaults = true
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \NSManagedObject.objectID, ascending: true)]

        fetchedResultsController = NSFetchedResultsController<T>(fetchRequest: fetchRequest,
                                                                 managedObjectContext: context,
                                                                 sectionNameKeyPath: nil,
                                                                 cacheName: nil)

        super.init()

        fetchedResultsController.delegate = self
        try? fetchedResultsController.performFetch()
    }

    public func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        countDidChange?(count)
    }
}

public class CountPublisher<CountPublisherModel: NSManagedObject>: Publisher {

    public typealias Output = Int
    public typealias Failure = Never

    private class CountSubscription<S, T: NSManagedObject>: Subscription where S : Subscriber, Never == S.Failure, Int == S.Input {

        let countObserver: CountObserver<T>
        var subscriber: S?

        init(subscriber: S, countObserver: CountObserver<T>) {
            self.countObserver = countObserver
            self.subscriber = subscriber
            countObserver.countDidChange = { [weak self] count in
                _ = self?.subscriber?.receive(count)
            }
            _ = subscriber.receive(countObserver.count)
        }


        func request(_ demand: Subscribers.Demand) {
            // no-op
        }

        func cancel() {
            subscriber = nil
        }
    }

    private let context: NSManagedObjectContext
    private let predicate: NSPredicate

    public init(context: NSManagedObjectContext, predicate: NSPredicate) {
        self.context = context
        self.predicate = predicate
    }

    public func receive<S>(subscriber: S) where S : Subscriber, Never == S.Failure, Int == S.Input {
        subscriber.receive(subscription: CountSubscription(subscriber: subscriber, countObserver: CountObserver<CountPublisherModel>(context: context, predicate: predicate)))
    }
}
