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

    static var titleMessages: String {
        NSLocalizedString("title.messages", value: "Messages", comment: "Second tab in the main app interface.")
    }

    static var titleSettings: String {
        NSLocalizedString("title.settings", value: "Settings", comment: "Row in Profile screen.")
    }

    static var titleMyPosts: String {
        NSLocalizedString("profile.row.my.posts", value: "My Posts", comment: "Row in Profile screen.")
    }

    // MARK: FAB Accessibility

    static var fabAccessibilityCamera: String {
        NSLocalizedString("fab.accessibility.camera", value: "Camera", comment: "VoiceOver label for camera button in floating compose post menu in Feed view.")
    }

    static var fabAccessibilityPhotoLibrary: String {
        NSLocalizedString("fab.accessibility.photo.library", value: "Photo Library", comment: "VoiceOver label for photo button in floating compose post menu in Feed view.")
    }

    static var fabAccessibilityTextPost: String {
        NSLocalizedString("fab.accessibility.text", value: "Text", comment: "VoiceOver label for text post button in floating compose post menu in Feed view.")
    }
    
    static var fabAccessibilityNewMessage: String {
        NSLocalizedString("fab.accessibility.new.message", value: "New message", comment: "VoiceOver label for floating compose message button in Messages view ")
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
    
    // MARK: User
    
    static var userYouCapitalized: String {
        NSLocalizedString("user.you.capitalized", value: "You", comment: "Capitalized reference to the user, second person pronoun")
    }
    
    static var userYou: String {
        NSLocalizedString("user.you", value: "you", comment: "Reference to the user, second person pronoun")
    }
    
    // MARK: Misc

    static var inviteFriendsAndFamily: String {
        "Invite friends & family"
    }

    static var settingsAppName: String {
        NSLocalizedString("app.ios.settings", value: "Settings", comment: "Translation of iPhone settings app.")
    }

}
