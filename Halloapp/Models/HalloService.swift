//
//  HalloService.swift
//  HalloApp
//
//  Created by Garrett on 8/20/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Combine
import Core
import CoreCommon
import UIKit

public struct HalloServiceFeedPayload {
    let content: FeedContent
    let group: HalloGroup?
    let isEligibleForNotification: Bool
}

protocol HalloService: CoreService {

    // MARK: Delegates
    var chatDelegate: HalloChatDelegate? { get set }
    var feedDelegate: HalloFeedDelegate? { get set }
    var callDelegate: HalloCallDelegate? { get set }
    var readyToHandleCallMessages: Bool { get set }

    // MARK: Profile
    func updateUsername(_ name: String)

    // MARK: Feed requests
    func retractPost(_ id: FeedPostID, in groupID: GroupID?, completion: @escaping ServiceRequestCompletion<Void>)
    func retractComment(id: FeedPostCommentID, postID: FeedPostID, in groupID: GroupID?, completion: @escaping ServiceRequestCompletion<Void>)
    func sharePosts(postIds: [FeedPostID], with userId: UserID, completion: @escaping ServiceRequestCompletion<Void>)
    func shareGroupHistory(items: Server_GroupFeedItems, with userId: UserID, completion: @escaping ServiceRequestCompletion<Void>)
    func uploadPostForExternalShare(encryptedBlob: Data,
                                    expiry: Date,
                                    ogTitle: String,
                                    ogDescription: String,
                                    ogThumbURL: URL?,
                                    ogThumbSize: CGSize?,
                                    completion: @escaping ServiceRequestCompletion<String>)
    func revokeExternalShareLink(blobID: String, completion: @escaping ServiceRequestCompletion<Void>)
    func externalSharePost(blobID: String, completion: @escaping ServiceRequestCompletion<Server_ExternalSharePostContainer>)

    // MARK: Receipts
    func sendReceipt(itemID: String, thread: HalloReceipt.Thread, type: HalloReceipt.`Type`, fromUserID: UserID, toUserID: UserID)

    // MARK: Chat
    var didGetNewChatMessage: PassthroughSubject<IncomingChatMessage, Never> { get }
    var didGetChatAck: PassthroughSubject<ChatAck, Never> { get }
    var didGetPresence: PassthroughSubject<ChatPresenceInfo, Never> { get }
    var didGetChatState: PassthroughSubject<ChatStateInfo, Never> { get }
    var didGetChatRetract: PassthroughSubject<ChatRetractInfo, Never> { get }
    func sendChatStateIfPossible(type: ChatType, id: String, state: ChatState)

    // MARK: Group Chat
    var didGetNewGroupChatMessage: PassthroughSubject<IncomingChatMessage, Never> { get }
    func sendGroupChatMessage(_ message: HalloGroupChatMessage)
    func retractGroupChatMessage(messageID: String, groupID: GroupID, messageToRetractID: String, completion: @escaping ServiceRequestCompletion<Void>)

    // MARK: Groups
    func createGroup(name: String,
                     expiryType: Server_ExpiryInfo.ExpiryType,
                     expiryTime: Int64,
                     groupType: GroupType,
                     members: [UserID],
                     completion: @escaping ServiceRequestCompletion<String>)
    func leaveGroup(groupID: GroupID, completion: @escaping ServiceRequestCompletion<Void>)
    func getGroupInviteLink(groupID: GroupID, completion: @escaping ServiceRequestCompletion<Server_GroupInviteLink>)
    func resetGroupInviteLink(groupID: GroupID, completion: @escaping ServiceRequestCompletion<Server_GroupInviteLink>)
    func getGroupsList(completion: @escaping ServiceRequestCompletion<HalloGroups>)
    func modifyGroup(groupID: GroupID, with members: [UserID], groupAction: ChatGroupAction,
                     action: ChatGroupMemberAction, completion: @escaping ServiceRequestCompletion<Void>)
    func changeGroupName(groupID: GroupID, name: String, completion: @escaping ServiceRequestCompletion<Void>)
    func changeGroupAvatar(groupID: GroupID, data: Data?, completion: @escaping ServiceRequestCompletion<String>)
    func changeGroupDescription(groupID: GroupID, description: String, completion: @escaping ServiceRequestCompletion<String>)
    func setGroupBackground(groupID: GroupID, background: Int32, completion: @escaping ServiceRequestCompletion<Void>)
    func changeGroupExpiry(groupID: GroupID,
                           expiryType: Server_ExpiryInfo.ExpiryType,
                           expirationTime: Int64,
                           completion: @escaping ServiceRequestCompletion<Void>)
    func exportDataStatus(isSetRequest: Bool, completion: @escaping ServiceRequestCompletion<Server_ExportData>)
    func requestAccountDeletion(phoneNumber: String, feedback: String?, completion: @escaping ServiceRequestCompletion<Void>)

