//
//  GroupWhisperSession.swift
//  Core
//
//  Created by Garrett on 8/18/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import Foundation
import CocoaLumberjackSwift

public typealias GroupEncryptionCompletion = (Result<GroupEncryptedData, EncryptionError>) -> Void
public typealias GroupDecryptionCompletion = (Result<Data, DecryptionError>) -> Void
public typealias GroupSenderStateCompletion = (Result<GroupSenderState, EncryptionError>) -> Void

public struct GroupSenderKey {
    var chainKey: Data
    var publicSignatureKey: Data
}

public struct GroupIncomingSenderState {
    var senderKey: GroupSenderKey
    var currentChainIndex: Int
    var unusedMessageKeys: [Int32: Data]
}

extension GroupIncomingSenderState {
    init(senderState: Clients_SenderState) {
        senderKey = GroupSenderKey(chainKey: senderState.senderKey.chainKey, publicSignatureKey: senderState.senderKey.publicSignatureKey)
        currentChainIndex = Int(senderState.currentChainIndex)
        unusedMessageKeys = [:]
    }
}

public struct GroupIncomingSession {
    var senderStates: [UserID: GroupIncomingSenderState]
}

public struct GroupOutgoingSession {
    var audienceHash: Data?
    var senderKey: GroupSenderKey
    var currentChainIndex: Int
    var privateSigningKey: Data
}

private enum GroupCryptoTask {
    case encryption(Data, GroupEncryptionCompletion)
    case decryption(Data, UserID, Clients_SenderState?, GroupDecryptionCompletion)
    case membersAdded([UserID])
    case membersRemoved([UserID])
    case removePending([UserID])
    case updateAudienceHash
    case fetchSenderState(GroupSenderStateCompletion)
    case updateSenderState(UserID, Clients_SenderState)
}

public struct GroupKeyBundle {
    var outgoingSession: GroupOutgoingSession?
    var incomingSession: GroupIncomingSession?
    // List of memberUids in the group: who need to be notified of the senderState on the next publish action.
    var pendingUids: [UserID]
}

public enum GroupSessionState: Int16 {
    case awaitingSetup = 0
    case ready = 1
}

public struct GroupEncryptedData {
    public init(data: Data, senderKey: GroupSenderKey?, chainIndex: Int?, audienceHash: Data?, receiverUids: [UserID]) {
        self.data = data
        self.senderKey = senderKey
        self.chainIndex = chainIndex == nil ? nil : Int32(chainIndex!)
        self.audienceHash = audienceHash
        self.receiverUids = receiverUids
    }

    public var data: Data
    public var senderKey: GroupSenderKey?
    public var chainIndex: Int32?
    public var audienceHash: Data?
    public var receiverUids: [UserID]
}

public struct GroupSenderState {
    public init(senderKey: GroupSenderKey, chainIndex: Int) {
        self.senderKey = senderKey
        self.chainIndex = Int32(chainIndex)
    }

    public var senderKey: GroupSenderKey
    public var chainIndex: Int32
}

final class GroupWhisperSession {
    init(groupID: GroupID, service: CoreService, keyStore: KeyStore) {
        self.groupID = groupID
        self.service = service
        self.keyStore = keyStore
        self.state = .empty
        DDLogInfo("GroupWhisperSession/\(groupID) - state: \(self.state)")
        // Read from coredata and update
        self.state = loadFromKeyStore(for: groupID)
        DDLogInfo("GroupWhisperSession/\(groupID) - state: \(self.state)")
    }

