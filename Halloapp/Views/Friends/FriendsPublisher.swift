//
//  FriendsPublisher.swift
//  HalloApp
//
//  Created by Tanveer on 8/28/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import Combine
import CoreData
import Core

struct FriendsPublisher: Publisher {

    typealias Friend = FriendsDataSource.Friend
    typealias Output = [Friend]
    typealias Failure = Never

    enum Status {
        case friends, incoming, outgoing, pending
    }

    private let predicate: NSPredicate

    init(_ status: Status) {
        let predicate: NSPredicate

        switch status {
        case.friends:
            predicate = .init(format: "friendshipStatusValue == %d",
                              UserProfile.FriendshipStatus.friends.rawValue)
        case .incoming:
            predicate = .init(format: "friendshipStatusValue == %d",
                              UserProfile.FriendshipStatus.incomingPending.rawValue)
        case .outgoing:
            predicate = .init(format: "friendshipStatusValue == %d",
                              UserProfile.FriendshipStatus.outgoingPending.rawValue)
        case .pending:
            predicate = .init(format: "friendshipStatusValue == %d OR friendshipStatusValue == %d",
                              UserProfile.FriendshipStatus.incomingPending.rawValue,
                              UserProfile.FriendshipStatus.outgoingPending.rawValue)
        }

        self.predicate = predicate
    }

    func receive<S>(subscriber: S) where S : Subscriber, Never == S.Failure, [Friend] == S.Input {
        let subscription = FriendSubscription(context: MainAppContext.shared.mainDataStore.viewContext,
                                              predicate: predicate,
                                              subscriber: subscriber)

        subscriber.receive(subscription: subscription)
        _ = subscriber.receive(subscription.friends)
    }
}

// MARK: - FriendSubscription

fileprivate class FriendSubscription<S: Subscriber>: NSObject, NSFetchedResultsControllerDelegate, Subscription where S.Input == [FriendsPublisher.Friend] {

    typealias Friend = FriendsPublisher.Friend

    private let resultsController: NSFetchedResultsController<UserProfile>
    private var subscriber: S?

    var friends: [Friend] {
        let profiles = resultsController.fetchedObjects ?? []
        return profiles.map {
            Friend(id: $0.id, name: $0.name, username: $0.username, friendshipStatus: $0.friendshipStatus)
        }
    }

    init(context: NSManagedObjectContext, predicate: NSPredicate, subscriber: S) {
        let request = UserProfile.fetchRequest()
        request.predicate = predicate
        request.sortDescriptors = []

        resultsController = .init(fetchRequest: request,
                                  managedObjectContext: context,
                                  sectionNameKeyPath: nil,
                                  cacheName: nil)
        self.subscriber = subscriber
        super.init()

        resultsController.delegate = self

        do {
            try resultsController.performFetch()
            _ = subscriber.receive(friends)
        } catch {
            subscriber.receive(completion: .finished)
        }
    }

    func request(_ demand: Subscribers.Demand) {

    }

    func cancel() {
        subscriber = nil
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        _ = subscriber?.receive(friends)
    }
}
