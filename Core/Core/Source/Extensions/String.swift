//
//  String.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 3/9/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CommonCrypto
import CryptoKit
import Foundation
import NaturalLanguage

extension String {
    /**
     Generate searchable tokens from the string.

     - returns:
     An array of words contained in receiver, converted to lower case.

     Example: "Michael Donohue" would produce ["michael" , "donohue"]
     */
    public func searchTokens() -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = self
        var result: [String] = []
        tokenizer.enumerateTokens(in: self.startIndex..<self.endIndex) { tokenRange, _ in
            result.append(String(self[tokenRange]).localizedLowercase)
            return true
        }
        return result
    }

    /**
     Remove common non-digits from a phone number, but keeping '+'.

     - returns:
     Phone number with non-digits removed.
     */
    public func unformattedPhoneNumber() -> String {
        let mutable = NSMutableString(string: self)
        let stringsToRemove = [" ", "\u{00A0}", "(", ")", "-", "\u{2011}", "#", ".", "\u{202A}", "\u{202C}"]
        for string in stringsToRemove {
            mutable.replaceOccurrences(of: string, with: "", options: .literal, range: NSRange(location: 0, length: mutable.length))
        }
        return String(mutable)
    }

    public func sha256() -> Data? {
        guard let data = self.data(using: .utf8) else { return nil }
        return SHA256.hash(data: data).data
    }

    public func strippingNonDigits() -> String {
        return String(self.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) })
    }

    public var fullExtent: NSRange { NSRange(location: 0, length: count) }
}
