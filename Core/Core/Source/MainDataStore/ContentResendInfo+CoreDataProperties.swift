//
//  ContentResendInfo+CoreDataProperties.swift
//  Core
//
//  Created by Murali Balusu on 2/1/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//
//

import Foundation
import CoreData


extension ContentResendInfo {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ContentResendInfo> {
        return NSFetchRequest<ContentResendInfo>(entityName: "ContentResendInfo")
    }

    @NSManaged public var contentID: String
    @NSManaged public var retryCount: Int32
    @NSManaged public var userID: String
    @NSManaged public var groupHistoryInfo: GroupHistoryInfo?

}

extension ContentResendInfo : Identifiable {

}
