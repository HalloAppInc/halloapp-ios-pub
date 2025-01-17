//
//  Localizations+Chat.swift
//  HalloApp
//
//  Created by Tony Jiang on 11/5/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon

extension Localizations {

    // MARK: Chat
    
    static var chatTyping: String {
        NSLocalizedString("chat.typing.capitalized", value: "typing...", comment: "Label shown when user is typing")
    }
    
    static func userChatTyping(name: String) -> String {
        return String(
            format: NSLocalizedString("user.chat.typing", value: "%@ is typing...", comment: "Label shown in group chat when a user is typing"),
            name)
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

    static var chatMessageAudio: String {
        NSLocalizedString("chat.message.audio", value: "Audio note", comment: "Message text shown in a message that have audio media but no text")
    }

    static var chatMessageDocument: String {
        NSLocalizedString("chat.message.document", value: "File", comment: "Message text shown in a message that has document but no text")
    }

    static var chatMessageAudioPost: String {
        NSLocalizedString("chat.message.audiopost", value: "Audio post", comment: "Message text shown for quoted audio posts")
    }
    
    static func threadListPreviewAlreadyUserDefault(name: String) -> String {
        return String(
            format: NSLocalizedString("thread.list.preview.already.user.default", value: "%@ is on HalloApp", comment: "Default preview text shown for a symmetric contact in the chats list screen that the user haven't messaged yet"),
            name)
    }
    
    static func threadListPreviewInvitedUserDefault(name: String) -> String {
        return String(
            format: NSLocalizedString("thread.list.preview.new.user.default", value: "%@ is on HalloApp🎉", comment: "Default preview text shown for a symmetric contact who just joined Halloapp"),
            name)
    }
    
    // MARK: Group
    
    static var chatInviteFriends: String {
        NSLocalizedString("chat.invite.friends", value: "Invite Friends", comment: "Label for inviting friends")
    }
    
    static var chatCreateNewGroup: String {
        NSLocalizedString("chat.create.new.group", value: "Create New Group", comment: "Label for creating a new group")
    }
    
    static var chatGroupNameLabel: String {
        NSLocalizedString("chat.group.name.label", value: "Group Name", comment: "Label shown above group name input box")
    }
    
    static var groupDescriptionLabel: String {
        NSLocalizedString("group.description.label", value: "Group Description", comment: "Label shown above group description input box")
    }

    static var groupAddDescription: String {
        NSLocalizedString("group.add.description", value: "Add group description", comment: "Placeholder text shown in group description input box when there's no description")
    }

    static var groupBackgroundLabel: String {
        NSLocalizedString("group.background.label", value: "Background", comment: "Label shown above background selection row")
    }

    static var groupMembersLabel: String {
        NSLocalizedString("group.members.label", value: "Members", comment: "Label shown above group members list")
    }

    static var chatGroupPhotoTitle: String {
        NSLocalizedString("chat.group.photo.label", value: "Group Photo", comment: "Title for group photo actions")
    }
    
    static var chatGroupTakeOrChoosePhoto: String {
        NSLocalizedString("chat.group.take.or.choose.photo", value: "Take or Choose Photo", comment: "Action to take a picture or choose a photo from the library to use for the group photo")
    }

    static var learnMoreLabel: String {
        NSLocalizedString("learn.more", value: "Learn more.", comment: "Text with hyperlink to halloapp's faq on encryption.")
    }

    static func appendLearnMoreLabel(to waitingString: String) -> NSMutableAttributedString {
        let waitingAttributedString = NSMutableAttributedString(string: waitingString + " ")
        let learnMoreAttributedString = NSMutableAttributedString(string: Localizations.learnMoreLabel)
        if let url = URL(string: "https://halloapp.com/help/#waiting-for-this-message") {
            learnMoreAttributedString.setAttributes([.link: url], range: Localizations.learnMoreLabel.utf16Extent)
        }
        waitingAttributedString.append(learnMoreAttributedString)
        return waitingAttributedString
    }
}
