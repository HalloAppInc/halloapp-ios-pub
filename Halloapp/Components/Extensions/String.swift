//
//  String.swift
//  HalloApp
//
//  Created by Tony Jiang on 6/18/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import NaturalLanguage
import UIKit

extension String {
    var containsOnlyEmoji: Bool {
        !isEmpty && !contains { !$0.isEmoji }
    }
}

// MARK: - finding the natural language characteristics of a string

extension String {
    private static let languageTagger = NLTagger(tagSchemes: [.language])
    /// Because `languageTagger` is not thread-safe.
    private static let languageLock = NSLock()
    
    private func dominantLanguage() -> NLLanguage? {
        Self.languageLock.lock()
        
        Self.languageTagger.string = self
        let language = Self.languageTagger.dominantLanguage
        Self.languageTagger.string = nil
        
        Self.languageLock.unlock()
        return language
    }
    
    /// The proper text alignment for the string, based on the string's natural language.
    ///
    /// Because user-created content could be in a different language than that of the device, and therefore
    /// could require different formatting, we use this property to correctly align user-generated text.
    ///
    /// - note: Please access this property from the main thread.
    var naturalAlignment: NSTextAlignment {
        guard let language = dominantLanguage() else {
            return .natural
        }
        
        switch NSParagraphStyle.defaultWritingDirection(forLanguage: language.rawValue) {
        case .leftToRight:
            return .left
        case .rightToLeft:
            return .right
        default:
            return .natural
        }
    }
    
    func isRightToLeftLanguage() -> Bool {
        guard let language = dominantLanguage() else {
            return false
        }
        
        /* Arabic, Hebrew, Persian/Farsi, Urdu, Dhivehi/Maldivian, Kurdish */
        return ["ar", "he", "fa", "ur", "dv", "ku"].contains(language.rawValue)
    }
}
