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

protocol HalloService: CoreService {

    // MARK: Delegates
    var chatDelegate: HalloChatDelegate? { get set }
    var feedDelegate: HalloFeedDelegate? { get set }
    var keyDelegate: HalloKeyDelegate? { get set }

    // MARK: Profile
    func sendCurrentUserNameIfPossible()
    func sendCurrentAvatarIfPossible()

    // MARK: Feed requests
    func retractFeedItem(_ feedItem: FeedItemProtocol, completion: @escaping ServiceRequestCompletion<Void>)
    func sharePosts(postIds: [FeedPostID], with userId: UserID, completion: @escaping ServiceRequestCompletion<Void>)

    // MARK: Key requests
    func uploadWhisperKeyBundle(_ bundle: WhisperKeyBundle, completion: @escaping ServiceRequestCompletion<Void>)
    func requestAddOneTimeKeys(_ bundle: WhisperKeyBundle, completion: @escaping ServiceRequestCompletion<Void>)
    func requestCountOfOneTimeKeys(completion: @escaping ServiceRequestCompletion<Int32>)
    func requestWhisperKeyBundle(userID: UserID, completion: @escaping ServiceRequestCompletion<WhisperKeyBundle>)

    // MARK: Receipts
    func sendReceipt(itemID: String, thread: HalloReceipt.Thread, type: HalloReceipt.`Type`, fromUserID: UserID, toUserID: UserID)

    // MARK: Chat
    var didGetNewChatMessage: PassthroughSubject<ChatMessageProtocol, Never> { get }
    var didGetChatAck: PassthroughSubject<ChatAck, Never> { get }
    var didGetPresence: PassthroughSubject<ChatPresenceInfo, Never> { get }
    func sendPresenceIfPossible(_ presenceType: PresenceType)

    // MARK: Groups
    func sendGroupChatMessage(_ message: HalloGroupChatMessage, completion: @escaping ServiceRequestCompletion<Void>)
    func createGroup(name: String, members: [UserID], completion: @escaping ServiceRequestCompletion<Void>)
    func leaveGroup(groupID: GroupID, completion: @escaping ServiceRequestCompletion<Void>)
    func getGroupInfo(groupID: GroupID, completion: @escaping ServiceRequestCompletion<HalloGroup>)
    func modifyGroup(groupID: GroupID, with members: [UserID], groupAction: ChatGroupAction,
                     action: ChatGroupMemberAction, completion: @escaping ServiceRequestCompletion<Void>)

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
    func setAPNSToken(_ token: String?)
    func sendCurrentAPNSTokenIfPossible()
    func updateNotificationSettings(_ settings: [NotificationSettings.ConfigKey: Bool], completion: @escaping ServiceRequestCompletion<Void>)

    // MARK: Client version
    func checkVersionExpiration(completion: @escaping ServiceRequestCompletion<TimeInterval>)
    func getServerProperties(completion: @escaping ServiceRequestCompletion<ServerPropertiesResponse>)
}

protocol HalloFeedDelegate: AnyObject {
    func halloService(_ halloService: HalloService, didReceiveFeedItems items: [FeedElement], ack: (() -> Void)?)
    func halloService(_ halloService: HalloService, didReceiveFeedRetracts items: [FeedRetract], ack: (() -> Void)?)
    func halloService(_ halloService: HalloService, didReceiveFeedReceipt receipt: HalloReceipt, ack: (() -> Void)?)
    func halloService(_ halloService: HalloService, didSendFeedReceipt receipt: HalloReceipt)
}

protocol HalloChatDelegate: AnyObject {
    func halloService(_ halloService: HalloService, didReceiveMessageReceipt receipt: HalloReceipt, ack: (() -> Void)?)
    func halloService(_ halloService: HalloService, didSendMessageReceipt receipt: HalloReceipt)
    func halloService(_ halloService: HalloService, didReceiveGroupChatMessage message: HalloGroupChatMessage)
    func halloService(_ halloService: HalloService, didReceiveGroupMessage group: HalloGroup)
}

protocol HalloKeyDelegate: AnyObject {
    func halloService(_ halloService: HalloService, didReceiveWhisperMessage message: WhisperMessage)
}
