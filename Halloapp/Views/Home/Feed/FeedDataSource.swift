//
//  FeedDataSource.swift
//  HalloApp
//
//  Created by Garrett on 3/4/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import CoreData
import UIKit
import Combine

protocol FeedDataSourceDelegate: AnyObject {
    func itemsDidChange(_ items: [FeedDisplayItem])
    func itemDidChange(_ item: FeedDisplayItem, change type: FeedDataSource.FeedDataSourceChangeType)
    func modifyItems(_ items: [FeedDisplayItem]) -> [FeedDisplayItem]
}

// MARK: - default implementations

extension FeedDataSourceDelegate {
    func itemDidChange(_ item: FeedDisplayItem, change type: FeedDataSource.FeedDataSourceChangeType) { }

    func modifyItems(_ items: [FeedDisplayItem]) -> [FeedDisplayItem] {
        return items
    }
}

final class FeedDataSource: NSObject {
    typealias FeedDataSourceChangeType = NSFetchedResultsChangeType

    init(fetchRequest: NSFetchRequest<FeedPost>) {
        self.fetchRequest = fetchRequest
        super.init()

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification, object: nil)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.verifyOldestUnexpiredMoment()
            }
            .store(in: &cancellables)

        MainAppContext.shared.feedData.validMoment
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // in this case we want to refresh since we want the prompt cell to be
                // inserted again
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    weak var delegate: FeedDataSourceDelegate?
    private var cancellables: Set<AnyCancellable> = []
    
    private(set) var displayItems = [FeedDisplayItem]()
    var deletionLabelToExpand: FeedDisplayItem?
    private var oldestUnexpiredMoment: Date?

    var events = [FeedEvent]()

    func index(of feedPostID: FeedPostID) -> Int? {
        return displayItems.firstIndex(where: {
            switch $0 {
            case .momentStack(let moments):
                return moments.contains(where: { $0.moment?.id == feedPostID })
            case .moment(let post):
                return post.id == feedPostID
            case .post(let post):
                return post.id == feedPostID
            case .event, .groupWelcome, .inviteCarousel, .welcome:
                return false
            }
        })
    }

    func item(at index: Int) -> FeedDisplayItem? {
        guard index < displayItems.count else { return nil }
        return displayItems[index]
    }

    var hasUnreadPosts: Bool {
        return posts.contains(where: { [.incoming].contains($0.status) })
    }

    /// All posts, including moments.
    var posts: [FeedPost] {
        return fetchedResultsController?.fetchedObjects ?? []
    }
    /// Items that are in the moments stack.
    private(set) var momentItems: [MomentStackItem] = []

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
            displayItems = makeDisplayItems(orderedPosts: posts, orderedEvents: events)
            if let modifiedItems = delegate?.modifyItems(displayItems) {
                displayItems = modifiedItems
            }
            delegate?.itemsDidChange(displayItems)
        } catch {
            fatalError("Failed to fetch feed items \(error)")
        }
    }

    func refresh() {
        let posts = fetchedResultsController?.fetchedObjects ?? []
        displayItems = makeDisplayItems(orderedPosts: posts, orderedEvents: events)
        if let modifiedItems = delegate?.modifyItems(displayItems) {
            displayItems = modifiedItems
        }
        delegate?.itemsDidChange(displayItems)
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
        delegate?.itemsDidChange(displayItems)
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

    private func mergeDeletionPosts(originalItems: [FeedDisplayItem])->[FeedDisplayItem] {
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
                    let newEvent = FeedEvent(description: Self.deletedPostWithNumber(from: num-begin),
                                               timestamp: displayItems[begin].post?.timestamp ?? Date(),
                                                isThemed: false,
                                         containingItems: Array(displayItems[begin..<num]))
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
    private func makeDisplayItems(orderedPosts: [FeedPost], orderedEvents: [FeedEvent]) -> [FeedDisplayItem] {
        var originalItems = [FeedDisplayItem]()
        let (filteredPosts, validMoments) = filterOutMoments(orderedPosts)
        
        originalItems.append(contentsOf: filteredPosts.map { $0.isMoment ? .moment($0) : .post($0) })
        originalItems.append(contentsOf: orderedEvents.map { FeedDisplayItem.event($0) })
        
        originalItems = originalItems.sorted {
            let t1 = $0.post?.timestamp ?? $0.event?.timestamp ?? Date()
            let t2 = $1.post?.timestamp ?? $1.event?.timestamp ?? Date()
            return t1 > t2
        }

        if !validMoments.isEmpty {
            originalItems.insert(.momentStack(validMoments), at: 0)
        }

        self.momentItems = validMoments

        //merge consecutive deletion posts when the count of consecutive deletion posts >=3
        let displayItems = mergeDeletionPosts(originalItems: originalItems)
        return displayItems
    }

    /// Filters out expired moments and seperates valid moments from regular feed posts.
    private func filterOutMoments(_ orderedPosts: [FeedPost]) -> (posts: [FeedPost], moments: [MomentStackItem]) {
        let momentCutoff = FeedData.momentCutoffDate
        let expiredCache = MainAppContext.shared.feedData.expiredMoments
        var stackedMoments = [MomentStackItem]()
        oldestUnexpiredMoment = nil

        // regular feed posts and the user's own moment
        let nonStackedPosts = orderedPosts.filter {
            guard $0.isMoment else {
                return true
            }

            if $0.timestamp < momentCutoff || $0.status == .retracted || $0.status == .expired {
                // no tombstones for moments
                return false
            }

            if expiredCache.contains($0.id) {
                DDLogError("FeedDataSource/filterOutMoments/found an already expired moment id: [\($0.id)] status: [\($0.status)] cache contents: [\(expiredCache)]")
                MainAppContext.shared.errorLogger?.logError(NSError(domain: "ExpiredMomentInDataSource", code: 1))
                return false
            }

            // post is a moment and is valid
            // keep track of the oldest valid moment so that we can refresh when the app foregrounds
            if let currentOldest = oldestUnexpiredMoment {
                oldestUnexpiredMoment = $0.timestamp < currentOldest ? $0.timestamp : currentOldest
            } else {
                oldestUnexpiredMoment = $0.timestamp
            }

            if $0.userId == MainAppContext.shared.userData.userId {
                return true
            }

            stackedMoments.append(.moment($0))
            return false
        }

        DDLogInfo("FeedDataSource/filterOutMoments/ posts \(nonStackedPosts.count); moments: \(stackedMoments.count)")
        return (nonStackedPosts, stackedMoments)
    }

    /**
     Checks if the oldest unexpired moment in the feed is still valid. If not, refresh.

     - note: Right now this is called when the app enters the foreground. Can go a bit further and
             schedule a `DispatchItem` or `Timer` so that the feed will update while the app is active.
     */
    private func verifyOldestUnexpiredMoment() {
        guard
            let oldestUnexpiredMoment = oldestUnexpiredMoment,
            let expiration = Calendar.current.date(byAdding: .day, value: 1, to: oldestUnexpiredMoment)
        else {
            return
        }

        if expiration < Date() {
            refresh()
        }
    }
}

extension FeedDataSource: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        let posts = (controller.fetchedObjects as? [FeedPost]) ?? []
        displayItems = makeDisplayItems(orderedPosts: posts, orderedEvents: events)
        if let modifiedItems = delegate?.modifyItems(displayItems) {
            displayItems = modifiedItems
        }
        delegate?.itemsDidChange(displayItems)
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>,
              didChange anObject: Any,
                    at indexPath: IndexPath?,
                        for type: NSFetchedResultsChangeType,
                    newIndexPath: IndexPath?)
    {
        if let post = anObject as? FeedPost {
            let item = FeedDisplayItem.post(post)
            delegate?.itemDidChange(item, change: type)
        }
    }
}