    let groupID: GroupID
    private var keyStore: KeyStore
    private var state: GroupWhisperState {
        didSet {
            switch state {
            case .awaitingSetup(let attempts, _):
                DDLogInfo("GroupWhisperSession/set-state/awaitingSetup/attempts: \(attempts)")
                DDLogInfo("GroupWhisperSession/set-state/saving keybundle")
                keyStore.saveGroupSessionKeyBundle(groupID: groupID, state: .awaitingSetup, groupKeyBundle: state.keyBundle)
            case .retrievingKeys(_):
                DDLogInfo("GroupWhisperSession/set-state/retrievingKeys")
            case .updatingHash(let attempts, _):
                DDLogInfo("GroupWhisperSession/set-state/updatingHash/attempts: \(attempts)")
            case .ready(_):
                DDLogInfo("GroupWhisperSession/set-state/ready")
                DDLogInfo("GroupWhisperSession/set-state/saving keybundle")
                keyStore.saveGroupSessionKeyBundle(groupID: groupID, state: .ready, groupKeyBundle: state.keyBundle)
            case .empty:
                DDLogInfo("GroupWhisperSession/set-state/empty")
                return
            }
        }
    }
    private let service: CoreService
    private lazy var sessionQueue = { DispatchQueue(label: "com.halloapp.groupCrypto-\(groupID)", qos: .userInitiated) }()
    private var pendingTasks = [GroupCryptoTask]()

    public func encrypt(_ data: Data, completion: @escaping GroupEncryptionCompletion) {
        let dispatchedCompletion = { result in
            DispatchQueue.main.async { completion(result) }
        }
        sessionQueue.async {
            self.pendingTasks.append(.encryption(data, dispatchedCompletion))
            self.executeTasks()
        }
    }

    public func decrypt(_ data: Data, from userID: UserID, with senderState: Clients_SenderState?, completion: @escaping GroupDecryptionCompletion) {
        let dispatchedCompletion = { result in
            DispatchQueue.main.async { completion(result) }
        }
        sessionQueue.async {
            self.pendingTasks.append(.decryption(data, userID, senderState, dispatchedCompletion))
            self.executeTasks()
        }
    }

    public func addMembers(userIds: [UserID]) {
        sessionQueue.async {
            self.pendingTasks.append(.membersAdded(userIds))
            self.executeTasks()
        }
    }

    public func removeMembers(userIds: [UserID]) {
        sessionQueue.async {
            self.pendingTasks.append(.membersRemoved(userIds))
            self.executeTasks()
        }
    }

    public func removePending(userIds: [UserID]) {
        sessionQueue.async {
            self.pendingTasks.append(.removePending(userIds))
            self.executeTasks()
        }
    }

    public func updateAudienceHash() {
        sessionQueue.async {
            self.pendingTasks.append(.updateAudienceHash)
            self.executeTasks()
        }
    }

    public func updateSenderState(with senderState: Clients_SenderState?, for userID: UserID) {
        guard let senderState = senderState else {
            DDLogError("GroupWhisperSession/updateSenderState/\(groupID)/userID: \(userID)/senderState is empty")
            return
        }
        sessionQueue.async {
            self.pendingTasks.append(.updateSenderState(userID, senderState))
            self.executeTasks()
        }
    }

    public func fetchSenderState(completion: @escaping GroupSenderStateCompletion) {
        let dispatchedCompletion = { result in
            DispatchQueue.main.async { completion(result) }
        }
        sessionQueue.async {
            self.pendingTasks.append(.fetchSenderState(dispatchedCompletion))
            self.executeTasks()
        }
    }

    // MARK: Private
    // MARK: *All private functions should be called on sessionQueue!*

    private enum GroupWhisperState {
        case empty
        case awaitingSetup(attempts: Int, incomingSession: GroupIncomingSession?)
        case retrievingKeys(incomingSession: GroupIncomingSession?)
        case updatingHash(attempts: Int, keyBundle: GroupKeyBundle)
        case ready(keyBundle: GroupKeyBundle)

        var keyBundle: GroupKeyBundle {
            switch self {
            case .empty:
                return GroupKeyBundle(outgoingSession: nil, incomingSession: incomingSession, pendingUids: [])
            case .awaitingSetup(_, let incomingSession):
                return GroupKeyBundle(outgoingSession: nil, incomingSession: incomingSession, pendingUids: [])
            case .retrievingKeys(let incomingSession):
                return GroupKeyBundle(outgoingSession: nil, incomingSession: incomingSession, pendingUids: [])
            case .updatingHash(_, let keyBundle):
                return keyBundle
            case .ready(let keyBundle):
                return keyBundle
            }
        }

