//
//  HomeWhisperSession.swift
//  Core
//
//  Created by Murali on 6/19/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import Foundation
import CoreCommon
import CocoaLumberjackSwift
import CoreData

public typealias HomePostEncryptionCompletion = (Result<HomeEncryptedData, EncryptionError>) -> Void
public typealias HomeCommentEncryptionCompletion = (Result<Data, EncryptionError>) -> Void
public typealias HomeDecryptionCompletion = (Result<Data, DecryptionError>) -> Void
public typealias HomeSenderStateCompletion = (Result<HomeSenderState, EncryptionError>) -> Void
public typealias HomeCommentKeyCompletion = (Result <Data, EncryptionError>) -> Void

public struct HomeIncomingSession {
    var senderStates: [UserID: IncomingSenderState]
}

public struct HomeOutgoingSession {
    var senderKey: SenderKey
    var currentChainIndex: Int
    var privateSigningKey: Data
}

private enum HomeCryptoTask {
    case postEncryption(Data, FeedPostID, [UserID], HomePostEncryptionCompletion)
    case commentEncryption(Data, FeedPostID, HomeCommentEncryptionCompletion)
    case postDecryption(Data, UserID, FeedPostID, Clients_SenderState?, HomeDecryptionCompletion)
    case commentDecryption(Data, UserID, FeedPostID, HomeDecryptionCompletion)
    case membersAdded([UserID])
    case membersRemoved([UserID])
    case removePending([UserID])
    case fetchSenderState(HomeSenderStateCompletion)
    case updateSenderState(UserID, Clients_SenderState)
    case fetchCommentKey(FeedPostID, HomeCommentKeyCompletion)
}

public struct HomeKeyBundle {
    var outgoingSession: HomeOutgoingSession?
    var incomingSession: HomeIncomingSession?
    // List of memberUids in the audience: who need to be notified of the senderState on the next publish action.
    var pendingUids: [UserID]
    // List of memberUids in the audience: useful to keep track of members who have this senderState.
    var audienceUids: [UserID]
}

public enum HomeSessionType: Int16 {
    case all = 0
    case favorites = 1
}

extension HomeSessionType {
    var rawStringValue: String {
        switch self {
        case .all:
            return "all"
        case .favorites:
            return "favorites"
        }
    }
}

public enum HomeSessionState: Int16 {
    case awaitingSetup = 0
    case ready = 1
}

public struct HomeEncryptedData {
    public init(data: Data, senderKey: SenderKey?, chainIndex: Int?, receiverUids: [UserID], senderStateBundles: [Server_SenderStateBundle]) {
        self.data = data
        self.senderKey = senderKey
        self.chainIndex = chainIndex.flatMap { Int32($0) }
        self.receiverUids = receiverUids
        self.senderStateBundles = senderStateBundles
    }

    public var data: Data
    public var senderKey: SenderKey?
    public var chainIndex: Int32?
    public var receiverUids: [UserID]
    public var senderStateBundles: [Server_SenderStateBundle]
}

public struct HomeSenderState {
    public init(senderKey: SenderKey, chainIndex: Int) {
        self.senderKey = senderKey
        self.chainIndex = Int32(chainIndex)
    }

    public var senderKey: SenderKey
    public var chainIndex: Int32
}


final class HomeWhisperSession {
    init(type: HomeSessionType, service: CoreService, keyStore: KeyStore) {
        self.type = type
        self.service = service
        self.keyStore = keyStore
        self.state = .empty
        DDLogInfo("HomeWhisperSession/\(type) - state: \(self.state)")
        // Read from coredata and update
        updateState(to: loadFromKeyStore(for: type))
        DDLogInfo("HomeWhisperSession/\(type) - state: \(self.state)")
    }

    let type: HomeSessionType
    private var keyStore: KeyStore
    private var state: HomeWhisperState {
        didSet {
            switch state {
            case .awaitingSetup(let attempts, _, _):
                DDLogInfo("HomeWhisperSession/\(type)/set-state/awaitingSetup/attempts: \(attempts)")
            case .retrievingKeys(_, _):
                DDLogInfo("HomeWhisperSession/\(type)/set-state/retrievingKeys")
            case .ready(_):
                DDLogInfo("HomeWhisperSession/\(type)/set-state/ready")
            case .empty:
                DDLogInfo("HomeWhisperSession/\(type)/set-state/empty")
                return
            }
        }
    }
    private let service: CoreService
    private lazy var sessionQueue = { DispatchQueue(label: "com.halloapp.homeCrypto-\(type.rawStringValue)", qos: .userInitiated) }()
    private var pendingTasks = [HomeCryptoTask]()

    public func encryptPost(_ data: Data, postID: FeedPostID, audienceMemberUids: [UserID], completion: @escaping HomePostEncryptionCompletion) {
        let dispatchedCompletion = { result in
            DispatchQueue.main.async { completion(result) }
        }
        let ownUserID = AppContext.shared.userData.userId
        let filteredAudienceUserIds = audienceMemberUids.filter{ $0 != ownUserID }
        sessionQueue.async {
            self.pendingTasks.append(.postEncryption(data, postID, filteredAudienceUserIds, dispatchedCompletion))
            self.executeTasks()
        }
    }

