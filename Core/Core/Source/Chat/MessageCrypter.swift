//
//  MessageCrypter.swift
//  Core
//
//  Created by Garrett on 2/24/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import Foundation
import CoreCommon
import Combine
import CocoaLumberjackSwift

public typealias EncryptionLogInfo = [String: String]
public typealias OutboundCompletion = (Result<KeyBundle, EncryptionError>) -> Void
public typealias EncryptionCompletion = (Result<(EncryptedData, EncryptionLogInfo), EncryptionError>) -> Void
public typealias DecryptionCompletion = (Result<Data, DecryptionFailure>) -> Void
public typealias GroupFeedRerequestType = Server_GroupFeedRerequest.RerequestType
public typealias GroupFeedRerequestContentType = Server_GroupFeedRerequest.ContentType
public typealias HomeFeedRerequestType = Server_HomeFeedRerequest.RerequestType
public typealias HomeFeedRerequestContentType = Server_HomeFeedRerequest.ContentType

public final class MessageCrypter: KeyStoreDelegate {
    private var cancellableSet: Set<AnyCancellable> = []

    public init(userData: UserData, service: CoreService, keyStore: KeyStore) {
        self.service = service
        self.keyStore = keyStore
        self.cancellableSet.insert(
            service.didGetNewWhisperMessage.sink { [weak self] whisperMessage in
                self?.handleIncomingWhisperMessage(whisperMessage)
            }
        )

        // If user logs off - clear out all sessions.
        // We can reload sessions again when user registers.
        self.cancellableSet.insert(
            userData.didLogOff.sink { [weak self] in
                self?.clearAllSessions()
            }
        )
    }

    private func handleIncomingWhisperMessage(_ whisperMessage: WhisperMessage) {
        DDLogInfo("ChatData/handleIncomingWhisperMessage/begin")
        queue.async {
            switch whisperMessage {
            case .update(let userID, _):
                DDLogInfo("ChatData/handleIncomingWhisperMessage/execute update for \(userID)")
                // Clear cached whisper session.
                // All future requests will refetch session from the keystore.
                self.userSessions[userID] = nil
            default:
                DDLogInfo("ChatData/handleIncomingWhisperMessage/ignore")
                break
            }
        }
    }

    public func setupOutbound(
        for userID: UserID,
        completion: @escaping OutboundCompletion)
    {
        queue.async {
            let session = self.loadSession(for: userID)
            session.setupOutbound(completion: completion)
        }
    }

    public func encrypt(
        _ data: Data,
        for userID: UserID,
        completion: @escaping EncryptionCompletion)
    {
        queue.async {
            let session = self.loadSession(for: userID)
            session.encrypt(data, completion: completion)
        }
    }

    public func decrypt(
        _ encryptedData: EncryptedData,
        from userID: UserID,
        completion: @escaping DecryptionCompletion)
    {
        queue.async {
            let session = self.loadSession(for: userID)
            session.decrypt(encryptedData, completion: completion)
        }
    }

    public func encrypt(
        _ data: Data,
        in groupID: GroupID,
        completion: @escaping GroupEncryptionCompletion)
    {
        queue.async {
            let session = self.loadGroupSession(for: groupID)
            session.encrypt(data, potentialMemberUids: [], completion: completion)
        }
    }

    public func encrypt(
        _ data: Data,
        in groupID: GroupID,
        potentialMemberUids: [UserID],
        completion: @escaping GroupEncryptionCompletion)
    {
        queue.async {
            let session = self.loadGroupSession(for: groupID)
            session.encrypt(data, potentialMemberUids: potentialMemberUids, completion: completion)
        }
    }

    public func decrypt(
        _ encryptedData: Data,
        from userID: UserID,
        in groupID: GroupID,
        with senderState: Clients_SenderState?,
        completion: @escaping GroupDecryptionCompletion)
    {
        queue.async {
            let session = self.loadGroupSession(for: groupID)
            session.decrypt(encryptedData, from: userID, with: senderState, completion: completion)
        }
    }

    public func removePending(
        userIds: [UserID],
        in groupID: GroupID)
    {
        queue.async {
            let session = self.loadGroupSession(for: groupID)
            session.removePending(userIds: userIds)
        }
    }

    public func removeMembers(
        userIds: [UserID],
        in groupID: GroupID)
    {
        queue.async {
            let session = self.loadGroupSession(for: groupID)
            session.removeMembers(userIds: userIds)
        }
    }

    public func addMembers(
        userIds: [UserID],
        in groupID: GroupID)
    {
        queue.async {
            let session = self.loadGroupSession(for: groupID)
            session.addMembers(userIds: userIds)
        }
    }

    public func syncGroupSession(
        in groupID: GroupID,
        members: [UserID])
    {
        queue.async {
            let session = self.loadGroupSession(for: groupID)
            session.syncGroup(members: members)
        }
    }

