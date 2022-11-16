//
//  WhisperSession.swift
//  Core
//
//  Created by Garrett on 2/24/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import CoreCommon
import CocoaLumberjackSwift
import Foundation
import Combine
import CoreData

private enum WhisperTask {
    case encryption(Data, EncryptionCompletion)
    case decryption(EncryptedData, DecryptionCompletion)
    case getSessionSetupInfoForRerequest(((Data, Int)?) -> Void)
    case resetSession
    case setupOutbound(OutboundCompletion)
}

public final class WhisperSession {

    init(userID: UserID, service: CoreService, keyStore: KeyStore) {
        self.userID = userID
        self.service = service
        self.keyStore = keyStore
        // If userID is empty - then mark state as failed, we will never recover.
        if userID.isEmpty {
            self.state = .failed
        } else {
            self.state = .awaitingSetup(attempts: 0)

            if let (keyBundle, messageKeys) = loadFromKeyStore() {
                self.state = .ready(keyBundle, messageKeys)
            } else {
                AppContext.shared.eventMonitor.count(.sessionReset(false))
            }
        }

        // This should solve issues when client tries sending messages when facing connection problems.
        // We retry setup requests immediately and we could fail all 3times.
        // But we would not retry even after connection succeeds.
        // This would now reset our state to retry setup requests again.
        // That way: messages will be sent eventually.
        self.cancellableSet.insert(
            self.service.didConnect.sink { [weak self] in
                DDLogInfo("WhisperSession/onConnect")
                guard let self = self else { return }
                self.sessionQueue.async {
                    switch self.state {
                    case .awaitingSetup:
                        DDLogInfo("WhisperSession/reset-setup-attempts")
                        self.state = .awaitingSetup(attempts: 0)
                    default:
                        break
                    }
                }
            }
        )
    }

    public func setupOutbound(completion: @escaping OutboundCompletion)
    {
        let dispatchedCompletion = { result in
            DispatchQueue.main.async { completion(result) }
        }
        sessionQueue.async {
            self.pendingTasks.append(.setupOutbound(dispatchedCompletion))
            self.executeTasks()
        }
    }

    public func encrypt(
        _ data: Data,
        completion: @escaping EncryptionCompletion)
    {
        let dispatchedCompletion = { result in
            DispatchQueue.main.async { completion(result) }
        }
        sessionQueue.async {
            self.pendingTasks.append(.encryption(data, dispatchedCompletion))
            self.executeTasks()
        }
    }

    public func decrypt(
        _ encryptedData: EncryptedData,
        completion: @escaping DecryptionCompletion)
    {
        let dispatchedCompletion = { result in
            DispatchQueue.main.async { completion(result) }
        }
        sessionQueue.async {
            self.pendingTasks.append(.decryption(encryptedData, dispatchedCompletion))
            self.executeTasks()
        }
    }

