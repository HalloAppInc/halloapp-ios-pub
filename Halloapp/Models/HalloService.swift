//
//  HalloService.swift
//  HalloApp
//
//  Created by Garrett on 8/20/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Combine
import Core

public enum PresenceType: String {
    case available = "available"
    case away = "away"
}

public struct HalloServiceFeedPayload {
    enum Content {
        case newItems([FeedElement])
        case retracts([FeedRetract])
    }

    let content: Content
    let group: HalloGroup?
    let isEligibleForNotification: Bool
}

protocol HalloService: CoreService {

    // MARK: Delegates
    var chatDelegate: HalloChatDelegate? { get set }
    var feedDelegate: HalloFeedDelegate? { get set }
    var keyDelegate: HalloKeyDelegate? { get set }

    // MARK: Profile
    func sendCurrentUserNameIfPossible()
    func sendCurrentAvatarIfPossible()

    // MARK: Feed requests
    func retractPost(_ post: FeedPostProtocol, completion: @escaping ServiceRequestCompletion<Void>)
    func retractComment(_ comment: FeedCommentProtocol, completion: @escaping ServiceRequestCompletion<Void>)
    func sharePosts(postIds: [FeedPostID], with userId: UserID, completion: @escaping ServiceRequestCompletion<Void>)

    // MARK: Key requests
    func uploadWhisperKeyBundle(_ bundle: WhisperKeyBundle, completion: @escaping ServiceRequestCompletion<Void>)
    func requestAddOneTimeKeys(_ keys: [PreKey], completion: @escaping ServiceRequestCompletion<Void>)
    func requestCountOfOneTimeKeys(completion: @escaping ServiceRequestCompletion<Int32>)

    // MARK: Receipts
    func sendReceipt(itemID: String, thread: HalloReceipt.Thread, type: HalloReceipt.`Type`, fromUserID: UserID, toUserID: UserID)

    // MARK: Chat
    var didGetNewChatMessage: PassthroughSubject<IncomingChatMessage, Never> { get }
    var didGetChatAck: PassthroughSubject<ChatAck, Never> { get }
    var didGetPresence: PassthroughSubject<ChatPresenceInfo, Never> { get }
    var didGetChatState: PassthroughSubject<ChatStateInfo, Never> { get }
    var didGetChatRetract: PassthroughSubject<ChatRetractInfo, Never> { get }
    func retractChatMessage(messageID: String, toUserID: UserID, messageToRetractID: String)
    func sendPresenceIfPossible(_ presenceType: PresenceType)
    func sendChatStateIfPossible(type: ChatType, id: String, state: ChatState)

    // MARK: Groups
    func sendGroupChatMessage(_ message: HalloGroupChatMessage)
    func retractGroupChatMessage(messageID: String, groupID: GroupID, messageToRetractID: String)
    func createGroup(name: String, members: [UserID], completion: @escaping ServiceRequestCompletion<String>)
    func leaveGroup(groupID: GroupID, completion: @escaping ServiceRequestCompletion<Void>)
    func getGroupInfo(groupID: GroupID, completion: @escaping ServiceRequestCompletion<HalloGroup>)
    func getGroupInviteLink(groupID: GroupID, completion: @escaping ServiceRequestCompletion<Server_GroupInviteLink>)
    func resetGroupInviteLink(groupID: GroupID, completion: @escaping ServiceRequestCompletion<Server_GroupInviteLink>)
    func getGroupPreviewWithLink(inviteLink: String, completion: @escaping ServiceRequestCompletion<Server_GroupInviteLink>)
    func joinGroupWithLink(inviteLink: String, completion: @escaping ServiceRequestCompletion<Server_GroupInviteLink>)
    func getGroupsList(completion: @escaping ServiceRequestCompletion<HalloGroups>)
    func modifyGroup(groupID: GroupID, with members: [UserID], groupAction: ChatGroupAction,
                     action: ChatGroupMemberAction, completion: @escaping ServiceRequestCompletion<Void>)
    func changeGroupName(groupID: GroupID, name: String, completion: @escaping ServiceRequestCompletion<Void>)
    func changeGroupAvatar(groupID: GroupID, data: Data?, completion: @escaping ServiceRequestCompletion<String>)
    func setGroupBackground(groupID: GroupID, background: Int32, completion: @escaping ServiceRequestCompletion<Void>)
    
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
    func updateNotificationSettings(_ settings: [NotificationSettings.ConfigKey: Bool], completion: @escaping ServiceRequestCompletion<Void>)

    // MARK: Client version
    func getServerProperties(completion: @escaping ServiceRequestCompletion<ServerPropertiesResponse>)

    func mergeData(from sharedDataStore: SharedDataStore, completion: @escaping () -> ())
}

protocol HalloFeedDelegate: AnyObject {
    func halloService(_ halloService: HalloService, didReceiveFeedPayload payload: HalloServiceFeedPayload, ack: (() -> Void)?)
    func halloService(_ halloService: HalloService, didReceiveFeedReceipt receipt: HalloReceipt, ack: (() -> Void)?)
    func halloService(_ halloService: HalloService, didSendFeedReceipt receipt: HalloReceipt)
}

protocol HalloChatDelegate: AnyObject {
    func halloService(_ halloService: HalloService, didRerequestMessage messageID: String, from userID: UserID, ack: (() -> Void)?)
    func halloService(_ halloService: HalloService, didReceiveMessageReceipt receipt: HalloReceipt, ack: (() -> Void)?)
    func halloService(_ halloService: HalloService, didSendMessageReceipt receipt: HalloReceipt)
    func halloService(_ halloService: HalloService, didReceiveGroupMessage group: HalloGroup)
}

protocol HalloKeyDelegate: AnyObject {
    func halloService(_ halloService: HalloService, didReceiveWhisperMessage message: WhisperMessage)
}