    public func updateAudienceHash(for groupID: GroupID) {
        queue.async {
            let session = self.loadGroupSession(for: groupID)
            session.updateAudienceHash()
        }
    }

    public func fetchSenderState(
        in groupID: GroupID,
        completion: @escaping GroupSenderStateCompletion)
    {
        queue.async {
            let session = self.loadGroupSession(for: groupID)
            session.fetchSenderState(completion: completion)
        }
    }

    public func updateSenderState(
        with senderState: Clients_SenderState?,
        for userID: UserID,
        in groupID: GroupID)
    {
        queue.async {
            let session = self.loadGroupSession(for: groupID)
            session.updateSenderState(with: senderState, for: userID)
        }
    }

    public func receivedRerequest(
        _ rerequestData: RerequestData,
        from userID: UserID)
    {
        queue.async {
            let session = self.loadSession(for: userID)
            session.receivedRerequest(rerequestData)
        }
    }

    public func sessionSetupInfoForRerequest(
        from userID: UserID,
        completion: @escaping ((Data, Int)?) -> Void)
    {
        queue.async {
            let session = self.loadSession(for: userID)
            session.sessionSetupInfoForRerequest(completion: completion)
        }
    }

    public func resetWhisperSession(for userID: UserID)
    {
        queue.async {
            let session = self.loadSession(for: userID)
            session.resetWhisperSession()
        }
    }

    public func encrypt(
        _ data: Data,
        with postID: FeedPostID,
        for type: HomeSessionType,
        audienceMemberUids: [UserID],
        completion: @escaping HomePostEncryptionCompletion)
    {
        queue.async {
            let session = self.loadHomeSession(for: type)
            session.encryptPost(data, postID: postID, audienceMemberUids: audienceMemberUids, completion: completion)
        }
    }

    public func encrypt(
        _ data: Data,
        with postID: FeedPostID,
        for type: HomeSessionType,
        completion: @escaping HomeCommentEncryptionCompletion)
    {
        queue.async {
            let session = self.loadHomeSession(for: type)
            session.encryptComment(data, postID: postID, completion: completion)
        }
    }

    public func decrypt(
        _ data: Data,
        from userID: UserID,
        postID: FeedPostID,
        with senderState: Clients_SenderState?,
        for type: HomeSessionType,
        completion: @escaping HomeDecryptionCompletion)
    {
        queue.async {
            let session = self.loadHomeSession(for: type)
            session.decryptPost(data, from: userID, postID: postID, with: senderState, completion: completion)
        }
    }

    public func decrypt(
        _ data: Data,
        from userID: UserID,
        postID: FeedPostID,
        for type: HomeSessionType,
        completion: @escaping HomeDecryptionCompletion)
    {
        queue.async {
            let session = self.loadHomeSession(for: type)
            session.decryptComment(data, from: userID, postID: postID, completion: completion)
        }
    }

    public func removePending(
        userIds: [UserID],
        for type: HomeSessionType)
    {
        queue.async {
            let session = self.loadHomeSession(for: type)
            session.removePending(userIds: userIds)
        }
    }

    public func removeMembers(
        userIds: [UserID],
        for type: HomeSessionType)
    {
        queue.async {
            let session = self.loadHomeSession(for: type)
            session.removeMembers(userIds: userIds)
        }
    }

    public func addMembers(
        userIds: [UserID],
        for type: HomeSessionType)
    {
        queue.async {
            let session = self.loadHomeSession(for: type)
            session.addMembers(userIds: userIds)
        }
    }

    public func fetchSenderState(
        for type: HomeSessionType,
        completion: @escaping HomeSenderStateCompletion)
    {
        queue.async {
            let session = self.loadHomeSession(for: type)
            session.fetchSenderState(completion: completion)
        }
    }

    public func updateSenderState(
        with senderState: Clients_SenderState?,
        for userID: UserID,
        type: HomeSessionType)
    {
        queue.async {
            let session = self.loadHomeSession(for: type)
            session.updateSenderState(with: senderState, for: userID)
        }
    }

    public func fetchCommentKey(
        postID: FeedPostID,
        for type: HomeSessionType,
        completion: @escaping HomeCommentKeyCompletion)
    {
        queue.async {
            let session = self.loadHomeSession(for: type)
            session.fetchCommentKey(for: postID, completion: completion)
        }
    }

    public func saveCommentKey(
        postID: FeedPostID,
        commentKey: Data,
        for type: HomeSessionType)
    {
        queue.async {
            let session = self.loadHomeSession(for: type)
            session.saveCommentKey(for: postID, commentKey: commentKey)
        }
    }


    // MARK: Private