    public func encryptComment(_ data: Data, postID: FeedPostID, completion: @escaping HomeCommentEncryptionCompletion) {
        let dispatchedCompletion = { result in
            DispatchQueue.main.async { completion(result) }
        }
        sessionQueue.async {
            self.pendingTasks.append(.commentEncryption(data, postID, dispatchedCompletion))
            self.executeTasks()
        }
    }

    public func decryptPost(_ data: Data, from userID: UserID, postID: FeedPostID, with senderState: Clients_SenderState?, completion: @escaping HomeDecryptionCompletion) {
        let dispatchedCompletion = { result in
            DispatchQueue.main.async { completion(result) }
        }
        sessionQueue.async {
            self.pendingTasks.append(.postDecryption(data, userID, postID, senderState, dispatchedCompletion))
            self.executeTasks()
        }
    }

    public func decryptComment(_ data: Data, from userID: UserID, postID: FeedPostID, completion: @escaping HomeDecryptionCompletion) {
        let dispatchedCompletion = { result in
            DispatchQueue.main.async { completion(result) }
        }
        sessionQueue.async {
            self.pendingTasks.append(.commentDecryption(data, userID, postID, dispatchedCompletion))
            self.executeTasks()
        }
    }

    public func addMembers(userIds: [UserID]) {
        let ownUserID = AppContext.shared.userData.userId
        let filteredUserIds = userIds.filter{ $0 != ownUserID }
        sessionQueue.async {
            self.pendingTasks.append(.membersAdded(filteredUserIds))
            self.executeTasks()
        }
    }

    public func removeMembers(userIds: [UserID]) {
        let ownUserID = AppContext.shared.userData.userId
        let filteredUserIds = userIds.filter{ $0 != ownUserID }
        sessionQueue.async {
            self.pendingTasks.append(.membersRemoved(filteredUserIds))
            self.executeTasks()
        }
    }

    public func removePending(userIds: [UserID]) {
        let ownUserID = AppContext.shared.userData.userId
        let filteredUserIds = userIds.filter{ $0 != ownUserID }
        sessionQueue.async {
            self.pendingTasks.append(.removePending(filteredUserIds))
            self.executeTasks()
        }
    }

    public func updateSenderState(with senderState: Clients_SenderState?, for userID: UserID) {
        guard let senderState = senderState else {
            DDLogError("HomeWhisperSession/updateSenderState/\(type)/userID: \(userID)/senderState is empty")
            return
        }
        sessionQueue.async {
            self.pendingTasks.append(.updateSenderState(userID, senderState))
            self.executeTasks()
        }
    }

    public func fetchSenderState(completion: @escaping HomeSenderStateCompletion) {
        let dispatchedCompletion = { result in
            DispatchQueue.main.async { completion(result) }
        }
        sessionQueue.async {
            self.pendingTasks.append(.fetchSenderState(dispatchedCompletion))
            self.executeTasks()
        }
    }

    public func fetchCommentKey(for postID: FeedPostID, completion: @escaping HomeCommentKeyCompletion) {
        let dispatchedCompletion = { result in
            DispatchQueue.main.async { completion(result) }
        }
        sessionQueue.async {
            self.pendingTasks.append(.fetchCommentKey(postID, dispatchedCompletion))
            self.executeTasks()
        }
    }

    // MARK: Private
    // MARK: *All private functions should be called on sessionQueue!*

    private enum HomeWhisperState {
        case empty
        case awaitingSetup(attempts: Int, incomingSession: HomeIncomingSession?, audienceUids: [UserID])
        case retrievingKeys(incomingSession: HomeIncomingSession?, audienceUids: [UserID])
        case ready(keyBundle: HomeKeyBundle)

        var keyBundle: HomeKeyBundle {
            switch self {
            case .empty:
                return HomeKeyBundle(outgoingSession: nil, incomingSession: incomingSession, pendingUids: [], audienceUids: [])
            case .awaitingSetup(_, let incomingSession, let audienceUids):
                return HomeKeyBundle(outgoingSession: nil, incomingSession: incomingSession, pendingUids: [], audienceUids: audienceUids)
            case .retrievingKeys(let incomingSession, let audienceUids):
                return HomeKeyBundle(outgoingSession: nil, incomingSession: incomingSession, pendingUids: [], audienceUids: audienceUids)
            case .ready(let keyBundle):
                return keyBundle
            }
        }

        var failedSetupAttempts: Int? {
            switch self {
            case .awaitingSetup(let attempts, _, _):
                return attempts
            case .ready, .retrievingKeys, .empty:
                return nil
            }
        }

        var incomingSession: HomeIncomingSession? {
            switch self {
            case .awaitingSetup(_, let session, _):
                return session
            case .retrievingKeys(let session, _):
                return session
            case .ready(let keyBundle):
                return keyBundle.incomingSession
            case .empty:
                return nil
            }
        }

        var audienceUids: [UserID] {
            switch self {
            case .awaitingSetup(_, _, let audienceUids):
                return audienceUids
            case .retrievingKeys(_, let audienceUids):
                return audienceUids
            case .ready(let keyBundle):
                return keyBundle.audienceUids
            case .empty:
                return []
            }
        }
    }

