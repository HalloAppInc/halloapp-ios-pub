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

    init(mentionText: MentionText, linkPreviews: [LinkPreviewData]? = nil) {
        self.init()
        text = mentionText.collapsedText
        mentions = mentionText.mentions
            .map { (i, user) in
                var clientMention = Clients_Mention()
                clientMention.userID = user.userID
                clientMention.name = user.pushName ?? ""
                clientMention.index = Int32(i)
                return clientMention
            }
            .sorted { $0.index < $1.index }
        linkPreviews?.forEach { linkPreview in
            link.url = linkPreview.url.description
            link.title = linkPreview.title
            link.description_p = linkPreview.description
            
            linkPreview.previewImages.forEach { previewImage in
                if let downloadURL = previewImage.url?.absoluteString,
                      let encryptionKey = Data(base64Encoded: previewImage.key),
                      let cipherTextHash = Data(base64Encoded: previewImage.sha256)
                {
                    var res = Clients_EncryptedResource()
                    res.ciphertextHash = cipherTextHash
                    res.downloadURL = downloadURL
                    res.encryptionKey = encryptionKey
                    var img = Clients_Image()
                    img.img = res
                    img.width = Int32(previewImage.size.width)
                    img.height = Int32(previewImage.size.height)
                    link.preview = [img]
                }
            }
        }
    }
}

func mentionDictionary(from mentions: [Clients_Mention]) -> [Int: MentionedUser] {
    Dictionary(uniqueKeysWithValues: mentions.map {
        (Int($0.index), MentionedUser(userID: $0.userID, pushName: $0.name))
    })
}
