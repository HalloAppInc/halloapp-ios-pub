//
//  NotificationSettings.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 9/3/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Foundation

class NotificationSettings: ObservableObject {

    // MARK: Singleton

    static private let sharedInstance = NotificationSettings()
    static var current: NotificationSettings {
        sharedInstance
    }

    private init() {
        UserDefaults.standard.register(defaults: [ UserDefaultsKeys.postsEnabled: true, UserDefaultsKeys.commentsEnabled: true ])
        isPostsEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.postsEnabled)
        isCommentsEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.commentsEnabled)
    }

    // MARK: Settings

    var isPostsEnabled: Bool {
        didSet {
            if oldValue != isPostsEnabled {
                UserDefaults.standard.set(isPostsEnabled, forKey: UserDefaultsKeys.postsEnabled)
                UserDefaults.standard.set(false, forKey: UserDefaultsKeys.isSynchronized)
                sendConfigIfNecessary(using: MainAppContext.shared.service)
            }
        }
    }

    var isCommentsEnabled: Bool {
        didSet {
            if oldValue != isCommentsEnabled {
                UserDefaults.standard.set(isCommentsEnabled, forKey: UserDefaultsKeys.commentsEnabled)
                UserDefaults.standard.set(false, forKey: UserDefaultsKeys.isSynchronized)
                sendConfigIfNecessary(using: MainAppContext.shared.service)
            }
        }
    }

    // MARK: Synchronization

    private var isSyncInProgress = false

    private struct UserDefaultsKeys {
        static let isSynchronized = "NotificationSettings1"   // Bool
        static let postsEnabled = "NotificationSettings2"     // Bool
        static let commentsEnabled = "NotificationSettings3"  // Bool
    }

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
        let userDefaults = UserDefaults.standard
        guard !userDefaults.bool(forKey: UserDefaultsKeys.isSynchronized) else {
            DDLogInfo("NotificationSettings/sync/ Not required")
            return
        }

        isSyncInProgress = true
        userDefaults.set(true, forKey: UserDefaultsKeys.isSynchronized)

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
                userDefaults.set(false, forKey: UserDefaultsKeys.isSynchronized)
            }
        }
    }

}