    private func executeTasks() {
        while let task = pendingTasks.first {
            // TODO: murali@: update this log to only log the state here.
            DDLogInfo("HomeWhisperSession/executeTasks/\(type)/state: \(state) - task: \(task)")
            switch self.state {

            case .empty:
                DDLogError("HomeWhisperSession/\(type)/execute/task - InvalidState - pausing")
                return

            case .awaitingSetup(let setupAttempts, _, _):
                // We pause encryption when in this state, since we are still setting up outbound session.
                // Decryption can continue fine. removingMembers should clear that user's keys.
                // addingMembers/removingPendingUids/updating hash will be taken care when outbound is setup.
                switch task {
                case .postEncryption(_, _, let audienceUserIds, let completion):
                    guard setupAttempts < 3 else {
                        DDLogError("HomeWhisperSession/\(type)/execute/postEncryption outbound setup failed \(setupAttempts) times")
                        completion(.failure(.missingKeyBundle))
                        return
                    }
                    DDLogInfo("HomeWhisperSession/\(type)/execute/pausing (needs outbound setup)")
                    setupOutbound(audienceUserIds: audienceUserIds)
                    return
                case .commentEncryption(let data, let feedPostID, let completion):
                    guard let commentKey = commentKey(for: feedPostID) else {
                        DDLogError("HomeWhisperSession/\(type)/execute/commentEncryption/missing commentKey for postID: \(feedPostID)")
                        completion(.failure(.missingKeyBundle))
                        return
                    }
                    executeCommentEncryption(data, using: commentKey, completion: completion)
                case .postDecryption(let data, let userID, let feedPostID, let incomingSenderState, let completion):
                    DDLogInfo("HomeWhisperSession/\(type)/execute/postDecryption")
                    executePostDecryption(data, from: userID, postID: feedPostID, with: incomingSenderState, completion: completion)
                case .commentDecryption(let data, _, let feedPostID, let completion):
                    DDLogInfo("HomeWhisperSession/\(type)/execute/commentDecryption")
                    guard let commentKey = commentKey(for: feedPostID) else {
                        DDLogError("HomeWhisperSession/\(type)/execute/commentDecryption/missing commentKey for postID: \(feedPostID)")
                        completion(.failure(.missingCommentKey))
                        return
                    }
                    executeCommentDecryption(data, using: commentKey, completion: completion)
                case .membersAdded(let memberUserIds):
                    DDLogInfo("HomeWhisperSession/\(type)/execute/membersAdded: \(memberUserIds.count)")
                    executeAddMembers(userIds: memberUserIds)
                case .membersRemoved(let memberUserIds):
                    DDLogInfo("HomeWhisperSession/\(type)/execute/membersRemoved: \(memberUserIds.count)")
                    executeRemoveMembers(userIds: memberUserIds)
                case .removePending(let memberUserIds):
                    DDLogInfo("HomeWhisperSession/\(type)/execute/removePending \(memberUserIds.count) - ignoring")
                case .fetchSenderState(let completion):
                    guard setupAttempts < 3 else {
                        DDLogError("HomeWhisperSession/\(type)/execute/fetchSenderState outbound setup failed \(setupAttempts) times")
                        completion(.failure(.missingKeyBundle))
                        return
                    }
                    DDLogInfo("HomeWhisperSession/\(type)/execute/pausing (needs outbound setup)")
                    setupOutbound(audienceUserIds: self.state.audienceUids)
                    return
                case .updateSenderState(let userID, let senderState):
                    DDLogInfo("HomeWhisperSession/\(type)/execute/updateSenderState")
                    updateIncomingSession(from: userID, with: senderState)
                case .fetchCommentKey(let feedPostID, let completion):
                    DDLogInfo("HomeWhisperSession/\(type)/execute/fetchCommentKey")
                    guard let commentKey = commentKey(for: feedPostID, createIfNecessary: true) else {
                        guard setupAttempts < 3 else {
                            DDLogError("HomeWhisperSession/\(type)/execute/fetchCommentKey outbound setup failed \(setupAttempts) times")
                            completion(.failure(.missingCommentKey))
                            return
                        }
                        DDLogInfo("HomeWhisperSession/\(type)/execute/fetchCommentKey pausing (needs outbound setup)")
                        setupOutbound(audienceUserIds: self.state.audienceUids)
                        return
                    }
                    completion(.success(commentKey.rawData))
                }

            // We pause all tasks in this state because we are working on a serviceRequest here.
            case .retrievingKeys:
                DDLogInfo("HomeWhisperSession/\(type)/execute/pausing all (retrievingKeys)")
                return

            case .ready(_):
                switch task {
                case .postEncryption(let data, let feedpostID, let audienceUserIds, let completion):
                    DDLogInfo("HomeWhisperSession/\(type)/execute/postEncryption")
                    // Clear outbound session if necessary and revisit this task.
                    if shouldClearSession(audienceUserIds: audienceUserIds) {
                        clearOutbound(audienceUserIds: audienceUserIds)
                        return
                    } else {
                        executePostEncryption(data, postID: feedpostID, audienceUserIds: audienceUserIds, completion: completion)
                    }
                case .commentEncryption(let data, let feedPostID, let completion):
                    DDLogInfo("HomeWhisperSession/\(type)/execute/commentEncryption")
                    guard let commentKey = commentKey(for: feedPostID) else {
                        DDLogError("HomeWhisperSession/\(type)/execute/commentEncryption/missing commentKey for postID: \(feedPostID)")
                        completion(.failure(.missingKeyBundle))
                        return
                    }
                    executeCommentEncryption(data, using: commentKey, completion: completion)
                case .postDecryption(let data, let userID, let feedPostID, let incomingSenderState, let completion):
                    DDLogInfo("HomeWhisperSession/\(type)/execute/postDecryption")
                    executePostDecryption(data, from: userID, postID: feedPostID, with: incomingSenderState, completion: completion)
                case .commentDecryption(let data, _, let feedPostID, let completion):
                    DDLogInfo("HomeWhisperSession/\(type)/execute/commentDecryption")
                    guard let commentKey = commentKey(for: feedPostID) else {
                        DDLogError("HomeWhisperSession/\(type)/execute/commentDecryption/missing commentKey for postID: \(feedPostID)")
                        completion(.failure(.missingCommentKey))
                        return
                    }
                    executeCommentDecryption(data, using: commentKey, completion: completion)
                case .membersAdded(let memberUserids):
                    DDLogInfo("HomeWhisperSession/\(type)/execute/membersAdded: \(memberUserids.count)")
                    executeAddMembers(userIds: memberUserids)
                case .membersRemoved(let memberUserids):
                    DDLogInfo("HomeWhisperSession/\(type)/execute/membersRemoved: \(memberUserids.count)")
                    executeRemoveMembers(userIds: memberUserids)
                case .removePending(let memberUserids):
                    DDLogInfo("HomeWhisperSession/\(type)/execute/removePending: \(memberUserids.count)")
                    executeRemovePending(userIds: memberUserids)
                case .fetchSenderState(let completion):
                    DDLogInfo("HomeWhisperSession/\(type)/execute/fetchSenderState")
                    executeFetchSenderState(completion: completion)
                case .updateSenderState(let userID, let senderState):
                    DDLogInfo("HomeWhisperSession/\(type)/execute/updateSenderState")
                    updateIncomingSession(from: userID, with: senderState)
                case .fetchCommentKey(let feedPostID, let completion):
                    DDLogInfo("HomeWhisperSession/\(type)/execute/fetchCommentKey")
                    guard let commentKey = commentKey(for: feedPostID, createIfNecessary: true) else {
                        DDLogError("HomeWhisperSession/\(type)/execute/fetchCommentKey/missing commentKey for postID: \(feedPostID)")
                        completion(.failure(.missingCommentKey))
                        return
                    }
                    completion(.success(commentKey.rawData))
                }
            }
            pendingTasks.removeFirst()
        }
    }

