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
    var canSaveMedia: Bool {
        return groupID != nil
    }

    var externalShareDescription: String {
        let media = media ?? []
        if media.isEmpty {
            return Localizations.externalShareTextPostDescription
        } else if media.count == 1, media.first?.type == .audio {
            return Localizations.externalShareAudioPostDescription
        } else {
            return Localizations.externalShareMediaPostDescription
        }
    }
}
