//
//  ServerStrings.swift
//  HalloApp
//
//  Created by Murali Balusu on 4/28/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation
import Core

extension Localizations {

    // MARK: Server Strings

    static var serverChatMessageNotification: String {
        NSLocalizedString("server.new.message", value: "New Message", comment: "fallback text in notification for a new chat message")
    }

    static var serverGroupMessageNotification: String {
        NSLocalizedString("server.new.group.message", value: "New Group Message", comment: "fallback text in notification for a new group chat message")
    }

    static var serverInviterNotification: String {
        NSLocalizedString("server.new.inviter", value: "%@ just accepted your invite to join HalloApp 🎉", comment: "fallback text in notification when an invitee joins")
    }

    static var serverContactNotification: String {
        NSLocalizedString("server.new.contact", value: "%@ is now on HalloApp", comment: "fallback text in notification when a new contact joins")
    }

    static var serverFeedPostNotification: String {
        NSLocalizedString("server.new.post", value: "New Post", comment: "fallback text in notification for a new feed post")
    }

    static var serverFeedCommentNotification: String {
        NSLocalizedString("server.new.comment", value: "New Comment", comment: "fallback text in notification for a new comment")
    }

    static var serverGroupAddNotification: String {
        NSLocalizedString("server.new.group", value: "You were added to a new group", comment: "fallback text in notification when user is added to a new group")
    }

    static var serverSmsVerification: String {
        NSLocalizedString("server.sms.verification", value: "Your HalloApp verification code", comment: "text in the sms sent with verification code")
    }

    static var serverVoiceCallVerification: String {
        NSLocalizedString("server.voicecall.verification", value: "Your HalloApp verification code is", comment: "text in the voice call sent with verification code")
    }

    static var serverMarketingTitle: String {
        NSLocalizedString("server.marketing.title", value: "Hallo there!", comment: "title of the marketing alert sent to users")
    }

    static var serverMarketingBody: String {
        NSLocalizedString("server.marketing.body", value: "Invite your friends to enjoy HalloApp!", comment: "body of the marketing alert sent to users")
    }

}