    public func receivedRerequest(_ rerequestData: RerequestData)
    {
        sessionQueue.async {
            let restartState: RestartState = {
                if rerequestData.sessionSetupEphemeralKey.isEmpty {
                    switch self.state {
                    case .failed:
                        // This is not expected.
                        DDLogError("WhisperSession/\(self.userID)/rerequest-state/failed/just return")
                        return .alreadyRestartedNoEphemeralKey
                    case .awaitingSetup, .retrievingKeys:
                        return .alreadyRestartingNoEphemeralKey
                    case .ready(let keyBundle, _):
                        return keyBundle.outboundChainIndex == 0 ? .alreadyRestartedNoEphemeralKey : .needsRestartNoEphemeralKey
                    }
                } else {
                    // NB: We ignore current state because this inbound ephemeral key should take precedence
                    let ephemeralKeyMatch = rerequestData.sessionSetupEphemeralKey == self.state.keyBundle?.inboundEphemeralPublicKey
                    return ephemeralKeyMatch ? .alreadyRestartedEphemeralKeyMatch : .needsRestartEphemeralKeyMismatch
                }
            }()

            switch restartState {
            case .alreadyRestartingNoEphemeralKey, .alreadyRestartedNoEphemeralKey, .alreadyRestartedEphemeralKeyMatch:
                DDLogInfo("WhisperSession/\(self.userID)/rerequest/setup/aborting [\(restartState)]")
                return
            case .needsRestartEphemeralKeyMismatch, .needsRestartNoEphemeralKey:
                DDLogInfo("WhisperSession/\(self.userID)/rerequest/setup/continuing [\(restartState)]")
                break
            }

            var wasSessionRestartSuccessful = false
            if rerequestData.identityKey.count > 0 && rerequestData.sessionSetupEphemeralKey.count > 0 {

                var setupResult: Result<KeyBundle, DecryptionError> = .failure(.missingUserKeys) // this value will be overwritten
                self.keyStore.performOnBackgroundContextAndWait { managedObjectContext in
                    guard let userKeys = self.keyStore.keyBundle(in: managedObjectContext) else {
                        DDLogError("WhisperSession/\(self.userID)/rerequest/setup/error [no-user-keys]")
                        return
                    }

                    // Attempt to setup session with keys included in rerequest
                    setupResult = Whisper.receiveSessionSetup(
                        userID: self.userID,
                        inboundIdentityPublicEdKey: rerequestData.identityKey,
                        inboundEphemeralPublicKey: rerequestData.sessionSetupEphemeralKey,
                        inboundEphemeralKeyID: 0,
                        oneTimeKeyID: rerequestData.oneTimePreKeyID,
                        previousChainLength: 0,
                        userKeys: userKeys)
                }

                switch setupResult {
                case .success(let keyBundle):
                    DDLogInfo("WhisperSession/\(self.userID)/rerequest/setup/complete")
                    self.updateState(to: .ready(keyBundle, [:]), saveToKeyStore: true)
                    wasSessionRestartSuccessful = true
                case .failure(let error):
                    DDLogError("WhisperSession/\(self.userID)/rerequest/setup/error [\(error)]")
                }
            } else {
                DDLogInfo("WhisperSession/\(self.userID)/rerequest/no-inbound-session-provided")
            }

            if case .ready = self.state, !wasSessionRestartSuccessful {
                DDLogInfo("WhisperSession/\(self.userID)/rerequest/deleting-keys")
                self.keyStore.deleteMessageKeyBundles(for: self.userID)
                self.updateState(to: .awaitingSetup(attempts: 1), saveToKeyStore: true)
            }
        }
    }

    public func sessionSetupInfoForRerequest(completion: @escaping ((Data, Int)?) -> Void) {
        let dispatchedCompletion = { result in
            DispatchQueue.main.async { completion(result) }
        }
        sessionQueue.async {
            switch self.state {
            case .ready(let keyBundle, _):
                DDLogVerbose("WhisperSession/sessionSetupInfoForRerequest/state: ready")
                // We have a new session, call completion immediately
                dispatchedCompletion((keyBundle.outboundEphemeralPublicKey, Int(keyBundle.outboundOneTimePreKeyId)))
            case .awaitingSetup:
                DDLogVerbose("WhisperSession/sessionSetupInfoForRerequest/state: awaitingSetup")
                // First session setup attempt must have failed.
                // so try setting up outbound session and then send the rerequest info.
                // Add this task to the queue
                self.pendingTasks.append(.getSessionSetupInfoForRerequest(dispatchedCompletion))
            case .retrievingKeys:
                DDLogVerbose("WhisperSession/sessionSetupInfoForRerequest/state: retrievingKeys")
                // Add this task to the queue
                self.pendingTasks.append(.getSessionSetupInfoForRerequest(dispatchedCompletion))
            case .failed:
                DDLogVerbose("WhisperSession/sessionSetupInfoForRerequest/state: failed")
                // Ignore this task - cant recover in this state.
                dispatchedCompletion(nil)
            }
        }
    }

    public func resetWhisperSession() {
        // reset 1-1 session completely
        sessionQueue.async {
            switch self.state {
            case .ready:
                // We should add this to the pendingTasks.
                self.pendingTasks.append(.resetSession)
            case .awaitingSetup:
                // We should add this to the pendingTasks.
                self.pendingTasks.append(.resetSession)
            case .retrievingKeys:
                // We are resetting our outboundSetup here already - so we can ignore this task.
                break
            case .failed:
                // We wont recover on this state - so ignore.
                break
            }
        }
    }

