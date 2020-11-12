//
//  Localizations+Chat.swift
//  HalloApp
//
//  Created by Tony Jiang on 11/5/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import Core

extension Localizations {

    // MARK: CHAT
    
    static var chatTypingCapitalized: String {
        NSLocalizedString("chat.typing.capitalized", value: "Typing...", comment: "Capitalized label shown when user is typing")
    }
    
    static var chatMessageDeleted: String {
        NSLocalizedString("chat.message.deleted", value: "This message was deleted.", comment: "Message text shown for the message that was deleted")
    }
    
    static var chatMessagePhoto: String {
        NSLocalizedString("chat.message.photo", value: "Photo", comment: "Message text shown in a message has photo media but no text")
    }
    
    static var chatMessageVideo: String {
        NSLocalizedString("chat.message.video", value: "Video", comment: "Message text shown in a message has video media but no text")
    }
    
    // MARK: Chat Group
    
    static var chatCreateNewGroup: String {
        NSLocalizedString("chat.create.new.group", value: "Create New Group", comment: "Label for creating a new group")
    }
    
    static var chatGroupNameLabel: String {
        NSLocalizedString("chat.group.name.label", value: "GROUP NAME", comment: "Label shown above group name input box")
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
