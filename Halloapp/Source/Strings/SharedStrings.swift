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

    static var buttonNext: String {
        NSLocalizedString("button.next", value: "Next", comment: "Title for generic Next button. Mostly used to proceed to next screen in flow.")
    }
    
    static var buttonCreate: String {
        NSLocalizedString("button.create", value: "Create", comment: "Title for generic Create button")
    }

    static var buttonDone: String {
        NSLocalizedString("button.done", value: "Done", comment: "Title for generic Done button. Mostly used to complete some modal flow.")
    }
    
    static var buttonSave: String {
        NSLocalizedString("button.done", value: "Save", comment: "Title for generic Save button. Mostly used to complete some modal flow.")
    }

    // MARK: Links

    static var linkLearnMore: String {
        NSLocalizedString("link.learnMore", value: "Learn more", comment: "Generic 'learn more' link. Mostly used to present additional information about topic.")
    }

    // MARK: Misc

    static var unknownContact: String {
        NSLocalizedString("unknown.contact", value: "Unknown Contact", comment: "Displayed in place of contact name if name is not known.")
    }

}
