//
//  Locale.swift
//  HalloApp
//
//  Created by Garrett on 4/22/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation

extension Locale {
    var halloServiceLangID: String? {
        guard let languageCode = languageCode else {
            return nil
        }
        guard let regionCode = regionCode, ["en", "pt", "zh"].contains(languageCode) else {
            // Only append region code for specific languages (defined in push_language_id spec)
            return languageCode
        }
        return "\(languageCode)-\(regionCode)"
    }
}
