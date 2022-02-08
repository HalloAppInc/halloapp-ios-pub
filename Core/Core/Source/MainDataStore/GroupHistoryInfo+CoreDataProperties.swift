//
//  GroupHistoryInfo+CoreDataProperties.swift
//  Core
//
//  Created by Murali Balusu on 2/1/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//
//

import Foundation
import CoreData


extension GroupHistoryInfo {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<GroupHistoryInfo> {
        return NSFetchRequest<GroupHistoryInfo>(entityName: "GroupHistoryInfo")
    }

    @NSManaged public var groupId: String
    @NSManaged public var id: String
    // This data could be HistoryResend-info or GroupFeedItems-history-info.
    @NSManaged public var payload: Data
    @NSManaged public var contentResendInfo: NSSet


}

// MARK: Generated accessors for contentResendInfo
extension GroupHistoryInfo {

    @objc(addContentResendInfoObject:)
    @NSManaged public func addToContentResendInfo(_ value: ContentResendInfo)

    @objc(removeContentResendInfoObject:)
    @NSManaged public func removeFromContentResendInfo(_ value: ContentResendInfo)

    @objc(addContentResendInfo:)
    @NSManaged public func addToContentResendInfo(_ values: NSSet)

    @objc(removeContentResendInfo:)
    @NSManaged public func removeFromContentResendInfo(_ values: NSSet)

}

extension GroupHistoryInfo : Identifiable {

}
