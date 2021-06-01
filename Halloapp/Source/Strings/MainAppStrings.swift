//
//  MainAppStrings.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 10/26/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import Core

extension Localizations {

    // MARK: Screen Titles

    static var titleHome: String {
        NSLocalizedString("title.home", value: "Home", comment: "First tab in the main app interface.")
    }

    static var titleGroups: String {
        NSLocalizedString("title.groups", value: "Groups", comment: "Second tab in the main app interface.")
    }
    
    static var titleChats: String {
        NSLocalizedString("title.chats", value: "Chats", comment: "Third tab in the main app interface.")
    }

    static var titleSettings: String {
        NSLocalizedString("title.settings", value: "Settings", comment: "Fourth tab in the main app interface")
    }
    
    static var titleMyPosts: String {
        NSLocalizedString("profile.row.my.posts", value: "My Posts", comment: "Row in Settings screen")
    }
    
    static var titleNotifications: String {
        NSLocalizedString("title.notifications", value: "Notifications", comment: "Row in Settings screen")
    }

    static var titlePrivacy: String {
        NSLocalizedString("title.privacy", value: "Privacy", comment: "Row in Settings screen")
    }
    
    // MARK: FAB Accessibility

    static var fabAccessibilityCamera: String {
        NSLocalizedString("fab.accessibility.camera", value: "Camera", comment: "VoiceOver label for camera button in floating compose post menu in Home view.")
    }

    static var fabAccessibilityPhotoLibrary: String {
        NSLocalizedString("fab.accessibility.photo.library", value: "Photo Library", comment: "VoiceOver label for photo button in floating compose post menu in Home view.")
    }

    static var fabAccessibilityTextPost: String {
        NSLocalizedString("fab.accessibility.text", value: "Text", comment: "VoiceOver label for text post button in floating compose post menu in Home view.")
    }
    
    // MARK: Message Actions

    static var messageReply: String {
        NSLocalizedString("message.reply", value: "Reply", comment: "Message action. Verb.")
    }

    static var messageCopy: String {
        NSLocalizedString("message.copy", value: "Copy", comment: "Message action. Verb.")
    }

    static var messageInfo: String {
        NSLocalizedString("message.info", value: "Info", comment: "Message action. Verb.")
    }

    static var messageDelete: String {
        NSLocalizedString("message.delete", value: "Delete", comment: "Message action. Verb.")
    }

    // MARK: Contact permissions

    static var contactsPermissionExplanation: String {
        NSLocalizedString(
            "contacts.permission.explanation",
            value: "To help you connect with friends and family allow HalloApp access to your contacts.",
            comment: "Message requesting the user enable contacts permission")
    }

    static var contactsTutorialTitle: String {
        NSLocalizedString(
            "contacts.permission.tutorial.title",
            value: "How to turn on “Contacts”",
            comment: "Title for tutorial explaining how user can enable contacts permission")
    }

    static var tutorialTapBelow: String {
        NSLocalizedString(
            "tutorial.tap.below",
            value: "Tap “%@” below.",
            comment: "Instructs user to tap a button (e.g., Tap “Go to Settings” below.)")
    }

    static var tutorialTurnOnContacts: String {
        NSLocalizedString(
            "turn.on.contacts",
            value: "Turn on “Contacts”.",
            comment: "Indicates which switch a user needs to turn on to enable contacts permissions.")
    }

    
    // MARK: User
    
    static var userYouCapitalized: String {
        NSLocalizedString("user.you.capitalized", value: "You", comment: "Capitalized reference to the user, second person pronoun")
    }
    
    static var userYou: String {
        NSLocalizedString("user.you", value: "you", comment: "Reference to the user, second person pronoun")
    }
    
    static var userOptionBlock: String {
        NSLocalizedString("user.option.block", value: "Block on HalloApp", comment: "Option when user taps more on profile page")
    }
    
    static func blockMessage(username: String) -> String {
        return NSLocalizedString("user.block.message", value: "Are you sure you want to block %@ on HalloApp? You can always change this later.", comment: "Message asking if the user is sure they want to block this user").replacingOccurrences(of: "%@", with: username)
    }
    
    static var blockButton: String {
        NSLocalizedString("user.block", value: "Block", comment: "Button to confirm blocking user via profile page")
    }
    
    // MARK: Misc

    static var inviteFriendsAndFamily: String {
        "Invite friends & family"
    }

    static var settingsAppName: String {
        NSLocalizedString("app.ios.settings", value: "Settings", comment: "Translation of iPhone settings app.")
    }

}
