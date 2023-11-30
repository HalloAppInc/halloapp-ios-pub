//
//  FetchedResultsControllerAsyncSequence.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 11/28/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreData

struct PhotoSuggestionsFetchedResultsControllerAsyncSequence<FetchedResultType: NSFetchRequestResult, ResultType: Sendable>: AsyncSequence {

    typealias Element = ResultType

    private let fetchRequest: NSFetchRequest<FetchedResultType>
    private let photoSuggestionsData: PhotoSuggestionsData
    private let mapping: @Sendable (FetchedResultType) -> ResultType?

    init(fetchRequest: NSFetchRequest<FetchedResultType>, photoSuggestionsData: PhotoSuggestionsData, mapping: @escaping @Sendable (FetchedResultType) -> ResultType?) {
        self.fetchRequest = fetchRequest
        self.photoSuggestionsData = photoSuggestionsData
        self.mapping = mapping
    }

    class Iterator: NSObject, NSFetchedResultsControllerDelegate, AsyncIteratorProtocol {
        
        private let fetchedResultsController: NSFetchedResultsController<FetchedResultType>
        private let mapping: @Sendable (FetchedResultType) -> ResultType?

        private let onChangeStream: AsyncStream<Void>
        private let onChangeContinuation: AsyncStream<Void>.Continuation

        init(fetchedResultsController: NSFetchedResultsController<FetchedResultType>, mapping: @escaping @Sendable (FetchedResultType) -> ResultType?) {
            self.fetchedResultsController = fetchedResultsController
            self.mapping = mapping
            (onChangeStream, onChangeContinuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingOldest(1))

            super.init()

            fetchedResultsController.delegate = self

            do {
                try fetchedResultsController.performFetch()
            } catch {
                DDLogError("UnclusteredAssetIterator/failed initial fetch: \(error)")
            }
        }

        func next() async -> ResultType? {
            // Loop infinitely, return to break
            while true {
                if Task.isCancelled {
                    return nil
                }

                let nextIdentifier = await fetchedResultsController.managedObjectContext.perform {
                    return self.fetchedResultsController.fetchedObjects?.first.flatMap { self.mapping($0) }
                }

                if let nextIdentifier {
                    return nextIdentifier
                }

                let onChangeContinuation = onChangeContinuation
                await withTaskCancellationHandler {
                    var iterator = onChangeStream.makeAsyncIterator()
                    await iterator.next()
                } onCancel: {
                    onChangeContinuation.finish()
                }
            }
        }

        func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith diff: CollectionDifference<NSManagedObjectID>) {
            onChangeContinuation.yield()
        }
    }

    func makeAsyncIterator() -> Iterator {
        let context = photoSuggestionsData.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true

        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: nil,
                                                                  cacheName: nil)

        return Iterator(fetchedResultsController: fetchedResultsController, mapping: mapping)
    }
}

extension PhotoSuggestionsFetchedResultsControllerAsyncSequence where FetchedResultType: IdentifiableManagedObject, ResultType == String, FetchedResultType == FetchedResultType.ManagedObjectType {

    init(fetchRequest: NSFetchRequest<FetchedResultType>, photoSuggestionsData: PhotoSuggestionsData) {
        self.init(fetchRequest: fetchRequest, photoSuggestionsData: photoSuggestionsData) { identifiableManagedObject in
            return identifiableManagedObject.identifier
        }
    }
}