        var failedSetupAttempts: Int? {
            switch self {
            case .awaitingSetup(let attempts, _):
                return attempts
            case .ready, .retrievingKeys, .updatingHash, .empty:
                return nil
            }
        }

        var failedUpdateHashAttempts: Int? {
            switch self {
            case .updatingHash(let attempts, _):
                return attempts
            case .ready, .retrievingKeys, .awaitingSetup, .empty:
                return nil
            }
        }

        var incomingSession: GroupIncomingSession? {
            switch self {
            case .awaitingSetup(_, let session):
                return session
            case .retrievingKeys(let session):
                return session
            case .updatingHash(_, let keyBundle):
                return keyBundle.incomingSession
            case .ready(let keyBundle):
                return keyBundle.incomingSession
            case .empty:
                return nil
            }
        }
    }

    private func executeTasks() {
        while let task = pendingTasks.first {
            // TODO: murali@: update this log to only log the state here.
            DDLogInfo("GroupWhisperSession/executeTasks/\(groupID)/state: \(state) - task: \(task)")
            switch state {

            case .empty:
                DDLogError("GroupWhisperSession/\(groupID)/execute/task - InvalidState - pausing")
                return
            case .awaitingSetup(let setupAttempts, _):
                // We pause encryption when in this state, since we are still setting up outbound session.
                // Decryption can continue fine. removingMembers should clear that user's keys.
                // addingMembers/removingPendingUids/updating hash will be taken care when outbound is setup.
                switch task {
                case .encryption(_, let completion):
                    guard setupAttempts < 3 else {
                        DDLogInfo("GroupWhisperSession/\(groupID)/execute/encryption outbound setup failed \(setupAttempts) times")
                        completion(.failure(.missingKeyBundle))
                        return
                    }
                    DDLogInfo("GroupWhisperSession/\(groupID)/execute/pausing (needs outbound setup)")
                    setupOutbound()
                    return
                case .decryption(let data, let userID, let incomingSenderState, let completion):
                    DDLogInfo("GroupWhisperSession/\(groupID)/execute/decrypting")
                    executeDecryption(data, from: userID, with: incomingSenderState, completion: completion)
                case .membersAdded(let memberUserids):
                    DDLogInfo("GroupWhisperSession/\(groupID)/execute/membersAdded: \(memberUserids.count) - ignoring")
                case .membersRemoved(let memberUserids):
                    DDLogInfo("GroupWhisperSession/\(groupID)/execute/membersRemoved: \(memberUserids.count)")
                    executeRemoveMembers(userIds: memberUserids)
                case .removePending(let memberUserids):
                    DDLogInfo("GroupWhisperSession/\(groupID)/execute/removePending \(memberUserids.count) - ignoring")
                case .updateAudienceHash:
                    DDLogInfo("GroupWhisperSession/\(groupID)/execute/updateAudienceHash - ignoring")
                case .fetchSenderState(let completion):
                    guard setupAttempts < 3 else {
                        DDLogInfo("GroupWhisperSession/\(groupID)/execute/fetchSenderState outbound setup failed \(setupAttempts) times")
                        completion(.failure(.missingKeyBundle))
                        return
                    }
                    DDLogInfo("GroupWhisperSession/\(groupID)/execute/pausing (needs outbound setup)")
                    setupOutbound()
                    return
                case .updateSenderState(let userID, let senderState):
                    DDLogInfo("GroupWhisperSession/\(groupID)/execute/updateSenderState")
                    updateIncomingSession(from: userID, with: senderState)
                }

            // We pause all tasks in this state because we are working on a serviceRequest here.
            case .retrievingKeys:
                DDLogInfo("GroupWhisperSession/\(groupID)/execute/pausing all (retrievingKeys)")
                return

            // We pause all tasks in this state because we are working on a serviceRequest here.
            case .updatingHash(_, _):
                DDLogInfo("GroupWhisperSession/\(groupID)/execute/pausing all (updatingHash)")
                return

            case .ready(let groupKeyBundle):
                switch task {
                case .encryption(let data, let completion):
                    DDLogInfo("GroupWhisperSession/\(groupID)/execute/encrypting")
                    executeEncryption(data, pendingUids: groupKeyBundle.pendingUids,  completion: completion)
                case .decryption(let data, let userID, let incomingSenderState, let completion):
                    DDLogInfo("GroupWhisperSession/\(groupID)/execute/decrypting")
                    executeDecryption(data, from: userID, with: incomingSenderState, completion: completion)
                case .membersAdded(let memberUserids):
                    DDLogInfo("GroupWhisperSession/\(groupID)/execute/membersAdded: \(memberUserids.count)")
                    executeAddMembers(userIds: memberUserids)
                case .membersRemoved(let memberUserids):
                    DDLogInfo("GroupWhisperSession/\(groupID)/execute/membersRemoved: \(memberUserids.count)")
                    executeRemoveMembers(userIds: memberUserids)
                case .removePending(let memberUserids):
                    DDLogInfo("GroupWhisperSession/\(groupID)/execute/removePending: \(memberUserids.count)")
                    executeRemovePending(userIds: memberUserids)
                case .updateAudienceHash:
                    DDLogInfo("GroupWhisperSession/\(groupID)/execute/updateAudienceHash")
                    executeUpdateAudienceHash()
                case .fetchSenderState(let completion):
                    DDLogInfo("GroupWhisperSession/\(groupID)/execute/fetchSenderState")
                    executeFetchSenderState(completion: completion)
                case .updateSenderState(let userID, let senderState):
                    DDLogInfo("GroupWhisperSession/\(groupID)/execute/updateSenderState")
                    updateIncomingSession(from: userID, with: senderState)
                }
            }
            pendingTasks.removeFirst()
        }
    }

