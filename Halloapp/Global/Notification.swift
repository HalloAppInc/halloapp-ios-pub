//
//  Notification.swift
//  HalloApp
//
//  Created by Alan Luo on 6/5/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation

struct NotificationKey {
    struct keys {
        static let metadata = "metadata"
        static let contentType = "content-type"
        static let fromId = "from-id"
        static let userDefaults = "tap-notification-metadata"
    }
    
    struct contentType {
        static let chat = "chat"
        static let comment = "comment"
        static let feedpost = "feedpost"
    }
}
