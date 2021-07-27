//
//  FeedDataSource.swift
//  HalloApp
//
//  Created by Garrett on 3/4/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
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
    
    var events = [FeedEvent]()

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

    func refresh() {
        let posts = fetchedResultsController?.fetchedObjects ?? []
        displayItems = FeedDataSource.makeDisplayItems(orderedPosts: posts, orderedEvents: events)
        itemsDidChange?(displayItems)
    }

    // MARK: Private

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

        displayItems.append(contentsOf: orderedPosts.map { FeedDisplayItem.post($0) })
        displayItems.append(contentsOf: orderedEvents.map { FeedDisplayItem.event($0) })
        
        return displayItems.sorted {
            let t1 = $0.post?.timestamp ?? $0.event?.timestamp ?? Date()
            let t2 = $1.post?.timestamp ?? $1.event?.timestamp ?? Date()
            return t1 > t2
        }
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

    static func homeFeedRequest() -> NSFetchRequest<FeedPost> {
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "groupId == nil || statusValue != %d", FeedPost.Status.retracted.rawValue)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
        return fetchRequest
    }

    static func userFeedRequest(userID: UserID) -> NSFetchRequest<FeedPost> {
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userId == %@ && (groupId == nil || statusValue != %d)", userID, FeedPost.Status.retracted.rawValue)
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
    
    var event: FeedEvent? {
        switch self {
        case .post: return nil
        case .event(let event): return event
        }
    }
}

struct FeedPostDisplayData: Equatable {
    var currentMediaIndex: Int? = nil
    var isTextExpanded = false
}

struct FeedEvent: Hashable, Equatable {
    var description: String
    var timestamp: Date
    var isThemed: Bool
}
