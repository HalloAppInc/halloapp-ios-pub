//
//  CommonLocation+CoreDataProperties.swift
//  
//
//  Created by Cay Zhang on 8/2/22.
//
//

import Foundation
import CoreData


extension CommonLocation {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CommonLocation> {
        return NSFetchRequest<CommonLocation>(entityName: "CommonLocation")
    }

    @NSManaged public var latitude: Double
    @NSManaged public var longitude: Double
    @NSManaged public var name: String?
    @NSManaged public var addressString: String?

}

extension CommonLocation {
    
    public convenience init(chatLocation: any ChatLocationProtocol, context: NSManagedObjectContext) {
        self.init(context: context)
        latitude = chatLocation.latitude
        longitude = chatLocation.longitude
        name = chatLocation.name
        addressString = chatLocation.formattedAddressLines.joined(separator: "\n")
    }
    
}
