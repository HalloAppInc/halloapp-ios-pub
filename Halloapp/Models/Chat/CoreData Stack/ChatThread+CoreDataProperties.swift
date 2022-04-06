//
//  ChatThread+CoreDataProperties.swift
//  HalloApp
//
//  Created by Tony Jiang on 4/28/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Core
import CoreCommon
import CoreData
import Foundation

extension ChatThreadLegacy {

    @nonobjc class func fetchRequest() -> NSFetchRequest<ChatThread> {
        return NSFetchRequest<ChatThread>(entityName: "ChatThread")
    }

    @NSManaged private var typeValue: Int16
    
    @NSManaged var groupId: GroupID?
    @NSManaged var chatWithUserId: UserID?
    
    @NSManaged var title: String?
    
    // currently only used to show a specific preview for when a contact was invited by user and then accepts
    // once set to true, flag does not need to be set to false
    @NSManaged var isNew: Bool
    
    @NSManaged var lastMsgId: String?
    @NSManaged var lastMsgUserId: UserID?
    @NSManaged private var lastMsgStatusValue: Int16
    @NSManaged var lastMsgText: String?
    @NSManaged private var lastMsgMediaTypeValue: Int16
    @NSManaged var lastMsgTimestamp: Date?
    @NSManaged var unreadCount: Int32

    @NSManaged var lastFeedId: FeedPostID?
    @NSManaged var lastFeedUserID: UserID?
    @NSManaged private var lastFeedStatusValue: Int16
    @NSManaged var lastFeedText: String?
    @NSManaged private var lastFeedMediaTypeValue: Int16
    @NSManaged var unreadFeedCount: Int32

    @NSManaged var lastFeedTimestamp: Date?

    var type: ChatType {
        get {
            return ChatType(rawValue: self.typeValue) ?? .oneToOne
        }
        set {
            self.typeValue = newValue.rawValue
        }
    }
    
    var lastMsgStatus: CommonThread.LastMsgStatus {
        get {
            return CommonThread.LastMsgStatus(rawValue: self.lastMsgStatusValue) ?? .none
        }
        set {
            self.lastMsgStatusValue = newValue.rawValue
        }
    }
    
    var lastMsgMediaType: CommonThread.LastMediaType {
        get {
            return CommonThread.LastMediaType(rawValue: self.lastMsgMediaTypeValue) ?? .none
        }
        set {
            self.lastMsgMediaTypeValue = newValue.rawValue
        }
    }

    var lastFeedStatus: CommonThread.LastFeedStatus {
        get {
            return CommonThread.LastFeedStatus(rawValue: self.lastFeedStatusValue) ?? .none
        }
        set {
            self.lastFeedStatusValue = newValue.rawValue
        }
    }
    
    var lastFeedMediaType: CommonThread.LastMediaType {
        get {
            return CommonThread.LastMediaType(rawValue: self.lastMsgMediaTypeValue) ?? .none
        }
        set {
            self.lastMsgMediaTypeValue = newValue.rawValue
        }
    }

}
