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

    typealias ID = String

    enum Status: Int16 {
        case none = 0
        case sending = 1
        case sent = 2
        case sendError = 3
        case incoming = 4
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<FeedPostComment> {
        return NSFetchRequest<FeedPostComment>(entityName: "FeedPostComment")
    }

    @NSManaged var id: ID
    @NSManaged var text: String
    @NSManaged var timestamp: Date
    @NSManaged var userId: String
    @NSManaged var parent: FeedPostComment?
    @NSManaged var post: FeedPost
    @NSManaged var replies: FeedPostComment?
    @NSManaged private var statusValue: Int16
    var status: Status {
        get {
            return Status(rawValue: self.statusValue)!
        }
        set {
            self.statusValue = newValue.rawValue
        }
    }

}
