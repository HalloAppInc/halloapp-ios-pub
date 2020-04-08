//
//  FeedPostMedia+CoreDataProperties.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/7/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Foundation
import CoreData
import UIKit

extension FeedPostMedia {

    enum MediaType: Int16 {
        case image = 0
        case video = 1
    }

    enum Status: Int16 {
        case none = 0
        case uploading = 1
        case uploaded = 2
        case downloading = 3
        case downloaded = 4
    }

    @nonobjc public class func fetchRequest() -> NSFetchRequest<FeedPostMedia> {
        return NSFetchRequest<FeedPostMedia>(entityName: "FeedPostMedia")
    }

    var `type`: MediaType {
        get {
            return MediaType(rawValue: self.typeValue)!
        }
        set {
            self.typeValue = newValue.rawValue
        }
    }
    @NSManaged public var typeValue: Int16
    @NSManaged public var path: URL?
    @NSManaged public var url: URL
    @NSManaged public var post: FeedPost
    @NSManaged private var statusValue: Int16
    var status: Status {
        get {
            return Status(rawValue: self.statusValue)!
        }
        set {
            self.statusValue = newValue.rawValue
        }
    }

    @NSManaged private var width: Float
    @NSManaged private var height: Float
    var size: CGSize {
        get {
            return CGSize(width: CGFloat(self.width), height: CGFloat(self.height))
        }
        set {
            self.width = Float(newValue.width)
            self.height = Float(newValue.height)
        }
    }

    @NSManaged var key: String
    @NSManaged var sha256: String
    @NSManaged var order: Int16
}
