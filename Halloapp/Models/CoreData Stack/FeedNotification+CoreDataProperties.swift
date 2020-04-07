//
//  FeedNotification+CoreDataProperties.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import CoreData
import Foundation
import UIKit

extension FeedNotification {
    enum Event: Int16 {
        case comment = 0    // comment on your post
        case reply = 1      // reply to your comment
    }

    enum MediaType: Int16 {
        case none = 0
        case image = 1
        case video = 2
    }

    @nonobjc public class func fetchRequest() -> NSFetchRequest<FeedNotification> {
        return NSFetchRequest<FeedNotification>(entityName: "FeedNotification")
    }

    @NSManaged private var eventValue: Int16
    var event: Event {
        get {
            return Event(rawValue: self.eventValue)!
        }
        set {
            self.eventValue = newValue.rawValue
        }
    }
    @NSManaged public var commentId: String?
    @NSManaged public var mediaPreview: Data?
    @NSManaged public var postId: String
    @NSManaged public var userId: String
    @NSManaged public var read: Bool
    @NSManaged public var text: String?
    @NSManaged public var timestamp: Date
    @NSManaged private var postMediaType: Int16
    var mediaType: MediaType {
        get {
            return MediaType(rawValue: self.postMediaType) ?? .none
        }
        set {
            self.postMediaType = newValue.rawValue
        }
    }

}
