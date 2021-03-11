//
//  FeedDataSource.swift
//  HalloApp
//
//  Created by Garrett on 3/4/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
import CoreData
import UIKit

final class FeedDataSource: NSObject {

    init(fetchRequest: NSFetchRequest<FeedPost>) {
        self.fetchRequest = fetchRequest
        super.init()
        setup()
    }

    var itemsDidChange: (([FeedDisplayItem]) -> Void)?
    private(set) var displayItems = [FeedDisplayItem]()

    func index(of feedPostID: FeedPostID) -> Int? {
        return displayItems.firstIndex(where: {
            guard case .post(let post) = $0 else { return false }
            return post.id == feedPostID
        })
    }

    func item(at index: Int) -> FeedDisplayItem? {
        guard index < displayItems.count else { return nil }
        return displayItems[index]
    }

    func clear() {
        fetchedResultsController = nil
        events.removeAll()
        displayItems.removeAll()
    }

    func setup() {
        fetchedResultsController = newFetchedResultsController()
        do {
            try fetchedResultsController?.performFetch()
            let posts = fetchedResultsController?.fetchedObjects ?? []
            displayItems = FeedDataSource.makeDisplayItems(orderedPosts: posts, orderedEvents: events)
            itemsDidChange?(displayItems)
        } catch {
            fatalError("Failed to fetch feed items \(error)")
        }
    }

    // MARK: Private

    private var events = [FeedEvent]()

    private var fetchedResultsController: NSFetchedResultsController<FeedPost>?
    private let fetchRequest: NSFetchRequest<FeedPost>

    private func newFetchedResultsController() -> NSFetchedResultsController<FeedPost> {
        let fetchedResultsController = NSFetchedResultsController<FeedPost>(
            fetchRequest: fetchRequest,
            managedObjectContext: MainAppContext.shared.feedData.viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil)
        fetchedResultsController.delegate = self
        return fetchedResultsController
    }

    /// Merges lists of posts and events (sorted by descending timestamp) into a single display item list
    private static func makeDisplayItems(orderedPosts: [FeedPost], orderedEvents: [FeedEvent]) -> [FeedDisplayItem]
    {
        var displayItems = [FeedDisplayItem]()
        var post_i = 0
        var event_i = 0

        // Choose newest post or event until one list is exhausted
        while post_i < orderedPosts.count && event_i < orderedEvents.count {
            let post = orderedPosts[post_i]
            let event = orderedEvents[event_i]
            if post.timestamp > event.timestamp {
                displayItems.append(.post(post))
                post_i += 1
            } else {
                displayItems.append(.event(event))
                event_i += 1
            }
        }

        // Add remaining items from whichever list still has some
        displayItems.append(contentsOf: orderedPosts[post_i...].map { FeedDisplayItem.post($0) })
        displayItems.append(contentsOf: orderedEvents[event_i...].map { FeedDisplayItem.event($0) })

        return displayItems
    }
}

extension FeedDataSource: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        let posts = (controller.fetchedObjects as? [FeedPost]) ?? []
        displayItems = FeedDataSource.makeDisplayItems(orderedPosts: posts, orderedEvents: events)
        itemsDidChange?(displayItems)
    }
}

extension FeedDataSource {
    static func groupFeedRequest(groupID: GroupID) -> NSFetchRequest<FeedPost> {
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "groupId == %@", groupID)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
        return fetchRequest
    }

    static func homeFeedRequest(combinedFeed: Bool) -> NSFetchRequest<FeedPost> {
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        if !combinedFeed {
            fetchRequest.predicate = NSPredicate(format: "groupId == nil")
        }
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
        return fetchRequest
    }

    static func userFeedRequest(userID: UserID) -> NSFetchRequest<FeedPost> {
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userId == %@", userID)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
        return fetchRequest
    }
}

enum FeedDisplaySection {
    case posts
}

enum FeedDisplayItem: Hashable, Equatable {
    case post(FeedPost)
    case event(FeedEvent)

    var post: FeedPost? {
        switch self {
        case .post(let post): return post
        case .event: return nil
        }
    }
}

struct FeedEvent: Hashable, Equatable {
    var description: String
    var timestamp: Date
}
