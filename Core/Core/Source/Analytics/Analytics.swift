//
//  Analytics.swift
//  Core
//
//  Created by Chris Leonavicius on 10/27/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import Amplitude
import Combine
import CoreCommon
import CryptoKit
import UIKit

public class Analytics {

    public enum Event: String {
        case appForegrounded
        case appBackgrounded
        case openScreen
        case sendPost
        case sendPostReaction
        case sendChatMessage
        case sendChatMessageReaction
        case sendComment
        case sendCommentReaction
        case sendMoment
        case notificationReceived
        case notificationOpened
        case sendInvite
        case createGroup
        case externalShare

        // fab
        case fabOpen
        case fabCancel
        case fabSelect

        // Onboarding
        case onboardingEnteredPhoneValidNumber
        case onboardingEnteredOTP
        case onboardingRerequestOTP
        case onboardingRequestOTPCall
        case onboardingOTPWrongNumber
        case onboardingAddedProfilePhoto
        case onboardingEnteredName
        case onboardingPermissionsGetStarted
        case promptedContactPermission
        case promptedNotificationPermission
    }

    public enum Screen: String {
        case homeFeed
        case userFeed
        case groupFeed
        case chatList
        case groupList
        case settings
        case composer
        case comments
        case userChat
        case groupChat
        case profile
        case camera
        case activity
        case invite
    }

    public typealias EventProperties = [EventProperty: Any]

    public enum EventProperty: String {
        case screen
        case granted // promptedContactPermission, promptedNotificationPermission
        case valid // onboardingEnteredOTP
        case destination // openPostFab
        case attachedImageCount // sendPost, sendChatMessage, sendComment
        case attachedVideoCount // sendPost, sendChatMessage, sendComment
        case attachedAudioCount // sendPost, sendChatMessage, sendComment
        case attachedLinkPreviewCount // sendPost, sendChatMessage, sendComment
        case attachedLocationCount // sendChatMessage
        case attachedDocumentCount // sendChatMessage
        case hasText // sendPost, sendChatMessage, sendComment
        case chatType // sendChatMessage
        case replyType // sendChatMessage
        case destinationSendToAll // sendPost
        case destinationSendToFavorites // sendPost
        case destinationNumGroups // sendPost
        case destinationNumContacts // sendPost
        case notificationType // notificationReceived, notificationOpened
        case hasSelfie // sendMoment
        case isUnlock // sendMoment
        case service // sendInvite
        case groupType // createGroup
        case shareDestination // externalShare
        case fabSelection // fabSelect
    }

    public typealias UserProperties = [UserProperty: Any]

    public enum UserProperty: String {
        case lastScreen
        case numberOfContacts
        case serverProperties
        case notificationPermissionEnabled
        case contactPermissionEnabled
        case clientVersion
    }

    private static var userIDUpdateCancellable: AnyCancellable?

    static func setup(userData: UserData) {
        let isAppExtension = Bundle.main.bundlePath.hasSuffix("appex")
        if isAppExtension {
            Amplitude.instance().eventUploadPeriodSeconds = 3
            Amplitude.instance().trackingSessionEvents = false
        }

        Amplitude.instance().setServerUrl("https://amplitude.halloapp.net")

        userIDUpdateCancellable = userData.userIDPublisher
            .filter { !$0.isEmpty }
            .sink { Amplitude.instance().setUserId($0.analyticsHashedString) }

        let apiKey: String
        #if DEBUG
        apiKey = "60bca64d4d07b8a1e6f829772b2e2177" // Test Env
        #else
        apiKey = "0244bb1d81bac8beaad8046b7a5905e1" // Prod
        #endif
        Amplitude.instance().initializeApiKey(apiKey)
    }

    public static func log(event: Event, properties: EventProperties? = nil) {
        Amplitude.instance().logEvent(event.rawValue, withEventProperties: properties?.amplitudeProperties)
    }

    public static func openScreen(_ screen: Screen, properties: EventProperties? = nil) {
        var amendedProperties = properties ?? [:]
        amendedProperties[.screen] = screen.rawValue
        log(event: .openScreen, properties: amendedProperties)

        setUserProperties([.lastScreen: screen.rawValue])
    }

    public static func setUserProperties(_ userProperties: UserProperties) {
        Amplitude.instance().setUserProperties(userProperties.amplitudeProperties)
    }

    public static func logout() {
        Amplitude.instance().clearUserProperties()
        Amplitude.instance().setUserId(nil)
        Amplitude.instance().regenerateDeviceId()
    }

    public static func flushEvents() {
        Amplitude.instance().uploadEvents()
    }
}

// MARK: - Utils

private extension String {

    var analyticsHashedString: String? {
        return data(using: .utf8).flatMap { Data(SHA256.hash(data: $0).prefix(16)).toHexString() }
    }
}

private extension Dictionary where Key == Analytics.UserProperty {

    var amplitudeProperties: [AnyHashable: Any] {
        return reduce(into: [:]) { partialResult, element in
            partialResult[element.key.rawValue] = element.value
        }
    }
}

private extension Dictionary where Key == Analytics.EventProperty {

    var amplitudeProperties: [AnyHashable: Any] {
        return reduce(into: [:]) { partialResult, element in
            partialResult[element.key.rawValue] = element.value
        }
    }
}
