//
//  NotificationSettings.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 9/3/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Foundation
import Core
import CoreCommon

class NotificationSettings: ObservableObject {

    private let userDefaults: UserDefaults

    static var current: NotificationSettings {
        return MainAppContext.shared.notificationSettings
    }

    init(userDefaults: UserDefaults) {
        Self.migrateSettings(userDefaults: userDefaults)
        userDefaults.register(defaults: [NotificationUserDefaultKeys.postsEnabled: true,
                                         NotificationUserDefaultKeys.commentsEnabled: true,
                                         NotificationUserDefaultKeys.momentsEnabled: true,
                                         NotificationUserDefaultKeys.magicPostsEnabled: true])

        self.userDefaults = userDefaults
        isPostsEnabled = userDefaults.bool(forKey: NotificationUserDefaultKeys.postsEnabled)
        isCommentsEnabled = userDefaults.bool(forKey: NotificationUserDefaultKeys.commentsEnabled)
        isMomentsEnabled = userDefaults.bool(forKey: NotificationUserDefaultKeys.momentsEnabled)
        isMagicPostsEnabled = userDefaults.bool(forKey: NotificationUserDefaultKeys.momentsEnabled)
        DDLogInfo("NotificationSettings/values: \(isPostsEnabled): \(isCommentsEnabled): \(isMomentsEnabled): \(isMagicPostsEnabled)")
    }

    private static func migrateSettings(userDefaults: UserDefaults) {
        guard UserDefaults.standard.value(forKey: NotificationUserDefaultKeys.postsEnabled) != nil else {
            DDLogInfo("NotificationSettings/migrateSettings/skip")
            return
        }
        DDLogInfo("NotificationSettings/migrateSettings/begin")
        let postsEnabled = UserDefaults.standard.bool(forKey: NotificationUserDefaultKeys.postsEnabled)
        let commentsEnabled = UserDefaults.standard.bool(forKey: NotificationUserDefaultKeys.commentsEnabled)
        let isSynchronized = UserDefaults.standard.bool(forKey: NotificationUserDefaultKeys.isSynchronized)

        userDefaults.register(defaults: [ NotificationUserDefaultKeys.postsEnabled: true, NotificationUserDefaultKeys.commentsEnabled: true ])

        userDefaults.set(postsEnabled, forKey: NotificationUserDefaultKeys.postsEnabled)
        userDefaults.set(commentsEnabled, forKey: NotificationUserDefaultKeys.commentsEnabled)
        userDefaults.set(isSynchronized, forKey: NotificationUserDefaultKeys.isSynchronized)

        UserDefaults.standard.removeObject(forKey: NotificationUserDefaultKeys.postsEnabled)
        UserDefaults.standard.removeObject(forKey: NotificationUserDefaultKeys.commentsEnabled)
        UserDefaults.standard.removeObject(forKey: NotificationUserDefaultKeys.isSynchronized)
        DDLogInfo("NotificationSettings/migrateSettings/success")
    }

    // MARK: Settings

    var isPostsEnabled: Bool {
        didSet {
            if oldValue != isPostsEnabled {
                userDefaults.set(isPostsEnabled, forKey: NotificationUserDefaultKeys.postsEnabled)
                userDefaults.set(false, forKey: NotificationUserDefaultKeys.isSynchronized)
                sendConfigIfNecessary(using: MainAppContext.shared.service)
            }
        }
    }

    var isCommentsEnabled: Bool {
        didSet {
            if oldValue != isCommentsEnabled {
                userDefaults.set(isCommentsEnabled, forKey: NotificationUserDefaultKeys.commentsEnabled)
                userDefaults.set(false, forKey: NotificationUserDefaultKeys.isSynchronized)
                sendConfigIfNecessary(using: MainAppContext.shared.service)
            }
        }
    }

    var isMomentsEnabled: Bool {
        didSet {
            if oldValue != isMomentsEnabled {
                userDefaults.set(isMomentsEnabled, forKey: NotificationUserDefaultKeys.momentsEnabled)
            }
        }
    }

    var isMagicPostsEnabled: Bool {
        didSet {
            if oldValue != isMagicPostsEnabled {
                userDefaults.set(isMagicPostsEnabled, forKey: NotificationUserDefaultKeys.magicPostsEnabled)
            }
        }
    }

    // MARK: Synchronization

    private var isSyncInProgress = false

    enum ConfigKey: String {
        case post
        case comment
    }

    private var currentConfig: [ConfigKey: Bool] {
        [ .post: isPostsEnabled, .comment: isCommentsEnabled ]
    }

    func sendConfigIfNecessary(using service: HalloService) {
        guard service.isConnected else {
            DDLogWarn("NotificationSettings/sync/ Not connected")
            return
        }
        guard !isSyncInProgress else {
            DDLogInfo("NotificationSettings/sync/ Already in progress")
            return
        }

        guard !userDefaults.bool(forKey: NotificationUserDefaultKeys.isSynchronized) else {
            DDLogInfo("NotificationSettings/sync/ Not required")
            return
        }

        isSyncInProgress = true
        userDefaults.set(true, forKey: NotificationUserDefaultKeys.isSynchronized)

        service.updateNotificationSettings(currentConfig) { result in
            self.isSyncInProgress = false

            switch result {
            case .success(_):
                // Check if there are more changes to send.
                DispatchQueue.main.async {
                    self.sendConfigIfNecessary(using: service)
                }
                break

            case .failure(let error):
                // Will be retried on connect.
                DDLogError("NotificationSettings/sync/error [\(error)]]")
                self.userDefaults.set(false, forKey: NotificationUserDefaultKeys.isSynchronized)
            }
        }
    }

}