    public func reloadKeysFromKeyStore() {
        DDLogInfo("WhisperSession/reloadKeysFromKeyStore/userID: \(userID)")
        sessionQueue.async {
            // Dont overwrite the state when current target is currently retrieving keys.
            switch self.state {
            case .retrievingKeys:
                DDLogInfo("WhisperSession/reloadKeysFromKeyStore/userID: \(self.userID)/state: retrievingKeys")
                AppContext.shared.errorLogger?.logError(NSError.init(domain: "WhisperSessionMergeError", code: 1005, userInfo: nil))
                return
            case .ready(_, _):
                if let (keyBundle, messageKeys) = self.loadFromKeyStore() {
                    DDLogInfo("WhisperSession/reloadKeysFromKeyStore/userID: \(self.userID)/state: ready")
                    self.updateState(to: .ready(keyBundle, messageKeys), saveToKeyStore: false)
                } else {
                    DDLogInfo("WhisperSession/reloadKeysFromKeyStore/userID: \(self.userID)/state: awaitingSetup")
                    // If we are not able to retrieve keys properly.
                    // Then this means the keyBundle has been deleted - so we have to start afresh.
                    self.updateState(to: .awaitingSetup(attempts: 0), saveToKeyStore: false)
                }
            case .awaitingSetup(_):
                DDLogInfo("WhisperSession/reloadKeysFromKeyStore/userID: \(self.userID)/state: awaitingSetup")
                if let (keyBundle, messageKeys) = self.loadFromKeyStore() {
                    self.updateState(to: .ready(keyBundle, messageKeys), saveToKeyStore: false)
                }
                // Else -- continue trying to setup keys.
            case .failed:
                break
            }
        }
    }

    // MARK: Private
    // MARK: *All private functions should be called on sessionQueue!*

    private enum State {
        case awaitingSetup(attempts: Int)
        case retrievingKeys
        case ready(KeyBundle, MessageKeyMap)
        case failed

        var keyBundle: KeyBundle? {
            switch self {
            case .awaitingSetup, .retrievingKeys, .failed:
                return nil
            case .ready(let keyBundle, _):
                return keyBundle
            }
        }

        var failedSetupAttempts: Int? {
            switch self {
            case .awaitingSetup(let attempts):
                return attempts
            case .ready, .retrievingKeys:
                return nil
            case .failed:
                return Int.max
            }
        }
    }

    /// Enumerates the different scenarios upon receiving a rerequest
    private enum RestartState: String {
        case alreadyRestartingNoEphemeralKey
        case alreadyRestartedNoEphemeralKey
        case alreadyRestartedEphemeralKeyMatch
        case needsRestartEphemeralKeyMismatch
        case needsRestartNoEphemeralKey
    }

    private let service: CoreService
    private let keyStore: KeyStore
    private let userID: UserID
    private var cancellableSet: Set<AnyCancellable> = []

    private lazy var sessionQueue = { DispatchQueue(label: "com.halloapp.whisper-\(userID)", qos: .userInitiated) }()
    private var pendingTasks = [WhisperTask]()

    private var state: State

    private func updateState(to state: State, saveToKeyStore: Bool = false) {
        self.state = state
        if saveToKeyStore {
            switch state {
            case .awaitingSetup(_):
                DDLogInfo("WhisperSession/set-state/awaitingSetup")
            case .retrievingKeys:
                DDLogInfo("WhisperSession/set-state/retrievingKeys")
            case .ready(let keyBundle, let messageKeys):
                DDLogInfo("WhisperSession/set-state/ready")

                keyStore.saveKeyBundle(keyBundle)
                keyStore.saveMessageKeys(messageKeys, for: userID)
            case .failed:
                DDLogInfo("WhisperSession/set-state/failed")
                keyStore.deleteMessageKeyBundles(for: userID)
            }
        }
    }

    private func deleteOneTimeKey(id: Int) {
        keyStore.deleteUserOneTimePreKey(oneTimeKeyId: id)
    }

    private func teardown(_ teardownKey: Data?) {
        guard let keyBundle = state.keyBundle else {
            DDLogError("WhisperSession/\(userID)/teardown/error [missing key bundle]")
            return
        }
        var newKeyBundle = keyBundle
        newKeyBundle.teardownKey = teardownKey
        state = .ready(newKeyBundle, [:])

        DDLogError("WhisperSession/\(userID)/teardown/finished [\(teardownKey?.bytes.prefix(4) ?? [])...]")
    }