    private func executeAddMembers(userIds: [UserID]) {
        DDLogInfo("HomeWhisperSession/executeAddMembers/\(type)/state: \(state)")
        switch state {
        case .empty, .retrievingKeys:
            DDLogError("HomeWhisperSession/executeAddMembers/\(type)/Invalid state")
            return
        case .awaitingSetup(let attempts, let incomingSession, var audienceUids):
            audienceUids.append(contentsOf: userIds)
            updateState(to: .awaitingSetup(attempts: attempts, incomingSession: incomingSession, audienceUids: audienceUids), saveToKeyStore: true)
        case .ready(var homeKeyBundle):
            for userId in userIds {
                homeKeyBundle.incomingSession?.senderStates[userId] = nil
            }
            homeKeyBundle.audienceUids.append(contentsOf: userIds)
            homeKeyBundle.pendingUids.append(contentsOf: userIds)
            updateState(to: .ready(keyBundle: homeKeyBundle), saveToKeyStore: true)
        }
    }

    private func executeRemoveMembers(userIds: [UserID]) {
        DDLogInfo("HomeWhisperSession/executeRemoveMembers/\(type)/state: \(state)")
        let newAudienceUids: [UserID]
        switch state {
        case .empty, .retrievingKeys:
            DDLogError("HomeWhisperSession/executeRemoveMembers/\(type)/Invalid state")
            return
        case .awaitingSetup(let attempts, var incomingSession, let audienceUids):
            for userId in userIds {
                incomingSession?.senderStates[userId] = nil
            }
            newAudienceUids = audienceUids.filter { !userIds.contains($0) }
            state = .awaitingSetup(attempts: attempts, incomingSession: incomingSession, audienceUids: newAudienceUids)
        case .ready(var homeKeyBundle):
            for userId in userIds {
                homeKeyBundle.incomingSession?.senderStates[userId] = nil
            }
            newAudienceUids = homeKeyBundle.audienceUids.filter { !userIds.contains($0) }
            let newPendingUids = homeKeyBundle.pendingUids.filter { !userIds.contains($0) }
            // Remove these members from pendingUids/audienceUids if any.
            homeKeyBundle.audienceUids = newAudienceUids
            homeKeyBundle.pendingUids = newPendingUids
            state = .ready(keyBundle: homeKeyBundle)
        }
        if userIds.contains(AppContext.shared.userData.userId) {
            clearOutbound(audienceUserIds: newAudienceUids)
        } else {
            setupOutbound(audienceUserIds: newAudienceUids)
        }
    }

