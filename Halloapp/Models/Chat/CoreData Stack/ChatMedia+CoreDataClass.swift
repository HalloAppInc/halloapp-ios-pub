//
//  ChatMedia+CoreDataClass.swift
//  HalloApp
//
//  Created by Tony Jiang on 4/28/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Core
import CoreCommon
import Foundation
import CoreData

@objc(ChatMedia)
public class ChatMedia: NSManagedObject {
    
    @NSManaged public var linkPreview: ChatLinkPreview?

    public var feedMediaType: FeedMediaType {
        get {
            switch type {
            case .image:
                return .image
            case .video:
                return .video
            case .audio:
                return .audio
            }
        }
    }
}