    private func executeTasks() {
        while let task = pendingTasks.first {
            switch state {
            case .retrievingKeys:
                DDLogInfo("WhisperSession/\(userID)/execute/pausing (retrieving keys)")
                return
            case .awaitingSetup(let setupAttempts):
                switch task {
                case .encryption(_, let completion):
                    guard setupAttempts < 3 else {
                        DDLogInfo("WhisperSession/\(userID)/execute/failing (outbound setup failed \(setupAttempts) times")
                        completion(.failure(.missingKeyBundle))
                        return
                    }
                    DDLogInfo("WhisperSession/\(userID)/execute/pausing (needs outbound setup)")
                    setupOutbound()
                    return
                case .decryption(let data, let completion):
                    DDLogInfo("WhisperSession/\(userID)/execute/decrypting")
                    executeDecryption(data, completion: completion)
                case .getSessionSetupInfoForRerequest(let completion):
                    guard setupAttempts < 3 else {
                        DDLogInfo("WhisperSession/\(userID)/execute/failing (outbound setup failed \(setupAttempts) times")
                        completion(nil)
                        return
                    }
                    DDLogInfo("WhisperSession/\(userID)/execute/pausing (needs outbound setup)")
                    setupOutbound()
                    return
                case .resetSession:
                    DDLogInfo("WhisperSession/\(userID)/execute/resetSession - (needs outbound setup)")
                    self.teardown(nil)
                    self.setupOutbound()
                case .setupOutbound(let completion):
                    guard setupAttempts < 3 else {
                        DDLogInfo("WhisperSession/\(userID)/execute/setupOutbound failing (outbound setup failed \(setupAttempts) times")
                        completion(.failure(.missingKeyBundle))
                        return
                    }
                    DDLogInfo("WhisperSession/\(userID)/execute/setupOutbound - setting up")
                    setupOutbound()
                    return
                }
            case .ready(let keyBundle, let messageKeys):
                switch task {
                case .encryption(let data, let completion):
                    DDLogInfo("WhisperSession/\(userID)/execute/encrypting")
                    executeEncryption(data, with: keyBundle, messageKeys: messageKeys, completion: completion)
                case .decryption(let data, let completion):
                    DDLogInfo("WhisperSession/\(userID)/execute/decrypting")
                    executeDecryption(data, completion: completion)
                case .getSessionSetupInfoForRerequest(let completion):
                    completion((keyBundle.outboundEphemeralPublicKey, Int(keyBundle.outboundOneTimePreKeyId)))
                case .resetSession:
                    DDLogInfo("WhisperSession/\(userID)/execute/resetSession - (needs outbound setup)")
                    self.teardown(nil)
                    self.setupOutbound()
                case .setupOutbound(let completion):
                    DDLogInfo("WhisperSession/\(userID)/execute/setupOutbound")
                    completion(.success(keyBundle))
                }
            case .failed:
                switch task {
                case .encryption(_, let completion):
                    DDLogInfo("WhisperSession/\(userID)/execute/encrypting")
                    completion(.failure(.invalidUid))
                case .decryption(_, let completion):
                    DDLogInfo("WhisperSession/\(userID)/execute/decrypting")
                    completion(.failure(.init(.keyGenerationFailure, ephemeralKey: nil)))
                case .getSessionSetupInfoForRerequest(let completion):
                    completion(nil)
                case .resetSession:
                    DDLogInfo("WhisperSession/\(userID)/execute/resetSession - (needs outbound setup)")
                    break
                case .setupOutbound(let completion):
                    DDLogInfo("WhisperSession/\(userID)/execute/setupOutbound")
                    completion(.failure(.invalidUid))
                }
            }
            pendingTasks.removeFirst()
        }
    }

