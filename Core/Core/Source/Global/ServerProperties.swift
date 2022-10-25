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
        case targetVideoBitRate = "target_video_bit_rate"
        case targetVideoResolution = "target_video_resolution"
        case contactSyncFrequency = "contact_sync_frequency"
        case callWaitTimeoutSec = "call_wait_timeout"
        case canHoldCalls = "call_hold"
        case streamingUploadChunkSize = "streaming_upload_chunk_size"
        case streamingInitialDownloadSize = "streaming_initial_download_size"
        case streamingSendingEnabled = "streaming_sending_enabled"
        case isMediaDrawingEnabled = "draw_media"
        case isGroupCommentNotificationsEnabled = "group_comments_notification"
        case isHomeCommentNotificationsEnabled = "home_feed_comment_notifications"
        case isFileSharingEnabled = "file_sharing"
        case inviteStrings = "invite_strings"
        case nseRuntimeSec = "nse_runtime_sec"
        case newChatUI = "new_chat_ui"
        case maxPostMediaItems = "max_post_media_items"
        case maxChatMediaItems = "max_chat_media_items"
        case sendClearTextHomeFeedContent = "cleartext_home_feed"
        case useClearTextHomeFeedContent = "use_cleartext_home_feed"
        case enableSentryPerfTracking = "enable_sentry_perf_tracking"
        case enableGroupExpiry = "group_expiry"
        case preAnswerCalls = "pre_answer_calls"
        case chatReactions = "chat_reactions"
        case commentReactions = "comment_reactions"
        case enableNewMediaUploader = "background_upload"
        case enableChatLocationSharing = "location_sharing"
        case closeFriendRecommendations = "close_friends_recos"
        case enableGroupChat = "group_chat"
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
        static let maxVideoBitRate = 6000000.0
        static let targetVideoBitRate = 4000000.0
        static let targetVideoResolution = 720.0
        static let contactSyncFrequency: TimeInterval = 24 * 3600
        static let callWaitTimeoutSec = 60
        static let canHoldCalls = false
        static let streamingUploadChunkSize = 65536
        static let streamingInitialDownloadSize = 5242880
        static let streamingSendingEnabled = false
        static let isMediaDrawingEnabled = false
        static let isGroupCommentNotificationsEnabled = false
        static let isHomeCommentNotificationsEnabled = false
        static let isFileSharingEnabled = false
        static let nseRuntimeSec = 17.0
        static let newChatUI = false
        static let maxPostMediaItems = 10
        static let maxChatMediaItems = 30
        static let sendClearTextHomeFeedContent = true
        static let useClearTextHomeFeedContent = true
        static let enableSentryPerfTracking = false
        static let enableGroupExpiry = false
        static let preAnswerCalls = false
        static let chatReactions = false
        static let commentReactions = false
        static let enableNewMediaUploader = false
        static let enableChatLocationSharing = false
        static let closeFriendRecommendations = false
        static let enableGroupChat = false
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
            decodedObject = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSDictionary.self, NSString.self],
                                                                   from: data)
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
    
    private static func json(forKey key: Key) -> [String: Any]? {
        guard let data = string(forKey: key)?.data(using: .utf16) else {
            return nil
        }
        
        return try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
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

    public static var targetVideoBitRate: Double {
        ServerProperties.double(forKey: .targetVideoBitRate) ?? Defaults.targetVideoBitRate
    }

    public static var targetVideoResolution: Double {
        ServerProperties.double(forKey: .targetVideoResolution) ?? Defaults.targetVideoResolution
    }

    public static var contactSyncFrequency: TimeInterval {
        ServerProperties.double(forKey: .contactSyncFrequency) ?? Defaults.contactSyncFrequency
    }

    public static var sendClearTextHomeFeedContent: Bool {
        ServerProperties.bool(forKey: .sendClearTextHomeFeedContent) ?? Defaults.sendClearTextHomeFeedContent
    }

    public static var useClearTextHomeFeedContent: Bool {
        ServerProperties.bool(forKey: .useClearTextHomeFeedContent) ?? Defaults.useClearTextHomeFeedContent
    }

    public static var callWaitTimeoutSec: Int {
        ServerProperties.integer(forKey: .callWaitTimeoutSec) ?? Defaults.callWaitTimeoutSec
    }

    public static var canHoldCalls: Bool {
        ServerProperties.bool(forKey: .canHoldCalls) ?? Defaults.canHoldCalls
    }

    public static var streamingUploadChunkSize: Int {
        ServerProperties.integer(forKey: .streamingUploadChunkSize) ?? Defaults.streamingUploadChunkSize
    }

    public static var streamingInitialDownloadSize: Int {
        ServerProperties.integer(forKey: .streamingInitialDownloadSize) ?? Defaults.streamingInitialDownloadSize
    }

    public static var streamingSendingEnabled: Bool {
        ServerProperties.bool(forKey: .streamingSendingEnabled) ?? Defaults.streamingSendingEnabled
    }

    public static var isMediaDrawingEnabled: Bool {
        ServerProperties.bool(forKey: .isMediaDrawingEnabled) ?? Defaults.isMediaDrawingEnabled
    }

    public static var isGroupCommentNotificationsEnabled: Bool {
        ServerProperties.bool(forKey: .isGroupCommentNotificationsEnabled) ?? Defaults.isGroupCommentNotificationsEnabled
    }

    public static var isHomeCommentNotificationsEnabled: Bool {
        ServerProperties.bool(forKey: .isHomeCommentNotificationsEnabled) ?? Defaults.isHomeCommentNotificationsEnabled
    }

    public static var isFileSharingEnabled: Bool {
        // NB: depends on new chat UI and new uploader
        ServerProperties.bool(forKey: .isFileSharingEnabled) ?? Defaults.isFileSharingEnabled
    }

    public static var nseRuntimeSec: TimeInterval {
        ServerProperties.double(forKey: .nseRuntimeSec) ?? Defaults.nseRuntimeSec
    }

    public static var newChatUI: Bool {
        ServerProperties.bool(forKey: .newChatUI) ?? Defaults.newChatUI
    }

    public static var enableChatLocationSharing: Bool {
        ServerProperties.bool(forKey: .enableChatLocationSharing) ?? Defaults.enableChatLocationSharing
    }
    
    public static var inviteString: String? {
        guard
            let allInviteStrings = json(forKey: .inviteStrings),
            let locale = Locale.current.languageCode?.lowercased(),
            let specificInviteString = allInviteStrings[locale] as? String
        else {
            return nil
        }
        
        // lowercased locale because Apple has some capitalization in their language codes (e.g. pt-BR)
        // while the server keys do not
        return specificInviteString
    }

    public static var maxPostMediaItems: Int {
        ServerProperties.integer(forKey: .maxPostMediaItems) ?? Defaults.maxPostMediaItems
    }

    public static var maxChatMediaItems: Int {
        ServerProperties.integer(forKey: .maxChatMediaItems) ?? Defaults.maxChatMediaItems
    }

    public static var enableSentryPerfTracking: Bool {
        ServerProperties.bool(forKey: .enableSentryPerfTracking) ?? Defaults.enableSentryPerfTracking
    }

    public static var enableGroupExpiry: Bool {
        ServerProperties.bool(forKey: .enableGroupExpiry) ?? Defaults.enableGroupExpiry
    }

    public static var preAnswerCalls: Bool {
        ServerProperties.bool(forKey: .preAnswerCalls) ?? Defaults.preAnswerCalls
    }
    
    public static var chatReactions: Bool {
        ServerProperties.bool(forKey: .chatReactions) ?? Defaults.chatReactions
    }
    
    public static var commentReactions: Bool {
        ServerProperties.bool(forKey: .commentReactions) ?? Defaults.commentReactions
    }

    public static var enableNewMediaUploader: Bool {
        ServerProperties.bool(forKey: .enableNewMediaUploader) ?? Defaults.enableNewMediaUploader
    }

    public static var closeFriendRecommendations: Bool {
        ServerProperties.bool(forKey: .closeFriendRecommendations) ?? Defaults.closeFriendRecommendations
    }

    public static var enableGroupChat: Bool {
        ServerProperties.bool(forKey: .enableGroupChat) ?? Defaults.enableGroupChat
    }
}
