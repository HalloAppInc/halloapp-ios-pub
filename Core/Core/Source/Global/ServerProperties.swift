//
//  ServerProperties.swift
//  Core
//
//  Created by Igor Solomennikov on 7/29/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Foundation

public struct ServerProperties {

    // MARK: Keys

    private enum Key: String {
        case internalUser = "dev"
        case maxGroupSize = "max_group_size"
        case groupSyncTime = "group_sync_time"
        case maxFeedVideoDuration = "max_feed_video_duration"
        case maxChatVideoDuration = "max_chat_video_duration"
        case maxVideoBitRate = "max_video_bit_rate"
        case useClientContainer = "new_client_container"
        case contactSyncFrequency = "contact_sync_frequency"
        case isVoiceNotesEnabled = "voice_notes"
        case isMediaCommentsEnabled = "media_comments"
        case sendClearTextGroupFeedContent = "cleartext_group_feed"
    }

    private struct UserDefaultsKey {
        static var data: String {
            return "SP-\(AppContext.shared.userData.userId)"
        }
        static var date = "SPDate"
        static let version = "SPVersion"
    }

    // MARK: Defaults

    private struct Defaults {
        static let internalUser = false
        static let maxGroupSize = 50
        static let groupSyncTime = 604800
        static let maxFeedVideoDuration = 60.0
        static let maxChatVideoDuration = 120.0
        static let maxVideoBitRate = 8000000.0
        static let useClientContainer = false
        static let contactSyncFrequency: TimeInterval = 24 * 3600
        static let isVoiceNotesEnabled = false
        static let isMediaCommentsEnabled = false
        static let sendClearTextGroupFeedContent = true
    }

    // MARK: Storage

    private static var properties: [String : String]? = nil

    private static let queue: DispatchQueue = {
        let queue = DispatchQueue(label: "com.halloapp.server-properties", attributes: .concurrent)
        DDLogDebug("serverprops/init")
        reloadFromPreferences(usingQueue: queue)
        return queue
    }()

    private static func reloadFromPreferences(usingQueue queue: DispatchQueue = queue) {
        let loadedProperties = propertiesFromPreferences()
        queue.async(flags: .barrier) {
            properties = loadedProperties
            DDLogInfo("serverprops/reloaded values=[\(properties?.count ?? 0)]")
        }
        if loadedProperties == nil {
            DDLogInfo("serverprops/default")
        }
    }

    private static func propertiesFromPreferences() -> [String : String]? {
        guard let data = AppContext.shared.userDefaults.data(forKey: UserDefaultsKey.data) else {
            return nil
        }
        var decodedObject: Any?
        do {
            decodedObject = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSDictionary.self, from: data)
        }
        catch {
            DDLogError("serverprops/error [invalid pref value]")
            return nil
        }
        guard let dictionary = decodedObject as? [String : String] else {
            DDLogError("serverprops/error [invalid pref value]")
            return nil
        }
        return dictionary
    }

    public static func reset() {
        DDLogInfo("serverprops/reset")
        AppContext.shared.userDefaults.removeObject(forKey: UserDefaultsKey.data)
        AppContext.shared.userDefaults.removeObject(forKey: UserDefaultsKey.date)
        AppContext.shared.userDefaults.removeObject(forKey: UserDefaultsKey.version)
        reloadFromPreferences()
    }

    // MARK: Server Sync

    public static func shouldQuery(forVersion version: String?) -> Bool {
        guard let serverVersion = version else {
            DDLogInfo("serverprops/missing-server-version")
            return true
        }
        guard let savedVersion = AppContext.shared.userDefaults.string(forKey: UserDefaultsKey.version) else {
            DDLogInfo("serverprops/missing-version")
            return true
        }
        if serverVersion != savedVersion {
            DDLogInfo("serverprops/version-mismatch/existing/\(savedVersion)/current/\(serverVersion)")
            return true
        }

        return false
    }

    public static func update(withProperties properties: [String: String], version: String) {
        DDLogInfo("serverprops/set [\(properties)]")

        let userDefaults = AppContext.shared.userDefaults!
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: properties, requiringSecureCoding: true)
            userDefaults.set(data, forKey: UserDefaultsKey.data)
            userDefaults.set(version, forKey: UserDefaultsKey.version)
            userDefaults.set(Date(), forKey: UserDefaultsKey.date)
        }
        catch {
            DDLogError("serverprops/error [failed to archive]")
        }

        reloadFromPreferences()
    }

    // MARK: Lookup

    private static func string(forKey key: Key) -> String? {
        let maybeProperties = queue.sync {
            return properties
        }
        return maybeProperties?[key.rawValue]
    }

    private static func integer(forKey key: Key) -> Int? {
        guard let value = string(forKey: key) else {
            return nil
        }
        return Int(value)
    }

    private static func bool(forKey key: Key) -> Bool? {
        guard let value = string(forKey: key) else {
            return nil
        }
        // Parse "true" or "false"
        if let boolValue = Bool(value) {
            return boolValue
        }
        // Parse integer values
        guard let intValue = Int(value) else {
            return nil
        }
        return intValue > 0
    }

    private static func double(forKey key: Key) -> Double? {
        guard let value = string(forKey: key) else {
            return nil
        }
        return Double(value)
    }

    // MARK: Getters

    public static var isInternalUser: Bool {
        ServerProperties.bool(forKey: .internalUser) ?? Defaults.internalUser
    }

    public static var maxGroupSize: Int {
        ServerProperties.integer(forKey: .maxGroupSize) ?? Defaults.maxGroupSize
    }

    public static var groupSyncTime: Int {
        ServerProperties.integer(forKey: .groupSyncTime) ?? Defaults.groupSyncTime
    }

    public static var maxFeedVideoDuration: TimeInterval {
        ServerProperties.double(forKey: .maxFeedVideoDuration) ?? Defaults.maxFeedVideoDuration
    }

    public static var maxChatVideoDuration: TimeInterval {
        ServerProperties.double(forKey: .maxChatVideoDuration) ?? Defaults.maxChatVideoDuration
    }

    public static var maxVideoBitRate: Double {
        ServerProperties.double(forKey: .maxVideoBitRate) ?? Defaults.maxVideoBitRate
    }

    public static var useClientContainer: Bool {
        ServerProperties.bool(forKey: .useClientContainer) ?? Defaults.useClientContainer
    }

    public static var contactSyncFrequency: TimeInterval {
        ServerProperties.double(forKey: .contactSyncFrequency) ?? Defaults.contactSyncFrequency
    }

    public static var isVoiceNotesEnabled: Bool {
        ServerProperties.bool(forKey: .isVoiceNotesEnabled) ?? Defaults.isVoiceNotesEnabled
    }

    public static var isMediaCommentsEnabled: Bool {
        ServerProperties.bool(forKey: .isMediaCommentsEnabled) ?? Defaults.isVoiceNotesEnabled
    }

    public static var sendClearTextGroupFeedContent: Bool {
        ServerProperties.bool(forKey: .sendClearTextGroupFeedContent) ?? Defaults.sendClearTextGroupFeedContent
    }
}
