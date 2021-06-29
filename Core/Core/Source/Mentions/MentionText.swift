//
//  MentionText.swift
//  Core
//
//  Created by Garrett on 8/19/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Foundation

public typealias MentionRangeMap = [NSRange: MentionedUser]

/// Struct representing user that was mentioned in a post or comment
public struct MentionedUser: Codable {
    public init(userID: UserID, pushName: String?) {
        self.userID = userID
        self.pushName = pushName
    }

    public var userID: UserID

    // TODO: Remove optional here once pushName is available in MentionableUser
    public var pushName: String?
}

/// Contains text with "@" placeholders that can be replaced with the names of mentioned users.
public struct MentionText: Codable {
    public var collapsedText: String
    public var mentions: [Int: MentionedUser]

    public init(collapsedText: String, mentions: [Int: MentionedUser]) {
        self.collapsedText = collapsedText
        self.mentions = mentions
    }

    public init(expandedText: String, mentionRanges: MentionRangeMap) {
        var outputText = expandedText as NSString
        mentions = [Int: MentionedUser]()
        var charactersToDrop = mentionRanges.keys.reduce(0) { sum, range in sum + range.length } - mentionRanges.count
        let reverseOrderedMentions = mentionRanges.sorted { $0.key.location > $1.key.location }
        for (range, user) in reverseOrderedMentions {
            outputText = outputText.replacingCharacters(in: range, with: "@") as NSString
            charactersToDrop -= (range.length - 1)

            // Input ranges are based on the expanded text, but output indices should be based on collapsed text.
            // The offset between them is the number of characters that will be removed from earlier mentions.
            mentions[range.location - charactersToDrop] = user
        }
        collapsedText = outputText as String
    }

    /// Returns a copy with leading and trailing whitespace removed, adjusting mention indices accordingly
    public func trimmed() -> MentionText {
        var trimStart = 0
        while trimStart < collapsedText.count && collapsedText.characterAtOffset(trimStart).isWhitespace {
            trimStart += 1
        }
        var trimEnd = 0
        while trimEnd < (collapsedText.count - trimStart) && collapsedText.characterAtOffset(collapsedText.count - 1 - trimEnd).isWhitespace {
            trimEnd += 1
        }

        let trimmedText = String(collapsedText.dropFirst(trimStart).dropLast(trimEnd))
        let offsetMentions = Dictionary(uniqueKeysWithValues: mentions.map { (index, userID) in
            (index - trimStart, userID)
        })

        return MentionText(collapsedText: trimmedText, mentions: offsetMentions)
    }

    /// Returns an attributed string where mention placeholders have been replaced with provided names. User IDs are retrievable via the .userMention attribute.
    public func expandedText(nameProvider: (UserID) -> String) -> NSAttributedString {
        return expandedTextAndMentions(nameProvider: nameProvider).text
    }
    
    /// - Parameter nameProvider: This closure returns the user's name given an ID. User IDs are retrievable via the .userMention attribute.
    /// - Returns: A tuple including an attributed string where mention placeholders have been replaced with provided names and a map of NSRanges to the user being mentioned
    public func expandedTextAndMentions(nameProvider: (UserID) -> String) -> (text: NSAttributedString, mentions: MentionRangeMap) {
        let mutableString = NSMutableAttributedString(string: collapsedText)
        var mentionsMap: MentionRangeMap = [:]
        // NB: We replace mention placeholders with usernames in reverse order so we don't change indices
        let reverseOrderedMentions = mentions.sorted { $0.key > $1.key }
        for (index, user) in reverseOrderedMentions {
            guard index < mutableString.length else {
                DDLogError("MentionText/expandedText/error invalid index \(index) for \(mutableString.length) length string")
                continue
            }

            let replacementString = NSAttributedString(
                string: "@\(nameProvider(user.userID))",
                attributes: [NSAttributedString.Key.userMention: user.userID])

            mutableString.replaceCharacters(
                in: NSRange(location: index, length: 1),
                with: replacementString)
            
            mentionsMap[NSRange(location: index, length: replacementString.length)] = user
        }
        
        return (mutableString, mentionsMap)
    }
}
