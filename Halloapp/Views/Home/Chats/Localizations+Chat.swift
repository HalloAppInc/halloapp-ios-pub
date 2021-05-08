//
//  Localizations+Chat.swift
//  HalloApp
//
//  Created by Tony Jiang on 11/5/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import Core

extension Localizations {

    // MARK: Chat
    
    static var chatTyping: String {
        NSLocalizedString("chat.typing.capitalized", value: "typing...", comment: "Label shown when user is typing")
    }
    
    static var chatMessageDeleted: String {
        NSLocalizedString("chat.message.deleted", value: "This message was deleted.", comment: "Message text shown for the message that was deleted")
    }

    static var chatMessageWaiting: String {
        NSLocalizedString("chat.message.waiting", value: "Waiting for this message. This may take a while.", comment: "Text shown in place of a received message we are not able to decrypt yet.")
    }

    static var chatMessageUnsupported: String {
        NSLocalizedString("chat.message.unsupported", value: "Your version of HalloApp does not support this type of message.", comment: "Text shown in place of a received message we are not able to process yet.")
    }

    static var chatMessagePhoto: String {
        NSLocalizedString("chat.message.photo", value: "Photo", comment: "Message text shown in a message that have photo media but no text")
    }
    
    static var chatMessageVideo: String {
        NSLocalizedString("chat.message.video", value: "Video", comment: "Message text shown in a message that have video media but no text")
    }
    
    static func threadListPreviewAlreadyUserDefault(name: String) -> String {
        return String(
            format: NSLocalizedString("thread.list.preview.already.user.default", value: "%@ is on HalloApp", comment: "Default preview text shown for a symmetric contact in the chats list screen that the user haven't messaged yet"),
            name)
    }
    
    static func threadListPreviewNewUserDefault(name: String) -> String {
        return String(
            format: NSLocalizedString("thread.list.preview.new.user.default", value: "%@ is on HalloApp! 🎉", comment: "Default preview text shown for a symmetric contact who just joined Halloapp"),
            name)
    }
    
    // MARK: Chat Group
    
    static var chatInviteFriends: String {
        NSLocalizedString("chat.invite.friends", value: "Invite Friends", comment: "Label for inviting friends")
    }
    
    static var chatCreateNewGroup: String {
        NSLocalizedString("chat.create.new.group", value: "Create New Group", comment: "Label for creating a new group")
    }
    
    static var chatGroupNameLabel: String {
        NSLocalizedString("chat.group.name.label", value: "GROUP NAME", comment: "Label shown above group name input box")
    }

    static var chatGroupBackgroundLabel: String {
        NSLocalizedString("chat.group.background.label", value: "BACKGROUND", comment: "Label shown above background selection row")
    }

    static var chatGroupMembersLabel: String {
        NSLocalizedString("chat.group.members.label", value: "MEMBERS", comment: "Label shown above group members list")
    }

    static var chatGroupPhotoTitle: String {
        NSLocalizedString("chat.group.photo.label", value: "Group Photo", comment: "Title for group photo actions")
    }
    
    static var chatGroupTakeOrChoosePhoto: String {
        NSLocalizedString("chat.group.take.or.choose.photo", value: "Take or Choose Photo", comment: "Action to take a picture or choose a photo from the library to use for the group photo")
    }
    
}
