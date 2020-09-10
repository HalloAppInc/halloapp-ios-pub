//
//  ProtoService.swift
//  HalloApp
//
//  Created by Garrett on 8/27/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import XMPPFramework

fileprivate let userDefaultsKeyForAPNSToken = "apnsPushToken"
fileprivate let userDefaultsKeyForNameSync = "xmpp.name-sent"

enum ProtoServiceError: Error {
    case unimplemented
    case unexpectedResponseFormat
}

final class ProtoService: ProtoServiceCore {

    public required init(userData: UserData) {
        super.init(userData: userData)

        self.cancellableSet.insert(
            userData.didLogIn.sink {
                DDLogInfo("xmpp/userdata/didLogIn")
                self.stream.myJID = self.userData.userJID
                self.connect()
            })
        self.cancellableSet.insert(
            userData.didLogOff.sink {
                DDLogInfo("xmpp/userdata/didLogOff")
                self.stream.disconnect() // this is only necessary when manually logging out from a developer menu.
                self.stream.myJID = nil
            })
    }

    private var cancellableSet = Set<AnyCancellable>()

    weak var chatDelegate: HalloChatDelegate?
    weak var feedDelegate: HalloFeedDelegate?
    weak var keyDelegate: HalloKeyDelegate?

    let didGetNewChatMessage = PassthroughSubject<ChatMessageProtocol, Never>()
    let didGetChatAck = PassthroughSubject<ChatAck, Never>()
    let didGetPresence = PassthroughSubject<ChatPresenceInfo, Never>()

    // MARK: Receipts

    typealias ReceiptData = (HalloReceipt, UserID)
    private var sentReceipts: [ String : HalloReceipt ] = [:] // Key is message's id - it would be the same as "id" in ack.
    private var unackedReceipts: [ String : ReceiptData ] = [:]

    // MARK: User Name

    private func resendNameIfNecessary() {
        guard !UserDefaults.standard.bool(forKey: userDefaultsKeyForNameSync) else { return }
        guard !userData.name.isEmpty else { return }

        enqueue(request: ProtoSendNameRequest(name: userData.name) { result in
            if case .success = result {
                UserDefaults.standard.set(true, forKey: userDefaultsKeyForNameSync)
            }
        })
    }

    // MARK: Avatar

    private func resendAvatarIfNecessary() {
        guard UserDefaults.standard.bool(forKey: AvatarStore.Keys.userDefaultsUpload) else { return }

        let userAvatar = MainAppContext.shared.avatarStore.userAvatar(forUserId: self.userData.userId)
        guard userAvatar.isEmpty || userAvatar.data != nil else {
            DDLogError("ProtoService/resendAvatarIfNecessary/upload/error avatar data is not ready")
            return
        }

        let logAction = userAvatar.isEmpty ? "removed" : "uploaded"
        enqueue(request: ProtoUpdateAvatarRequest(data: userAvatar.data) { result in
            switch result {
            case .success(let avatarID):
                DDLogInfo("ProtoService/resendAvatarIfNecessary avatar has been \(logAction)")
                UserDefaults.standard.set(false, forKey: AvatarStore.Keys.userDefaultsUpload)

                if let avatarID = avatarID {
                    DDLogInfo("ProtoService/resendAvatarIfNecessary received new avatarID [\(avatarID)]")
                    MainAppContext.shared.avatarStore.update(avatarId: avatarID, forUserId: self.userData.userId)
                }

            case .failure(let error):
                DDLogError("ProtoService/resendAvatarIfNecessary/error avatar not \(logAction): \(error)")
            }
        })
    }
}

extension ProtoService: HalloService {

    func sendCurrentUserNameIfPossible() {
        UserDefaults.standard.set(false, forKey: userDefaultsKeyForNameSync)

        if isConnected {
            resendNameIfNecessary()
        }
    }

    func sendCurrentAvatarIfPossible() {
        UserDefaults.standard.set(true, forKey: AvatarStore.Keys.userDefaultsUpload)

        if isConnected {
            resendAvatarIfNecessary()
        }
    }

