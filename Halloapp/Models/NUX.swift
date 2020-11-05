//
//  NUX.swift
//  HalloApp
//
//  Created by Garrett on 9/22/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core

final class NUX {
    enum Event: String {
        case homeFeedIntro
        case chatListIntro
        case activityCenterIcon
        case newPostButton
        case feedPostWhoWillSee
    }

    private var isDemoMode = false
    private var demoEventsCompleted = Set<Event>()

    func isIncomplete(_ event: Event) -> Bool {
        if isDemoMode {
            return !demoEventsCompleted.contains(event)
        }

        // Not live yet
        return false
    }

    func didComplete(_ event: Event) {
        if isDemoMode {
            demoEventsCompleted.insert(event)
        }
    }

    func startDemo() {
        isDemoMode = true
        demoEventsCompleted.removeAll()
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
