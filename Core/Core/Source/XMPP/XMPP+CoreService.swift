//
//  XMPP+CoreService.swift
//  Core
//
//  Created by Garrett on 8/20/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation

public enum XMPPControllerError: Error {
    case responseMissingKeyCount
    case responseMissingKeys
}

extension XMPPController: CoreService {
    public func sendChatMessage(_ message: ChatMessageProtocol, encryption: EncryptOperation?, completion: @escaping ServiceRequestCompletion<Void>) {
        if let encryption = encryption {
            message.encryptXMPPElement(encryption) { encryptedMessage in
                self.xmppStream.send(encryptedMessage)
                completion(.success(()))
            }
        } else {
            xmppStream.send(message.xmppElement)
            completion(.success(()))
        }
    }

    public func requestMediaUploadURL(size: Int, completion: @escaping ServiceRequestCompletion<MediaURLInfo>) {
        let request = XMPPMediaUploadURLRequest(size: size, completion: completion)
        // Wait until connected to request URLs. User meanwhile can cancel posting.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.enqueue(request: request)
        }
    }

    public func requestWhisperKeyBundle(userID: UserID, completion: @escaping ServiceRequestCompletion<WhisperKeyBundle>) {
        enqueue(request: XMPPWhisperGetBundleRequest(targetUserId: userID) { (iq, error) in
            if let iq = iq, let keys = WhisperKeyBundle(itemElement: iq) {
                completion(.success(keys))
            } else {
                completion(.failure(error ?? XMPPControllerError.responseMissingKeys))
            }
        })
    }

    public func publishPost(_ post: FeedPostProtocol, feed: Feed, completion: @escaping ServiceRequestCompletion<Date?>) {
        let request = XMPPPostItemRequest(feedPost: post, feed: feed, completion: completion)
        // Request will fail immediately if we're not connected, therefore delay sending until connected.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.enqueue(request: request)
        }
    }

    public func publishComment(_ comment: FeedCommentProtocol, groupId: GroupID?, completion: @escaping ServiceRequestCompletion<Date?>) {
        let request = XMPPPostItemRequest(feedPostComment: comment, groupId: groupId, completion: completion)
        // Request will fail immediately if we're not connected, therefore delay sending until connected.
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.enqueue(request: request)
        }
    }

    public func log(events: [CountableEvent], completion: @escaping ServiceRequestCompletion<Void>) {
        let request = XMPPLogEventsRequest(events: events, completion: completion)
        execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.enqueue(request: request)
        }
    }
}
