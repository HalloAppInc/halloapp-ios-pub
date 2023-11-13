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

/// Core aspects of the service available in extensions
public protocol CoreService: CoreServiceCommon {

    // WhisperKeys
    var didGetNewWhisperMessage: PassthroughSubject<WhisperMessage, Never> { get }

    // MARK: Feed
    func requestMediaUploadURL(type: Server_UploadMedia.TypeEnum, size: Int, downloadURL: URL?, completion: @escaping ServiceRequestCompletion<MediaURLInfo?>)
    func publishPost(_ post: PostData, feed: Feed, completion: @escaping ServiceRequestCompletion<Date>)
    func publishComment(_ comment: CommentData, groupId: GroupID?, completion: @escaping ServiceRequestCompletion<Date>)
    func resendPost(_ post: PostData, feed: Feed, rerequestCount: Int32, to toUserID: UserID, completion: @escaping ServiceRequestCompletion<Void>)
    func resendComment(_ comment: CommentData, groupId: GroupID?, rerequestCount: Int32, to toUserID: UserID, completion: @escaping ServiceRequestCompletion<Void>)
    func retractPost(_ id: FeedPostID, in groupID: GroupID?, to toUserID: UserID, completion: @escaping ServiceRequestCompletion<Void>)
    func retractComment(_ id: FeedPostCommentID, postID: FeedPostID, in groupID: GroupID?, to toUserID: UserID, completion: @escaping ServiceRequestCompletion<Void>)
    func decryptGroupFeedPayload(for item: Server_GroupFeedItem, in groupID: GroupID, completion: @escaping (FeedContent?, GroupDecryptionFailure?) -> Void)
    func processGroupFeedRetract(for item: Server_GroupFeedItem, in groupID: GroupID, completion: @escaping () -> Void)
    func rerequestGroupFeedItemIfNecessary(id contentID: String, groupID: GroupID, contentType: GroupFeedRerequestContentType, failure: GroupDecryptionFailure, completion: @escaping ServiceRequestCompletion<Void>)
    func resendHistoryResendPayload(id historyResendID: String, groupID: GroupID, payload: Data, to toUserID: UserID, rerequestCount: Int32, completion: @escaping ServiceRequestCompletion<Void>)
    func sendGroupFeedHistoryPayload(id groupFeedHistoryID: String, groupID: GroupID, payload: Data, to toUserID: UserID, rerequestCount: Int32, completion: @escaping ServiceRequestCompletion<Void>)
    func shareGroupHistory(items: Server_GroupFeedItems, with userId: UserID, completion: @escaping ServiceRequestCompletion<Void>)

    // MARK: Keys
    func getGroupMemberIdentityKeys(groupID: GroupID, completion: @escaping ServiceRequestCompletion<Server_GroupStanza>)
    func getAudienceIdentityKeys(members: [UserID], completion: @escaping ServiceRequestCompletion<Server_WhisperKeysCollection>)

    // MARK: Chat
    func sendPresenceIfPossible(_ presenceType: PresenceType)
    func sendChatMessage(_ message: ChatMessageProtocol, completion: @escaping ServiceRequestCompletion<Void>)
    func sendAck(messageId: String, completion: @escaping ServiceRequestCompletion<Void>)
    func decryptChat(_ serverChat: Server_ChatStanza, from fromUserID: UserID, completion: @escaping (ChatContent?, ChatContext?, DecryptionFailure?) -> Void)
    func rerequestMessage(_ messageID: String, senderID: UserID, failedEphemeralKey: Data?, contentType: Server_Rerequest.ContentType, completion: @escaping ServiceRequestCompletion<Void>)
    func retractChatMessage(messageID: String, toUserID: UserID, messageToRetractID: String, completion: @escaping ServiceRequestCompletion<Void>)

    // MARK: GroupChat
    func retractGroupChatMessage(messageID: String, groupID: GroupID, to toUserID: UserID, messageToRetractID: String, completion: @escaping ServiceRequestCompletion<Void>)
    func retractGroupChatMessage(messageID: String, groupID: GroupID, messageToRetractID: String, completion: @escaping ServiceRequestCompletion<Void>)
    func resendGroupChatMessage(_ message: ChatMessageProtocol, groupId: GroupID, to toUserID: UserID, rerequestCount: Int32, completion: @escaping ServiceRequestCompletion<Void>)

    // MARK: Groups
    func getGroupInfo(groupID: GroupID, completion: @escaping ServiceRequestCompletion<HalloGroup>)

    // MARK: Usernames
    func updateUsername(username: String, completion: @escaping ServiceRequestCompletion<Server_UsernameResponse>)
    func checkUsernameAvailability(username: String, completion: @escaping ServiceRequestCompletion<Server_UsernameResponse>)

    // MARK: Links
    func addProfileLink(type: Server_Link.TypeEnum, text: String, completion: @escaping ServiceRequestCompletion<Server_SetLinkResult>)
    func removeProfileLink(type: Server_Link.TypeEnum, text: String, completion: @escaping ServiceRequestCompletion<Server_SetLinkResult>)

    // MARK: UserProfiles
    func modifyFriendship(userID: UserID, action: Server_FriendshipRequest.Action, completion: @escaping ServiceRequestCompletion<Server_HalloappUserProfile>)
    func friendList(action: Server_FriendListRequest.Action,
                    cursor: String,
                    completion: @escaping ServiceRequestCompletion<(profiles: [Server_FriendProfile], cursor: String)>)

    // MARK: UserProfile lookup
    func userProfile(userID: UserID, completion: @escaping ServiceRequestCompletion<Server_HalloappUserProfile>)
    func userProfile(username: String, completion: @escaping ServiceRequestCompletion<Server_HalloappUserProfile>)

    // MARK: UserProfile search
    func searchUsernames(string: String, completion: @escaping ServiceRequestCompletion<[Server_HalloappUserProfile]>)

    // MARK: ContentMissing - Handle rerequests
    func sendContentMissing(id contentID: String, type contentType: Server_ContentMissing.ContentType, to toUserID: UserID, completion: @escaping ServiceRequestCompletion<Void>)

    // MARK: Event Logging
    func log(countableEvents: [CountableEvent], discreteEvents: [DiscreteEvent], completion: @escaping ServiceRequestCompletion<Void>)

    // MARK: Receipts
    func sendReceipt(itemID: String, thread: HalloReceipt.Thread, type: HalloReceipt.`Type`, fromUserID: UserID, toUserID: UserID, completion: @escaping ServiceRequestCompletion<Void>)
}