    // MARK: Calls
    func getCallServers(id callID: CallID, for peerUserID: UserID, callType: CallType, completion: @escaping ServiceRequestCompletion<Server_GetCallServersResult>)
    func startCall(id callID: CallID, to peerUserID: UserID, callType: CallType, payload: Data, callCapabilities: Server_CallCapabilities, completion: @escaping ServiceRequestCompletion<Server_StartCallResult>)
    func iceRestartOfferCall(id callID: CallID, to peerUserID: UserID, payload: Data, iceIdx: Int32, completion: @escaping (Result<Void, RequestError>) -> Void)
    func answerCall(id callID: CallID, to peerUserID: UserID, answerPayload: Data, completion: @escaping (Result<Void, RequestError>) -> Void)
    func answerCall(id callID: CallID, to peerUserID: UserID, offerPayload: Data, completion: @escaping (Result<Void, RequestError>) -> Void)
    func holdCall(id callID: CallID, to peerUserID: UserID, hold: Bool, completion: @escaping (Result<Void, RequestError>) -> Void)
    func muteCall(id callID: CallID, to peerUserID: UserID, muted: Bool, mediaType: Server_MuteCall.MediaType, completion: @escaping (Result<Void, RequestError>) -> Void)
    func iceRestartAnswerCall(id callID: CallID, to peerUserID: UserID, payload: Data, iceIdx: Int32, completion: @escaping (Result<Void, RequestError>) -> Void)
    func sendCallRinging(id callID: CallID, to peerUserID: UserID)
    func sendCallRinging(id callID: CallID, to peerUserID: UserID, payload: Data, completion: @escaping (Result<Void, RequestError>) -> Void)
    func sendCallSdp(id callID: CallID, to peerUserID: UserID, payload: Data, completion: @escaping (Result<Void, RequestError>) -> Void)
    func endCall(id callID: CallID, to peerUserID: UserID, reason: EndCallReason)
    func sendIceCandidate(id callID: CallID, to peerUserID: UserID, iceCandidateInfo: IceCandidateInfo)
    
    @discardableResult
    func subscribeToPresenceIfPossible(to userID: UserID) -> Bool

    // MARK: Invites
    func requestInviteAllowance(completion: @escaping ServiceRequestCompletion<(Int, Date)>)
    func sendInvites(phoneNumbers: [ABContact.NormalizedPhoneNumber], completion: @escaping ServiceRequestCompletion<InviteResponse>)

    // MARK: Contacts
    func syncContacts<T: Sequence>(with contacts: T, type: ContactSyncRequestType, syncID: String, batchIndex: Int?, isLastBatch: Bool?,
                                   completion: @escaping ServiceRequestCompletion<[HalloContact]>) where T.Element == HalloContact

    // MARK: Privacy
    func updatePrivacyList(_ update: PrivacyListUpdateProtocol, completion: @escaping ServiceRequestCompletion<Void>)
    func getPrivacyLists(_ listTypes: [PrivacyListType], completion: @escaping ServiceRequestCompletion<([PrivacyListProtocol], PrivacyListType)>)

