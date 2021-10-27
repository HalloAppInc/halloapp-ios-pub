//
//  NUX.swift
//  HalloApp
//
//  Created by Garrett on 9/22/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core

final class NUX {

    enum State: String {
        case none
        case zeroZone
        case somewhatActive
    }

    enum Event: String {
        case homeFeedIntro // no longer used
        case chatListIntro
        case activityCenterIcon
        case newPostButton
        case feedPostWhoWillSee
        
        case createdUserGroup           // zerozone
        case seenUserGroupWelcomePost   // zerozone
    }

    init(userDefaults: UserDefaults, appVersion: String = AppContext.appVersionForService) {
        self.userDefaults = userDefaults
        self.appVersion = appVersion
        loadFromUserDefaults()

        let contacts = MainAppContext.shared.contactStore.allRegisteredContacts(sorted: false)
        if contacts.count == 0 {
            state = .zeroZone
        }
    }

    private let userDefaults: UserDefaults
    private let appVersion: String
    public private(set) var isDemoMode = false

    public private(set) var state: State = .none

    private var eventCompletedVersions = [Event: String]()

    func isComplete(_ event: Event) -> Bool {
        return eventCompletedVersions.keys.contains(event)
    }

    func isIncomplete(_ event: Event) -> Bool {
        return !eventCompletedVersions.keys.contains(event)
    }

    func didComplete(_ event: Event) {
        eventCompletedVersions[event] = appVersion
        saveToUserDefaults()
    }

    func startDemo() {
        isDemoMode = true
        eventCompletedVersions.removeAll()
    }

    func devSetStateZeroZone() {
        state = .zeroZone
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
    static func shortInvitesCount(_ count: Int) -> String {
        let format = NSLocalizedString("n.invites.count", comment: "Indicates how many invites are remaining")
        return String.localizedStringWithFormat(format, count)
    }
    static var inviteAFriend: String {
        NSLocalizedString("link.invite.friend", value: "Invite a friend", comment: "Link text to open invite flow")
    }
    static func inviteAcceptedActivityItem(inviter: String) -> String {
        let format = NSLocalizedString("activity.center.invite.accepted.item",
                                       value: "You accepted %@'s invite 🎉",
                                       comment: "Message shown when a user first joins from a friend's invitation (e.g., 'You accepted David's invite 🎉'")
        return String(format: format, inviter)
    }
    static var welcomeToHalloApp: String {
        NSLocalizedString("activity.center.welcome.item", value: "Welcome to HalloApp!", comment: "Message shown when a user first joins")
    }
    static var nuxActivityCenterIconContent: String {
        NSLocalizedString(
            "nux.activity.center.icon",
            value: "Hallo!",
            comment: "Text for new user popup pointing at activity center icon")
    }
    static var nuxGroupsListEmpty: String {
        NSLocalizedString(
            "nux.groups.list.empty",
            value: "Your groups will appear here",
            comment: "Shown on groups list when there are no groups to display"
        )
    }
    
    static var nuxGroupsInCommonListEmpty: String {
        NSLocalizedString(
            "nux.groups.common.list.empty",
            value: "You have no group in common",
            comment: "Shown on groups in common when there are no groups to display"
        )
    }
    
    static var nuxChatIntroContent: String {
        NSLocalizedString(
            "nux.chat.list",
            value: "This is where you’ll find messages from your friends & family. When someone new joins HalloApp you can see them here.",
            comment: "Text for new user popup pointing at chat list")
    }
    static var nuxChatEmpty: String {
        NSLocalizedString(
            "nux.chat.empty",
            value: "Your contacts & messages will appear here",
            comment: "Shown on chats list when there are no contacts or messages to display"
        )
    }
    static var nuxNewPostButtonContent: String {
        NSLocalizedString(
            "nux.new.post.button",
            value: "Tap to share an update with your friends & family on HalloApp",
            comment: "Text for new user popup pointing at new post button")
    }
    static var nuxHomeFeedEmpty: String {
        NSLocalizedString(
            "nux.home.feed.empty",
            value: "Posts from your phone’s contacts will appear here",
            comment: "Shown on home feed when no posts are available"
        )
    }
}
