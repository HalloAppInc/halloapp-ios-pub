//
//  Thread+CoreDataProperties.swift
//  Core
//
//  Created by Garrett on 4/1/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CoreCommon
import CoreData

public enum ThreadType: Int16 {
    case oneToOne = 0
    case group = 1 // Group feed
}

public extension CommonThread {

    enum LastMsgStatus: Int16 {
        case none = 0
        case pending = 1
        case sentOut = 2
        case delivered = 3
        case seen = 4
        case error = 5
        case retracting = 6
        case retracted = 7
        case played = 8
    }

    enum LastMediaType: Int16 {
        case none = 0
        case image = 1
        case video = 2
        case audio = 3
        case missedAudioCall = 4
        case incomingAudioCall = 5
        case outgoingAudioCall = 6
        case missedVideoCall = 7
        case incomingVideoCall = 8
        case outgoingVideoCall = 9
        case location = 10
    }

    enum LastFeedStatus: Int16 {
        case none = 0
        case retracted = 11
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<CommonThread> {
        return NSFetchRequest<CommonThread>(entityName: "CommonThread")
    }

    @NSManaged private var typeValue: Int16

    @NSManaged var groupID: GroupID?
    @NSManaged var userID: UserID?

    @NSManaged var title: String?

    // currently only used to show a specific preview for when a contact was invited by user and then accepts
    // once set to true, flag does not need to be set to false
    @NSManaged var isNew: Bool

    @NSManaged var lastContentID: String?
    @NSManaged var lastUserID: UserID?
    @NSManaged private var lastStatusValue: Int16
    @NSManaged var lastText: String?
    @NSManaged private var lastMediaTypeValue: Int16
    @NSManaged var lastTimestamp: Date?
    @NSManaged var unreadCount: Int32

    var type: ChatType {
        get {
            return ChatType(rawValue: self.typeValue) ?? .oneToOne
        }
        set {
            self.typeValue = newValue.rawValue
        }
    }

    var lastMediaType: LastMediaType {
        get {
            return LastMediaType(rawValue: self.lastMediaTypeValue) ?? .none
        }
        set {
            self.lastMediaTypeValue = newValue.rawValue
        }
    }

    var lastMsgStatus: LastMsgStatus {
        get {
            guard type == .oneToOne else { return .none }
            return LastMsgStatus(rawValue: self.lastStatusValue) ?? .none
        }
        set {
            guard type == .oneToOne else { return }
            self.lastStatusValue = newValue.rawValue
        }
    }

    var lastFeedStatus: LastFeedStatus {
        get {
            guard type == .group else { return .none }
            return LastFeedStatus(rawValue: self.lastStatusValue) ?? .none
        }
        set {
            guard type == .group else { return }
            self.lastStatusValue = newValue.rawValue
        }
    }
}

public extension CommonThread {

    // TODO: Remove these shims

    var groupId: GroupID? {
        get { return groupID }
        set { groupID = newValue }
    }

    var lastMsgMediaType: LastMediaType {
        get { return type == .oneToOne ? lastMediaType : .none }
        set {
            guard type == .oneToOne else { return }
            lastMediaType = newValue
        }
    }

    var lastFeedMediaType: LastMediaType {
        get { return type == .group ? lastMediaType : .none }
        set {
            guard type == .group else { return }
            lastMediaType = newValue
        }
    }

    var unreadFeedCount: Int32 {
        get { return type == .group ? unreadCount : 0 }
        set {
            guard type == .group else { return }
            unreadCount = newValue
        }
    }

    var lastFeedId: String? {
        get { return type == .group ? lastContentID : nil }
        set {
            guard type == .group else { return }
            lastContentID = newValue
        }
    }

    var lastMsgId: String? {
        get { return type == .oneToOne ? lastContentID : nil }
        set {
            guard type == .oneToOne else { return }
            lastContentID = newValue
        }
    }

    var lastFeedTimestamp: Date? {
        get { return type == .group ? lastTimestamp : nil }
        set {
            guard type == .group else { return }
            lastTimestamp = newValue
        }
    }

    var lastMsgTimestamp: Date? {
        get { return type == .oneToOne ? lastTimestamp : nil }
        set {
            guard type == .oneToOne else { return }
            lastTimestamp = newValue
        }
    }

    var lastFeedText: String? {
        get { return type == .group ? lastText : nil }
        set {
            guard type == .group else { return }
            lastText = newValue
        }
    }

    var lastMsgText: String? {
        get { return type == .oneToOne ? lastText : nil }
        set {
            guard type == .oneToOne else { return }
            lastText = newValue
        }
    }

    var lastFeedUserID: String? {
        get { return type == .group ? lastUserID : nil }
        set {
            guard type == .group else { return }
            lastUserID = newValue
        }
    }

    var lastMsgUserId: String? {
        get { return type == .oneToOne ? lastUserID : nil }
        set {
            guard type == .oneToOne else { return }
            lastUserID = newValue
        }
    }
}
