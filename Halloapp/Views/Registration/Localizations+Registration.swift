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
        NSLocalizedString("registration.invite.only", value: "We are currently invite only. If you have a friend family member who uses HalloApp, ask them to invite you using your phone number.", comment: "Popup that appears when user tries to register uninvited number")
    }

    static var registrationCodeDisclaimer: String {
        NSLocalizedString("registration.code.disclaimer", value: "You’ll receive a verification code.\nCarrier rates may apply.", comment: "Disclaimer text about receiving SMS verification code")
    }

    static var registrationCodeResend: String {
        NSLocalizedString("registration.code.resend", value: "Resend Code", comment: "Button label to resend verification code")
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
            value: "HalloApp only uses the phone number field to match you with your friends on HalloApp, and does not capture any additional data from your contact book.",
            comment: "Text for modal describing how we use contacts data")
    }
}
