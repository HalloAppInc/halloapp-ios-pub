//
//  FeedPostComment+CoreDataProperties.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/7/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Core
import CoreData
import Foundation

extension FeedPostComment {

    enum Status: Int16 {
        case none = 0
        case sending = 1
        case sent = 2
        case sendError = 3
        case incoming = 4
        case retracted = 5
        case retracting = 6
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<FeedPostComment> {
        return NSFetchRequest<FeedPostComment>(entityName: "FeedPostComment")
    }

    @NSManaged public var id: FeedPostID
    @NSManaged public var mentions: Set<FeedMention>?
    @NSManaged public var text: String
    @NSManaged public var timestamp: Date
    @NSManaged public var userId: UserID
    @NSManaged var parent: FeedPostComment?
    @NSManaged var post: FeedPost
    @NSManaged var replies: Set<FeedPostComment>?
    @NSManaged private var statusValue: Int16
    var status: Status {
        get {
            return Status(rawValue: self.statusValue)!
        }
        set {
            self.statusValue = newValue.rawValue
        }
    }

    var canBeRetracted: Bool {
        get {
            status == .sent
        }
    }

    var isRetracted: Bool {
        get {
            return status == .retracted || status == .retracting
        }
    }

    var isPosted: Bool {
        get {
            return status == .sent || status == .incoming
        }
    }
}

extension FeedPostComment: FeedCommentProtocol {

    public static var itemType: FeedItemType {
        .comment
    }

    public var feedPostId: String {
        get { post.id }
    }

    public var feedPostUserId: UserID {
        get { post.userId }
    }

    public var parentId: String? {
        get { parent?.id }
    }

    public var orderedMentions: [FeedMentionProtocol] {
        get {
            guard let mentions = self.mentions else { return [] }
            return mentions.sorted { $0.index < $1.index }
        }
    }
}
