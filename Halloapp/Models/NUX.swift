//
//  NUX.swift
//  HalloApp
//
//  Created by Garrett on 9/22/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation

final class NUX {
    enum Event: String {
        case homeFeedIntro
        case chatListIntro
        case profileIntro
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

    static let activityCenterIconContent = "This is your activity center. Tap to see your most recent activity."
    static let profileContent = "This is your profile. Your own posts will collect here. Each post expires in 30 days."
    static let chatIntroContent = "This is where you’ll find messages from your friends & family. When someone new joins HalloApp you can see them here."
    static let newPostButtonContent = "Tap to share an update with your friends & family on HalloApp"
    static let homeFeedIntroContent = "Welcome to your home feed! This is where you can see posts from your phone contacts who use HalloApp."
    static let homeFeedDetailsTitle = "About HalloApp"
    static let homeFeedDetailsBody = """
Home feed allows you to share text, photo, and video updates that disappear after 30 days.

If you want to share updates with someone, both parties must have each other's numbers saved on their phones.

You can share your updates with your entire contact list or only with selected people. Go to settings to change feed privacy.
"""
}
