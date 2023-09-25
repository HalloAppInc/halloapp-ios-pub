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
        return !fromExternalShare
    }

    var externalShareDescription: String {
        var mentionText: String?
        if let managedObjectContext {
            mentionText = UserProfile.text(with: orderedMentions, collapsedText: rawText, in: managedObjectContext)?.string
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