    private func executeAddMembers(userIds: [UserID]) {
        DDLogInfo("GroupWhisperSession/executeAddMembers/\(groupID)/state: \(state)")
        switch state {
        case .ready(var groupKeyBundle):
            groupKeyBundle.pendingUids.append(contentsOf: userIds)
            self.state = .ready(keyBundle: groupKeyBundle)
        default:
            DDLogError("GroupWhisperSession/executeRemoveMembers/\(groupID)/Invalid state")
            return
        }
        executeUpdateAudienceHash()
    }

    private func executeRemoveMembers(userIds: [UserID]) {
        DDLogInfo("GroupWhisperSession/executeRemoveMembers/\(groupID)/state: \(state)")
        switch state {
        case .empty, .retrievingKeys, .updatingHash:
            DDLogError("GroupWhisperSession/executeRemoveMembers/\(groupID)/Invalid state")
            return
        case .awaitingSetup(let attempts, var incomingSession):
            for userId in userIds {
                incomingSession?.senderStates[userId] = nil
            }
            state = .awaitingSetup(attempts: attempts, incomingSession: incomingSession)
        case .ready(var groupKeyBundle):
            for userId in userIds {
                groupKeyBundle.incomingSession?.senderStates[userId] = nil
            }
            state = .ready(keyBundle: groupKeyBundle)
        }
        if userIds.contains(AppContext.shared.userData.userId) {
            clearOutbound()
        } else {
            setupOutbound()
        }
    }

    private func executeRemovePending(userIds: [UserID]) {
        // It is possible that before we recieved a success response for the publish iq.
        // We might have gotten an add member/remove member event here.
        // so we need to act accordingly and remove pendingUids only if our current list is the same.
        // TODO: murali@: think more if we have to remove these Uids if the list is different.
        DDLogInfo("GroupWhisperSession/executeRemovePending/\(groupID)/state: \(state)")
        switch state {
        case .empty, .awaitingSetup, .retrievingKeys, .updatingHash:
            DDLogError("GroupWhisperSession/executeRemovePending/\(groupID)/Invalid state")
            return
        case .ready(var groupKeyBundle):
            if Set(groupKeyBundle.pendingUids) == Set(userIds) {
                groupKeyBundle.pendingUids = []
            }
            DDLogInfo("GroupWhisperSession/executeRemovePending/\(groupID)/finalPendingUids: \(groupKeyBundle.pendingUids)")
            state = .ready(keyBundle: groupKeyBundle)
        }
    }

