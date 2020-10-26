//
//  XMPP+HalloService.swift
//  HalloApp
//
//  Created by Garrett on 8/18/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import XMPPFramework

extension XMPPControllerMain: HalloService {
    public func retractFeedItem(_ feedItem: FeedItemProtocol, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: XMPPRetractItemRequest(feedItem: feedItem, completion: completion))
    }

    public func sharePosts(postIds: [FeedPostID], with userId: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: XMPPSharePostsRequest(feedPostIds: postIds, userId: userId, completion: completion))
    }

    public func uploadWhisperKeyBundle(_ bundle: WhisperKeyBundle, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: XMPPWhisperUploadRequest(keyBundle: bundle) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        })
    }

    public func requestAddOneTimeKeys(_ bundle: WhisperKeyBundle, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: XMPPWhisperAddOneTimeKeysRequest(whisperKeyBundle: bundle) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        })
    }

    public func requestCountOfOneTimeKeys(completion: @escaping ServiceRequestCompletion<Int32>) {
        enqueue(request: XMPPWhisperGetCountOfOneTimeKeysRequest() { (iq, error) in
            if let whisperKeys = iq?.element(forName: "whisper_keys"), let keyCount = whisperKeys.element(forName: "otp_key_count")?.stringValueAsInt() {
                completion(.success(keyCount))
            } else {
                completion(.failure(error ?? XMPPControllerError.responseMissingKeyCount))
            }
        })
    }

    public func sendReceipt(itemID: String, thread: HalloReceipt.Thread, type: HalloReceipt.`Type`, fromUserID: UserID, toUserID: UserID) {
        // todo: should timestamp always be nil? saw a comment about server adding timestamp...
        let receipt = XMPPReceipt(
            itemId: itemID,
            userId: fromUserID,
            type: type,
            timestamp: nil,
            thread: thread)
        sendSeenReceipt(receipt, to: toUserID)
    }
    
    func updatePrivacyList(_ update: PrivacyListUpdateProtocol, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: XMPPSendPrivacyListRequest(privacyList: update, completion: completion))
    }

    func getPrivacyLists(_ listTypes: [PrivacyListType], completion: @escaping ServiceRequestCompletion<([PrivacyListProtocol], PrivacyListType)>) {
        enqueue(request: XMPPGetPrivacyListsRequest(listTypes, completion: completion))
    }

    public func requestInviteAllowance(completion: @escaping ServiceRequestCompletion<(Int, Date)>) {
        enqueue(request: XMPPGetInviteAllowanceRequest(completion: completion))
    }

    func sendInvites(phoneNumbers: [ABContact.NormalizedPhoneNumber], completion: @escaping ServiceRequestCompletion<InviteResponse>) {
        enqueue(request: XMPPRegisterInvitesRequest(phoneNumbers: phoneNumbers, completion: completion))
    }

    func syncContacts<T>(with contacts: T, type: ContactSyncRequestType, syncID: String, batchIndex: Int?, isLastBatch: Bool?, completion: @escaping ServiceRequestCompletion<[HalloContact]>) where T : Sequence, T.Element == HalloContact {
        enqueue(request: XMPPContactSyncRequest(
            with: contacts,
            type: type,
            syncID: syncID,
            batchIndex: batchIndex,
            isLastBatch: isLastBatch,
            completion: completion))
    }

    func setAPNSToken(_ token: String?) {
        apnsToken = token
    }

    func updateNotificationSettings(_ settings: [NotificationSettings.ConfigKey : Bool], completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: XMPPSendPushConfigRequest(config: settings, completion: completion))
    }

    func sendPresenceIfPossible(_ presenceType: PresenceType) {
        guard isConnected else { return }
        DDLogInfo("ChatData/sendPresence \(presenceType.rawValue)")
        let xmppJID = XMPPJID(user: userData.userId, domain: "s.halloapp.net", resource: nil)
        let xmppPresence = XMPPPresence(type: presenceType.rawValue, to: xmppJID)
        xmppStream.send(xmppPresence)
    }

    func subscribeToPresenceIfPossible(to userID: UserID) -> Bool {
        guard isConnected else { return false }
        DDLogDebug("ChatData/subscribeToPresence [\(userID)]")
        let message = XMPPElement(name: "presence")
        message.addAttribute(withName: "to", stringValue: "\(userID)@s.halloapp.net")
        message.addAttribute(withName: "type", stringValue: "subscribe")
        xmppStream.send(message)
        return true
    }

    func sendChatStateIfPossible(type: ChatType, id: String, state: ChatState) {
        guard isConnected else { return }
        DDLogInfo("XMPP Service/sendChatStateIfPossible \(state.rawValue) in \(id)")
        let chatState = XMPPElement(name: "chat_state")
        chatState.addAttribute(withName: "to", stringValue: "s.halloapp.net")
        chatState.addAttribute(withName: "thread_type", stringValue: type == .oneToOne ? "chat" : "group_chat")
        chatState.addAttribute(withName: "thread_id", stringValue: id)
        chatState.addAttribute(withName: "type", stringValue: state.rawValue)
        xmppStream.send(chatState)
    }
    
    func checkVersionExpiration(completion: @escaping ServiceRequestCompletion<TimeInterval>) {
        enqueue(request: XMPPClientVersionRequest() { (iq, error) in
            guard let clientVersion = iq?.element(forName: "client_version"),
                let secondsLeft = clientVersion.element(forName: "seconds_left") else
            {
                completion(.failure(error ?? XMPPError.malformed))
                return
            }
            completion(.success(TimeInterval(secondsLeft.stringValueAsInt())))
        })
    }

    func getServerProperties(completion: @escaping ServiceRequestCompletion<ServerPropertiesResponse>) {
        enqueue(request: XMPPGetServerPropertiesRequest(completion: completion))
    }

    func sendGroupChatMessage(_ message: XMPPChatGroupMessage) {
        xmppStream.send(message.xmppElement)
    }

    func createGroup(name: String, members: [UserID], completion: @escaping ServiceRequestCompletion<String>) {
        enqueue(request: XMPPGroupCreateRequest(name: name, members: members) { (xml, error) in
            if let xml = xml, let group = xml.forName("group"), let groupID = group.attributeStringValue(forName: "gid") {
                completion(.success(groupID))
            } else {
                completion(.failure(error ?? XMPPError.malformed))
            }
        })
    }

    func leaveGroup(groupID: GroupID, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: XMPPGroupLeaveRequest(groupId: groupID) { (_, error) in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        })
    }

    func getGroupInfo(groupID: GroupID, completion: @escaping ServiceRequestCompletion<HalloGroup>) {
        enqueue(request: XMPPGroupGetInfoRequest(groupId: groupID) { (xml, error) in
            if let xml = xml, let groupEl = xml.element(forName: "group"), let group = XMPPGroup(itemElement: groupEl) {
                completion(.success(group))
            } else {
                completion(.failure(error ?? XMPPError.malformed))
            }
        })
    }
    
    func modifyGroup(groupID: GroupID, with members: [UserID], groupAction: ChatGroupAction,
                     action: ChatGroupMemberAction, completion: @escaping ServiceRequestCompletion<Void>)
    {
        enqueue(request: XMPPGroupModifyRequest(groupId: groupID, members: members, groupAction: groupAction, action: action) { (_, error) in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        })
    }
    
    func changeGroupName(groupID: GroupID, name: String, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: XMPPGroupChangeNameRequest(groupId: groupID, name: name) { (_, error) in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        })
    }
    
    func changeGroupAvatar(groupID: GroupID, data: Data, completion: @escaping ServiceRequestCompletion<String>) {
        enqueue(request: XMPPGroupChangeAvatarRequest(groupID: groupID, data: data) { (xml, error) in
            if let xml = xml, let group = xml.forName("group"), let avatarID = group.attributeStringValue(forName: "avatar"), avatarID != "" {
                completion(.success(avatarID))
            } else {
                completion(.failure(error ?? XMPPError.malformed))
            }
        })
    }
}
