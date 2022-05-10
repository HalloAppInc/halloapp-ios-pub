//
//  CommonLinkPreview+CoreDataProperties.swift
//  Core
//
//  Created by Garrett on 3/22/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CoreData

public extension CommonLinkPreview {

    @nonobjc class func fetchRequest() -> NSFetchRequest<CommonLinkPreview> {
        return NSFetchRequest<CommonLinkPreview>(entityName: "CommonLinkPreview")
    }

    @NSManaged var id: FeedLinkPreviewID
    @NSManaged var desc: String?
    @NSManaged var title: String?
    @NSManaged var url: URL?
    @NSManaged var comment: FeedPostComment?
    @NSManaged var media: Set<CommonMedia>?
    @NSManaged var post: FeedPost?
    @NSManaged var message: ChatMessage?

    var contentOwnerID: String? {
        if let post = post {
            return post.id
        } else if let comment = comment {
            return comment.id
        } else if let message = message {
            return message.id
        }
        return nil
    }
}
