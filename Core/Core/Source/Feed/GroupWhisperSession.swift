//
//  GroupWhisperSession.swift
//  Core
//
//  Created by Garrett on 8/18/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import Foundation
import CoreCommon
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
    case encryption(Data, [UserID], GroupEncryptionCompletion)
    case decryption(Data, UserID, Clients_SenderState?, GroupDecryptionCompletion)
    case membersAdded([UserID])
    case membersRemoved([UserID])
    case removePending([UserID])
    case updateAudienceHash
    case fetchSenderState(GroupSenderStateCompletion)
    case updateSenderState(UserID, Clients_SenderState)
    case sync([UserID])
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
    public init(data: Data, senderKey: GroupSenderKey?, chainIndex: Int?, audienceHash: Data, receiverUids: [UserID], senderStateBundles: [Server_SenderStateBundle]) {
        self.data = data
        self.senderKey = senderKey
        self.chainIndex = chainIndex == nil ? nil : Int32(chainIndex!)
        self.audienceHash = audienceHash
        self.receiverUids = receiverUids
        self.senderStateBundles = senderStateBundles
    }

    public var data: Data
    public var senderKey: GroupSenderKey?
    public var chainIndex: Int32?
    public var audienceHash: Data
    public var receiverUids: [UserID]
    public var senderStateBundles: [Server_SenderStateBundle]
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
        updateState(to: loadFromKeyStore(for: groupID))
        DDLogInfo("GroupWhisperSession/\(groupID) - state: \(self.state)")
    }

    let groupID: GroupID
    private var keyStore: KeyStore
    private var state: GroupWhisperState {
        didSet {
            switch state {
            case .awaitingSetup(let attempts, _):
                DDLogInfo("GroupWhisperSession/\(groupID)/set-state/awaitingSetup/attempts: \(attempts)")
            case .retrievingKeys(_):
                DDLogInfo("GroupWhisperSession/\(groupID)/set-state/retrievingKeys")
            case .updatingHash(let attempts, _):
                DDLogInfo("GroupWhisperSession/\(groupID)/set-state/updatingHash/attempts: \(attempts)")
            case .ready(_):
                DDLogInfo("GroupWhisperSession/\(groupID)/set-state/ready")
            case .empty:
                DDLogInfo("GroupWhisperSession/\(groupID)/set-state/empty")
                return
            }
        }
    }
    private let service: CoreService
    private lazy var sessionQueue = { DispatchQueue(label: "com.halloapp.groupCrypto-\(groupID)", qos: .userInitiated) }()
    private var pendingTasks = [GroupCryptoTask]()

    public func encrypt(_ data: Data, potentialMemberUids: [UserID], completion: @escaping GroupEncryptionCompletion) {
        let dispatchedCompletion = { result in
            DispatchQueue.main.async { completion(result) }
        }
        sessionQueue.async {
            self.pendingTasks.append(.encryption(data, potentialMemberUids, dispatchedCompletion))
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

    public func syncGroup(members: [UserID]) {
        sessionQueue.async {
            self.pendingTasks.append(.sync(members))
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
            switch self.state {

            case .empty:
                DDLogError("GroupWhisperSession/\(groupID)/execute/task - InvalidState - pausing")
                return
            case .awaitingSetup(let setupAttempts, _):
                // We pause encryption when in this state, since we are still setting up outbound session.
                // Decryption can continue fine. removingMembers should clear that user's keys.
                // addingMembers/removingPendingUids/updating hash will be taken care when outbound is setup.
                switch task {
                case .encryption(_, _, let completion):
                    guard setupAttempts < 3 else {
                        DDLogError("GroupWhisperSession/\(groupID)/execute/encryption outbound setup failed \(setupAttempts) times")
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
                        DDLogError("GroupWhisperSession/\(groupID)/execute/fetchSenderState outbound setup failed \(setupAttempts) times")
                        completion(.failure(.missingKeyBundle))
                        return
                    }
                    DDLogInfo("GroupWhisperSession/\(groupID)/execute/pausing (needs outbound setup)")
                    setupOutbound()
                    return
                case .updateSenderState(let userID, let senderState):
                    DDLogInfo("GroupWhisperSession/\(groupID)/execute/updateSenderState")
                    updateIncomingSession(from: userID, with: senderState)
                case .sync(let members):
                    DDLogInfo("GroupWhisperSession/\(groupID)/execute/sync - \(members.count)")
                    sync(members: members)
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
                case .encryption(let data, let potentialMemberUids, let completion):
                    DDLogInfo("GroupWhisperSession/\(groupID)/execute/encrypting")
                    checkAndExecuteEncryption(data, pendingUids: groupKeyBundle.pendingUids, potentialMemberUids: potentialMemberUids,  completion: completion)
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
                case .sync(let members):
                    DDLogInfo("GroupWhisperSession/\(groupID)/execute/sync - \(members.count)")
                    sync(members: members)
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
            updateState(to: .ready(keyBundle: groupKeyBundle), saveToKeyStore: true)
        default:
            DDLogError("GroupWhisperSession/executeAddMembers/\(groupID)/Invalid state")
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
            // Remove these members from pendingUids if any.
            groupKeyBundle.pendingUids = groupKeyBundle.pendingUids.filter { !userIds.contains($0) }
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

    private func checkAndExecuteEncryption(_ data: Data, pendingUids: [UserID], potentialMemberUids: [UserID], completion: @escaping GroupEncryptionCompletion) {
        // State will always be ready - when we run this function.
        var groupKeyBundle = self.state.keyBundle
        // Make sure pending UIDs are active group members before encrypting.
        AppContext.shared.mainDataStore.performSeriallyOnBackgroundContext { [weak self] context in
            guard let self = self else { return }
            let memberUserIds = AppContext.shared.coreChatData.chatGroupMemberUserIds(for: self.groupID, in: context)
            let memberSet = Set(memberUserIds)
            let currentPendingUserIds = groupKeyBundle.pendingUids
            let currentPendingUidSet = Set(currentPendingUserIds)
            // Ensure PendingUidSet is a subset of group-members.
            // Else - cleanup PendingUid list.
            if !currentPendingUidSet.isSubset(of: memberSet) {
                DDLogError("GroupWhisperSession/\(self.groupID)/error with pendingUids/currentPendingUserIds: \(currentPendingUserIds)/memberUserIds: \(memberUserIds)")
                AppContext.shared.errorLogger?.logError(NSError(domain: "GroupWhisperEncryptionError", code: 1007))
                let pendingUids = Array(currentPendingUidSet.intersection(memberSet))
                // Cleanup pendingUids to only have members.
                groupKeyBundle.pendingUids = pendingUids
            }
            self.state = .ready(keyBundle: groupKeyBundle)
            self.executeEncryption(data, pendingUids: groupKeyBundle.pendingUids, potentialMemberUids: potentialMemberUids,  completion: completion)
        }
    }

    private func executeEncryption(_ data: Data, pendingUids: [UserID], potentialMemberUids: [UserID], completion: @escaping GroupEncryptionCompletion) {
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
            guard let audienceHash = newOutgoingSession.audienceHash else {
                DDLogError("GroupWhisperSession/executeEncryption/\(groupID)/failure")
                completion(.failure(.missingAudienceHash))
                return
            }
            constructGroupEncryptedData(data,
                                        senderKey: outgoingSession.senderKey,
                                        chainIndex: outgoingSession.currentChainIndex,
                                        audienceHash: audienceHash,
                                        pendingUids: pendingUids + potentialMemberUids) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success:
                    self.updateState(to: .ready(keyBundle: updatedKeyBundle), saveToKeyStore: true)
                    DDLogInfo("GroupWhisperSession/executeEncryption/\(self.groupID)/success")
                case .failure(let error):
                    DDLogError("GroupWhisperSession/executeEncryption/\(self.groupID)/failure: \(error)")
                }
                completion(result)
            }
        case .failure(let error):
            DDLogError("GroupWhisperSession/executeEncryption/\(groupID)/error \(error)")
            completion(.failure(error))
        }
    }

    private func constructGroupEncryptedData(_ data: Data,
                                             senderKey: GroupSenderKey?,
                                             chainIndex: Int?,
                                             audienceHash: Data,
                                             pendingUids: [UserID],
                                             completion: @escaping (Result<GroupEncryptedData, EncryptionError>) -> Void) {
        do {
            var senderStateBundles: [Server_SenderStateBundle] = []
            var numberOfFailedEncrypts = 0
            let encryptGroup = DispatchGroup()
            let encryptCompletion: (Result<(EncryptedData, EncryptionLogInfo), EncryptionError>) -> Void = { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .failure(.invalidUid):
                    // not really an error - so we dont count it towards failed encryptions.
                    DDLogInfo("ProtoServiceCore/makeGroupEncryptedPayload/\(self.groupID)/encryptCompletion/accountDeleted/failed:  \(numberOfFailedEncrypts)")
                    break
                case .failure(let error):
                    numberOfFailedEncrypts += 1
                    DDLogError("ProtoServiceCore/makeGroupEncryptedPayload/\(self.groupID)/encryptCompletion/error: \(error)/failed: \(numberOfFailedEncrypts)")
                default:
                    break
                }
                encryptGroup.leave()
            }
            guard let chainKey = senderKey?.chainKey,
                  let signKey = senderKey?.publicSignatureKey,
                  let chainIndex = chainIndex else {
                      completion(.failure(.missingKeyBundle))
                      return
                  }

            // construct own senderState
            var clientSenderKey = Clients_SenderKey()
            clientSenderKey.chainKey = chainKey
            clientSenderKey.publicSignatureKey = signKey
            var senderState = Clients_SenderState()
            senderState.senderKey = clientSenderKey
            senderState.currentChainIndex = Int32(chainIndex)
            let senderStatePayload = try senderState.serializedData()

            // encrypt senderState using 1-1 channel for all the receivers.
            for receiverUserID in pendingUids {
                encryptGroup.enter()
                AppContext.shared.messageCrypter.encrypt(senderStatePayload, for: receiverUserID) { [weak self] result in
                    guard let self = self else { return }
                    var senderStateWithKeyInfo = Server_SenderStateWithKeyInfo()
                    var senderStateBundle = Server_SenderStateBundle()
                    senderStateBundle.uid = Int64(receiverUserID) ?? 0
                    switch result {
                    case .failure(_):
                        DDLogError("ProtoServiceCore/makeGroupEncryptedPayload/\(self.groupID)/failed to encrypt for userID: \(receiverUserID)")
                        break
                    case .success((let encryptedData, _)):
                        if let publicKey = encryptedData.identityKey, !publicKey.isEmpty {
                            senderStateWithKeyInfo.publicKey = publicKey
                            senderStateWithKeyInfo.oneTimePreKeyID = Int64(encryptedData.oneTimeKeyId)
                        }
                        senderStateWithKeyInfo.encSenderState = encryptedData.data
                    }
                    senderStateBundle.senderState = senderStateWithKeyInfo
                    senderStateBundles.append(senderStateBundle)
                    encryptCompletion(result)
                }
            }

            encryptGroup.notify(queue: .main) {
                // After successfully obtaining the senderStateBundles
                // return groupEncryptedData properly.
                if numberOfFailedEncrypts > 0 {
                    completion(.failure(.missingEncryptedSenderState))
                } else {
                    // send keys that were used for encryption
                    completion(.success(GroupEncryptedData(data: data,
                                                           senderKey: senderKey,
                                                           chainIndex: chainIndex,
                                                           audienceHash: audienceHash,
                                                           receiverUids: pendingUids,
                                                           senderStateBundles: senderStateBundles)))
                }
            }
        } catch {
            completion(.failure(.serialization))
        }
    }

    private func executeDecryption(_ encryptedData: Data, from userID: UserID, with incomingSenderState: Clients_SenderState?, completion: @escaping GroupDecryptionCompletion) {
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
                updateState(to: .ready(keyBundle: updatedKeyBundle), saveToKeyStore: true)
            case .awaitingSetup(let attempts, _):
                updateState(to: .awaitingSetup(attempts: attempts, incomingSession: newIncomingSession), saveToKeyStore: true)
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
        let ownUserID = AppContext.shared.userData.userId

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
                    let pendingUids = members.filter{ $0 != ownUserID }
                    let groupKeyBundle = GroupKeyBundle(outgoingSession: outgoingSession, incomingSession: self.state.incomingSession, pendingUids: pendingUids)
                    DDLogInfo("GroupWhisperSession/setupOutbound/\(self.groupID)/success")
                    self.updateState(to: .ready(keyBundle: groupKeyBundle), saveToKeyStore: true)
                } else {
                    DDLogError("GroupWhisperSession/\(self.groupID)/setupOutbound/failed [\(attemptNumber)]")
                    self.updateState(to: .awaitingSetup(attempts: attemptNumber, incomingSession: self.state.incomingSession), saveToKeyStore: true)
                }

                self.executeTasks()
            }
        }
    }

    private func clearOutbound() {
        DDLogError("GroupWhisperSession/\(self.groupID)/clearOutbound/state: \(state)")
        updateState(to: .awaitingSetup(attempts: 0, incomingSession: self.state.incomingSession), saveToKeyStore: true)
    }

    private func executeUpdateAudienceHash() {
        // Currently, we always try to update our hash exactly once.
        // If this request fails for some reason: then we move-on and
        // correct our hash next time when we get rejected by the server.
        // TODO: We could try having a limit (say 3 times): similar to setting up outbound keys.
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
                var members: [UserID] = []
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
                            members.append(UserID(member.uid))
                        }
                        DDLogInfo("GroupWhisperSession/executeUpdateAudienceHash/\(self.groupID)/computing now")
                        return Whisper.computeAudienceHash(memberKeys: memberKeys)
                    }
                }()

                var groupKeyBundle = self.state.keyBundle
                if let hash = audienceHash {
                    if groupKeyBundle.outgoingSession != nil {
                        // It is possible that group-membership also changed at this point.
                        // So we should be sending our sender-state to some members if necessary.
                        // Let us pre-emptively send it to all members from whom we dont have an incoming session.
                        // Also we remove non-members from our pendingUids list - since they are no longer members.
                        // This should help improve group-encryption when we have a lot of group-membership and posting activity going on.
                        let currentPending = groupKeyBundle.pendingUids
                        let oldMemberUids = groupKeyBundle.incomingSession?.senderStates.map { $0.key } ?? []
                        let newPendingUids = members.filter { member in
                            // return true if we dont have an incoming sender state for this user.
                            // or
                            // return true if this was a pendingUid from the old state.
                            // either-way we ensure that only members are being added to the pendingUid set.
                            !oldMemberUids.contains(member) || currentPending.contains(member)
                        }
                        groupKeyBundle.pendingUids = newPendingUids
                        groupKeyBundle.outgoingSession?.audienceHash = hash
                        DDLogInfo("GroupWhisperSession/executeUpdateAudienceHash/\(self.groupID)/success, audienceHash: \(hash.toHexString())")
                        self.updateState(to: .ready(keyBundle: groupKeyBundle), saveToKeyStore: true)
                    } else {
                        DDLogError("GroupWhisperSession/executeUpdateAudienceHash/\(self.groupID)/outgoingSession is missing")
                        self.updateState(to: .awaitingSetup(attempts: 0, incomingSession: groupKeyBundle.incomingSession ?? GroupIncomingSession(senderStates: [:])), saveToKeyStore: true)
                    }
                } else {
                    DDLogError("GroupWhisperSession/executeUpdateAudienceHash/\(self.groupID)/updatingHash - failed, so moving on!")
                    self.updateState(to: .ready(keyBundle: groupKeyBundle))
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
            self.updateState(to: .awaitingSetup(attempts: setupAttempts, incomingSession: incomingSession), saveToKeyStore: true)

        case .retrievingKeys(var incomingSession):
            if incomingSession == nil {
                incomingSession = GroupIncomingSession(senderStates: [:])
            }
            incomingSession?.senderStates[userID] = senderState
            self.state = .retrievingKeys(incomingSession: incomingSession)
            self.updateState(to: .retrievingKeys(incomingSession: incomingSession))

        case .updatingHash(let updateHashAttempts, var groupKeyBundle):
            if groupKeyBundle.incomingSession == nil {
                groupKeyBundle.incomingSession = GroupIncomingSession(senderStates: [:])
            }
            groupKeyBundle.incomingSession?.senderStates[userID] = senderState
            self.updateState(to: .updatingHash(attempts: updateHashAttempts, keyBundle: groupKeyBundle))

        case .ready(var groupKeyBundle):
            if groupKeyBundle.incomingSession == nil {
                groupKeyBundle.incomingSession = GroupIncomingSession(senderStates: [:])
            }
            groupKeyBundle.incomingSession?.senderStates[userID] = senderState
            self.updateState(to: .ready(keyBundle: groupKeyBundle), saveToKeyStore: true)
        }
        DDLogInfo("GroupWhisperSession/updateIncomingSession/\(groupID)/from \(userID)/success")

    }

    private func sync(members: [UserID]) {
        DDLogInfo("GroupWhisperSession/sync/\(groupID)/members: \(members)/begin")
        let membersSet = Set(members)

        var groupKeyBundle = self.state.keyBundle
        if groupKeyBundle.incomingSession == nil {
            groupKeyBundle.incomingSession = GroupIncomingSession(senderStates: [:])
        }
        // Clear out sender-states for non-members.
        let currentUids = groupKeyBundle.incomingSession?.senderStates.map { $0.key }
        currentUids?.forEach { userID in
            if !membersSet.contains(userID) {
                groupKeyBundle.incomingSession?.senderStates[userID] = nil
            }
        }
        groupKeyBundle.pendingUids = groupKeyBundle.pendingUids.filter { membersSet.contains($0) }

        switch self.state {
        case .empty:
            DDLogError("GroupWhisperSession/sync/\(groupID)/Invalid empty state")
            return
        case .awaitingSetup(let setupAttempts, _):
            self.updateState(to: .awaitingSetup(attempts: setupAttempts, incomingSession: groupKeyBundle.incomingSession), saveToKeyStore: true)
        case .retrievingKeys:
            self.updateState(to: .retrievingKeys(incomingSession: groupKeyBundle.incomingSession))
        case .updatingHash(let updateHashAttempts, _):
            self.updateState(to: .updatingHash(attempts: updateHashAttempts, keyBundle: groupKeyBundle))
        case .ready(_):
            self.updateState(to: .ready(keyBundle: groupKeyBundle), saveToKeyStore: true)
        }
        DDLogInfo("GroupWhisperSession/sync/\(groupID)/success")

    }

    private func loadFromKeyStore(for groupID: GroupID) -> GroupWhisperState {
        var localState: GroupWhisperState = .awaitingSetup(attempts: 0, incomingSession: GroupIncomingSession(senderStates: [:]))
        keyStore.performOnBackgroundContextAndWait { context in
            guard let groupSessionKeyBundle = keyStore.groupSessionKeyBundle(for: groupID, in: context) else {
                return
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
                    localState = .awaitingSetup(attempts: 0, incomingSession: incomingSession)
                case .ready:
                    localState = .ready(keyBundle: groupKeyBundle)
                }
            } else {
                // Setup correctState accordingly and return
                localState = .awaitingSetup(attempts: 0, incomingSession: incomingSession)
            }
        }
        return localState
    }

    public func reloadKeysFromKeyStore() {
        sessionQueue.async {
            self.updateState(to: self.loadFromKeyStore(for: self.groupID))
        }
    }

    private func updateState(to state: GroupWhisperState, saveToKeyStore: Bool = false) {
        self.state = state
        if saveToKeyStore {
            switch state {
            case .awaitingSetup(_, _):
                DDLogInfo("GroupWhisperSession/\(groupID)/set-state/saving keybundle \(state)")
                keyStore.checkAndSaveGroupSessionKeyBundle(groupID: groupID, state: .awaitingSetup, groupKeyBundle: state.keyBundle)
            case .ready(_):
                DDLogInfo("GroupWhisperSession/\(groupID)/set-state/saving keybundle \(state)")
                keyStore.checkAndSaveGroupSessionKeyBundle(groupID: groupID, state: .ready, groupKeyBundle: state.keyBundle)
            default:
                break
            }
        }
    }

}
