//
//  HalloService.swift
//  Core
//
//  Created by Garrett on 8/17/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CoreCommon
import Combine
import Foundation

public enum Feed {
    case personal(FeedAudience)
    case group(GroupID)
}

public typealias AvatarInfo = (userID: UserID, avatarID: AvatarID)

/// Core aspects of the service available in extensions
public protocol CoreService: CoreServiceCommon {

    // WhisperKeys
    var didGetNewWhisperMessage: PassthroughSubject<WhisperMessage, Never> { get }

    // MARK: Avatar
    func updateAvatar(_ avatarData: AvatarData?, for userID: UserID, completion: @escaping ServiceRequestCompletion<AvatarID?>)

    // MARK: Feed
    func requestMediaUploadURL(size: Int, downloadURL: URL?, completion: @escaping ServiceRequestCompletion<MediaURLInfo?>)
    func publishPost(_ post: PostData, feed: Feed, completion: @escaping ServiceRequestCompletion<Date>)
    func publishComment(_ comment: CommentData, groupId: GroupID?, completion: @escaping ServiceRequestCompletion<Date>)
    func resendPost(_ post: PostData, feed: Feed, rerequestCount: Int32, to toUserID: UserID, completion: @escaping ServiceRequestCompletion<Void>)
    func resendComment(_ comment: CommentData, groupId: GroupID?, rerequestCount: Int32, to toUserID: UserID, completion: @escaping ServiceRequestCompletion<Void>)
    func retractPost(_ id: FeedPostID, in groupID: GroupID, to toUserID: UserID, completion: @escaping ServiceRequestCompletion<Void>)
    func retractComment(_ id: FeedPostCommentID, postID: FeedPostID, in groupID: GroupID, to toUserID: UserID, completion: @escaping ServiceRequestCompletion<Void>)
    func decryptGroupFeedPayload(for item: Server_GroupFeedItem, in groupID: GroupID, completion: @escaping (FeedContent?, GroupDecryptionFailure?) -> Void)
    func processGroupFeedRetract(for item: Server_GroupFeedItem, in groupID: GroupID, completion: @escaping () -> Void)
    func rerequestGroupFeedItemIfNecessary(id contentID: String, groupID: GroupID, contentType: GroupFeedRerequestContentType, failure: GroupDecryptionFailure, completion: @escaping ServiceRequestCompletion<Void>)
    func resendHistoryResendPayload(id historyResendID: String, groupID: GroupID, payload: Data, to toUserID: UserID, rerequestCount: Int32, completion: @escaping ServiceRequestCompletion<Void>)
    func sendGroupFeedHistoryPayload(id groupFeedHistoryID: String, groupID: GroupID, payload: Data, to toUserID: UserID, rerequestCount: Int32, completion: @escaping ServiceRequestCompletion<Void>)

    // MARK: Keys
    func getGroupMemberIdentityKeys(groupID: GroupID, completion: @escaping ServiceRequestCompletion<Server_GroupStanza>)

    // MARK: Chat
    func sendPresenceIfPossible(_ presenceType: PresenceType)
    func sendChatMessage(_ message: ChatMessageProtocol, completion: @escaping ServiceRequestCompletion<Void>)
    func sendAck(messageId: String, completion: @escaping ServiceRequestCompletion<Void>)
    func decryptChat(_ serverChat: Server_ChatStanza, from fromUserID: UserID, completion: @escaping (ChatContent?, ChatContext?, DecryptionFailure?) -> Void)
    func rerequestMessage(_ messageID: String, senderID: UserID, failedEphemeralKey: Data?, contentType: Server_Rerequest.ContentType, completion: @escaping ServiceRequestCompletion<Void>)
    func retractChatMessage(messageID: String, toUserID: UserID, messageToRetractID: String, completion: @escaping ServiceRequestCompletion<Void>)

    // MARK: ContentMissing - Handle rerequests
    func sendContentMissing(id contentID: String, type contentType: Server_ContentMissing.ContentType, to toUserID: UserID, completion: @escaping ServiceRequestCompletion<Void>)

    // MARK: Event Logging
    func log(countableEvents: [CountableEvent], discreteEvents: [DiscreteEvent], completion: @escaping ServiceRequestCompletion<Void>)

    // MARK: Delegates
    var avatarDelegate: ServiceAvatarDelegate? { get set }
}

public protocol ServiceAvatarDelegate: AnyObject {
    func service(_ service: CoreService, didReceiveAvatarInfo avatarInfo: AvatarInfo)
}
