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
    // TODO: Add these back in once they're migrated to protocol
    //var chatDelegate: HalloChatDelegate? { get set }
    var feedDelegate: HalloFeedDelegate? { get set }
    var keyDelegate: HalloKeyDelegate? { get set }

    // MARK: Profile
    func sendCurrentUserNameIfPossible()
    func sendCurrentAvatarIfPossible()

    // MARK: Feed requests
    func retractFeedItem(_ feedItem: FeedItemProtocol, ownerID: UserID, completion: @escaping ServiceRequestCompletion<Void>)

    // MARK: Key requests
    func uploadWhisperKeyBundle(_ bundle: WhisperKeyBundle, completion: @escaping ServiceRequestCompletion<Void>)
    func requestAddOneTimeKeys(_ bundle: WhisperKeyBundle, completion: @escaping ServiceRequestCompletion<Void>)
    func requestCountOfOneTimeKeys(completion: @escaping ServiceRequestCompletion<Int32>)
    func requestWhisperKeyBundle(userID: UserID, completion: @escaping ServiceRequestCompletion<WhisperKeyBundle>)

    // MARK: Receipts
    func sendReceipt(itemID: String, thread: HalloReceipt.Thread, type: HalloReceipt.`Type`, fromUserID: UserID, toUserID: UserID)

    // MARK: Chat
    // TODO: Add these back in once we migrate chat to protocols
    //var didGetNewChatMessage: PassthroughSubject<ChatMessageProtocol, Never> { get }
    //var didGetChatAck: PassthroughSubject<ChatAck, Never> { get }
    //var didGetPresence: PassthroughSubject<ChatPresenceInfo, Never> { get }
    func sendPresenceIfPossible(_ presenceType: PresenceType)

    @discardableResult
    func subscribeToPresenceIfPossible(to userID: UserID) -> Bool

    // MARK: Invites
    func requestInviteAllowance(completion: @escaping ServiceRequestCompletion<(Int, Date)>)
    func sendInvites(phoneNumbers: [ABContact.NormalizedPhoneNumber], completion: @escaping ServiceRequestCompletion<InviteResponse>)

    // MARK: Contacts
    func syncContacts<T: Sequence>(with contacts: T, type: ContactSyncRequestType, syncID: String, batchIndex: Int?, isLastBatch: Bool?,
                                   completion: @escaping ServiceRequestCompletion<[HalloContact]>) where T.Element == HalloContact

    // MARK: Privacy
    func sendPrivacyList(_ privacyList: PrivacyList, completion: @escaping ServiceRequestCompletion<Void>)
    func getPrivacyLists(_ listTypes: [PrivacyListType], completion: @escaping ServiceRequestCompletion<([PrivacyListProtocol], PrivacyListType)>)

    // MARK: APNS
    var hasValidAPNSPushToken: Bool { get }
    func setAPNSToken(_ token: String?)
    func sendCurrentAPNSTokenIfPossible()

    // MARK: Client version
    func checkVersionExpiration(completion: @escaping ServiceRequestCompletion<TimeInterval>)
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
}

protocol HalloKeyDelegate: AnyObject {
    func halloService(_ halloService: HalloService, didReceiveWhisperMessage message: WhisperMessage)
}