    private let service: CoreService
    private let keyStore: KeyStore
    private var userSessions = [UserID: WhisperSession]()
    private var groupSessions = [GroupID: GroupWhisperSession]()
    private var homeSessions = [String: HomeWhisperSession]()
    private var queue = DispatchQueue(label: "com.halloapp.message-crypter", qos: .userInitiated)

    private func loadSession(for userID: UserID) -> WhisperSession {
        if let session = userSessions[userID] {
            return session
        } else {
            let newSession = WhisperSession(userID: userID, service: service, keyStore: keyStore)
            userSessions[userID] = newSession
            return newSession
        }
    }

    private func loadGroupSession(for groupID: GroupID) -> GroupWhisperSession {
        if let session = groupSessions[groupID] {
            return session
        } else {
            let newSession = GroupWhisperSession(groupID: groupID, service: service, keyStore: keyStore)
            groupSessions[groupID] = newSession
            return newSession
        }
    }

    private func loadHomeSession(for type: HomeSessionType) -> HomeWhisperSession {
        if let session = homeSessions[type.rawStringValue] {
            return session
        } else {
            let newSession = HomeWhisperSession(type: type, service: service, keyStore: keyStore)
            homeSessions[type.rawStringValue] = newSession
            return newSession
        }
    }

    // Triggered when managedObjectContext of the keystore changes.
    // This indicates that all the keyBundles we loaded in-memory could be void.
    // We should let those sessions refetch and update their keys.
    public func keyStoreContextChanged() {
        queue.async {
            self.userSessions.forEach{ (_, session) in
                session.reloadKeysFromKeyStore()
            }
            self.groupSessions.forEach{ (_, session) in
                session.reloadKeysFromKeyStore()
            }
            self.homeSessions.forEach{ (_, session) in
                session.reloadKeysFromKeyStore()
            }
        }
    }

    // Clears all cached sessions.
    public func clearAllSessions() {
        queue.async {
            self.userSessions.removeAll()
            self.groupSessions.removeAll()
            self.homeSessions.removeAll()
        }
    }
}

public struct DecryptionFailure: Error {
    public init(_ error: DecryptionError, ephemeralKey: Data? = nil) {
        self.error = error
        self.ephemeralKey = ephemeralKey
    }

    public var error: DecryptionError
    public var ephemeralKey: Data?
}

public struct GroupDecryptionFailure: Error {
    public init(_ id: String?, _ fromUserId: UserID?, _ error: DecryptionError, _ rerequestType: GroupFeedRerequestType) {
        self.contentId = id
        self.fromUserId = fromUserId
        self.error = error
        self.rerequestType = rerequestType
    }

    public var contentId: String?
    public var fromUserId: UserID?
    public var error: DecryptionError
    public var rerequestType: GroupFeedRerequestType
}

public struct HomeDecryptionFailure: Error {
    public init(_ id: String?, _ fromUserId: UserID?, _ error: DecryptionError, _ rerequestType: HomeFeedRerequestType) {
        self.contentId = id
        self.fromUserId = fromUserId
        self.error = error
        self.rerequestType = rerequestType
    }

    public var contentId: String?
    public var fromUserId: UserID?
    public var error: DecryptionError
    public var rerequestType: HomeFeedRerequestType
}

// Add new error cases at the end (the index is used as the error code)
public enum DecryptionError: String, Error {
    case aesError
    case deserialization
    case hmacMismatch
    case invalidMessageKey
    case invalidPayload
    case keyGenerationFailure
    case masterKeyComputation
    case missingMessageKey
    case missingOneTimeKey
    case missingPublicKey
    case missingSignedPreKey
    case missingUserKeys
    case ratchetFailure
    case x25519Conversion
    case teardownKeyMatch
    case missingSenderState
    case signatureMisMatch
    case missingPayload
    case missingContent
    case invalidGroup
    case missingCommentKey
    case postNotFound
}

// Add new error cases at the end (the index is used as the error code)
public enum EncryptionError: String, Error {
    case aesError
    case hmacError
    case missingKeyBundle
    case ratchetFailure
    case serialization
    case signing
    case missingAudienceHash
    case missingEncryptedSenderState
    case invalidUid
    case invalidGroup
    case missingCommentKey
}


extension EncryptionError {
    func serviceError() -> RequestError {
        switch self {
        // These errors are unrecoverable crypto states and we abort it - we return .aborted
        case .invalidUid, .invalidGroup, .missingCommentKey: return .aborted
        // These are some serious crypto errors that should only occur in the case of malformed keys.
        case .aesError, .hmacError, .ratchetFailure, .serialization, .signing: return .aborted
        // These are errors that could happen due to connection failures and we can recover from these.
        case .missingKeyBundle, .missingAudienceHash, .missingEncryptedSenderState: return .malformedRequest
        }
    }
}