    private func executeEncryption(_ data: Data, pendingUids: [UserID], completion: GroupEncryptionCompletion) {
        DDLogInfo("GroupWhisperSession/executeEncryption/\(groupID)/begin/pendingUids: \(pendingUids)")
        let keyBundle = self.state.keyBundle
        guard let outgoingSession = keyBundle.outgoingSession else {
            DDLogError("GroupWhisperSession/executeEncryption/\(groupID)/empty outgoing session")
            completion(.failure(.missingKeyBundle))
            return
        }

        let result = Whisper.signAndEncrypt(data, session: outgoingSession)
        switch result {
        case .success(let (data, chainKey)):
            var newOutgoingSession = outgoingSession
            newOutgoingSession.senderKey.chainKey = chainKey
            newOutgoingSession.currentChainIndex += 1
            let updatedKeyBundle = GroupKeyBundle(outgoingSession: newOutgoingSession,
                                                  incomingSession: keyBundle.incomingSession,
                                                  pendingUids: keyBundle.pendingUids)
            let output: GroupEncryptedData = {
                if pendingUids.isEmpty {
                    return GroupEncryptedData(data: data,
                                              senderKey: nil,
                                              chainIndex: nil,
                                              audienceHash: updatedKeyBundle.outgoingSession?.audienceHash,
                                              receiverUids: pendingUids)
                } else {
                    return GroupEncryptedData(data: data,
                                              senderKey: outgoingSession.senderKey, // send keys that were used for encryption
                                              chainIndex: outgoingSession.currentChainIndex, // send status that were used for encryption
                                              audienceHash: updatedKeyBundle.outgoingSession?.audienceHash,
                                              receiverUids: pendingUids)
                }
            }()
            self.state = .ready(keyBundle: updatedKeyBundle)
            DDLogInfo("GroupWhisperSession/executeEncryption/\(groupID)/success")
            completion(.success(output))
        case .failure(let error):
            DDLogError("GroupWhisperSession/executeEncryption/\(groupID)/error \(error)")
            completion(.failure(error))
        }
    }

    private func executeDecryption(_ encryptedData: Data, from userID: UserID, with incomingSenderState: Clients_SenderState?, completion: GroupDecryptionCompletion) {
        DDLogInfo("GroupWhisperSession/executeDecryption/\(groupID)/begin/from: \(userID)")
        updateIncomingSession(from: userID, with: incomingSenderState)
        let keyBundle = self.state.keyBundle
        guard let payload = EncryptedGroupPayload(data: encryptedData) else {
            DDLogError("GroupWhisperSession/executeDecryption/\(groupID)/error invalidPayload")
            completion(.failure(.invalidPayload))
            return
        }

        guard let groupIncomingSession = keyBundle.incomingSession else {
            DDLogError("GroupWhisperSession/executeDecryption/\(groupID)/error groupIncomingSession, state: \(state)")
            completion(.failure(.missingSenderState))
            return
        }

        guard let senderState = groupIncomingSession.senderStates[userID] else {
            DDLogError("GroupWhisperSession/executeDecryption/\(groupID)/error missingSenderState")
            completion(.failure(.missingSenderState))
            return
        }

        switch Whisper.decrypt(payload, senderState: senderState) {
        case .success((let data, let updatedSenderState)):
            var newIncomingSession = groupIncomingSession
            newIncomingSession.senderStates[userID] = updatedSenderState
            let updatedKeyBundle = GroupKeyBundle(outgoingSession: keyBundle.outgoingSession,
                                                  incomingSession: newIncomingSession,
                                                  pendingUids: keyBundle.pendingUids)

            let currentState = self.state
            switch currentState {
            case .empty, .updatingHash, .retrievingKeys:
                DDLogError("GroupWhisperSession/executeDecryption/\(groupID)/Invalid state")
                return
            case .ready(_):
                self.state = .ready(keyBundle: updatedKeyBundle)
            case .awaitingSetup(let attempts, _):
                self.state = .awaitingSetup(attempts: attempts, incomingSession: newIncomingSession)
            }

            DDLogInfo("GroupWhisperSession/executeDecryption/\(groupID)/success")
            completion(.success(data))
        case .failure(let failure):
            DDLogError("GroupWhisperSession/executeDecryption/\(groupID)/error \(failure)")
            completion(.failure(failure))
        }
    }

