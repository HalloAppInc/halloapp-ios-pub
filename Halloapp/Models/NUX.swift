//
//  NUX.swift
//  HalloApp
//
//  Created by Garrett on 9/22/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core

final class NUX {
    enum Event: String {
        case homeFeedIntro
        case chatListIntro
        case activityCenterIcon
        case newPostButton
        case feedPostWhoWillSee
    }

    init(userDefaults: UserDefaults, appVersion: String = AppContext.appVersionForXMPP) {
        self.userDefaults = userDefaults
        self.appVersion = appVersion
        loadFromUserDefaults()
    }

    private let userDefaults: UserDefaults
    private let appVersion: String
    private var isDemoMode = false

    private var eventCompletedVersions = [Event: String]()

    func isIncomplete(_ event: Event) -> Bool {
        return !eventCompletedVersions.keys.contains(event)
    }

    func didComplete(_ event: Event) {
        eventCompletedVersions[event] = appVersion
        if !isDemoMode {
            saveToUserDefaults()
        }
    }

    func startDemo() {
        isDemoMode = true
        eventCompletedVersions.removeAll()
    }

    private func loadFromUserDefaults() {
        if let completions = userDefaults.dictionary(forKey: UserDefaultsKey.eventCompletedVersions) {
            let eventVersionPairs: [(Event, String)] = completions.compactMap { eventName, version in
                guard let event = Event(rawValue: eventName), let version = version as? String else { return nil }
                return (event, version)
            }
            eventCompletedVersions = Dictionary(uniqueKeysWithValues: eventVersionPairs)
            DDLogInfo("NUX/loadFromUserDefaults loaded events from user defaults [\(eventCompletedVersions.count)]")
        } else {
            DDLogInfo("NUX/loadFromUserDefaults no events saved in user defaults")
        }
    }

    private func saveToUserDefaults() {
        let userDefaultsDict = Dictionary(uniqueKeysWithValues: eventCompletedVersions.map { ($0.key.rawValue, $0.value) })
        DDLogInfo("NUX/saveToUserDefaults saving events [\(userDefaultsDict.count)]")
        userDefaults.set(userDefaultsDict, forKey: UserDefaultsKey.eventCompletedVersions)
    }

    private struct UserDefaultsKey {
        static var eventCompletedVersions = "nux.completed"
    }
}

extension Localizations {
    static var nuxActivityCenterIconContent: String {
        NSLocalizedString(
            "nux.activity.center.icon",
            value: "This is your activity center. Tap to see your most recent activity.",
            comment: "Text for new user popup pointing at activity center icon")
    }
    static var nuxChatIntroContent: String {
        NSLocalizedString(
            "nux.chat.list",
            value: "This is where you’ll find messages from your friends & family. When someone new joins HalloApp you can see them here.",
            comment: "Text for new user popup pointing at chat list")
    }
    static var nuxNewPostButtonContent: String {
        NSLocalizedString(
            "nux.new.post.button",
            value: "Tap to share an update with your friends & family on HalloApp",
            comment: "Text for new user popup pointing at new post button")
    }
    static var nuxHomeFeedIntroContent: String {
        NSLocalizedString(
            "nux.home.feed",
            value: "Welcome to your home feed! This is where you can see posts from your phone contacts who use HalloApp.",
            comment: "Text for new user info panel on home feed")
    }
    static var nuxHomeFeedDetailsTitle: String {
        NSLocalizedString(
            "nux.home.feed.details.title",
            value: "About HalloApp",
            comment: "Title for more detailed new user popup on home feed")
    }
    static var nuxHomeFeedDetailsBody: String {
        NSLocalizedString(
            "nux.home.feed.details.text",
            value: """
Home feed allows you to share text, photo, and video updates that disappear after 30 days.

If you want to share updates with someone, both parties must have each other's numbers saved on their phones.

You can share your updates with your entire contact list or only with selected people. Go to settings to change feed privacy.
""",
            comment: "Text for more detailed new user popup on home feed")
    }
}
