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
    var deletionLabelToExpand: FeedDisplayItem?
    
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
    
    func expand(expandItem: FeedDisplayItem) {
        var thisEvent: FeedEvent?
        var index = -1
        for term in displayItems {
            index += 1
            if let evt = term.event {
                if expandItem == term {
                    thisEvent = evt
                    break
                }
            }
        }
        if let thisEvent = thisEvent {
            displayItems.remove(at: index)
            for addDeletion in thisEvent.containingItems! {
                displayItems.insert(addDeletion, at: index)
            }
        }
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

    private static func mergeDeletionPosts(originalItems: [FeedDisplayItem])->[FeedDisplayItem] {
        var displayItems = originalItems
        var count = 0
        var begin = 0
        var num = -1
        for item in displayItems {
            num += 1
            var isRetracted = false
            if let thisPost = item.post {
                if thisPost.isPostRetracted {
                    count += 1
                    isRetracted = true
                }
            }
            if ((!isRetracted) || (num == displayItems.count && isRetracted)) {
                if count >= 3 {
                    let newEvent = FeedEvent(description: deletedPostWithNumber(from: num-begin), timestamp: displayItems[begin].post?.timestamp ?? Date(), isThemed: false, containingItems: Array(displayItems[begin..<num]))
                    var pos = num - 1
                    while pos >= begin {
                        displayItems.remove(at: pos)
                        pos -= 1
                    }
                    num = pos + 1
                    displayItems.insert(FeedDisplayItem.event(newEvent), at: num)
                    num += 1
                }
                count = 0
                begin = num + 1
            }
        }
        return displayItems
    }
    
    /// Merges lists of posts and events (sorted by descending timestamp) into a single display item list
    private static func makeDisplayItems(orderedPosts: [FeedPost], orderedEvents: [FeedEvent]) -> [FeedDisplayItem]
    {
        var originalItems = [FeedDisplayItem]()

        originalItems.append(contentsOf: orderedPosts.map { FeedDisplayItem.post($0) })
        originalItems.append(contentsOf: orderedEvents.map { FeedDisplayItem.event($0) })
        
        originalItems = originalItems.sorted {
            let t1 = $0.post?.timestamp ?? $0.event?.timestamp ?? Date()
            let t2 = $1.post?.timestamp ?? $1.event?.timestamp ?? Date()
            return t1 > t2
        }
        
        //merge consecutive deletion posts when the count of consecutive deletion posts >=3
        let displayItems = mergeDeletionPosts(originalItems: originalItems)
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
        fetchRequest.predicate = NSPredicate(format: "groupId == %@ && timestamp >= %@", groupID, FeedData.cutoffDate as NSDate)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
        return fetchRequest
    }

    static func homeFeedRequest() -> NSFetchRequest<FeedPost> {
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "(groupId == nil || statusValue != %d) && timestamp >= %@",
                                             FeedPost.Status.retracted.rawValue,
                                             FeedData.cutoffDate as NSDate)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
        return fetchRequest
    }

    static func userFeedRequest(userID: UserID) -> NSFetchRequest<FeedPost> {
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userId == %@ && (groupId == nil || statusValue != %d) && timestamp >= %@", userID,
                                             FeedPost.Status.retracted.rawValue,
                                             FeedData.cutoffDate as NSDate)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
        return fetchRequest
    }
    
    static func archiveFeedRequest() -> NSFetchRequest<FeedPost> {
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
//            NSPredicate(format: "userId == -1", MainAppContext.shared.userData.userId),
            NSPredicate(format: "userId == %@", MainAppContext.shared.userData.userId),
//            NSPredicate(format: "timestamp < %@", FeedData.cutoffDate as NSDate)
        ])
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
        return fetchRequest
    }
    
    static func deletedPostWithNumber(from number: Int) -> String {
        let format = NSLocalizedString("n.posts.deleted", value: "%@ posts deleted", comment: "Displayed in place of deleted feed posts.")
        return String(format: format, String(number))
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
    var containingItems: [FeedDisplayItem]?
}