extension FeedDataSource {
    static func groupFeedRequest(groupID: GroupID) -> NSFetchRequest<FeedPost> {
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "groupID == %@ && (expiration >= now() || expiration == nil) && fromExternalShare == NO", groupID)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
        return fetchRequest
    }

    static func homeFeedRequest() -> NSFetchRequest<FeedPost> {
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "(groupID == nil || statusValue != %d) && (expiration >= now() || expiration == nil) && fromExternalShare == NO",
                                             FeedPost.Status.retracted.rawValue)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
        fetchRequest.relationshipKeyPathsForPrefetching = ["mentions", "media", "linkPreviews"]
        return fetchRequest
    }

    static func userFeedRequest(userID: UserID) -> NSFetchRequest<FeedPost> {
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userID == %@ && (groupID == nil || statusValue != %d) && (expiration >= now() || expiration == nil) && fromExternalShare == NO",
                                             userID,
                                             FeedPost.Status.retracted.rawValue)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
        return fetchRequest
    }
    
    static func archiveFeedRequest() -> NSFetchRequest<FeedPost> {
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "userID == %@", MainAppContext.shared.userData.userId),
            NSPredicate(format: "expiration < now()"),
            NSPredicate(format: "fromExternalShare == NO"),
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
    case moment(FeedPost)
    case momentStack([MomentStackItem])
    case event(FeedEvent)
    case welcome
    case groupWelcome(GroupID)
    case inviteCarousel

    var post: FeedPost? {
        switch self {
        case .post(let post): return post
        case .moment(let post): return post
        case .momentStack: return nil
        case .event: return nil
        case .welcome: return nil
        case .groupWelcome: return nil
        case .inviteCarousel: return nil
        }
    }
    
    var event: FeedEvent? {
        switch self {
        case .post: return nil
        case .moment: return nil
        case .momentStack: return nil
        case .event(let event): return event
        case .welcome: return nil
        case .groupWelcome: return nil
        case .inviteCarousel: return nil
        }
    }
    
    var groupWelcome: GroupID? {
        switch self {
        case .post: return nil
        case .moment: return nil
        case .event: return nil
        case .welcome: return nil
        case .groupWelcome(let groupID): return groupID
        case .inviteCarousel: return nil
        case .momentStack: return nil
        }
    }
}

struct FeedPostDisplayData: Equatable {
    var currentMediaIndex: Int?
    var textNumberOfLines: Int?
}

struct FeedEvent: Hashable, Equatable {
    var description: String
    var timestamp: Date
    var isThemed: Bool
    var containingItems: [FeedDisplayItem]?
}


