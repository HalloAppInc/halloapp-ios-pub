//
//  InvitePeopleView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 7/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import SwiftUI

extension Localizations {
    static var pleaseWait: String {
        NSLocalizedString("invite.please.wait", value: "Please wait...", comment: "Displayed white user is inviting someone.")
    }

    static func outOfInvitesWith(date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .short
        dateFormatter.dateStyle = .medium
        let format = NSLocalizedString("invite.out.of.invites.w.date",
                                       value: "You're out of invites. Please check back after %@",
                                       comment: "Displayed when user does not have any invites left. Parameter is date.")
        return String(format: format, dateFormatter.string(from: date))
    }

    static var inviteErrorTitle: String {
        NSLocalizedString("invite.error.alert.title",
                          value: "Could not invite",
                          comment: "Title of the alert popup that is displayed when something went wrong with inviting a contact to HalloApp.")
    }

    static var inviteErrorMessage: String {
        NSLocalizedString("invite.error.alert.message",
                          value: "Something went wrong. Please try again later.",
                          comment: "Body of the alert popup that is displayed when something went wrong with inviting a contact to HalloApp.")
    }

    static func inviteText(name: String?, number: String?) -> String {
        guard let name = name, let number = number else {
            return NSLocalizedString("invite.text",
                              value: "Join me on HalloApp – a simple, private, and secure way to stay in touch with friends and family. Get it at https://halloapp.com/dl",
                              comment: "Text of invitation to join HalloApp.")
        }
        let format = NSLocalizedString("invite.text.specific",
                                       value: "Hey %1$@, I have an invite for you to join me on HalloApp (a simple social app for sharing everyday moments). Use %2$@ to register. Get it at https://halloapp.com/dl",
                                       comment: "Text of invitation to join HalloApp. First argument is the invitee's name, second argument is their phone number.")
        return String(format: format, name, number)
    }
}
