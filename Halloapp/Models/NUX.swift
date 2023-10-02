//
//  NUX.swift
//  HalloApp
//
//  Created by Garrett on 9/22/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon

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
    }

    /*
        Main Feed Welcome Post:
            - Shown when in Zero Zone or when there are zero posts
            - Once shown, stays in feed until closed or expired
            - Marked as seen immediately when it's shown
            - Does not increment any unread counters
        Sample Group:
            - Created once if user is in Zero Zone or when there are zero groups
        Sample Group Welcome Post:
            - Recorded once sample group is created even if not shown
            - Increments bottom nav unread counter and thread unread counter if not seen
            - Stays in sample group until closed or expired
        Group Welcome Post:
            - Shown in groups that user creates while in Zero Zone
            - Once shown, stays in group feed until closed or expired
            - Marked as seen immediately when it's shown
            - Does not increment any unread counters
    */
    struct WelcomePost: Hashable, Codable {
        var id: String // GroupID with the exception when it's the main feed, then it's the UserID
        var type: WelcomePostType
        var creationDate: Date
        var seen: Bool = false
        var show: Bool = true
    }

    enum WelcomePostType: String, Codable {
        case mainFeed
        case sampleGroup
        case group
    }

    init(userDefaults: UserDefaults, appVersion: String = AppContext.appVersionForService) {
        self.userDefaults = userDefaults
        self.appVersion = appVersion
        loadFromUserDefaults()
        expireWelcomePosts()

        let friends = UserProfile.find(predicate: NSPredicate(format: "friendshipStatusValue == %d", UserProfile.FriendshipStatus.friends.rawValue),
                                       in: MainAppContext.shared.mainDataStore.viewContext)
        if friends.count == 0 {
            state = .zeroZone
        }
    }

    private let userDefaults: UserDefaults
    private let appVersion: String
    public private(set) var isDemoMode = false

    public private(set) var state: State = .none

    private var eventCompletedVersions = [Event: String]()

    private var welcomePostsDict = [String: WelcomePost]()

    func welcomePostExist(id: String) -> Bool {
        return welcomePostsDict[id] != nil ? true : false
    }

    func showWelcomePost(id: String) -> Bool {
        guard let welcomePost = welcomePostsDict[id] else { return false }
        return welcomePost.show
    }

    func recordWelcomePost(id: String, type: WelcomePostType) {
        var post = WelcomePost(id: id, type: type, creationDate: Date())

        // mainFeed and new groups created do not increment the unread counters,
        // so they are considered seen as they are recorded
        if type == .mainFeed {
            post.seen = true
        } else if type == .group {
            post.seen = true
        }
        welcomePostsDict[id] = post
        saveToUserDefaults()
    }

    func sampleGroupID() -> GroupID? {
        guard let key = welcomePostsDict.first(where: {
            let welcomePost = $0.value as WelcomePost
            return welcomePost.type == .sampleGroup ? true : false
        })?.key else {
            return nil
        }
        return key
    }

    func sampleGroupWelcomePostSeen() -> Bool? {
        guard let sampleGroupID = sampleGroupID() else { return nil }
        guard let welcomePost = welcomePostsDict[sampleGroupID] else { return nil }
        return welcomePost.seen
    }

    func markSampleGroupWelcomePostSeen() {
        guard let sampleGroupID = sampleGroupID() else { return }
        if welcomePostsDict[sampleGroupID] != nil {
            welcomePostsDict[sampleGroupID]?.seen = true
        }
        saveToUserDefaults()
        // trigger count update
        MainAppContext.shared.chatData.unreadGroupThreadCountController.updateCount()
    }
    
    func stopShowingWelcomePost(id: String) {
        if welcomePostsDict[id] != nil {
            welcomePostsDict[id]?.show = false
        }
        saveToUserDefaults()
    }

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
        welcomePostsDict.removeAll()
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
        
        if let decoded: [String: WelcomePost] = try? AppContext.shared.userDefaults.codable(forKey: UserDefaultsKey.welcomePosts) {
            welcomePostsDict = decoded
        }
    }

    // expiring welcome posts mean not showing them, it does not delete them
    private func expireWelcomePosts() {
        let cutoffDate = Date(timeIntervalSinceNow: -FeedPost.defaultExpiration)

        for (key, value) in welcomePostsDict {
            guard value.show else { return }
            if value.creationDate < cutoffDate {
                DDLogInfo("NUX/expireWelcomePosts/expiring \(value.id)")
                welcomePostsDict[key]?.show = false
            }
        }
        saveToUserDefaults()
    }

    // only delete welcome posts when the actual group is deleted
    // keep the mainfeed welcome post and sample group welcome post since those are to be shown just once
    func deleteWelcomePost(id: String) {
        guard let key = welcomePostsDict.first(where: {
            let welcomePost = $0.value as WelcomePost
            guard [.sampleGroup, .group].contains(welcomePost.type) else { return false }
            return welcomePost.id == id ? true : false
        })?.key else {
            return
        }

        // count sample group's welcome post as seen if user deletes sample group without clicking into it
        // note: do not remove sample group since we will only create it once
        if id == sampleGroupID() {
            DDLogInfo("NUX/deleteWelcomePost/sampleGroup/groupID/\(id)")
            markSampleGroupWelcomePostSeen()
        } else {
            DDLogInfo("NUX/deleteWelcomePost/groupID/\(id)")
            welcomePostsDict.removeValue(forKey: key)
            saveToUserDefaults()
        }
    }

    private func saveToUserDefaults() {
        let userDefaultsDict = Dictionary(uniqueKeysWithValues: eventCompletedVersions.map { ($0.key.rawValue, $0.value) })
        DDLogInfo("NUX/saveToUserDefaults saving events [\(userDefaultsDict.count)]")
        userDefaults.set(userDefaultsDict, forKey: UserDefaultsKey.eventCompletedVersions)
        
        try? AppContext.shared.userDefaults.setCodable(welcomePostsDict, forKey: UserDefaultsKey.welcomePosts)
    }

    private struct UserDefaultsKey {
        static var eventCompletedVersions = "nux.completed"
        static var welcomePosts = "nux.welcome.posts"
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