    // MARK: Push notifications
    var hasValidAPNSPushToken: Bool { get }
    func sendAPNSTokenIfNecessary(_ token: String?)
    func sendVOIPTokenIfNecessary(_ token: String?)
    func updateNotificationSettings(_ settings: [NotificationSettings.ConfigKey: Bool], completion: @escaping ServiceRequestCompletion<Void>)

    // MARK: Client version
    func getServerProperties(completion: @escaping ServiceRequestCompletion<ServerPropertiesResponse>)

    func mergeData(from sharedDataStore: SharedDataStore, completion: @escaping () -> ())
}

protocol HalloFeedDelegate: AnyObject {
    func halloService(_ halloService: HalloService, didReceiveFeedPayload payload: HalloServiceFeedPayload, ack: (() -> Void)?)
    func halloService(_ halloService: HalloService, didRerequestGroupFeedItem contentID: String, contentType: GroupFeedRerequestContentType, from userID: UserID, ack: (() -> Void)?)
    func halloService(_ halloService: HalloService, didRerequestHomeFeedItem contentID: String, contentType: HomeFeedRerequestContentType, from userID: UserID, ack: (() -> Void)?)
    func halloService(_ halloService: HalloService, didRerequestGroupFeedHistory contentID: String, from userID: UserID, ack: (() -> Void)?)
    func halloService(_ halloService: HalloService, didReceiveFeedReceipt receipt: HalloReceipt, ack: (() -> Void)?)
    func halloService(_ halloService: HalloService, didSendFeedReceipt receipt: HalloReceipt)
}

protocol HalloChatDelegate: AnyObject {
    func halloService(_ halloService: HalloService, didRerequestMessage messageID: String, from userID: UserID, ack: (() -> Void)?)
    func halloService(_ halloService: HalloService, didRerequestReaction reactionID: String, from userID: UserID, ack: (() -> Void)?)
    func halloService(_ halloService: HalloService, didReceiveMessageReceipt receipt: HalloReceipt, ack: (() -> Void)?)
    func halloService(_ halloService: HalloService, didSendMessageReceipt receipt: HalloReceipt)
    func halloService(_ halloService: HalloService, didReceiveGroupMessage group: HalloGroup)
    func halloService(_ halloService: HalloService, didReceiveHistoryResendPayload historyPayload: Clients_GroupHistoryPayload?, withGroupMessage group: HalloGroup)
    func halloService(_ halloService: HalloService, didReceiveHistoryResendPayload historyPayload: Clients_GroupHistoryPayload, for groupID: GroupID, from fromUserID: UserID)
}

protocol HalloCallDelegate: AnyObject {
    func halloService(_ halloService: HalloService, from peerUserID: UserID, didReceiveIncomingCallPush incomingCallPush: Server_IncomingCallPush)
    func halloService(_ halloService: HalloService, from peerUserID: UserID, didReceiveIncomingCall incomingCall: Server_IncomingCall, ack: (() -> ())?)
    func halloService(_ halloService: HalloService, from peerUserID: UserID, didReceiveAnswerCall answerCall: Server_AnswerCall)
    func halloService(_ halloService: HalloService, from peerUserID: UserID, didReceiveIceOffer iceOffer: Server_IceRestartOffer)
    func halloService(_ halloService: HalloService, from peerUserID: UserID, didReceiveIceAnswer iceAnswer: Server_IceRestartAnswer)
    func halloService(_ halloService: HalloService, from peerUserID: UserID, didReceiveCallRinging callRinging: Server_CallRinging)
    func halloService(_ halloService: HalloService, from peerUserID: UserID, didReceiveIceCandidate iceCandidate: Server_IceCandidate)
    func halloService(_ halloService: HalloService, from peerUserID: UserID, didReceiveEndCall endCall: Server_EndCall)
    func halloService(_ halloService: HalloService, from peerUserID: UserID, didReceiveHoldCall holdCall: Server_HoldCall)
    func halloService(_ halloService: HalloService, from peerUserID: UserID, didReceiveMuteCall muteCall: Server_MuteCall)
    func halloService(_ halloService: HalloService, from peerUserID: UserID, didReceiveCallSdp callSdp: Server_CallSdp)
}
