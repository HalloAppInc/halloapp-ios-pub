//
//  Proto+Mentions.swift
//  Core
//
//  Created by Garrett on 8/19/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation

public extension Clients_Container {
    func mentionPushName(for userID: UserID) -> String? {
        var mentions = [Clients_Mention]()
        if hasPost {
            mentions += post.mentions
        }
        if hasComment {
            mentions += comment.mentions
        }
        if hasChatMessage {
            mentions += chatMessage.mentions
        }
        
        return mentions.first(where: { $0.userID == userID })?.name
    }
}

public extension Clients_Post {
    var mentionText: MentionText {
        MentionText(collapsedText: text, mentions: mentionDictionary(from: mentions))
    }
}

public extension Clients_Comment {
    var mentionText: MentionText {
        MentionText(collapsedText: text, mentions: mentionDictionary(from: mentions))
    }
}

public extension Clients_ChatMessage {
    var mentionText: MentionText {
        MentionText(collapsedText: text, mentions: mentionDictionary(from: mentions))
    }
}

public extension Clients_Text {
    var mentionText: MentionText {
        MentionText(collapsedText: text, mentions: mentionDictionary(from: mentions))
    }
}

func mentionDictionary(from mentions: [Clients_Mention]) -> [Int: MentionedUser] {
    Dictionary(uniqueKeysWithValues: mentions.map {
        (Int($0.index), MentionedUser(userID: $0.userID, pushName: $0.name))
    })
}