    private func executeRemovePending(userIds: [UserID]) {
        // It is possible that before we recieved a success response for the publish iq.
        // We might have gotten an add member/remove member event here.
        // so we need to act accordingly and remove pendingUids only if our current list is the same.
        // TODO: murali@: think more if we have to remove these Uids if the list is different.
        DDLogInfo("HomeWhisperSession/executeRemovePending/\(type)/state: \(state)")
        switch state {
        case .empty, .awaitingSetup, .retrievingKeys:
            DDLogError("HomeWhisperSession/executeRemovePending/\(type)/Invalid state")
            return
        case .ready(var homeKeyBundle):
            if Set(homeKeyBundle.pendingUids) == Set(userIds) {
                homeKeyBundle.pendingUids = []
            }
            DDLogInfo("HomeWhisperSession/executeRemovePending/\(type)/finalPendingUids: \(homeKeyBundle.pendingUids)")
            updateState(to: .ready(keyBundle: homeKeyBundle), saveToKeyStore: true)
        }
    }

    private func shouldClearSession(audienceUserIds: [UserID]) -> Bool {
        DDLogInfo("HomeWhisperSession/shouldClearSession/\(type)/begin/audienceUserIds: \(audienceUserIds)")
        let keyBundle = self.state.keyBundle

        // These are userIds in the current state.
        let oldAudienceUserIds = keyBundle.audienceUids

        // These are the new audience userIds for the post.
        let newAudienceUserIds = audienceUserIds
        let newAudienceUserIdsSet = Set(newAudienceUserIds)

        // We should clear our session if a userId from the old audience set is no longer in this new audience set.
        var shouldClearSession: Bool = false
        oldAudienceUserIds.forEach { userId in
            if !newAudienceUserIdsSet.contains(userId) {
                shouldClearSession = true
            }
        }
        DDLogInfo("HomeWhisperSession/shouldClearSession/\(type)/done/shouldClearSession: \(shouldClearSession)")
        return shouldClearSession
    }

