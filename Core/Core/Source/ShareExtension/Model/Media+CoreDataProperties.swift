//
//  Media+CoreDataProperties.swift
//  
//
//  Created by Alan Luo on 7/16/20.
//
//

import CoreData
import UIKit


/*
 SharedMedia can be used to describe media for
 both SharedFeedPost and SharedChatMessage (coming soon)
 */
extension SharedMedia {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<SharedMedia> {
        return NSFetchRequest<SharedMedia>(entityName: "SharedMedia")
    }
    
    public var `type`: FeedMediaType {
        get {
            return FeedMediaType(rawValue: Int(self.typeValue))!
        }
        set {
            typeValue = Int16(newValue.rawValue)
        }
    }
    
    public var size: CGSize {
        get {
            return CGSize(width: CGFloat(width), height: CGFloat(height))
        }
        set {
            width = Float(newValue.width)
            height = Float(newValue.height)
        }
    }

    @NSManaged public var height: Float
    @NSManaged public var key: String
    @NSManaged public var order: Int16
    @NSManaged public var relativeFilePath: String
    @NSManaged public var sha256: String
    @NSManaged public var typeValue: Int16
    @NSManaged public var url: URL
    @NSManaged public var width: Float
    
    @NSManaged public var post: SharedFeedPost?
    @NSManaged public var message: SharedChatMessage?

}

extension SharedMedia: FeedMediaProtocol {
    public var id: String {
        "\(post!.id)-\(order)"
    }
}
