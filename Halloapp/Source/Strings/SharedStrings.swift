//
//  SharedStrings.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 10/26/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import Core

extension Localizations {

    // MARK: Buttons

    static var buttonOK: String {
        NSLocalizedString("button.ok", value: "OK", comment: "Title for generic OK button. Mostly used in popups and as such.")
    }

    static var buttonCancel: String {
        NSLocalizedString("button.cancel", value: "Cancel", comment: "Title for generic Cancel button. Mostly used in popups and as such.")
    }

    static var buttonCancelCapitalized: String {
        NSLocalizedString("button.cancel", value: "CANCEL", comment: "Title for generic capitalized CANCEL button. Mostly used in popups and as such.")
    }
    
    static var buttonNext: String {
        NSLocalizedString("button.next", value: "Next", comment: "Title for generic Next button. Mostly used to proceed to next screen in flow.")
    }
    
    static var buttonCreate: String {
        NSLocalizedString("button.create", value: "Create", comment: "Title for generic Create button")
    }

    static var buttonShare: String {
        NSLocalizedString("button.share", value: "Share", comment: "Title for generic Share button. Mostly used to complete some modal flow.")
    }

    static var buttonSend: String {
        NSLocalizedString("button.send", value: "Send", comment: "Title for generic Send button. Mostly used to complete some modal flow.")
    }
    
    static var buttonDone: String {
        NSLocalizedString("button.done", value: "Done", comment: "Title for generic Done button. Mostly used to complete some modal flow.")
    }
    
    static var buttonSave: String {
        NSLocalizedString("button.save", value: "Save", comment: "Title for generic Save button. Mostly used to complete some modal flow.")
    }
    
    static var buttonUpdate: String {
        NSLocalizedString("button.update", value: "Update", comment: "Title for generic Update button. Mostly used to complete some modal flow.")
    }

    static var buttonDismiss: String {
        NSLocalizedString("button.dismiss", value: "Dismiss", comment: "Title for generic Dismiss button. Mostly used to complete some modal flow.")
    }
    
    static var buttonRemove: String {
        NSLocalizedString("button.remove", value: "Remove", comment: "Title for generic Remove button. Mostly used to complete some modal flow.")
    }

    static var buttonMore: String {
        NSLocalizedString("button.more", value: "More", comment: "Title for generic More button. Mostly used to complete some modal flow.")
    }

    static var buttonContinue: String {
        NSLocalizedString("button.continue", value: "Continue", comment: "Title for generic Continue button. Mostly used to complete some modal flow.")
    }

    static var buttonNotNow: String {
        NSLocalizedString("button.not.now", value: "Not Now", comment: "Title for generic Not Now button. Mostly used to complete some modal flow.")
    }

    static var buttonGoToSettings: String {
        NSLocalizedString("button.go.to.settings", value: "Go to Settings", comment: "Title for button that will take user to iOS settings (e.g., to enable some permission we need).")
    }
    
    // MARK: Links

    static var linkLearnMore: String {
        NSLocalizedString("link.learnMore", value: "Learn more", comment: "Generic 'learn more' link. Mostly used to present additional information about topic.")
    }

    static var linkUpdateYourApp: String {
        NSLocalizedString("link.update.your.app", value: "Update your app.", comment: "Link that when tapped will open App Store so user can update to the latest version of the app.")
    }

    // MARK: Misc

    static var meCapitalized: String {
        NSLocalizedString("meCapitalized", value: "Me", comment: "Displayed in place of own name (e.g., next to own comments)")
    }

    static var unknownContact: String {
        NSLocalizedString("unknown.contact", value: "Unknown Contact", comment: "Displayed in place of contact name if name is not known.")
    }

}