    private func executePostEncryption(_ data: Data, postID: FeedPostID, audienceUserIds: [UserID], completion: @escaping HomePostEncryptionCompletion) {
        // This will run after ensuring we can use the existing session.
        // So we just need to update our pendingUserIds and encrypt the post.

        DDLogInfo("HomeWhisperSession/executePostEncryption/\(type)/begin/audienceUserIds: \(audienceUserIds)")
        let keyBundle = self.state.keyBundle
        guard let outgoingSession = keyBundle.outgoingSession else {
            DDLogError("HomeWhisperSession/executePostEncryption/\(type)/empty outgoing session")
            completion(.failure(.missingKeyBundle))
            return
        }

        // These are userIds in the current state.
        let oldAudienceUserIds = keyBundle.audienceUids
        let oldAudienceUserIdsSet = Set(oldAudienceUserIds)

        // Update pendingUserIds if necessary.
        var newPendingUserIds = keyBundle.pendingUids
        audienceUserIds.forEach { userId in
            if !oldAudienceUserIdsSet.contains(userId) {
                newPendingUserIds.append(userId)
            }
        }

        let newAudienceUserIds = audienceUserIds

        let result = Whisper.signAndEncrypt(data, session: outgoingSession)
        switch result {
        case .success(let (data, chainKey)):
            var newOutgoingSession = outgoingSession
            newOutgoingSession.senderKey.chainKey = chainKey
            newOutgoingSession.currentChainIndex += 1
            let updatedKeyBundle = HomeKeyBundle(outgoingSession: newOutgoingSession,
                                                 incomingSession: keyBundle.incomingSession,
                                                 pendingUids: newPendingUserIds,
                                                 audienceUids: newAudienceUserIds)

            constructHomeEncryptedData(data,
                                       senderKey: outgoingSession.senderKey,
                                       chainIndex: outgoingSession.currentChainIndex,
                                       pendingUids: newPendingUserIds) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success:
                    self.updateState(to: .ready(keyBundle: updatedKeyBundle), saveToKeyStore: true)
                    DDLogInfo("HomeWhisperSession/executePostEncryption/\(self.type)/success")
                case .failure(let error):
                    DDLogError("HomeWhisperSession/executePostEncryption/\(self.type)/failure: \(error)")
                }
                completion(result)
            }
        case .failure(let error):
            DDLogError("HomeWhisperSession/executePostEncryption/\(type)/error \(error)")
            completion(.failure(error))
        }
    }

    private func constructHomeEncryptedData(_ data: Data,
                                            senderKey: SenderKey?,
                                            chainIndex: Int?,
                                            pendingUids: [UserID],
                                            completion: @escaping (Result<HomeEncryptedData, EncryptionError>) -> Void) {
        do {
            var senderStateBundles: [Server_SenderStateBundle] = []
            var numberOfFailedEncrypts = 0
            let encryptGroup = DispatchGroup()
            let encryptCompletion: (Result<(EncryptedData, EncryptionLogInfo), EncryptionError>) -> Void = { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .failure(.invalidUid):
                    // not really an error - so we dont count it towards failed encryptions.
                    DDLogInfo("HomeWhisperSession/constructHomeEncryptedData/\(self.type)/encryptCompletion/accountDeleted/failed:  \(numberOfFailedEncrypts)")
                    break
                case .failure(let error):
                    numberOfFailedEncrypts += 1
                    DDLogError("HomeWhisperSession/constructHomeEncryptedData/\(self.type)/encryptCompletion/error: \(error)/failed: \(numberOfFailedEncrypts)")
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
                        DDLogError("HomeWhisperSession/constructHomeEncryptedData/\(self.type)/failed to encrypt for userID: \(receiverUserID)")
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
                // return HomeEncryptedData properly.
                if numberOfFailedEncrypts > 0 {
                    completion(.failure(.missingEncryptedSenderState))
                } else {
                    // send keys that were used for encryption
                    completion(.success(HomeEncryptedData(data: data,
                                                          senderKey: senderKey,
                                                          chainIndex: chainIndex,
                                                          receiverUids: pendingUids,
                                                          senderStateBundles: senderStateBundles)))
                }
            }
        } catch {
            completion(.failure(.serialization))
        }
    }

    private func executeCommentEncryption(_ data: Data, using commentKey: CommentKey, completion: HomeCommentEncryptionCompletion) {
        DDLogInfo("HomeWhisperSession/executeCommentEncryption/\(type)")
        let result = Whisper.signAndEncrypt(data, using: commentKey)
        switch result {
        case .success(let data):
            DDLogError("HomeWhisperSession/executeCommentEncryption/\(type)/success")
            completion(.success(data))
        case .failure(let error):
            DDLogError("HomeWhisperSession/executeCommentEncryption/\(type)/error \(error)")
            completion(.failure(error))
        }
    }

    private func executeCommentDecryption(_ encryptedData: Data, using commentKey: CommentKey, completion: HomeDecryptionCompletion) {
        DDLogInfo("HomeWhisperSession/executeCommentDecryption/\(type)")
        guard let commentEncryptedData = CommentEncryptedPayload(data: encryptedData) else {
            DDLogError("HomeWhisperSession/executeCommentDecryption/\(type)/error invalid encryptedData")
            completion(.failure(.invalidPayload))
            return
        }

        let result = Whisper.decrypt(commentEncryptedData, using: commentKey)
        switch result {
        case .success(let data):
            DDLogError("HomeWhisperSession/executeCommentDecryption/\(type)/success")
            completion(.success(data))
        case .failure(let error):
            DDLogError("HomeWhisperSession/executeCommentDecryption/\(type)/error \(error)")
            completion(.failure(error))
        }
    }

    private func executePostDecryption(_ encryptedData: Data, from userID: UserID, postID: FeedPostID, with incomingSenderState: Clients_SenderState?, completion: @escaping HomeDecryptionCompletion) {
        DDLogInfo("HomeWhisperSession/executePostDecryption/\(type)/begin/from: \(userID)")
        updateIncomingSession(from: userID, with: incomingSenderState)
        let keyBundle = self.state.keyBundle
        // We use the group decryption API here - since posts are encrypted/decrypted in the same way.
        guard let payload = EncryptedGroupPayload(data: encryptedData) else {
            DDLogError("HomeWhisperSession/executePostDecryption/\(type)/error invalidPayload")
            completion(.failure(.invalidPayload))
            return
        }

        guard let homeIncomingSession = keyBundle.incomingSession else {
            DDLogError("HomeWhisperSession/executePostDecryption/\(type)/error homeIncomingSession, state: \(state)")
            completion(.failure(.missingSenderState))
            return
        }

        guard let senderState = homeIncomingSession.senderStates[userID] else {
            DDLogError("HomeWhisperSession/executePostDecryption/\(type)/error missingSenderState")
            completion(.failure(.missingSenderState))
            return
        }

        // We use the group decryption API here - since posts are encrypted/decrypted in the same way.
        switch Whisper.decryptHome(payload, senderState: senderState) {
        case .success((let data, let updatedSenderState)):
            var newIncomingSession = homeIncomingSession
            newIncomingSession.senderStates[userID] = updatedSenderState
            let updatedKeyBundle = HomeKeyBundle(outgoingSession: keyBundle.outgoingSession,
                                                 incomingSession: newIncomingSession,
                                                 pendingUids: keyBundle.pendingUids,
                                                 audienceUids: keyBundle.audienceUids)

            let currentState = self.state
            switch currentState {
            case .empty, .retrievingKeys:
                DDLogError("HomeWhisperSession/executePostDecryption/\(type)/Invalid state")
                return
            case .ready(_):
                updateState(to: .ready(keyBundle: updatedKeyBundle), saveToKeyStore: true)
            case .awaitingSetup(let attempts, _, let audienceUids):
                updateState(to: .awaitingSetup(attempts: attempts,
                                               incomingSession: newIncomingSession,
                                               audienceUids: audienceUids),
                            saveToKeyStore: true)
            }

            DDLogInfo("HomeWhisperSession/executePostDecryption/\(type)/success")
            completion(.success(data))
        case .failure(let failure):
            DDLogError("HomeWhisperSession/executePostDecryption/\(type)/error \(failure)")
            completion(.failure(failure))
        }
    }

    private func executeFetchSenderState(completion: HomeSenderStateCompletion) {
        DDLogInfo("HomeWhisperSession/executeFetchSenderState/\(type)/begin")
        let keyBundle = self.state.keyBundle
        guard let outgoingSession = keyBundle.outgoingSession else {
            DDLogError("HomeWhisperSession/executeFetchSenderState/\(type)/empty outgoing session")
            completion(.failure(.missingKeyBundle))
            return
        }

        // send current senderKey and current chainIndex
        // TODO: murali@: check senderKey value.
        let output = HomeSenderState(senderKey: outgoingSession.senderKey,
                                     chainIndex: outgoingSession.currentChainIndex)
        completion(.success(output))
    }

    private func setupOutbound(audienceUserIds: [UserID]) {
        if case .retrievingKeys = state {
            DDLogInfo("HomeWhisperSession/setupOutbound/\(type)/state \(state) returning")
            return
        }

        let ownUserID = AppContext.shared.userData.userId
        let filteredAudienceUserIds = audienceUserIds.filter{ $0 != ownUserID }
        state = .retrievingKeys(incomingSession: state.incomingSession, audienceUids: filteredAudienceUserIds)

        let outgoingSession = Whisper.setupHomeOutgoingSession(for: self.type)
        let homeKeyBundle = HomeKeyBundle(outgoingSession: outgoingSession,
                                          incomingSession: self.state.incomingSession,
                                          pendingUids: filteredAudienceUserIds,
                                          audienceUids: filteredAudienceUserIds)
        DDLogInfo("HomeWhisperSession/setupOutbound/\(self.type)/success")
        self.updateState(to: .ready(keyBundle: homeKeyBundle), saveToKeyStore: true)

        self.executeTasks()
    }

    private func clearOutbound(audienceUserIds: [UserID]) {
        DDLogInfo("HomeWhisperSession/clearOutbound/\(type)/state: \(state)")
        updateState(to: .awaitingSetup(attempts: 0,
                                       incomingSession: self.state.incomingSession,
                                       audienceUids: audienceUserIds),
                    saveToKeyStore: true)
    }

    private func updateIncomingSession(from userID: UserID, with incomingSenderState: Clients_SenderState?) {
        DDLogInfo("HomeWhisperSession/updateIncomingSession/\(type)/from \(userID)/begin")
        let homeIncomingSenderState: IncomingSenderState? = {
            if let incomingSenderState = incomingSenderState {
                return IncomingSenderState(senderState: incomingSenderState)
            } else {
                let keyBundle = self.state.keyBundle
                guard let homeIncomingSession = keyBundle.incomingSession else {
                    DDLogError("HomeWhisperSession/updateIncomingSession/\(type)/error homeIncomingSession")
                    return nil
                }
                return homeIncomingSession.senderStates[userID]
            }
        }()

        guard let senderState = homeIncomingSenderState else {
            DDLogError("HomeWhisperSession/updateIncomingSession/\(type)/error missingSenderState")
            return
        }

        switch self.state {
        case .empty:
            DDLogError("HomeWhisperSession/updateIncomingSession/\(type)/Invalid empty state")
            return
        case .awaitingSetup(let setupAttempts, var incomingSession, let audienceUids):
            if incomingSession == nil {
                incomingSession = HomeIncomingSession(senderStates: [:])
            }
            incomingSession?.senderStates[userID] = senderState
            self.updateState(to: .awaitingSetup(attempts: setupAttempts, incomingSession: incomingSession, audienceUids: audienceUids), saveToKeyStore: true)

        case .retrievingKeys(var incomingSession, let audienceUids):
            if incomingSession == nil {
                incomingSession = HomeIncomingSession(senderStates: [:])
            }
            incomingSession?.senderStates[userID] = senderState
            self.updateState(to: .retrievingKeys(incomingSession: incomingSession, audienceUids: audienceUids))

        case .ready(var homeKeyBundle):
            if homeKeyBundle.incomingSession == nil {
                homeKeyBundle.incomingSession = HomeIncomingSession(senderStates: [:])
            }
            homeKeyBundle.incomingSession?.senderStates[userID] = senderState
            self.updateState(to: .ready(keyBundle: homeKeyBundle), saveToKeyStore: true)
        }
        DDLogInfo("HomeWhisperSession/updateIncomingSession/\(type)/from \(userID)/success")

    }

    private func loadFromKeyStore(for type: HomeSessionType) -> HomeWhisperState {
        var localState: HomeWhisperState = .awaitingSetup(attempts: 0, incomingSession: HomeIncomingSession(senderStates: [:]), audienceUids: [])
        keyStore.performOnBackgroundContextAndWait { context in
            guard let homeSessionKeyBundle = keyStore.homeSessionKeyBundle(for: type, in: context) else {
                DDLogInfo("HomeWhisperSession/loadFromKeyStore/type: \(type)/nil")
                return
            }
            DDLogInfo("HomeWhisperSession/loadFromKeyStore/type: \(type)/\(homeSessionKeyBundle)")
            let ownUserID = AppContext.shared.userData.userId

            // Obtain all senderStates including own copy.
            var memberSenderStates: [UserID: IncomingSenderState] = [:]
            homeSessionKeyBundle.senderStates?.forEach{ senderState in
                var messageKeys: [Int32: Data] = [:]
                senderState.messageKeys?.forEach { groupMessageKey in
                    messageKeys[groupMessageKey.chainIndex] = groupMessageKey.messageKey
                }
                let senderKey = SenderKey(chainKey: senderState.chainKey,
                                               publicSignatureKey: senderState.publicSignatureKey)
                let incomingSenderState = IncomingSenderState(senderKey: senderKey,
                                                                   currentChainIndex: Int(senderState.currentChainIndex),
                                                                   unusedMessageKeys: messageKeys)
                memberSenderStates[senderState.userId] = incomingSenderState
            }

            // First setup outgoingSession if available.
            var outgoingSession: HomeOutgoingSession? = nil
            let signKey = homeSessionKeyBundle.privateSignatureKey
            if let ownSenderState = memberSenderStates[ownUserID],
               !signKey.isEmpty {
                outgoingSession = HomeOutgoingSession(senderKey: ownSenderState.senderKey,
                                                      currentChainIndex: ownSenderState.currentChainIndex,
                                                      privateSigningKey: signKey)
            }

            // Remove our own senderState and setup incomingSession
            memberSenderStates.removeValue(forKey: ownUserID)
            let incomingSession = HomeIncomingSession(senderStates: memberSenderStates)

            if let outgoingSession = outgoingSession {
                // Creating homeKeyBundle
                let homeKeyBundle = HomeKeyBundle(outgoingSession: outgoingSession,
                                                   incomingSession: incomingSession,
                                                   pendingUids: homeSessionKeyBundle.pendingUserIDs,
                                                   audienceUids: homeSessionKeyBundle.audienceUserIDs)
                switch homeSessionKeyBundle.state {
                case .awaitingSetup:
                    localState = .awaitingSetup(attempts: 0, incomingSession: incomingSession, audienceUids: homeSessionKeyBundle.audienceUserIDs)
                case .ready:
                    localState = .ready(keyBundle: homeKeyBundle)
                }
            } else {
                // Setup correctState accordingly and return
                localState = .awaitingSetup(attempts: 0, incomingSession: incomingSession, audienceUids: homeSessionKeyBundle.audienceUserIDs)
            }
        }
        return localState
    }

    public func commentKey(for postID: FeedPostID, createIfNecessary: Bool = false) -> CommentKey? {
        var commentKey: CommentKey? = nil
        keyStore.performOnBackgroundContextAndWait { managedObjectContext in
            commentKey = keyStore.commentKey(for: postID, in: managedObjectContext)
            if createIfNecessary, commentKey == nil {
                if let feedPostCommentKey = createCommentKey(for: postID, in: managedObjectContext) {
                    keyStore.save(managedObjectContext)
                    commentKey = CommentKey(data: feedPostCommentKey.commentKey)
                }
            }
        }
        return commentKey
    }

    public func createCommentKey(for postID: FeedPostID, in managedObjectContext: NSManagedObjectContext) -> FeedPostCommentKey? {
        guard let outgoingSession = self.state.keyBundle.outgoingSession else {
            DDLogError("HomeWhisperSession/\(type)/createCommentKey/postID: \(postID)/error - invalid outgoingSession")
            return nil
        }


        let result = Whisper.generateCommentKey(for: postID, using: outgoingSession)
        switch result {
        case .success(let data):
            DDLogInfo("HomeWhisperSession/\(type)/createCommentKey/postID: \(postID)/success")
            let feedPostCommentKey = FeedPostCommentKey(context: managedObjectContext)
            feedPostCommentKey.postID = postID
            feedPostCommentKey.commentKey = data
            return feedPostCommentKey
        case .failure(let error):
            DDLogError("HomeWhisperSession/\(type)/createCommentKey/postID: \(postID)/error: \(error)")
            return nil
        }
    }

    public func reloadKeysFromKeyStore() {
        sessionQueue.async {
            self.updateState(to: self.loadFromKeyStore(for: self.type))
        }
    }

    private func updateState(to state: HomeWhisperState, saveToKeyStore: Bool = false) {
        self.state = state
        if saveToKeyStore {
            switch state {
            case .awaitingSetup(_, _, _):
                DDLogInfo("HomeWhisperSession/\(type)/updateState/saving keybundle \(state)")
                keyStore.saveHomeSessionKeyBundle(type: type, state: .awaitingSetup, homeKeyBundle: state.keyBundle)
            case .ready(_):
                DDLogInfo("HomeWhisperSession/\(type)/updateState/saving keybundle \(state)")
                keyStore.saveHomeSessionKeyBundle(type: type, state: .ready, homeKeyBundle: state.keyBundle)
            default:
                break
            }
        }
    }

}
