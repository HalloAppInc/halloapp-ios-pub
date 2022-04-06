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
import CoreData
import Foundation

extension FeedPost: ChatQuotedProtocol {

    public var quotedText: String? {
        return rawText
    }

    public var type: ChatQuoteType {
        return .feedpost
    }

    public var mediaList: [QuotedMedia] {
        if let media = media {
            return Array(media)
        } else {
            return []
        }
    }
}

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
