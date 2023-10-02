//
//  FriendActivity+CoreDataProperties.swift
//  
//
//  Created by Tanveer on 9/28/23.
//
//

import Foundation
import CoreData
import CoreCommon
import CocoaLumberjackSwift

extension FriendActivity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<FriendActivity> {
        return NSFetchRequest<FriendActivity>(entityName: "FriendActivity")
    }

    @NSManaged public var userID: String
    @NSManaged public var timestamp: Date
    @NSManaged public var read: Bool
    @NSManaged private var statusValue: Int16
}

// MARK: - Status

extension FriendActivity {

    public enum Status: Int16 {
        case none = 0
        /// An incoming friend request.
        case pending = 1
        /// An outgoing friend request that has been accepted.
        case accepted = 2
    }

    public var status: Status {
        get {
            Status(rawValue: statusValue) ?? .none
        }

        set {
            refresh(newValue)
            statusValue = newValue.rawValue
        }
    }

    private func refresh(_ newStatus: Status) {
        let updatedRead: Bool

        if case .none = newStatus {
            updatedRead = true
        } else if status != newStatus {
            updatedRead = false
        } else {
            updatedRead = true
        }

        read = updatedRead
        timestamp = Date()
    }
}

// MARK: - Fetch

extension FriendActivity {

    public class func findOrCreate(with userID: UserID, in context: NSManagedObjectContext) -> FriendActivity {
        if let existing = find(with: userID, in: context) {
            return existing
        } else {
            let activity = FriendActivity(context: context)
            activity.userID = userID
            return activity
        }
    }

    public class func find(with userID: UserID, in context: NSManagedObjectContext) -> FriendActivity? {
        let predicate = NSPredicate(format: "userID == %@", userID)
        return findFirst(predicate: predicate, in: context)
    }

    public class func findFirst(predicate: NSPredicate, in context: NSManagedObjectContext) -> FriendActivity? {
        let request = Self.fetchRequest()
        request.predicate = predicate
        request.fetchLimit = 1

        do {
            return try context.fetch(request).first
        } catch {
            DDLogError("FriendActivity/findFirst/fetch failed with error [\(String(describing: error))]")
            return nil
        }
    }

    public class func find(predicate: NSPredicate, in context: NSManagedObjectContext) -> [FriendActivity] {
        let request = Self.fetchRequest()
        request.predicate = predicate

        do {
            return try context.fetch(request)
        } catch {
            DDLogError("FriendActivity/find/fetch failed with error [\(String(describing: error))]")
            return []
        }
    }
}