    func retractFeedItem(_ feedItem: FeedItemProtocol, ownerID: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoRetractItemRequest(feedItem: feedItem, feedOwnerId: ownerID, completion: completion))
    }

    func sharePosts(postIds: [FeedPostID], with userId: UserID, completion: @escaping ServiceRequestCompletion<Void>) {

    }

    func uploadWhisperKeyBundle(_ bundle: WhisperKeyBundle, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoWhisperUploadRequest(keyBundle: bundle, completion: completion))
    }

    func requestAddOneTimeKeys(_ bundle: WhisperKeyBundle, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoWhisperAddOneTimeKeysRequest(whisperKeyBundle: bundle, completion: completion))
    }

    func requestCountOfOneTimeKeys(completion: @escaping ServiceRequestCompletion<Int32>) {
        enqueue(request: ProtoWhisperGetCountOfOneTimeKeysRequest(completion: completion))
    }

    func requestWhisperKeyBundle(userID: UserID, completion: @escaping ServiceRequestCompletion<WhisperKeyBundle>) {
        enqueue(request: ProtoWhisperGetBundleRequest(targetUserId: userID, completion: completion))
    }

    func sendReceipt(itemID: String, thread: HalloReceipt.Thread, type: HalloReceipt.`Type`, fromUserID: UserID, toUserID: UserID) {
        let receipt = HalloReceipt(itemId: itemID, userId: fromUserID, type: type, timestamp: nil, thread: thread)

        // TODO: implement receipt management logic
        sentReceipts[itemID] = receipt
        unackedReceipts[itemID] = (receipt, toUserID)

        enqueue(request: ProtoSendReceipt(
            itemID: itemID,
            thread: thread,
            type: type,
            fromUserID: fromUserID,
            toUserID: toUserID) { _ in
                self.unackedReceipts[itemID] = nil
            }
        )
    }

    func sendPresenceIfPossible(_ presenceType: PresenceType) {
        guard isConnected else { return }
        enqueue(request: ProtoPresenceUpdate(status: presenceType) { _ in })
    }

    func subscribeToPresenceIfPossible(to userID: UserID) -> Bool {
        guard isConnected else { return false }
        enqueue(request: ProtoPresenceSubscribeRequest(userID: userID) { _ in })
        return true
    }

    func requestInviteAllowance(completion: @escaping ServiceRequestCompletion<(Int, Date)>) {
        enqueue(request: ProtoGetInviteAllowanceRequest(completion: completion))
    }

    func sendInvites(phoneNumbers: [ABContact.NormalizedPhoneNumber], completion: @escaping ServiceRequestCompletion<InviteResponse>) {
        enqueue(request: ProtoRegisterInvitesRequest(phoneNumbers: phoneNumbers, completion: completion))
    }

    func syncContacts<T>(with contacts: T, type: ContactSyncRequestType, syncID: String, batchIndex: Int?, isLastBatch: Bool?, completion: @escaping ServiceRequestCompletion<[HalloContact]>) where T : Sequence, T.Element == HalloContact {
        enqueue(request: ProtoContactSyncRequest(
            with: contacts,
            type: type,
            syncID: syncID,
            batchIndex: batchIndex,
            isLastBatch: isLastBatch,
            completion: completion))
    }

    func sendPrivacyList(_ privacyList: PrivacyList, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoSendPrivacyListRequest(privacyList: privacyList, completion: completion))
    }

    func getPrivacyLists(_ listTypes: [PrivacyListType], completion: @escaping ServiceRequestCompletion<([PrivacyListProtocol], PrivacyListType)>) {
        enqueue(request: ProtoGetPrivacyListsRequest(listTypes: listTypes, completion: completion))
    }

    var hasValidAPNSPushToken: Bool {
        if let token = UserDefaults.standard.string(forKey: userDefaultsKeyForAPNSToken) {
            return !token.isEmpty
        }
        return false
    }

    func setAPNSToken(_ token: String?) {
        if let token = token {
            UserDefaults.standard.set(token, forKey: userDefaultsKeyForAPNSToken)
        } else {
            UserDefaults.standard.removeObject(forKey: userDefaultsKeyForAPNSToken)
        }
    }

    func sendCurrentAPNSTokenIfPossible() {
        if isConnected, let token = UserDefaults.standard.string(forKey: userDefaultsKeyForAPNSToken) {
            let request = ProtoPushTokenRequest(token: token) { (error) in
                DDLogInfo("proto/push-token/sent")
            }
            enqueue(request: request)
        } else {
            DDLogInfo("proto/push-token/could-not-send")
        }
    }

    func checkVersionExpiration(completion: @escaping ServiceRequestCompletion<TimeInterval>) {
        enqueue(request: ProtoClientVersionCheck(version: AppContext.appVersionForXMPP, completion: completion))
    }

    func getServerProperties(completion: @escaping ServiceRequestCompletion<ServerPropertiesResponse>) {
        enqueue(request: ProtoGetServerPropertiesRequest(completion: completion))
    }

    func sendGroupChatMessage(_ message: HalloGroupChatMessage, completion: @escaping ServiceRequestCompletion<Void>) {
        completion(.failure(ProtoServiceError.unimplemented))
    }

    func createGroup(name: String, members: [UserID], completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoGroupCreateRequest(name: name, members: members, completion: completion))
    }

    func leaveGroup(groupID: GroupID, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoGroupLeaveRequest(groupID: groupID, completion: completion))
    }

    func getGroupInfo(groupID: GroupID, completion: @escaping ServiceRequestCompletion<HalloGroup>) {
        enqueue(request: ProtoGroupInfoRequest(groupID: groupID, completion: completion))
    }
    func modifyGroup(groupID: GroupID, with members: [UserID], groupAction: ChatGroupAction,
                     action: ChatGroupMemberAction, completion: @escaping ServiceRequestCompletion<Void>) {
        enqueue(request: ProtoGroupModifyRequest(
            groupID: groupID,
            members: members,
            groupAction: groupAction,
            action: action,
            completion: completion))
    }
}
