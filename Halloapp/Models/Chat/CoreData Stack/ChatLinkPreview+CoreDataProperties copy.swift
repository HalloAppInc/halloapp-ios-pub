//
//  ChatLinkPreview+CoreDataProperties.swift
//  HalloApp
//
//  Created by Nandini Shetty on 10/29/21.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Core
import CoreCommon
import CoreData
import Foundation
import UIKit

extension ChatLinkPreview {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ChatLinkPreview> {
        return NSFetchRequest<ChatLinkPreview>(entityName: "ChatLinkPreview")
    }

    @NSManaged public var id: ChatLinkPreviewID
    @NSManaged public var desc: String?
    @NSManaged public var title: String?
    @NSManaged public var url: URL?
    @NSManaged public var message: ChatMessage?
    @NSManaged var media: Set<ChatMedia>?

}

// MARK: Generated accessors for media
extension ChatLinkPreview {

    @objc(addMediaObject:)
    @NSManaged public func addToMedia(_ value: ChatMedia)

    @objc(removeMediaObject:)
    @NSManaged public func removeFromMedia(_ value: ChatMedia)

    @objc(addMedia:)
    @NSManaged public func addToMedia(_ values: NSSet)

    @objc(removeMedia:)
    @NSManaged public func removeFromMedia(_ values: NSSet)

}

extension ChatLinkPreview : Identifiable {

}