    private func executeFetchSenderState(completion: GroupSenderStateCompletion) {
        DDLogInfo("GroupWhisperSession/executeFetchSenderState/\(groupID)/begin")
        let keyBundle = self.state.keyBundle
        guard let outgoingSession = keyBundle.outgoingSession else {
            DDLogError("GroupWhisperSession/executeEncryption/\(groupID)/empty outgoing session")
            completion(.failure(.missingKeyBundle))
            return
        }

        // send current senderKey and current chainIndex
        // TODO: murali@: check senderKey value.
        let output = GroupSenderState(senderKey: outgoingSession.senderKey,
                                      chainIndex: outgoingSession.currentChainIndex)
        completion(.success(output))
    }

    private func setupOutbound() {
        // TODO: murali@: there is opportunity to improve this by using identity keys of audience locally stored instead of asking server.
        // This was easier to start with for now.

        if case .retrievingKeys = state {
            DDLogInfo("GroupWhisperSession/setupOutbound/\(groupID)/state \(state) returning")
            return
        }
        
        let attemptNumber = 1 + (state.failedSetupAttempts ?? 0)
        state = .retrievingKeys(incomingSession: state.incomingSession)
        
        service.getGroupMemberIdentityKeys(groupID: groupID) { result in
            self.sessionQueue.async {
                switch self.state {
                case .empty:
                    DDLogError("GroupWhisperSession/setupOutbound/\(self.groupID)/Invalid empty state")
                    return
                case .awaitingSetup, .retrievingKeys, .updatingHash:
                    DDLogInfo("GroupWhisperSession/\(self.groupID)/setupOutbound/received-keys")
                case .ready:
                    // It's possible a rerequest or inbound message arrived while we were fetching keys
                    // this is from 1-1 and i think it applies here too.
                    DDLogInfo("GroupWhisperSession/\(self.groupID)/setupOutbound/aborting [session already set up]")
                    return
                }
                
                var members: [UserID] = []
                // Initialize outgoing session if possible
                let outgoingSession: GroupOutgoingSession? = {
                    switch result {
                    case .failure(let error):
                        DDLogError("GroupWhisperSession/\(self.groupID)/setupOutbound/error [\(error)]")
                        return nil
                    case .success(let protoGroupStanza):
                        var memberKeys: [UserID : Data] = [:]
                        for member in protoGroupStanza.members {
                            memberKeys[UserID(member.uid)] = member.identityKey
                            members.append(UserID(member.uid))
                        }
                        DDLogInfo("GroupWhisperSession/setupOutbound/\(self.groupID)/state \(self.state) setting it up")
                        DDLogInfo("GroupWhisperSession/setupOutbound/\(self.groupID)/audienceHash from server: \(protoGroupStanza.audienceHash.toHexString())")
                        return Whisper.setupGroupOutgoingSession(for: self.groupID, memberKeys: memberKeys)
                    }
                }()

                if let outgoingSession = outgoingSession {
                    let groupKeyBundle = GroupKeyBundle(outgoingSession: outgoingSession, incomingSession: self.state.incomingSession, pendingUids: members)
                    DDLogInfo("GroupWhisperSession/setupOutbound/\(self.groupID)/success")
                    self.state = .ready(keyBundle: groupKeyBundle)
                } else {
                    DDLogError("GroupWhisperSession/\(self.groupID)/setupOutbound/failed [\(attemptNumber)]")
                    self.state = .awaitingSetup(attempts: attemptNumber, incomingSession: self.state.incomingSession)
                }

                self.executeTasks()
            }
        }
    }

