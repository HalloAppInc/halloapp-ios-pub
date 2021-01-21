//
//  ServerProperties.swift
//  Core
//
//  Created by Igor Solomennikov on 7/29/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjack
import Foundation

public struct ServerProperties {

    // MARK: Keys

    private enum Key: String {
        case internalUser = "dev"
        case groups
        case maxGroupSize = "max_group_size"
        case groupFeed = "group_feed"
        case groupChat = "group_chat"
        case combineFeed = "combine_feed"
        case silentChatMessages = "silent_chat_messages"
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
        static let groups = false
        static let groupFeed = false
        static let groupChat = true
        static let combineFeed = false
        static let maxGroupSize = 25
        static let silentChatMessages = 0
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

    public static var isGroupsEnabled: Bool {
        ServerProperties.bool(forKey: .groups) ?? Defaults.groups
    }

    public static var isGroupFeedEnabled: Bool {
        ServerProperties.bool(forKey: .groupFeed) ?? Defaults.groupFeed
    }

    public static var maxGroupSize: Int {
        ServerProperties.integer(forKey: .maxGroupSize) ?? Defaults.maxGroupSize
    }
    
    public static var isGroupChatEnabled: Bool {
        ServerProperties.bool(forKey: .groupChat) ?? Defaults.groupChat
    }

    public static var isCombineFeedEnabled: Bool {
        ServerProperties.bool(forKey: .combineFeed) ?? Defaults.combineFeed
    }
    /// Number of silent chat messages to send alongside each user-initiated message
    public static var silentChatMessages: Int {
        ServerProperties.integer(forKey: .silentChatMessages) ?? Defaults.silentChatMessages
    }

}
