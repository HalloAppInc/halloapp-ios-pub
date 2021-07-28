//
//  String.swift
//  HalloApp
//
//  Created by Tony Jiang on 6/18/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import NaturalLanguage

extension String {
    var containsOnlyEmoji: Bool { !isEmpty && !contains { !$0.isEmoji } }
    
    func isRightToLeftLanguage() -> Bool {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(self)
        guard let language = recognizer.dominantLanguage else { return false }
        /* Arabic, Hebrew, Persian/Farsi, Urdu, Dhivehi/Maldivian, Kurdish */
        return ["ar", "he", "fa", "ur", "dv", "ku"].contains(language.rawValue)
    }
}