    private func executeDecryption(_ encryptedData: EncryptedData, completion: DecryptionCompletion) {
        guard let payload = EncryptedPayload(data: encryptedData.data) else {
            completion(.failure(.init(.invalidPayload, ephemeralKey: nil)))
            return
        }
        if let teardownKey = state.keyBundle?.teardownKey, teardownKey == payload.ephemeralPublicKey {
            DDLogInfo("WhisperSession/\(self.userID)/decrypt/skipping [teardown key match]")
            completion(.failure(.init(.teardownKeyMatch, ephemeralKey: teardownKey)))
            return
        }
        switch setupInbound(with: encryptedData) {
        case .success((let keyBundle, let messageKeys)):
            switch Whisper.decrypt(payload, keyBundle: keyBundle, messageKeys: messageKeys) {
            case .success((let data, let keyBundle, let messageKeys)):
                self.updateState(to: .ready(keyBundle, messageKeys), saveToKeyStore: true)
                self.deleteOneTimeKey(id: encryptedData.oneTimeKeyId)
                completion(.success(data))
            case .failure(let failure):
                DDLogInfo("WhisperSession/\(self.userID)/decrypt/teardown [\(failure.error)]")
                AppContext.shared.eventMonitor.count(.sessionReset(true))
                self.teardown(payload.ephemeralPublicKey)
                self.setupOutbound()
                completion(.failure(failure))
            }
        case .failure(let error):
            completion(.failure(.init(error, ephemeralKey: payload.ephemeralPublicKey)))
        }
    }

    private func executeEncryption(_ data: Data, with keyBundle: KeyBundle, messageKeys: MessageKeyMap, completion: @escaping EncryptionCompletion) {
        let result = Whisper.encrypt(data, keyBundle: keyBundle)
        switch result {
        case .success(let (data, chainKey)):
            var newKeyBundle = keyBundle
            newKeyBundle.outboundChainKey = chainKey
            newKeyBundle.outboundChainIndex += 1
            let output: EncryptedData = {
                switch newKeyBundle.phase {
                case .conversation:
                    return EncryptedData(data: data, identityKey: nil, oneTimeKeyId: -1)
                case .keyAgreement:
                    return EncryptedData(data: data, identityKey: newKeyBundle.outboundIdentityPublicEdKey, oneTimeKeyId: Int(newKeyBundle.outboundOneTimePreKeyId))
                }
            }()
            state = .ready(newKeyBundle, messageKeys)

            keyStore.performSeriallyOnBackgroundContext { managedObjectContext in
                let logInfo: EncryptionLogInfo = [
                    "MIK": self.keyStore.keyBundle(in: managedObjectContext)?.identityPublicEdKey.base64EncodedString() ?? "[???]",
                    "PIK": keyBundle.inboundIdentityPublicEdKey.base64EncodedString(),
                    "MICKH": self.obfuscate(keyBundle.inboundChainKey),
                    "MOCKH": self.obfuscate(keyBundle.outboundChainKey),
                ]
                completion(.success((output, logInfo)))
            }
        case .failure(let error):
            completion(.failure(error))
        }
    }

    private func obfuscate(_ secret: Data) -> String {
        return "\(secret.sha256().toHexString().prefix(4)):\(secret.count)"
    }

    private func setupOutbound() {

        if case .retrievingKeys = state {
            DDLogInfo("WhisperSession/\(self.userID)/setupOutbound/skipping [already retrieving keys]")
            return
        }

        let teardownKey = state.keyBundle?.teardownKey
        let attemptNumber = 1 + (state.failedSetupAttempts ?? 0)
        state = .retrievingKeys

        service.requestWhisperKeyBundle(userID: userID) { result in
            self.sessionQueue.async {

                switch self.state {
                case .failed:
                    DDLogInfo("WhisperSession/\(self.userID)/setupOutbound/aborting [session already failed]")
                    return
                case .awaitingSetup, .retrievingKeys:
                    DDLogInfo("WhisperSession/\(self.userID)/setupOutbound/received-keys")
                case .ready:
                    // It's possible a rerequest or inbound message arrived while we were fetching keys
                    DDLogInfo("WhisperSession/\(self.userID)/setupOutbound/aborting [session already set up]")
                    return
                }

                // Initialize key bundle if possible
                switch result {
                case .failure(let error):
                    DDLogError("WhisperSession/\(self.userID)/setupOutbound/error [\(error)]")
                    switch error {
                    case .serverError("invalid_uid"):
                        DDLogError("WhisperSession/\(self.userID)/setupOutbound/failed permanently")
                        self.updateState(to: .failed, saveToKeyStore: true)
                    default:
                        DDLogError("WhisperSession/\(self.userID)/setupOutbound/failed [\(attemptNumber)]")
                        self.updateState(to: .awaitingSetup(attempts: attemptNumber), saveToKeyStore: true)
                    }
                case .success(let whisperKeys):
                    var keyBundle: KeyBundle?
                    self.keyStore.performOnBackgroundContextAndWait { managedObjectContext in
                        guard let userKeys = self.keyStore.keyBundle(in: managedObjectContext) else {
                            DDLogError("WhisperSession/\(self.userID)/setupOutbound/error [no user keys!]")
                            return
                        }
                        keyBundle = Whisper.initiateSessionSetup(
                            for: self.userID,
                            with: whisperKeys,
                            userKeys: userKeys,
                            teardownKey: teardownKey)
                    }
                    if let keyBundle = keyBundle {
                        DDLogInfo("WhisperSession/\(self.userID)/setupOutbound/success")
                        self.updateState(to: .ready(keyBundle, [:]), saveToKeyStore: true)
                    } else {
                        DDLogError("WhisperSession/\(self.userID)/setupOutbound/failed although we got keys [\(attemptNumber)]")
                        self.updateState(to: .awaitingSetup(attempts: attemptNumber), saveToKeyStore: true)
                    }
                }
                self.executeTasks()
            }
        }
    }

