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
        
    static var titleChatNewMessage: String {
        NSLocalizedString("title.chat.new.message", value: "New Message", comment: "Title for new message screen where user chooses who to message")
    }

    static var titleSelectGroupMembersCreateGroup: String {
        NSLocalizedString("title.select.group.members.create.group", value: "Create New Group", comment: "Title of screen where user chooses members to add to either a new group or an existing one")
    }

    static var titleSelectGroupMembers: String {
        NSLocalizedString("title.select.group.members.title", value: "Add New Members", comment: "Title of screen where user chooses members to add to either a new group or an existing one")
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
    
    static var titleStorage: String {
        NSLocalizedString("title.storage", value: "Storage", comment: "Row in Settings screen")
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

    static var fabAccessibilityVoiceNote: String {
        NSLocalizedString("fab.accessibility.voice", value: "Voice Note", comment: "VoiceOver label for voice note button in floating compose post menu in Home view.")
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
    
    static var contactsPermissionExplanationTitle: String {
        NSLocalizedString("contacts.permission.explanation.title", value: "Contacts", comment: "Title for modal view when showing how to change contact permissions.")
    }

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
            value: "Turn on “Contacts”",
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
    
    static var userOptionUnblock: String {
        NSLocalizedString("user.option.unblock", value: "Unblock on HalloApp", comment: "Option when user taps more on profile page")
    }
    
    static var userOptionCopyPhoneNumber: String {
        NSLocalizedString("user.option.copy.phone.number", value: "Copy Phone Number", comment: "Option when User clicks on the phone number on profile page and this can let the user copy the phone number")
    }
    
    static func blockMessage(username: String) -> String {
        return NSLocalizedString("user.block.message", value: "Are you sure you want to block %@ on HalloApp? You can always change this later.", comment: "Message asking if the user is sure they want to block this user").replacingOccurrences(of: "%@", with: username)
    }
    
    static func unBlockMessage(username: String) -> String {
        return NSLocalizedString("user.unblock.message", value: "Are you sure you want to unblock %@ on HalloApp? You can always change this later.", comment: "Message asking if the user is sure they want to unblock this user").replacingOccurrences(of: "%@", with: username)
    }
    
    static var blockButton: String {
        NSLocalizedString("user.block", value: "Block", comment: "Button to confirm blocking user via profile page")
    }
    
    static var unBlockButton: String {
        NSLocalizedString("user.unblock", value: "Unblock", comment: "Button to confirm unblocking user via profile page")
    }
    
    // MARK: Misc

    static var inviteFriendsAndFamily: String {
        NSLocalizedString("app.ios.invite.friends", value: "Invite friends & family", comment: "Title of view where users can invite friends and family.")
    }

    static var inviteTitle: String {
        NSLocalizedString("invite.title", value: "Invite Friends", comment: "Title for the screen that allows to select contact to invite.")
    }

    static var settingsAppName: String {
        NSLocalizedString("app.ios.settings", value: "Settings", comment: "Translation of iPhone settings app.")
    }

}
