//
//  Mentions.swift
//  Core
//
//  Created by Garrett on 9/9/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation
import CoreCommon
import CocoaLumberjackSwift
import CoreData

// TODO: Add pushname and/or merge this with `MentionedUser`
/// Struct representing user that can be mentioned in a post or comment
public struct MentionableUser: Hashable {
    public init(userID: UserID, fullName: String) {
        self.userID = userID
        self.fullName = fullName
    }

    public var userID: UserID

    /// Name to be displayed in text and picker UI
    public var fullName: String
}

public final class Mentions {
    public static func mentionableUsersForNewPost(privacyListType: PrivacyListType, in context: NSManagedObjectContext) -> [MentionableUser] {
        let allContactIDs = (UserProfile.users(in: privacyListType, in: context) ?? [])
            .reduce(into: Set<UserID>()) {
                $0.insert($1.id)
            }

        return UserProfile.names(from: allContactIDs, in: AppContext.shared.mainDataStore.viewContext)
            .map { MentionableUser(userID: $0.key, fullName: $0.value) }
            .sorted { m1, m2 in m1.fullName < m2.fullName }
    }

    public static func isPotentialMatch(fullName: String, input: String) -> Bool {
        fullName.components(separatedBy: .whitespacesAndNewlines).contains {
            $0.lowercased().hasPrefix(input.lowercased())
        }
    }
}

/// Handles editing text with expanded mentions
public struct MentionInput: Codable{

    public init(text: String, mentions: MentionRangeMap, selectedRange: NSRange) {
        self.text = text
        self.mentions = mentions
        self.selectedRange = selectedRange
    }

    public var text: String
    public var mentions: MentionRangeMap
    public var selectedRange: NSRange

    public func impactedMentionRanges(in editRange: NSRange) -> [NSRange] {
        return mentions.keys.filter { editRange.overlaps($0) }
    }

    public mutating func addMention(name: String, userID: UserID, in range: NSRange) {
        let mentionString = "@\(name)"
        let mentionRange = NSRange(location: range.location, length: mentionString.utf16Extent.length)

        let replacementString = mentionString + " "

        changeText(in: range, to: replacementString)
        // Set pushname to `nil` for outgoing mentions (push names will be filled in later)
        mentions[mentionRange] = MentionedUser(userID: userID, pushName: nil)
    }

    public mutating func changeText(in range: NSRange, to replacementText: String) {
        guard let stringRange = Range(range, in: text) else {
            return
        }

        // Update mentions
        let impactedMentions = impactedMentionRanges(in: range)
        mentions = mentions.filter { !impactedMentions.contains($0.key) }
        applyOffsetToMentions(replacementText.utf16Extent.length - range.length, from: range.location)

        // Update text
        text = text.replacingCharacters(in: stringRange, with: replacementText)

        // Update selection (move cursor to end of range)
        let newCursorPosition = range.location + replacementText.utf16Extent.length
        selectedRange = NSRange(location: newCursorPosition, length: 0)
    }

    public func rangeOfMentionCandidateAtCurrentPosition() -> Range<String.Index>? {
        guard selectedRange.length == 0 else { return nil }
        guard let cursorPosition = Range(selectedRange, in: text)?.lowerBound else { return nil }

        // Range from most recent @ to current cursor position (not including any whitespace characters)
        let possibleCharacterRange: Range<String.Index>? = {
            var currentPosition = cursorPosition
            while currentPosition > text.startIndex {
                currentPosition = text.index(before: currentPosition)
                if text[currentPosition] == "@" {
                    return currentPosition..<cursorPosition
                } else if text[currentPosition].isWhitespace {
                    return nil
                }
            }
            return nil
        }()

        guard let characterRange = possibleCharacterRange,
            impactedMentionRanges(in: NSRange(characterRange, in: text)).isEmpty else
        {
            // Return nil if no range is found or it overlaps existing mentions
            return nil
        }

        return characterRange
    }

    public mutating func applyOffsetToMentions(_ offset: Int, from location: Int) {
        // Shift mentions when we make edits earlier in the text
        mentions = Dictionary(uniqueKeysWithValues: mentions.map { (range, userID) in
            var newRange = range
            if range.location >= location {
                newRange.location += offset
            }
            return (newRange, userID)
        })
    }
}
