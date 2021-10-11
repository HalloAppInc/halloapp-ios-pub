//
//  MessageCrypter.swift
//  Core
//
//  Created by Garrett on 2/24/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import Foundation

public typealias EncryptionLogInfo = [String: String]
public typealias EncryptionCompletion = (Result<(EncryptedData, EncryptionLogInfo), EncryptionError>) -> Void
public typealias DecryptionCompletion = (Result<Data, DecryptionFailure>) -> Void
public typealias GroupFeedRerequestType = Server_GroupFeedRerequest.RerequestType

public final class MessageCrypter: KeyStoreDelegate {

    public init(service: CoreService, keyStore: KeyStore) {
        self.service = service
        self.keyStore = keyStore
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
            session.encrypt(data, completion: completion)
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


    // MARK: Private

    private let service: CoreService
    private let keyStore: KeyStore
    private var userSessions = [UserID: WhisperSession]()
    private var groupSessions = [GroupID: GroupWhisperSession]()
    private var queue = DispatchQueue(label: "com.halloapp.message-crypter", qos: .userInitiated)

    private func loadSession(for userID: UserID) -> WhisperSession {
        if let session = userSessions[userID] {
            return session
        } else {
            let newSession = WhisperSession(userID: userID, service: service, keyStore: keyStore)
            userSessions[userID] = newSession
            AppContext.shared.eventMonitor.count(.sessionReset(false))
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
}
