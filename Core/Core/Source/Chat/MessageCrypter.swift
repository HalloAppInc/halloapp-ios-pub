//
//  MessageCrypter.swift
//  Core
//
//  Created by Garrett on 2/24/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import Foundation


public typealias EncryptionCompletion = (Result<EncryptedData, EncryptionError>) -> Void
public typealias DecryptionCompletion = (Result<Data, DecryptionFailure>) -> Void

public final class MessageCrypter {

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


    // MARK: Private

    private let service: CoreService
    private let keyStore: KeyStore
    private var sessions = [UserID: WhisperSession]()
    private var queue = DispatchQueue(label: "com.halloapp.message-crypter", qos: .userInitiated)

    private func loadSession(for userID: UserID) -> WhisperSession {
        if let session = sessions[userID] {
            return session
        } else {
            let newSession = WhisperSession(userID: userID, service: service, keyStore: keyStore)
            sessions[userID] = newSession
            return newSession
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
    case plaintextMismatch
    case ratchetFailure
    case x25519Conversion
    case teardownKeyMatch
}

// Add new error cases at the end (the index is used as the error code)
public enum EncryptionError: String, Error {
    case aesError
    case hmacError
    case missingKeyBundle
    case ratchetFailure
    case serialization
}
