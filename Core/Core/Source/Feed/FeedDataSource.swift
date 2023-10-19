//
//  FeedDataSource.swift
//  HalloApp
//
//  Created by Garrett on 3/4/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import CoreCommon
import CoreData

public protocol FeedDataSourceDelegate: AnyObject {
    func itemsDidChange(_ items: [FeedDisplayItem])
    func itemDidChange(_ item: FeedDisplayItem, change type: FeedDataSource.FeedDataSourceChangeType)
    func modifyItems(_ items: [FeedDisplayItem]) -> [FeedDisplayItem]
}

// MARK: - default implementations

public extension FeedDataSourceDelegate {
    func itemDidChange(_ item: FeedDisplayItem, change type: FeedDataSource.FeedDataSourceChangeType) { }

    func modifyItems(_ items: [FeedDisplayItem]) -> [FeedDisplayItem] {
        return items
    }
}

public final class FeedDataSource: NSObject {
    public typealias FeedDataSourceChangeType = NSFetchedResultsChangeType

    public init(fetchRequest: NSFetchRequest<FeedPost>) {
        self.fetchRequest = fetchRequest
        super.init()

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification, object: nil)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.verifyOldestUnexpiredMoment()
            }
            .store(in: &cancellables)
    }

    public weak var delegate: FeedDataSourceDelegate?
    private var cancellables: Set<AnyCancellable> = []
    
    public private(set) var displayItems = [FeedDisplayItem]()
    var deletionLabelToExpand: FeedDisplayItem?
    private var oldestUnexpiredMoment: Date?

    public var events = [FeedEvent]()

    public func index(of feedPostID: FeedPostID) -> Int? {
        return displayItems.firstIndex(where: {
            switch $0 {
            case .momentStack(let moments):
                return moments.contains(where: { $0.moment?.id == feedPostID })
            case .moment(let post):
                return post.id == feedPostID
            case .post(let post):
                return post.id == feedPostID
            case .event, .groupWelcome, .inviteCarousel, .suggestionsCarousel, .welcome, .shareCarousel:
                return false
            }
        })
    }

    public func index(of groupEvent: GroupEvent) -> Int? {
        return displayItems.firstIndex {
            switch $0 {
            case .event(let feedEvent):
                switch feedEvent {
                case .groupEvent(let event):
                    return event == groupEvent
                case .collapsedGroupEvents(let events):
                    return events.contains { $0 == groupEvent }
                default:
                    return false
                }
            default:
                return false
            }
        }
    }

    public func item(at index: Int) -> FeedDisplayItem? {
        guard index < displayItems.count else { return nil }
        return displayItems[index]
    }

    public func removeItem(_ item: FeedDisplayItem) {
        displayItems.removeAll { $0 == item }
        delegate?.itemsDidChange(displayItems)
    }

    public var hasUnreadPosts: Bool {
        return posts.contains(where: { [.incoming].contains($0.status) })
    }

    /// All posts, including moments.
    public var posts: [FeedPost] {
        return fetchedResultsController?.fetchedObjects ?? []
    }
    /// Items that are in the moments stack.
    public private(set) var momentItems: [MomentStackItem] = []

    public func clear() {
        fetchedResultsController = nil
        events.removeAll()
        displayItems.removeAll()
    }

    public func setup() {
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

    public func refresh() {
        let posts = fetchedResultsController?.fetchedObjects ?? []
        displayItems = makeDisplayItems(orderedPosts: posts, orderedEvents: events)
        if let modifiedItems = delegate?.modifyItems(displayItems) {
            displayItems = modifiedItems
        }
        delegate?.itemsDidChange(displayItems)
    }

    public func toggleExpansion(feedEvent: FeedEvent) {
        guard let index = displayItems.firstIndex(of: .event(feedEvent)) else {
            DDLogError("FeedDataSource/toggleExpansion/could not find feedEvent")
            return
        }

        switch feedEvent {
        case .groupEvent(let groupEvent):
            var groupEvents: [GroupEvent] = [groupEvent]
            var firstIndex = index
            while firstIndex > 0,
                  case .event(let previousFeedEvent) = displayItems[firstIndex - 1],
                  case .groupEvent(let previousGroupEvent) = previousFeedEvent,
                  groupEvent.canCollapse(with: previousGroupEvent) {
                groupEvents.insert(previousGroupEvent, at: 0)
                firstIndex -= 1
            }

            var lastIndex = index
            while lastIndex < displayItems.count - 1,
                  case .event(let nextFeedEvent) = displayItems[lastIndex + 1],
                  case .groupEvent(let nextGroupEvent) = nextFeedEvent,
                  groupEvent.canCollapse(with: nextGroupEvent){
                groupEvents.append(nextGroupEvent)
                lastIndex += 1
            }

            if groupEvents.count >= 3 {
                groupEvents.forEach { expandedEventObjectIDs.remove($0.objectID) }
                displayItems.replaceSubrange(Range(uncheckedBounds: (firstIndex, lastIndex + 1)), with: [.event(.collapsedGroupEvents(groupEvents))])
            }
        case .collapsedGroupEvents(let groupEvents):
            groupEvents.forEach { groupEvent in
                expandedEventObjectIDs.insert(groupEvent.objectID)
            }
            displayItems.remove(at: index)
            displayItems.insert(contentsOf: groupEvents.map { .event(.groupEvent($0)) }, at: index)
        case .deletedPost(let feedPost):
            var retractedPosts: [FeedPost] = [feedPost]
            var firstIndex = index
            while firstIndex > 0,
                  case .event(let previousFeedEvent) = displayItems[firstIndex - 1],
                  case .deletedPost(let previousRetractedPost) = previousFeedEvent {
                retractedPosts.insert(previousRetractedPost, at: 0)
                firstIndex -= 1
            }

            var lastIndex = index
            while lastIndex < displayItems.count - 1,
                  case .event(let nextFeedEvent) = displayItems[lastIndex + 1],
                  case .deletedPost(let nextRetractedPost) = nextFeedEvent {
                retractedPosts.append(nextRetractedPost)
                lastIndex += 1
            }

            if retractedPosts.count >= 3 {
                retractedPosts.forEach { expandedRetractedPostIDs.remove($0.id) }
                displayItems.replaceSubrange(Range(uncheckedBounds: (firstIndex, lastIndex + 1)), with: [.event(.collapsedDeletedPosts(retractedPosts))])
            }
        case .collapsedDeletedPosts(let feedPosts):
            feedPosts.forEach { feedPost in
                expandedRetractedPostIDs.insert(feedPost.id)
            }
            displayItems.remove(at: index)
            displayItems.insert(contentsOf: feedPosts.map { .event(.deletedPost($0)) }, at: index)
        }
        delegate?.itemsDidChange(displayItems)
    }
    
    // MARK: Private

    private var fetchedResultsController: NSFetchedResultsController<FeedPost>?
    private let fetchRequest: NSFetchRequest<FeedPost>

    private var expandedEventObjectIDs: Set<NSManagedObjectID> = []
    private var expandedRetractedPostIDs: Set<FeedPostID> = []

    private func newFetchedResultsController() -> NSFetchedResultsController<FeedPost> {
        let fetchedResultsController = NSFetchedResultsController<FeedPost>(
            fetchRequest: fetchRequest,
            managedObjectContext: AppContext.shared.mainDataStore.viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil)
        fetchedResultsController.delegate = self
        return fetchedResultsController
    }

    private func mergeEvents(in displayItems: [FeedDisplayItem]) -> [FeedDisplayItem] {
        var mergedDisplayItems: [FeedDisplayItem] = []
        var pendingGroupEvents: [GroupEvent]?
        var pendingRetractedPosts: [FeedPost]?

        let appendPendingGroupEvents = {
            guard let groupEvents = pendingGroupEvents else {
                return
            }
            if groupEvents.count >= 3 {
                mergedDisplayItems.append(.event(.collapsedGroupEvents(groupEvents)))
            } else {
                mergedDisplayItems.append(contentsOf: groupEvents.map { .event(.groupEvent($0)) })
            }
            pendingGroupEvents = nil
        }

        let appendPendingRetractedPosts = {
            guard let retractedPosts = pendingRetractedPosts  else {
                return
            }
            if retractedPosts.count >= 3 {
                mergedDisplayItems.append(.event(.collapsedDeletedPosts(retractedPosts)))
            } else {
                mergedDisplayItems.append(contentsOf: retractedPosts.map { .event(.deletedPost($0)) })
            }
            pendingRetractedPosts = nil
        }

        // Keep a buffer of events or posts that can be merged, and append once events no longer match.
        for displayItem in displayItems {
            if case .event(let feedEvent) = displayItem {
                switch feedEvent {
                case .deletedPost(let feedPost):
                    appendPendingGroupEvents()

                    if !(pendingRetractedPosts?.isEmpty ?? true), !expandedRetractedPostIDs.contains(feedPost.id) {
                        pendingRetractedPosts?.append(feedPost)
                    } else {
                        appendPendingRetractedPosts()
                        pendingRetractedPosts = [feedPost]
                    }
                case .groupEvent(let groupEvent):
                    appendPendingRetractedPosts()

                    if let lastGroupEvent = pendingGroupEvents?.last, groupEvent.canCollapse(with: lastGroupEvent), !expandedEventObjectIDs.contains(groupEvent.objectID) {
                        pendingGroupEvents?.append(groupEvent)
                    } else {
                        appendPendingGroupEvents()
                        pendingGroupEvents = [groupEvent]
                    }
                default:
                    appendPendingGroupEvents()
                    appendPendingRetractedPosts()
                    mergedDisplayItems.append(displayItem)
                }
            } else {
                appendPendingGroupEvents()
                appendPendingRetractedPosts()
                mergedDisplayItems.append(displayItem)
            }
        }

        appendPendingGroupEvents()
        appendPendingRetractedPosts()

        return mergedDisplayItems
    }

    /// Merges lists of posts and events (sorted by descending timestamp) into a single display item list
    private func makeDisplayItems(orderedPosts: [FeedPost], orderedEvents: [FeedEvent]) -> [FeedDisplayItem] {
        var originalItems = [FeedDisplayItem]()
        let (filteredPosts, validMoments) = filterOutMoments(orderedPosts)

        originalItems += filteredPosts.map { feedPost in
            if feedPost.isPostRetracted {
                return .event(.deletedPost(feedPost))
            } else if feedPost.isMoment {
                return .moment(feedPost)
            } else {
                return .post(feedPost)
            }
        }
        originalItems += orderedEvents.map { event in
            return .event(event)
        }

        originalItems = originalItems.sorted {
            let t1 = $0.post?.timestamp ?? $0.event?.timestamp ?? Date()
            let t2 = $1.post?.timestamp ?? $1.event?.timestamp ?? Date()
            return t1 > t2
        }

        if !validMoments.isEmpty {
            originalItems.insert(.momentStack(validMoments), at: 0)
        }

        self.momentItems = validMoments

        return mergeEvents(in: originalItems)
    }

    /// Filters out expired moments and seperates valid moments from regular feed posts.
    private func filterOutMoments(_ orderedPosts: [FeedPost]) -> (posts: [FeedPost], moments: [MomentStackItem]) {
        let momentCutoff = CoreFeedData.momentCutoffDate
        var stackedMoments = [MomentStackItem]()
        oldestUnexpiredMoment = nil

        // regular feed posts and the user's own moment
        let nonStackedPosts = orderedPosts.filter {
            guard $0.isMoment else {
                return true
            }

            if $0.timestamp < momentCutoff || $0.status == .retracted {
                // no tombstones for moments
                return false
            }

            // post is a moment and is valid
            // keep track of the oldest valid moment so that we can refresh when the app foregrounds
            if let currentOldest = oldestUnexpiredMoment {
                oldestUnexpiredMoment = $0.timestamp < currentOldest ? $0.timestamp : currentOldest
            } else {
                oldestUnexpiredMoment = $0.timestamp
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
    public func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        let posts = (controller.fetchedObjects as? [FeedPost]) ?? []
        displayItems = makeDisplayItems(orderedPosts: posts, orderedEvents: events)
        if let modifiedItems = delegate?.modifyItems(displayItems) {
            displayItems = modifiedItems
        }
        delegate?.itemsDidChange(displayItems)
    }
    
    public func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>,
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

public extension FeedDataSource {
    static func groupFeedRequest(groupID: GroupID) -> NSFetchRequest<FeedPost> {
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "groupID == %@ && (expiration >= now() || expiration == nil) && fromExternalShare == NO", groupID)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
        return fetchRequest
    }

    static func momentFeedRequest(since cutoffDate: Date) -> NSFetchRequest<FeedPost> {
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "timestamp > %@ && isMoment == YES", cutoffDate as NSDate)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
        return fetchRequest
    }

    static func homeFeedRequest() -> NSFetchRequest<FeedPost> {
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "(groupID == nil || statusValue != %d) && (expiration >= now() || expiration == nil) && fromExternalShare == NO",
                                             FeedPost.Status.retracted.rawValue)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
        fetchRequest.relationshipKeyPathsForPrefetching = ["user", "mentions", "media", "linkPreviews"]
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
    
    static func archiveFeedRequest(userID: UserID) -> NSFetchRequest<FeedPost> {
        let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "userID == %@", userID),
            NSPredicate(format: "expiration < now()"),
            NSPredicate(format: "fromExternalShare == NO"),
        ])
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
        return fetchRequest
    }
}

