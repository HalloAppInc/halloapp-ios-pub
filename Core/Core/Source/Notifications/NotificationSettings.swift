//
//  NotificationSettings.swift
//  Core
//
//  Created by Murali Balusu on 12/14/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import Foundation


public struct NotificationUserDefaultKeys {
    public static let isSynchronized = "NotificationSettings1"   // Bool
    public static let postsEnabled = "NotificationSettings2"     // Bool
    public static let commentsEnabled = "NotificationSettings3"  // Bool
    public static let momentsEnabled = "NotificationSettings4"    // Bool
}


public struct NotificationSettings {
    public static var isPostsEnabled: Bool {
        get {
            AppContext.shared.userDefaults.register(defaults: [ NotificationUserDefaultKeys.postsEnabled: true])
            return AppContext.shared.userDefaults.bool(forKey: NotificationUserDefaultKeys.postsEnabled)
        }
    }

    public static var isCommentsEnabled: Bool {
        get {
            AppContext.shared.userDefaults.register(defaults: [ NotificationUserDefaultKeys.commentsEnabled: true])
            return AppContext.shared.userDefaults.bool(forKey: NotificationUserDefaultKeys.commentsEnabled)
        }
    }

    public static var isMomentsEnabled: Bool {
        get {
            AppContext.shared.userDefaults.register(defaults: [ NotificationUserDefaultKeys.momentsEnabled: true])
            return AppContext.shared.userDefaults.bool(forKey: NotificationUserDefaultKeys.momentsEnabled)
        }
    }
}
