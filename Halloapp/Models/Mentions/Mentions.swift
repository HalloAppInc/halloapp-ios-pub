//
//  Mentions.swift
//  HalloApp
//
//  Created by Garrett on 7/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core

public struct MentionableUser: Hashable {
    var userID: UserID
    var fullName: String
}

public final class Mentions {
    public static func mentionableUsersForNewPost() -> [MentionableUser] {
        let allContactIDs = Set(MainAppContext.shared.contactStore.allRegisteredContactIDs())

        return MainAppContext.shared.contactStore.fullNames(forUserIds: allContactIDs)
            .map { MentionableUser(userID: $0.key, fullName: $0.value) }
            .sorted { m1, m2 in m1.fullName < m2.fullName }
    }

    public static func mentionableUsers(forPostID postID: FeedPostID) -> [MentionableUser] {
        guard let post = MainAppContext.shared.feedData.feedPost(with: postID) else { return [] }

        var contactSet = Set<UserID>()

        if post.userId != MainAppContext.shared.userData.userId {
            // Allow mentioning poster
            contactSet.insert(post.userId)
        } else {
            // Otherwise we can mention everyone in our friends since they should be able to see our post
            contactSet.formUnion(MainAppContext.shared.contactStore.allRegisteredContactIDs())
        }

        // Allow mentioning every mention from the post
        contactSet.formUnion(post.mentions?.map { $0.userID } ?? [])

        // Allow mentioning everyone who has commented on the post
        contactSet.formUnion(post.comments?.map { $0.userId } ?? [])

        // Disallow self mentions
        contactSet.remove(MainAppContext.shared.userData.userId)

        let fullNames = MainAppContext.shared.contactStore.fullNames(forUserIds: contactSet)

        return fullNames
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
public struct MentionInput {

    init(text: String, mentions: MentionRangeMap, selectedRange: NSRange) {
        self.text = text
        self.mentions = mentions
        self.selectedRange = selectedRange
    }

    var text: String
    var mentions: MentionRangeMap
    var selectedRange: NSRange

    public func impactedMentionRanges(in editRange: NSRange) -> [NSRange] {
        return mentions.keys.filter { editRange.overlaps($0) }
    }

    public mutating func addMention(name: String, userID: UserID, in range: NSRange) {
        let mentionString = "@\(name)"
        let mentionRange = NSRange(location: range.location, length: mentionString.count)

        let replacementString = mentionString + " "

        changeText(in: range, to: replacementString)
        mentions[mentionRange] = userID
    }

    public mutating func changeText(in range: NSRange, to replacementText: String) {
        guard let stringRange = Range(range, in: text) else {
            return
        }

        // Update mentions
        let impactedMentions = impactedMentionRanges(in: range)
        mentions = mentions.filter { !impactedMentions.contains($0.key) }
        applyOffsetToMentions(replacementText.count - range.length, from: range.location)

        // Update text
        text = text.replacingCharacters(in: stringRange, with: replacementText)

        // Update selection (move cursor to end of range)
        let newCursorPosition = range.location + replacementText.count
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

    private mutating func applyOffsetToMentions(_ offset: Int, from location: Int) {
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
