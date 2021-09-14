//
//  MediaHash+CoreDataProperties.swift
//  
//
//  Created by Murali Balusu on 9/13/21.
//
//

import Foundation
import CoreData


extension MediaHash {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<MediaHash> {
        return NSFetchRequest<MediaHash>(entityName: "MediaHash")
    }

    @NSManaged public var dataHash: String?
    @NSManaged public var sha256: String?
    @NSManaged public var timestamp: Date?
    @NSManaged public var url: URL?
    @NSManaged public var key: String?

}
