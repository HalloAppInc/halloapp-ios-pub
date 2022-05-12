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
        return groupID != nil
    }

    var externalShareDescription: String {
        if let mentionText = MainAppContext.shared.contactStore.textWithMentions(rawText, mentions: orderedMentions)?.string,
           !mentionText.isEmpty {
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