    private func setupNewInboundSession(with encryptedData: EncryptedData) -> Result<(KeyBundle, MessageKeyMap), DecryptionError> {
        var setupResult: Result<KeyBundle, DecryptionError> = .failure(.missingUserKeys)

        keyStore.performOnBackgroundContextAndWait { managedObjectContext in
            guard let userKeys = keyStore.keyBundle(in: managedObjectContext) else {
                setupResult = .failure(.missingUserKeys)
                return
            }
            guard let payload = EncryptedPayload(data: encryptedData.data) else {
                setupResult = .failure(.invalidPayload)
                return
            }
            guard let identityKey = encryptedData.identityKey else {
                setupResult = .failure(.missingPublicKey)
                return
            }

            setupResult = Whisper.receiveSessionSetup(
                userID: userID,
                inboundIdentityPublicEdKey: identityKey,
                inboundEphemeralPublicKey: payload.ephemeralPublicKey,
                inboundEphemeralKeyID: Int(payload.ephemeralKeyID),
                oneTimeKeyID: encryptedData.oneTimeKeyId,
                previousChainLength: Int(payload.previousChainLength),
                userKeys: userKeys)
        }

        switch setupResult {
        case .success(let keyBundle):
            DDLogInfo("WhisperSession/\(userID)/setup/new-key-bundle")
            return .success((keyBundle, [:]))
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Sets up new session if necessary, otherwise returns keys from current state
    private func setupInbound(with encryptedData: EncryptedData) -> Result<(KeyBundle, MessageKeyMap), DecryptionError> {

        guard case .ready(let keyBundle, let messageKeys) = state else {
            DDLogInfo("WhisperSession/\(userID)/setup/setup new inbound session")
            return setupNewInboundSession(with: encryptedData)
        }

        if let inboundIdentityKey = encryptedData.identityKey, !inboundIdentityKey.isEmpty {
            if keyBundle.inboundEphemeralPublicKey == nil {
                DDLogInfo("WhisperSession/\(userID)/setup/new-inbound [inbound identity with no existing inbound ephemeral]")
                return setupNewInboundSession(with: encryptedData)
            } else {
                DDLogInfo("WhisperSession/\(userID)/setup/new-inbound/skipping [existing inbound ephemeral]")
            }
        } else {
            DDLogInfo("WhisperSession/\(userID)/setup/no-inbound-identity-key")
        }

        return .success((keyBundle, messageKeys))
    }

    private func loadFromKeyStore() -> (KeyBundle, MessageKeyMap)? {
        var keyBundle: KeyBundle?
        var keyMap = MessageKeyMap()

        keyStore.performOnBackgroundContextAndWait { managedObjectContext in
            guard let messageKeyBundle = self.keyStore.messageKeyBundle(for: userID, in: managedObjectContext),
                  let bundle = messageKeyBundle.keyBundle else
            {
                return
            }

            keyBundle = bundle

            for key in messageKeyBundle.messageKeys ?? [] {
                keyMap[key.locator] = key.key
            }
        }

        if let keyBundle = keyBundle {
            return (keyBundle, keyMap)
        }

        return nil
    }
}

extension MessageKey {
    var locator: MessageKeyLocator {
        MessageKeyLocator(ephemeralKeyID: ephemeralKeyId, chainIndex: chainIndex)
    }
}