    private func clearOutbound() {
        DDLogError("GroupWhisperSession/\(self.groupID)/clearOutbound/state: \(state)")
        self.state = .awaitingSetup(attempts: 0, incomingSession: self.state.incomingSession)
    }

    private func executeUpdateAudienceHash() {
        let attemptNumber = 1 + (state.failedUpdateHashAttempts ?? 0)
        switch state {
        case .empty, .retrievingKeys, .awaitingSetup, .updatingHash:
            DDLogError("GroupWhisperSession/executeUpdateAudienceHash/\(groupID)/Invalid state")
            return
        case .ready(let groupKeyBundle):
            DDLogInfo("GroupWhisperSession/executeUpdateAudienceHash/\(groupID)/state \(state) begin")
            state = .updatingHash(attempts: attemptNumber, keyBundle: groupKeyBundle)
        }

        service.getGroupMemberIdentityKeys(groupID: groupID) { result in
            self.sessionQueue.async {
                // Initialize audience hash if possible
                let audienceHash: Data? = {
                    switch result {
                    case .failure(let error):
                        DDLogError("WhisperSession/executeUpdateAudienceHash/\(self.groupID)/error [\(error)]")
                        return nil
                    case .success(let protoGroupStanza):
                        var memberKeys: [UserID : Data] = [:]
                        for member in protoGroupStanza.members {
                            memberKeys[UserID(member.uid)] = member.identityKey
                        }
                        DDLogInfo("GroupWhisperSession/executeUpdateAudienceHash/\(self.groupID)/computing now")
                        return Whisper.computeAudienceHash(memberKeys: memberKeys)
                    }
                }()

                var groupKeyBundle = self.state.keyBundle
                if let hash = audienceHash {
                    if groupKeyBundle.outgoingSession != nil {
                        groupKeyBundle.outgoingSession?.audienceHash = hash
                        DDLogInfo("GroupWhisperSession/executeUpdateAudienceHash/\(self.groupID)/success, audienceHash: \(hash.toHexString())")
                        self.state = .ready(keyBundle: groupKeyBundle)
                    } else {
                        DDLogError("GroupWhisperSession/executeUpdateAudienceHash/\(self.groupID)/outgoingSession is missing")
                        self.state = .awaitingSetup(attempts: 0, incomingSession: groupKeyBundle.incomingSession ?? GroupIncomingSession(senderStates: [:]))
                    }
                } else {
                    DDLogError("GroupWhisperSession/executeUpdateAudienceHash/\(self.groupID)/audienceHash is missing")
                    self.state = .updatingHash(attempts: attemptNumber, keyBundle: self.state.keyBundle)
                }

                self.executeTasks()
            }
        }
    }

    private func updateIncomingSession(from userID: UserID, with incomingSenderState: Clients_SenderState?) {
        // TODO: murali@: this can be improved i think - since we dont expect to run in retrievingKeys/updatingHash state.
        DDLogInfo("GroupWhisperSession/updateIncomingSession/\(groupID)/from \(userID)/begin")
        let groupIncomingSenderState: GroupIncomingSenderState? = {
            if let incomingSenderState = incomingSenderState {
                return GroupIncomingSenderState(senderState: incomingSenderState)
            } else {
                let keyBundle = self.state.keyBundle
                guard let groupIncomingSession = keyBundle.incomingSession else {
                    DDLogError("GroupWhisperSession/updateIncomingSession/\(groupID)/error groupIncomingSession")
                    return nil
                }
                return groupIncomingSession.senderStates[userID]
            }
        }()

        guard let senderState = groupIncomingSenderState else {
            DDLogError("GroupWhisperSession/updateIncomingSession/\(groupID)/error missingSenderState")
            return
        }

        switch self.state {
        case .empty:
            DDLogError("GroupWhisperSession/updateIncomingSession/\(groupID)/Invalid empty state")
            return
        case .awaitingSetup(let setupAttempts, var incomingSession):
            if incomingSession == nil {
                incomingSession = GroupIncomingSession(senderStates: [:])
            }
            incomingSession?.senderStates[userID] = senderState
            self.state = .awaitingSetup(attempts: setupAttempts, incomingSession: incomingSession)

        case .retrievingKeys(var incomingSession):
            if incomingSession == nil {
                incomingSession = GroupIncomingSession(senderStates: [:])
            }
            incomingSession?.senderStates[userID] = senderState
            self.state = .retrievingKeys(incomingSession: incomingSession)

        case .updatingHash(let updateHashAttempts, var groupKeyBundle):
            if groupKeyBundle.incomingSession == nil {
                groupKeyBundle.incomingSession = GroupIncomingSession(senderStates: [:])
            }
            groupKeyBundle.incomingSession?.senderStates[userID] = senderState
            self.state = .updatingHash(attempts: updateHashAttempts, keyBundle: groupKeyBundle)

        case .ready(var groupKeyBundle):
            if groupKeyBundle.incomingSession == nil {
                groupKeyBundle.incomingSession = GroupIncomingSession(senderStates: [:])
            }
            groupKeyBundle.incomingSession?.senderStates[userID] = senderState
            self.state = .ready(keyBundle: groupKeyBundle)
        }
        DDLogInfo("GroupWhisperSession/updateIncomingSession/\(groupID)/from \(userID)/success")

    }

