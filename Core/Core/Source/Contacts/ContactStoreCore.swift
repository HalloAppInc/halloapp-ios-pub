//
//  ContactStoreCore.swift
//  Core
//
//  Created by Chris Leonavicius on 8/23/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import CoreCommon
import CoreData

open class ContactStoreCore: ContactStore {

    // MARK: Mentions

    /// Name appropriate for use in mention. Does not contain "@" prefix.
    public func mentionName(for userID: UserID, pushName: String?, in managedObjectContext: NSManagedObjectContext) -> String {
        if let name = mentionNameIfAvailable(for: userID, pushName: pushName, in: managedObjectContext) {
            return name
        }
        return Localizations.unknownContact
    }

    /// Returns an attributed string where mention placeholders have been replaced with contact names. User IDs are retrievable via the .userMention attribute.
    public func textWithMentions(_ collapsedText: String?, mentions: [FeedMentionProtocol], in managedObjectContext: NSManagedObjectContext) -> NSAttributedString? {
        guard let collapsedText = collapsedText else { return nil }

        let mentionText = MentionText(collapsedText: collapsedText, mentionArray: mentions)

        return mentionText.expandedText { userID in
            self.mentionName(for: userID, pushName: mentions.first(where: { userID == $0.userID })?.name, in: managedObjectContext)
        }
    }
}
