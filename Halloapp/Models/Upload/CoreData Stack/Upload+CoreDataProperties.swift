//
//  Upload+CoreDataProperties.swift
//
//

import Foundation
import CoreData


extension Upload {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Upload> {
        return NSFetchRequest<Upload>(entityName: "Upload")
    }

    @NSManaged public var url: URL?
    @NSManaged public var dataHash: String?
    @NSManaged public var sha256: String?
    @NSManaged public var key: String?
    @NSManaged public var timestamp: Date?

}
