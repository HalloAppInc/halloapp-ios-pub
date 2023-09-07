//
//  MainAppStrings.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 10/26/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon

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

    static var titleActivity: String {
        NSLocalizedString("activity.center.title", value: "Activity", comment: "Title for the activity center screen.")
    }
        
    static var titleChatNewMessage: String {
        NSLocalizedString("title.chat.new.message", value: "New Message", comment: "Title for new message screen where user chooses who to message")
    }

    static var titleSelectGroupMembersCreateGroup: String {
        NSLocalizedString("title.select.group.members.create.title", value: "Add Members", comment: "Title of screen where user can add members during group creation flow")
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
    
    static var titleStorage: String {
        NSLocalizedString("title.storage", value: "Storage", comment: "Row in Settings screen")
    }

    static var titleSuggestions: String {
        NSLocalizedString("title.suggestions", value: "Magic Post", comment: "Tab for suggestions tab in main interface")
    }

    // MARK: FAB

    static var fabPostButton: String {
        NSLocalizedString("fab.post.button", value: "Post", comment: "Label for floating compose post menu on Group screen.")
    }

    static var fabMoment: String {
        NSLocalizedString("fab.moment.button",
                   value: "New Moment",
                 comment: "Label for floating moment button on home feed.")
    }

    static var fabPost: String {
        NSLocalizedString("fab.moment.button",
                   value: "New Post",
                 comment: "Label for floating moment button on home feed.")
    }

    static var fabAccessibilityCamera: String {
        NSLocalizedString("fab.accessibility.camera", value: "Camera", comment: "VoiceOver label for camera button in floating compose post menu in Home view.")
    }

    static var fabAccessibilityPhotoLibrary: String {
        NSLocalizedString("fab.accessibility.photo.library", value: "Photo & Video", comment: "VoiceOver label for photo button in floating compose post menu in Home view.")
    }

    static var fabAccessibilityTextPost: String {
        NSLocalizedString("fab.accessibility.text", value: "Text", comment: "VoiceOver label for text post button in floating compose post menu in Home view.")
    }

    static var fabAccessibilityVoiceNote: String {
        NSLocalizedString("fab.accessibility.voice", value: "Audio", comment: "VoiceOver label for audio post button in floating compose post menu in Home view.")
    }
    
    // MARK: Message Actions

    static var messageReply: String {
        NSLocalizedString("message.reply", value: "Reply", comment: "Message action. Verb.")
    }

    static var messageForward: String {
        NSLocalizedString("message.forward", value: "Forward", comment: "Call to action to forward a message")
    }

    static var messageForwarded: String {
        NSLocalizedString("message.forwarded", value: "Forwarded", comment: "label on a chat message to indicate the chat message has been forwarded")
    }

    static var messageForwardTo: String {
        NSLocalizedString("message.forward", value: "Forward To", comment: "Title of page where user can pick contats to forward a chat messsage")
    }

    static var messageForwardAll: String {
        NSLocalizedString("message.forward.all", value: "Forward All", comment: "Call to action to forward a message which contains more than once media item")
    }

    static var messageCopy: String {
        NSLocalizedString("message.copy", value: "Copy", comment: "Message action. Verb.")
    }

    static var messageInfo: String {
        NSLocalizedString("message.info", value: "Info", comment: "Message action which shows receipt info when tapped. Verb.")
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

    static var buttonCall: String {
        NSLocalizedString("user.voice.call", value: "Call", comment: "Button to start voice call. Should be translated as verb.")
    }

    // MARK: Misc

    static var newPostTitle: String {
        NSLocalizedString("composer.post.title", value: "New Post", comment: "Composer New Post title.")
    }

    static var chatGroupInfoLeaveGroup: String {
        NSLocalizedString("chat.group.info.leave.group", value: "Leave group", comment: "Action label for leaving group")
    }

    static func leaveGroupConfirmation(groupName: String) -> String {
        let format = NSLocalizedString("chat.group.leave.group.confirmation", value: "Leave “%@”?", comment: "Confirmation message presented when leaving a group")
        return String(format: format, groupName)
    }

    static var inviteFriendsAndFamily: String {
        NSLocalizedString("app.ios.invite.friends", value: "Invite friends & family", comment: "Title of view where users can invite friends and family.")
    }

    static var inviteTitle: String {
        NSLocalizedString("invite.title", value: "Invite Friends", comment: "Title for the screen that allows to select contact to invite.")
    }

    static var settingsAppName: String {
        NSLocalizedString("app.ios.settings", value: "Settings", comment: "Translation of iPhone settings app.")
    }

    static func externalShareTitle(name: String) -> String {
        let format = NSLocalizedString("externalShare.og.title3",
                                       value: "%@'s HalloApp Post",
                                       comment: "Title for posts that are externally shared, 'John Smith's HalloApp Post'")
        return String(format: format, name)
    }

    static var externalShareAudioPostDescription: String {
        NSLocalizedString("externalShare.og.description.audio",
                          value: "Audio post",
                          comment: "Description of an externally shared post containing an audio post")
    }

    static var externalShareMediaPostDescription: String {
        NSLocalizedString("externalShare.og.description.media",
                          value: "Media post",
                          comment: "Description of an externally shared post containing photos/videos")
    }

    static var externalShareTextPostDescription: String {
        NSLocalizedString("externalShare.og.description.text",
                          value: "Text post",
                          comment: "Description of an externally shared post containing just text")
    }

    static func chatEventSecurityKeysChanged(name: String) -> String {
        return String(
            format: NSLocalizedString("chat.event.security.keys.changed", value: "Security keys with %@ changed", comment: "Text shown in Chat when the security keys of the contact user is chatting with, have changed"),
            name)
    }

    static func chatEventAddContactToAddressBook(name: String) -> String {
        return String(
            format: NSLocalizedString("chat.event.tap.to.add.contact", value: "Tap to add %@ to your address book", comment: "Chat entry that can be tapped to add the contact to address book"),
            name)
    }

    static var photoAndVideoLibrary: String {
        return String(
            format: NSLocalizedString("photo.and.video.library", value: "Photo & Video Library", comment: "button to launch photo and video library"))
    }

    static func unreadMessagesHeader(unreadCount: Int) -> String {
        let format = NSLocalizedString("n.unread.messages.title", comment: "Header that appears above unread messages in the chats view.")
        return String.localizedStringWithFormat(format, unreadCount)
    }

    static var chatEncryptionLabel: String {
        NSLocalizedString("chat.encryption.label", value: "All messages on HalloApp are end-to-end encrypted. Tap to learn more", comment: "Text shown at the top of the chat screen informing the user that the chat is end-to-end encrypted")
    }

    static var chatBlockedContactLabel: String {
        NSLocalizedString("chat.blocked.contact.label", value: "You blocked this contact", comment: "Text shown in the chat interface informing the user that the contact is blocked")
    }

    static var chatUnblockedContactLabel: String {
        NSLocalizedString("chat.unblocked.contact.label", value: "You unblocked this contact", comment: "Text shown in the chat interface informing the user that the contact is unblocked")
    }

    static var contactIsBlockedTitleLabel: String {
        NSLocalizedString("chat.contact.is.blocked.title.label", value: "Contact is blocked, you won't receive any messages until you unblock them.", comment: "Title of the bottom sheet shown in the chat screen of a contact that is blocked. The bottom sheet contains an unblock button.")
    }

    static var nonMemberLabel: String {
        NSLocalizedString("group.chat.contact.is.not.member", value: "You can’t send messages to this group because you’re no longer a member of this group.", comment: "When a user is no longer a member of a chat group, this message is displyed at the bottom of the chat, preventing them from sending messages.")
    }

    static var momentLabel: String {
        NSLocalizedString("chat.quoted.moment.label", value: "Moment", comment: "When user replies to a moment, it sends a quoted message to the author of the moment via chat. This label is displyed in the chat bubble to indicate a moment reply.")
    }

    static var momentExpiredLabel: String {
        NSLocalizedString("chat.quoted.moment.expired.label", value: "Moment expired", comment: "When user replies to a moment, it sends a quoted message to the author of the moment via chat. This label is displyed in the chat bubble to indicate a moment reply when the moment has expired.")
    }

    static var postExpiredLabel: String {
        NSLocalizedString("chat.quoted.post.expired.label", value: "Post expired", comment: "When user replies privately to a post, it sends a quoted message to the author of the post via chat. This label is displyed in the chat bubble to indicate a post reply when the post has expired.")
    }

    static var postDeletedLabel: String {
        NSLocalizedString("chat.quoted.post.deleted.label", value: "Post deleted", comment: "When user replies privately to a post, it sends a quoted message to the author of the post via chat. This label is displyed in the chat bubble to indicate a post reply when the post has been deleted.")
    }

    static var voiceCall: String {
        NSLocalizedString("call.history.voice.call", value: "Voice call", comment: "Title for call history event. Appears next to details of a successful call.")
    }

    static func incomingCall(name: String) -> String {
        return String(
            format: NSLocalizedString("call.history.incoming.call", value: "%@ called you", comment: "Title for call history event for an incoming call."),
            name)
    }
    
    static func outgoingCall(name: String) -> String {
        return String(
            format: NSLocalizedString("call.history.outgoing.call", value: "You called %@", comment: "Title for call history event for an outgoing call"),
            name)
    }

    static var voiceCallMissed: String {
        NSLocalizedString("call.history.voice.call.missed", value: "Missed voice call", comment: "Title for call history event. Appears next to details of a missed call.")
    }

    static var videoCall: String {
        NSLocalizedString("call.history.video.call", value: "Video call", comment: "Title for call history event. Appears next to details of a successful call.")
    }

    static var videoCallMissed: String {
        NSLocalizedString("call.history.video.call.missed", value: "Missed video call", comment: "Title for call history event. Appears next to details of a missed call.")
    }

    static var showMore: String {
        NSLocalizedString("share.destination.more", value: "Show more...", comment: "Show more groups in the share group selection")
    }

    static var sendTo: String {
        NSLocalizedString("destination.send.to", value: "Send To", comment: "Send to button and screen title")
    }

    static var messageInfoTitle: String {
        NSLocalizedString("message.info", value: "Message Info", comment: "Title of the view that displays receipt info for a message.")
    }

    static var addMedia: String {
        NSLocalizedString("composer.addmedia", value: "Add media", comment: "Label for add media button in post composer")
    }

    static var writePost: String {
        NSLocalizedString("composer.placeholder.text.post", value: "Write a post", comment: "Placeholder text in text post composer screen.")
    }
}
