//
//  ExternalShareInfo+CoreDataProperties.swift
//  
//
//  Created by Chris Leonavicius on 3/18/22.
//
//

import Foundation
import CoreData


extension ExternalShareInfo {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ExternalShareInfo> {
        return NSFetchRequest<ExternalShareInfo>(entityName: "ExternalShareInfo")
    }

    @NSManaged public var feedPostID: String?
    @NSManaged public var blobID: String?
    @NSManaged public var key: Data?

}
