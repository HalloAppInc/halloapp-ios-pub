//
//  SharedServerMessage+CoreDataProperties.swift
//  
//
//  Created by Murali Balusu on 4/26/21.
//
//

import Foundation
import CoreData


extension SharedServerMessage {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<SharedServerMessage> {
        return NSFetchRequest<SharedServerMessage>(entityName: "SharedServerMessage")
    }

    @NSManaged public var msg: Data
    @NSManaged public var timestamp: Date

}
