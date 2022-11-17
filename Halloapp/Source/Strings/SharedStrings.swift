//
//  SharedStrings.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 10/26/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon

extension Localizations {

    static var appNameHalloApp: String {
        NSLocalizedString("app.name.halloapp", value: "HalloApp", comment: "Company name")
    }

    // MARK: Inviting

    static var shareHalloAppString: String {
        NSLocalizedString("settings.share.text", value: "Join my real-relationship network on HalloApp. Download for free at halloapp.com/dl", comment: "String to auto-fill if a user tried to share to a friend.")
    }

    // MARK: Buttons

    static var buttonOK: String {
        NSLocalizedString("button.ok", value: "OK", comment: "Title for generic OK button. Mostly used in popups and as such.")
    }

    static var buttonCancel: String {
        NSLocalizedString("button.cancel", value: "Cancel", comment: "Title for generic Cancel button. Mostly used in popups and as such.")
    }

    static var buttonCancelCapitalized: String {
        NSLocalizedString("button.cancel.capitalized", value: "CANCEL", comment: "Title for generic capitalized CANCEL button. Mostly used in popups and as such.")
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

    static var buttonInvite: String {
        NSLocalizedString("button.invite", value: "Invite", comment: "Title for generic Invite button.")
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

    static var buttonDiscard: String {
        NSLocalizedString("media.button.discard", value: "Discard", comment: "Button title. Refers to discarding photo/video edits in media composer.")
    }

    static var buttonGoToSettings: String {
        NSLocalizedString("button.go.to.settings", value: "Go to Settings", comment: "Title for button that will take user to iOS settings (e.g., to enable some permission we need).")
    }
    
    static var buttonLearnMore: String {
        NSLocalizedString("button.learn.more", value: "Learn More", comment: "Title for generic Learn More button. Used to provide user with additional context to actions requested.")
    }
    
    static var buttonDelete: String {
        NSLocalizedString("Delete", comment: "Title for generic delete button.")
    }

    static var buttonAdd: String {
        NSLocalizedString("button.add", value: "Add", comment: "Title for generic Add button. Used to add more items to current selection (e.g., add more members to a group)")
    }

    static var buttonStop: String {
        NSLocalizedString("button.stop", value: "Stop", comment: "Title for generic Stop button. Currently used to stop an audio recording)")
    }
    
    static var labelSearch: String {
        NSLocalizedString("label.search", value: "Search", comment: "Generic label for search, mostly used as placeholder text for searchbar")
    }

    static var copyLink: String {
        return NSLocalizedString("button.copy.link", value: "Copy Link", comment: "Title for generic copy URL button")
    }
    
    // MARK: Links

    static var linkLearnMore: String {
        NSLocalizedString("link.learnMore", value: "Learn more", comment: "Generic 'learn more' link. Mostly used to present additional information about topic.")
    }

    static var linkUpdateYourApp: String {
        NSLocalizedString("link.update.your.app", value: "Update your app.", comment: "Link that when tapped will open App Store so user can update to the latest version of the app.")
    }

    // MARK: No Internet Connection Alert Box

    static var alertNoInternetTitle: String {
        NSLocalizedString("alert.no.internet.title", value: "No Internet Connection", comment: "Title for alert shown when there's no internet connectivity")
    }

    static var alertNoInternetTryAgain: String {
        NSLocalizedString("alert.no.internet.try.again", value: "Please check if you have internet connectivity, then try again.", comment: "Message to tell the user to try again when they have internet connectivity again")
    }

    // MARK: Audio Rermissions Alert

    static var micAccessDeniedTitle: String {
        NSLocalizedString("chat.mic.access.denied.title", value: "Unable to access microphone", comment: "Alert title when missing microphone access")
    }

    static var micAccessDeniedMessage: String {
        NSLocalizedString("chat.mic.access.denied.message", value: "To enable audio recording, please tap on Settings and then turn on Microphone", comment: "Alert message when missing microphone access")
    }

    static var exporting: String {
        NSLocalizedString("toast.exporting", value: "Exporting…", comment: "Toast displayed while preparing video for external share")
    }

    // MARK: Privacy

    static var feedPrivacyShareWithAllContacts: String {
        return NSLocalizedString("feed.privacy.descr.all",
                                 value: "Share with all my contacts",
                                 comment: "Describes what 'All Contacts' feed privacy setting means.")
    }

    static var feedPrivacyShareWithContactsExcept: String {
        return NSLocalizedString("feed.privacy.descr.except",
                                 value: "Share with my contacts except people I select",
                                 comment: "Describes what 'All Contacts' feed privacy setting means.")
    }

    static var feedPrivacyShareWithSelected: String {
        return NSLocalizedString("feed.privacy.descr.only",
                                 value: "Only share with selected contacts",
                                 comment: "Describes what 'All Contacts' feed privacy setting means.")
    }

    // MARK: Screen Titles

    static var titlePrivacy: String {
        NSLocalizedString("title.privacy", value: "Privacy", comment: "Row in Settings screen")
    }

    static var titleEditFavorites: String {
        NSLocalizedString("title.edit.favorites", value: "Edit your Favorites list", comment: "Button to edit favorites list")
    }

    static var favoritesTitle: String {
        NSLocalizedString("feed.privacy.list.only.title", value: "Favorites", comment: "Title of the alert shown to user indicating their post is only shown to their favorites audience")
    }

    static var favoritesDescriptionOwn: String {
        NSLocalizedString("feed.privacy.list.own.only.description", value: "Only the people on your Favorites list can view this post.", comment: "Description of the alert shown to user indicating their post is only shown to their favorites audience")
    }

    static var favoritesDescriptionNotOwn: String {
        NSLocalizedString("feed.privacy.list.notOwn.only.description", value: "Only the people on %@'s Favorites list can view this post.", comment: "Description of the alert shown to user indicating the author's post is only shown to the author's favorites audience")
    }

    static var favoritesTitleAlt: String {
        return NSLocalizedString("feed.privacy.list.only.details", value: "Who will see this post", comment: "Header for the favorites list when editing contacts to share with.")
    }
 
    static var setFavorites: String {
        NSLocalizedString("feed.privacy.list.set.favorites", value: "Set Favorites", comment: "Button to edit favorites")
    }

    static var setFavoritesDescription: String {
        NSLocalizedString("feed.privacy.list.set.favorites.description", value: "Now you can create a list of your favorite contacts, and share your HalloApp posts with them.", comment: "Description of the new Favorites functionality.")
    }

    static var dismissEditFavorites: String {
        NSLocalizedString("feed.privacy.list.dismiss.edit.favorites", value: "Not Now", comment: "Button to dismiss edit favorites modal")
    }

    // MARK: - Group Expiry

    static var chatGroupExpiryOption24Hours: String {
        NSLocalizedString("chat.group.expiry.option.24hours", value: "24 Hours", comment: "Group content expiry time limit option")
    }

    static var chatGroupExpiryOption30Days: String {
        NSLocalizedString("chat.group.expiry.option.30days", value: "30 Days", comment: "Group content expiry time limit option")
    }

    static var chatGroupExpiryOptionNever: String {
        NSLocalizedString("chat.group.expiry.option.never", value: "Never", comment: "Group content expiry time limit option")
    }
}
