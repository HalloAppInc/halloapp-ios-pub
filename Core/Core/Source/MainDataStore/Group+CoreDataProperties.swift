//
//  Group+CoreDataProperties.swift
//  Core
//
//  Created by Garrett on 4/1/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CoreCommon
import CoreData

public typealias GroupType = ThreadType

public extension Group {

    enum ExpirationType: Int16 {
        case expiresInSeconds = 0
        case never = 1
        case customDate = 2

        public var serverExpiryType: Server_ExpiryInfo.ExpiryType {
            switch self {
            case .expiresInSeconds:
                return .expiresInSeconds
            case .never:
                return .never
            case .customDate:
                return .customDate
            }
        }
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<Group> {
        return NSFetchRequest<Group>(entityName: "Group")
    }

    @NSManaged var id: String
    @NSManaged var name: String
    @NSManaged var typeValue: Int16
    @NSManaged var avatarID: String?
    @NSManaged var background: Int32
    @NSManaged var desc: String?
    @NSManaged var maxSize: Int16
    @NSManaged var lastSync: Date?
    @NSManaged var inviteLink: String?

    @NSManaged private var expirationTypeValue: Int16

    var expirationType: ExpirationType {
        get {
            return ExpirationType(rawValue: expirationTypeValue) ?? .expiresInSeconds
        }
        set {
            expirationTypeValue = newValue.rawValue
        }
    }

    var type: GroupType {
        get {
            return GroupType(rawValue: self.typeValue) ?? .groupFeed
        }
        set {
            self.typeValue = newValue.rawValue
        }
    }

    /*
     If expirationType == .expiresInSeconds, this represents the number of seconds until a post expires
     If expirationType == .customDate, this represents the time interval since 1970
     */
    @NSManaged var expirationTime: Int64

    @NSManaged var members: Set<GroupMember>?

    var orderedMembers: [GroupMember] {
        get {
            guard let members = self.members else { return [] }
            return members.sorted { $0.userID < $1.userID }
        }
    }
}

// MARK: - Expiration Helpers

extension Group {

    public func postExpirationDate(from date: Date) -> Date? {
        switch expirationType {
        case .expiresInSeconds:
            return date.addingTimeInterval(TimeInterval(expirationTime))
        case .never:
            return nil
        case .customDate:
            return Date(timeIntervalSince1970: TimeInterval(expirationTime))
        }
    }
}

public extension Int64 {

    static let oneDay = Int64(24 * 60 * 60)
    static let thirtyDays = Int64(30 * 24 * 60 * 60)
}