public enum FeedDisplaySection {
    case posts
}

public enum FeedDisplayItem: Hashable, Equatable {
    case post(FeedPost)
    case moment(FeedPost)
    case momentStack([MomentStackItem])
    case event(FeedEvent)
    case welcome
    case groupWelcome(GroupID)
    case inviteCarousel
    case suggestionsCarousel
    case shareCarousel(FeedPostID)

    public var post: FeedPost? {
        switch self {
        case .post(let post): return post
        case .moment(let post): return post
        case .momentStack: return nil
        case .event: return nil
        case .welcome: return nil
        case .groupWelcome: return nil
        case .inviteCarousel: return nil
        case .suggestionsCarousel: return nil
        case .shareCarousel: return nil
        }
    }
    
    public var event: FeedEvent? {
        switch self {
        case .post: return nil
        case .moment: return nil
        case .momentStack: return nil
        case .event(let event): return event
        case .welcome: return nil
        case .groupWelcome: return nil
        case .inviteCarousel: return nil
        case .suggestionsCarousel: return nil
        case .shareCarousel: return nil
        }
    }
    
    public var groupWelcome: GroupID? {
        switch self {
        case .post: return nil
        case .moment: return nil
        case .event: return nil
        case .welcome: return nil
        case .groupWelcome(let groupID): return groupID
        case .inviteCarousel: return nil
        case .suggestionsCarousel: return nil
        case .momentStack: return nil
        case .shareCarousel: return nil
        }
    }
}

public enum MomentStackItem: Equatable, Hashable {
    case moment(FeedPost)
    case prompt

    public var moment: FeedPost? {
        switch self {
        case .moment(let moment):
            return moment
        case .prompt:
            return nil
        }
    }
}

public enum FeedEvent: Hashable, Equatable {
    case groupEvent(GroupEvent)
    case collapsedGroupEvents([GroupEvent])
    case deletedPost(FeedPost)
    case collapsedDeletedPosts([FeedPost])

    var timestamp: Date {
        switch self {
        case .groupEvent(let groupEvent):
            return groupEvent.timestamp
        case .collapsedGroupEvents(let groupEvents):
            return groupEvents.first?.timestamp ?? Date()
        case .deletedPost(let feedPost):
            return feedPost.timestamp
        case .collapsedDeletedPosts(let feedPosts):
            return feedPosts.first?.timestamp ?? Date()
        }
    }
}
