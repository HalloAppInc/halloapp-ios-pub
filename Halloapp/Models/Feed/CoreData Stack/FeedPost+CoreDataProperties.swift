//
//  FeedPost+CoreDataProperties.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/7/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Core
import CoreCommon

extension FeedPost {

    private static let maxExternalShareDescriptionLength = 100

    var canSaveMedia: Bool {
        return groupID != nil || userId == MainAppContext.shared.userData.userId
    }

    var externalShareDescription: String {
        var mentionText: String?
        MainAppContext.shared.contactStore.performOnBackgroundContextAndWait { managedObjectContext in
            mentionText = MainAppContext.shared.contactStore.textWithMentions(rawText, mentions: orderedMentions, in: managedObjectContext)?.string
        }

        if let mentionText = mentionText, !mentionText.isEmpty {
            if mentionText.count > Self.maxExternalShareDescriptionLength {
                return "\(mentionText.prefix(Self.maxExternalShareDescriptionLength))…"
            } else {
                return mentionText
            }
        }

        let media = media ?? []
        if media.count == 1, media.first?.type == .audio {
            return Localizations.externalShareAudioPostDescription
        } else {
            return Localizations.externalShareMediaPostDescription
        }
    }
}
