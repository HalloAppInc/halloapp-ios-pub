//
//  Localizations+Registration.swift
//  HalloApp
//
//  Created by Garrett on 11/3/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import Core

extension Localizations {

    // MARK: Registration

    static var registrationWelcome: String {
        NSLocalizedString("registration.welcome", value: "Welcome!", comment: "Shown above name and phone inputs")
    }

    static var registrationNamePlaceholder: String {
        NSLocalizedString("registration.nameEntry.placeholder", value: "Your Name", comment: "Placeholder text for name entry")
    }

    static var registrationPhoneEntryPlaceholder: String {
        NSLocalizedString("registration.phoneEntry.placeholder", value: "Phone number", comment: "Placeholder text for phone entry")
    }

    static var registrationInviteOnlyTitle: String {
        NSLocalizedString("registration.shucks", value: "Shucks!", comment: "Title for popup that appears when user tries to register uninvited number")
    }

    static var registrationInviteOnlyText: String {
        NSLocalizedString("registration.invite.only", value: "If you followed a Group Invite Link to register, please click on the link again to finish registration and join the group.", comment: "Popup that appears when user tries to register uninvited number")
    }

    static var registrationCodeDisclaimer: String {
        NSLocalizedString("registration.code.disclaimer", value: "You’ll receive a verification code.\nCarrier rates may apply.", comment: "Disclaimer text about receiving SMS verification code")
    }

    static var registrationCodeResend: String {
        NSLocalizedString("registration.code.resend", value: "Resend SMS", comment: "Button label to resend verification code")
    }

    static var registrationCodeResendByVoice: String {
        NSLocalizedString("registration.code.resend.by.voice", value: "Call me", comment: "Button label to resend verification code by voice call")
    }

    static var registrationCodeIncorrect: String {
        NSLocalizedString("registration.code.incorrect", value: "The code you entered is incorrect", comment: "Error message to display when user enters incorrect verification code")
    }

    static var registrationCodeRequestError: String {
        NSLocalizedString("registration.code.request.error", value: "Could not send code. Please try again later.", comment: "Error message to display when we cannot send a verification code")
    }

    static func registrationCodeInstructions(formattedNumber: String) -> String {
        String(
            format: NSLocalizedString(
                "registration.code.instructions",
                value: "Enter the code we sent to %@",
                comment: "Instructions for filling in SMS verification code. Parameter is formatted phone number"),
            formattedNumber)
    }

    static var registrationContactPermissionsTitle: String {
        NSLocalizedString("registration.contacts.title", value: "One last thing", comment: "Title for text explaining why we need contact permissions")
    }

    static var registrationContactPermissionsContent: String {
        NSLocalizedString(
            "registration.contacts.content",
            value: "In order to connect you with your friends & family we’ll need your permission to access your contacts.",
            comment: "Text explaining why we need contact permissions")
    }

    static var registrationPrivacyModalTitle: String {
        NSLocalizedString(
            "registration.privacy.title",
            value: "Your privacy is our priority",
            comment: "Title for modal describing how we use contacts data")
    }

    static var registrationPrivacyModalContent: String {
        NSLocalizedString(
            "registration.privacy.content",
            value: "HalloApp only uses the phone number field to match you with your friends on HalloApp, and does not transmit any additional data from your contact book.",
            comment: "Text for modal describing how we use contacts data")
    }

    static func registrationGroupName(formattedGroupName: String) -> String {
        String(
            format: NSLocalizedString(
                "registration.group.name",
                value: "You're invited to join the group %@",
                comment: "When user registers via group invite link, the name of the group they are invited to is displayed on the registration screen"),
            formattedGroupName)
    }

    static var freeAppDownloadText: String {
        NSLocalizedString("registration.free.app.notice", value: "Free on the iPhone App Store", comment: "Text indicating to the user that HalloApp is available for free on the iPhone App Store")
    }
    
    static var installAppToContinue: String {
        NSLocalizedString("registration.install.app.to.continue", value: "Install HalloApp to continue", comment: "Once the user completes registration in the app clip, this text is displayed in the AppClip prompting the user to install the full app to continue using HalloApp")
    }
    
    static var buttonInstall: String {
        NSLocalizedString("button.install", value: "Install", comment: "Title for Install button, takes the user to the HalloApp app store view where they can download the app.")
    }
    
    static var appUpdateNoticeTitle: String {
        NSLocalizedString("home.update.notice.title", value: "This version is out of date", comment: "Title of update notice shown to users who have old versions of the app")
    }

    static var appUpdateNoticeText: String {
        NSLocalizedString("home.update.notice.text", value: "Please update to the latest version of HalloApp", comment: "Text shown to users who have old versions of the app")
    }

    static var appUpdateNoticeButtonExit: String {
        NSLocalizedString("home.update.notice.button.exit", value: "Exit", comment: "Title for exit button that closes the app")
    }
}
