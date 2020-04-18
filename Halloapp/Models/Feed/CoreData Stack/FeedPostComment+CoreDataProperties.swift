//
//  FeedPostComment+CoreDataProperties.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/7/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Foundation
import CoreData

extension FeedPostComment {

    enum Status: Int16 {
        case none = 0
        case sending = 1
        case sent = 2
        case sendError = 3
        case incoming = 4
        case deleted = 5
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<FeedPostComment> {
        return NSFetchRequest<FeedPostComment>(entityName: "FeedPostComment")
    }

    @NSManaged var id: FeedPostID
    @NSManaged var text: String
    @NSManaged var timestamp: Date
    @NSManaged var userId: UserID
    @NSManaged var parent: FeedPostComment?
    @NSManaged var post: FeedPost
    @NSManaged var replies: NSSet?
    @NSManaged private var statusValue: Int16
    var status: Status {
        get {
            return Status(rawValue: self.statusValue)!
        }
        set {
            self.statusValue = newValue.rawValue
        }
    }

    var isCommentDeleted: Bool {
        get {
            return self.status == .deleted
        }
        set {
            self.status = .deleted
        }
    }

}
