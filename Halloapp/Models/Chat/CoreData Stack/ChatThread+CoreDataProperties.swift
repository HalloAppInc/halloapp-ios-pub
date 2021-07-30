//
//  ChatThread+CoreDataProperties.swift
//  HalloApp
//
//  Created by Tony Jiang on 4/28/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Core
import CoreData
import Foundation

extension ChatThread {

    enum LastMsgStatus: Int16 {
        case none = 0
        case pending = 1
        case sentOut = 2
        case delivered = 3
        case seen = 4
        case error = 5
        case retracting = 6
        case retracted = 7
    }
    
    enum LastMediaType: Int16 {
        case none = 0
        case image = 1
        case video = 2
    }
    
    enum LastFeedStatus: Int16 {
        case none = 0
        case retracted = 11
    }
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ChatThread> {
        return NSFetchRequest<ChatThread>(entityName: "ChatThread")
    }

    @NSManaged private var typeValue: Int16
    
    @NSManaged var groupId: GroupID?
    @NSManaged var chatWithUserId: UserID?
    
    @NSManaged var title: String?
    @NSManaged var isNew: Bool
    
    @NSManaged var lastMsgId: String?
    @NSManaged var lastMsgUserId: String?
    @NSManaged private var lastMsgStatusValue: Int16
    @NSManaged var lastMsgText: String?
    @NSManaged private var lastMsgMediaTypeValue: Int16
    @NSManaged var lastMsgTimestamp: Date?
    @NSManaged var unreadCount: Int32
    
    @NSManaged var draft: String?
    @NSManaged var draftMentions: Set<ChatMention>?
    
    @NSManaged var lastFeedId: String?
    @NSManaged var lastFeedUserID: String?
    @NSManaged private var lastFeedStatusValue: Int16
    @NSManaged var lastFeedText: String?
    @NSManaged private var lastFeedMediaTypeValue: Int16
    @NSManaged var lastFeedTimestamp: Date?
    @NSManaged var unreadFeedCount: Int32
    
    var type: ChatType {
        get {
            return ChatType(rawValue: self.typeValue) ?? .oneToOne
        }
        set {
            self.typeValue = newValue.rawValue
        }
    }
    
    var lastMsgStatus: LastMsgStatus {
        get {
            return LastMsgStatus(rawValue: self.lastMsgStatusValue) ?? .none
        }
        set {
            self.lastMsgStatusValue = newValue.rawValue
        }
    }
    
    var lastMsgMediaType: LastMediaType {
        get {
            return LastMediaType(rawValue: self.lastMsgMediaTypeValue) ?? .none
        }
        set {
            self.lastMsgMediaTypeValue = newValue.rawValue
        }
    }

    var lastFeedStatus: LastFeedStatus {
        get {
            return LastFeedStatus(rawValue: self.lastFeedStatusValue) ?? .none
        }
        set {
            self.lastFeedStatusValue = newValue.rawValue
        }
    }
    
    var lastFeedMediaType: LastMediaType {
        get {
            return LastMediaType(rawValue: self.lastMsgMediaTypeValue) ?? .none
        }
        set {
            self.lastMsgMediaTypeValue = newValue.rawValue
        }
    }
    
    
    public var orderedDraftMentions: [ChatMention] {
        get {
            guard let mentions = self.draftMentions else { return [] }
            return mentions.sorted { $0.index < $1.index }
        }
    }

}
