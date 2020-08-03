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

/// Contains text with "@" placeholders that can be replaced with the names of mentioned users.
public struct MentionText {
    var collapsedText: String
    var mentions: [Int: UserID]

    init(collapsedText: String, mentions: [Int: UserID]) {
        self.collapsedText = collapsedText
        self.mentions = mentions
    }

    init(expandedText: String, mentionRanges: [NSRange: UserID]) {
        var outputText = expandedText as NSString
        mentions = [Int: UserID]()
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
    func trimmed() -> MentionText {
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
}

public final class Mentions {
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
