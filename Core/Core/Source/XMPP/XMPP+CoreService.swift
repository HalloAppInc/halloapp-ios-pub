//
//  XMPP+CoreService.swift
//  Core
//
//  Created by Garrett on 8/20/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation

extension XMPPController: CoreService {
    public func sendChatMessage(_ message: ChatMessageProtocol, encryption: EncryptOperation?) {
        if let encryption = encryption {
            message.encryptXMPPElement(encryption) { encryptedMessage in
                self.xmppStream.send(encryptedMessage)
            }
        } else {
            xmppStream.send(message.xmppElement)
        }
    }

    public func requestMediaUploadURL(size: Int, completion: @escaping ServiceRequestCompletion<MediaURL>) {
        let request = XMPPMediaUploadURLRequest(completion: completion)
        // Wait until connected to request URLs. User meanwhile can cancel posting.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.enqueue(request: request)
        }
    }

    public func publishPost(_ post: FeedPostProtocol, audience: FeedAudience?, completion: @escaping ServiceRequestCompletion<Date?>) {
        let request: XMPPRequest
        if let audience = audience, ServerProperties.isInternalUser {
            request = XMPPPostItemRequest(feedPost: post, audience: audience, completion: completion)
        } else {
            request = XMPPPostItemRequestOld(feedItem: post, feedOwnerId: post.userId, completion: completion)
        }
        // Request will fail immediately if we're not connected, therefore delay sending until connected.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.enqueue(request: request)
        }
    }

    public func publishComment(_ comment: FeedCommentProtocol, feedOwnerID: UserID, completion: @escaping ServiceRequestCompletion<Date?>) {
        let request: XMPPRequest
        if ServerProperties.isInternalUser {
            request = XMPPPostItemRequest(feedPostComment: comment, completion: completion)
        } else {
            request = XMPPPostItemRequestOld(feedItem: comment, feedOwnerId: feedOwnerID, completion: completion)
        }
        // Request will fail immediately if we're not connected, therefore delay sending until connected.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.enqueue(request: request)
        }
    }
}