    private func loadFromKeyStore(for groupID: GroupID) -> GroupWhisperState {
        guard let groupSessionKeyBundle = keyStore.groupSessionKeyBundle(for: groupID) else {
            return .awaitingSetup(attempts: 0, incomingSession: GroupIncomingSession(senderStates: [:]))
        }

        let ownUserID = AppContext.shared.userData.userId

        // Obtain all senderStates including own copy.
        var memberSenderStates: [UserID: GroupIncomingSenderState] = [:]
        groupSessionKeyBundle.senderStates?.forEach{ senderState in
            var messageKeys: [Int32: Data] = [:]
            senderState.messageKeys?.forEach { groupMessageKey in
                messageKeys[groupMessageKey.chainIndex] = groupMessageKey.messageKey
            }
            let senderKey = GroupSenderKey(chainKey: senderState.chainKey,
                                           publicSignatureKey: senderState.publicSignatureKey)
            let incomingSenderState = GroupIncomingSenderState(senderKey: senderKey,
                                                               currentChainIndex: Int(senderState.currentChainIndex),
                                                               unusedMessageKeys: messageKeys)
            memberSenderStates[senderState.userId] = incomingSenderState
        }

        // First setup outgoingSession if available.
        var outgoingSession: GroupOutgoingSession? = nil
        if let ownSenderState = memberSenderStates[ownUserID],
           let signKey = groupSessionKeyBundle.privateSignatureKey,
           !signKey.isEmpty {
            let audienceHash = groupSessionKeyBundle.audienceHash ?? nil
            outgoingSession = GroupOutgoingSession(audienceHash: audienceHash, senderKey: ownSenderState.senderKey, currentChainIndex: ownSenderState.currentChainIndex, privateSigningKey: signKey)
        }

        // Remove our own senderState and setup incomingSession
        memberSenderStates.removeValue(forKey: ownUserID)
        let incomingSession = GroupIncomingSession(senderStates: memberSenderStates)

        if let outgoingSession = outgoingSession {
            // Creating groupKeyBundle
            let groupKeyBundle = GroupKeyBundle(outgoingSession: outgoingSession, incomingSession: incomingSession, pendingUids: groupSessionKeyBundle.pendingUserIds)
            switch groupSessionKeyBundle.state {
            case .awaitingSetup:
                return .awaitingSetup(attempts: 0, incomingSession: incomingSession)
            case .ready:
                return .ready(keyBundle: groupKeyBundle)
            }
        } else {
            // Setup correctState accordingly and return
            return .awaitingSetup(attempts: 0, incomingSession: incomingSession)
        }

    }

    public func reloadKeysFromKeyStore() {
        sessionQueue.async {
            self.state = self.loadFromKeyStore(for: self.groupID)
        }
    }

}