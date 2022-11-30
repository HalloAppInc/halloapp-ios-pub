//
//  WebClientManager.swift
//  HalloApp
//
//  Created by Garrett on 6/6/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import CoreCommon
import Foundation
import SwiftNoise
import CoreData

public protocol WebClientManagerDelegate: AnyObject {
    func webClientManager(_ manager: WebClientManager, didUpdateWebStaticKey staticKey: Data?)
}

public final class WebClientManager {

    public init(
        service: CoreServiceCommon,
        dataStore: MainDataStore,
        noiseKeys: NoiseKeys,
        webStaticKey: Data? = nil)
    {
        self.service = service
        self.dataStore = dataStore
        self.noiseKeys = noiseKeys
        self.webStaticKey = webStaticKey
        if webStaticKey != nil {
            registerForManagedObjectNotifications()
        }
    }

    public enum State {
        case disconnected
        case registering(Data)
        case handshaking(HandshakeState)
        case awaitingHandshake
        case connected(CipherState, CipherState)
    }

    public weak var delegate: WebClientManagerDelegate?
    public var state = CurrentValueSubject<State, Never>(.disconnected)

    private let service: CoreServiceCommon
    private let dataStore: MainDataStore
    private let noiseKeys: NoiseKeys
    private let webQueue = DispatchQueue(label: "hallo.web", qos: .userInitiated)

    private var handshakeTimeoutTask: DispatchWorkItem?

    private var updatedManagedObjectIDs = Set<NSManagedObjectID>()
    /// Countdown to send next update batch
    private var updateBatchTimer: Timer?
    /// Timestamp marking the first update from current batch
    private var updateBatchStart: Date?

    public private(set) var webStaticKey: Data?
    private var keysToRemove = Set<Data>()
    private var isRemovingKeys = false

    public func connect(staticKey: Data) {
        webQueue.async {
            switch self.state.value {
            case .disconnected, .connected, .awaitingHandshake:
                // OK to start new connection
                break
            case .registering, .handshaking:
                DDLogInfo("WebClientManager/connect/aborting [state: \(self.state.value)]")
                return
            }
            if let oldKey = self.webStaticKey {
                if oldKey == staticKey {
                    DDLogInfo("WebClientManager/connect/skipping-to-handshake [key-already-registered]")
                    self.initiateHandshake(isReconnecting: true)
                    return
                } else {
                    DDLogInfo("WebClientManager/connect/will-remove-old-key [\(oldKey.base64PrefixForLogs())]")
                    self.keysToRemove.insert(oldKey)
                }
            }
            DDLogInfo("WebClientManager/connect/registering [\(staticKey.base64PrefixForLogs())]")
            self.state.value = .registering(staticKey)
            self.service.authenticateWebClient(staticKey: staticKey) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success:
                    self.webStaticKey = staticKey
                    self.delegate?.webClientManager(self, didUpdateWebStaticKey: staticKey)
                    self.initiateHandshake()
                    self.registerForManagedObjectNotifications()

                case .failure:
                    self.disconnect(shouldRemoveOldKey: false)
                }
            }
            self.removeOldKeysIfNecessary()
        }
    }

    public func disconnect(shouldRemoveOldKey: Bool = true) {
        webQueue.async {
            if let webStaticKey = self.webStaticKey, shouldRemoveOldKey {
                self.keysToRemove.insert(webStaticKey)
            }
            self.webStaticKey = nil
            self.state.value = .disconnected
            self.delegate?.webClientManager(self, didUpdateWebStaticKey: nil)
            self.removeOldKeysIfNecessary()
        }
    }

    public func handleIncomingData(_ data: Data, from staticKey: Data) {
        webQueue.async {
            guard staticKey == self.webStaticKey else {
                DDLogError("WebClientManager/handleIncoming/error [unrecognized-static-key: \(staticKey.base64PrefixForLogs())] [expected: \(self.webStaticKey?.base64PrefixForLogs() ?? "nil")]")
                return
            }
            guard case .connected(_, let recv) = self.state.value else {
                DDLogError("WebClientManager/handleIncoming/error [not-connected]")
                return
            }
            guard let decryptedData = try? recv.decryptWithAd(ad: Data(), ciphertext: data) else {
                DDLogError("WebClientManager/handleIncoming/error [decryption-failure] [\(data.base64EncodedString())]")
                self.disconnect()
                return
            }
            guard let container = try? Web_WebContainer(serializedData: decryptedData) else {
                DDLogError("WebClientManager/handleIncoming/error [deserialization]")
                return
            }
            self.handleIncomingContainer(container)
        }
    }

    public func handleIncomingNoiseMessage(_ noiseMessage: Server_NoiseMessage, from staticKey: Data) {
        guard staticKey == self.webStaticKey else {
            DDLogError("WebClientManager/handleIncomingNoiseMessage/error [unrecognized-static-key: \(staticKey.base64EncodedString())] [expected: \(self.webStaticKey?.base64EncodedString() ?? "nil")]")
            return
        }

        handshakeTimeoutTask?.cancel()

        switch noiseMessage.messageType {
        case .kkA:
            receiveHandshake(with: noiseMessage)
        case .ikB, .kkB:
            guard case .handshaking(let handshake) = state.value else {
                DDLogError("WebClientManager/handleIncomingNoiseMessage/error [unexpected-handshake-response: \(noiseMessage.messageType)] [state: \(state.value)]")
                disconnect()
                return
            }
            continueHandshake(handshake, with: noiseMessage)
        case .ikA, .xxA, .xxB, .xxC, .xxFallbackA, .xxFallbackB, .UNRECOGNIZED:
            DDLogError("WebClientManager/handleIncomingNoiseMessage/error [unexpected-handshake-type: \(noiseMessage.messageType)] [state: \(state.value)]")
            disconnect()
        }
    }

    public func send(_ data: Data) {
        webQueue.async {
            guard case .connected(let send, _) = self.state.value else {
                DDLogError("WebClientManager/send/error [not-connected]")
                return
            }
            guard let key = self.webStaticKey else {
                DDLogError("WebClientManager/send/error [no-key]")
                return
            }
            do {
                let encryptedData = try send.encryptWithAd(ad: Data(), plaintext: data)
                self.service.sendToWebClient(staticKey: key, data: encryptedData) { _ in }
            } catch {
                DDLogError("WebClientManager/send/error [\(error)]")
            }
        }
    }

    private func makeConnectionPayload() -> Data {
        let userID = AppContext.shared.userData.userId

        var userInfo = Web_UserDisplayInfo()
        userInfo.contactName = AppContext.shared.userData.name
        if let avatarID = AppContext.shared.avatarStore.avatarID(forUserID: userID) {
            userInfo.avatarID = avatarID
        }
        if let uid = Int64(userID) {
            userInfo.uid = uid
        }

        var info = Web_ConnectionInfo()
        info.version = AppContext.userAgent
        info.user = userInfo

        do {
            return try info.serializedData()
        } catch {
            DDLogError("WebClientManager/makeConnectionPayload/error [serialization]")
            return Data()
        }
    }

    private func registerForManagedObjectNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleManagedObjectNotification),
            name: Notification.Name.NSManagedObjectContextDidMergeChangesObjectIDs,
            object: dataStore.viewContext)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleManagedObjectNotification),
            name: Notification.Name.NSManagedObjectContextDidSaveObjectIDs,
            object: dataStore.viewContext)
    }

    private func handleIncomingContainer(_ container: Web_WebContainer) {
        switch container.payload {
        case .feedResponse:
            DDLogError("WebClientManager/handleIncoming/feedResponse/error [invalid-payload]")
        case .feedUpdate:
            DDLogError("WebClientManager/handleIncoming/feedUpdate/error [invalid-payload]")
        case .privacyListResponse:
            DDLogError("WebClientManager/handleIncoming/privacyListResponse/error [invalid-payload]")
        case .groupResponse:
            DDLogError("WebClientManager/handleIncoming/groupResponse/error [invalid-payload]")
        case .momentStatus:
            DDLogError("WebClientManager/handleIncoming/momentStatus/error [invalid-payload]")
        case .groupRequest(let request):
            DispatchQueue.main.async {
                let response = self.groupResponse(for: request)
                var webContainer = Web_WebContainer()
                webContainer.payload = .groupResponse(response)
                do {
                    DDLogInfo("WebClientManager/handleIncoming/groupRequest/sending [\(response.groups.count)]")
                    let responseData = try webContainer.serializedData()
                    self.send(responseData)
                } catch {
                    DDLogError("WebClientManager/handleIncoming/groupRequest/error [serialization]")
                }
            }
        case .privacyListRequest(let request):
            DispatchQueue.main.async {
                let response = self.privacyListResponse(for: request)
                var webContainer = Web_WebContainer()
                webContainer.payload = .privacyListResponse(response)
                do {
                    DDLogInfo("WebClientManager/handleIncoming/privacyListRequest/sending [type=\(response.privacyLists.activeType)] [\(response.privacyLists.lists.count)]")
                    let responseData = try webContainer.serializedData()
                    self.send(responseData)
                } catch {
                    DDLogError("WebClientManager/handleIncoming/privacyListRequest/error [serialization]")
                }
            }
        case .receiptUpdate(let update):
            DispatchQueue.main.async {
                self.handleReceiptUpdate(update)
            }
        case .feedRequest(let request):
            DispatchQueue.main.async {
                guard let response = self.feedResponse(for: request) else {
                    DDLogError("WebClientManager/handleIncoming/feedResponse/error [no-response]")
                    return
                }
                var webContainer = Web_WebContainer()
                webContainer.payload = .feedResponse(response)
                do {
                    DDLogInfo("WebClientManager/handleIncoming/feedRequest/sending [\(response.items.count)]")
                    let responseData = try webContainer.serializedData()
                    self.send(responseData)
                } catch {
                    DDLogError("WebClientManager/handleIncoming/feedRequest/error [serialization]")
                }
            }
        case .none:
            DDLogError("WebClientManager/handleIncoming/error [missing-payload]")
        }
    }

    @objc
    private func handleManagedObjectNotification(_ notification: NSNotification) {
        guard let userInfo = notification.userInfo else { return }

        DispatchQueue.main.async {
            DDLogInfo("WebClientManager/handleManagedObjectNotification/starting [\(self.updatedManagedObjectIDs.count)]")

            var updatedIDs = Set<NSManagedObjectID>()

            if let inserts = userInfo[NSInsertedObjectIDsKey] as? Set<NSManagedObjectID> {
                updatedIDs.formUnion(inserts)
                DDLogInfo("WebClientManager/handleManagedObjectNotification/inserts [\(inserts.count)] [\(self.updatedManagedObjectIDs.count)]")
            }
            if let updates = userInfo[NSUpdatedObjectIDsKey] as? Set<NSManagedObjectID> {
                updatedIDs.formUnion(updates)
                DDLogInfo("WebClientManager/handleManagedObjectNotification/updates [\(updates.count)] [\(self.updatedManagedObjectIDs.count)]")
            }
            if let deletes = userInfo[NSDeletedObjectIDsKey] as? Set<NSManagedObjectID> {
                // Ignore deletes
                DDLogInfo("WebClientManager/handleManagedObjectNotification/deletes/skipping [\(deletes.count)]")
            }

            guard !updatedIDs.isEmpty else {
                DDLogInfo("WebClientManager/handleManagedObjectNotification/skipping [no updates]")
                return
            }

            self.updatedManagedObjectIDs.formUnion(updatedIDs)

            let currentTime = Date()
            let startTime = self.updateBatchStart ?? currentTime

            if let timer = self.updateBatchTimer {
                timer.invalidate()
                self.updateBatchTimer = nil
            }

            self.updateBatchStart = startTime

            if currentTime.timeIntervalSince(startTime) > 5 {
                // Send immediately if we've been waiting too long
                DDLogInfo("WebClientManager/handleManagedObjectNotification/send-immediately")
                self.updateBatchStart = nil
                self.sendUpdateBatch()
            } else {
                // Wait a few seconds to collect any changes
                DDLogInfo("WebClientManager/handleManagedObjectNotification/schedule-send")
                let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
                    self?.updateBatchStart = nil
                    self?.sendUpdateBatch()
                }
                self.updateBatchTimer = timer
            }
        }
    }

    private func sendUpdateBatch() {
        guard let updates = self.feedUpdate(for: self.updatedManagedObjectIDs) else {
            DDLogError("WebClientManager/sendUpdateBatch/error [no-updates]")
            return
        }
        var webContainer = Web_WebContainer()
        webContainer.payload = .feedUpdate(updates)
        do {
            DDLogInfo("WebClientManager/sendUpdateBatch/sending [\(updates.items.count)]")
            let responseData = try webContainer.serializedData()
            self.send(responseData)
            // TODO: Restore these managed object IDs in event of send failure
            self.updatedManagedObjectIDs.removeAll()
        } catch {
            DDLogError("WebClientManager/sendUpdateBatch/error [serialization]")
        }
    }

    private func receiveHandshake(with noiseMessage: Server_NoiseMessage) {
        guard case .kkA = noiseMessage.messageType else {
            DDLogError("WebClientManager/receiveHandshake/error [unexpected-message-type] [\(noiseMessage.messageType)]")
            disconnect()
            return
        }
        guard let ephemeralKeys = NoiseKeys() else {
            DDLogError("WebClientManager/receiveHandshake/error [keygen-failure]")
            disconnect()
            return
        }
        let handshake: HandshakeState
        do {
            handshake = try HandshakeState(
                pattern: .KK,
                initiator: false,
                prologue: Data(),
                s: noiseKeys.makeX25519KeyPair(),
                e: ephemeralKeys.makeX25519KeyPair(),
                rs: webStaticKey)
            let data = try handshake.readMessage(message: noiseMessage.content)
            DDLogInfo("WebClientManager/receiveHandshake/read [\(data.count) bytes]")
            let msgB = try handshake.writeMessage(payload: makeConnectionPayload())
            self.sendNoiseMessage(msgB, type: .kkB)
            let (receive, send) = try handshake.split()
            self.state.value = .connected(send, receive)
        } catch {
            DDLogError("WebClientManager/receiveHandshake/error [\(error)]")
            disconnect()
            return
        }
    }

    // Web expects us to use KK pattern when reconnecting
    private func initiateHandshake(isReconnecting: Bool = false) {
        guard let ephemeralKeys = NoiseKeys() else {
            DDLogError("WebClientManager/initiateHandshake/error [keygen-failure]")
            disconnect()
            return
        }
        let handshake: HandshakeState
        do {
            handshake = try HandshakeState(
                pattern: isReconnecting ? .KK : .IK,
                initiator: true,
                prologue: Data(),
                s: noiseKeys.makeX25519KeyPair(),
                e: ephemeralKeys.makeX25519KeyPair(),
                rs: webStaticKey)
        } catch {
            DDLogError("WebClientManager/initiateHandshake/error [\(error)]")
            disconnect()
            return
        }
        self.state.value = .handshaking(handshake)
        do {
            let msgA = try handshake.writeMessage(payload: makeConnectionPayload())
            self.sendNoiseMessage(msgA, type: isReconnecting ? .kkA : .ikA)

            // Disconnect on initial connection failure (i.e. no response after QR scan)
            // but not on reconnect failure (in case web client is temporarily offline)
            scheduleHandshakeTimeout(15, shouldDisconnect: !isReconnecting)
        } catch {
            DDLogError("WebClientManager/initiateHandshake/error [\(error)]")
        }
    }

    private func scheduleHandshakeTimeout(_ timeout: TimeInterval, shouldDisconnect: Bool) {
        // Schedule a timeout. Must be canceled when response is received.
        handshakeTimeoutTask?.cancel()
        let handshakeTimeout = DispatchWorkItem { [weak self] in
            DDLogInfo("WebClientManager/handshake/timeout")
            if shouldDisconnect {
                self?.disconnect()
            } else {
                self?.state.value = .awaitingHandshake
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: handshakeTimeout)
        handshakeTimeoutTask = handshakeTimeout
    }

    private func continueHandshake(_ handshake: HandshakeState, with noiseMessage: Server_NoiseMessage) {
        do {
            let data = try handshake.readMessage(message: noiseMessage.content)
            DDLogInfo("WebClientManager/handshake/reading data [\(data.count) bytes]")
        } catch {
            DDLogError("WebClientManager/handshake/error [\(error)]")
            return
        }
        do {
            let (send, receive) = try handshake.split()
            self.state.value = .connected(send, receive)
        } catch {
            DDLogError("WebClientManager/handshake/error [message-type: \(noiseMessage.messageType)] [\(error)]")
        }
    }

    private func sendNoiseMessage(_ content: Data, type: Server_NoiseMessage.MessageType) {
        guard let webStaticKey = webStaticKey else {
            DDLogError("WebClientManager/sendNoiseMessage/error [no-key]")
            return
        }

        var msg = Server_NoiseMessage()
        msg.messageType = type
        msg.content = content

        DDLogInfo("WebClientManager/sendNoiseMessage/\(type) [\(content.count)]")

        service.sendToWebClient(staticKey: webStaticKey, noiseMessage: msg) { _ in }
    }

    // TODO: Schedule this on timer
    private func removeOldKeysIfNecessary() {
        guard !keysToRemove.isEmpty else {
            DDLogInfo("WebClientManager/removeOldKeys/skipping [no-keys]")
            return
        }
        guard !isRemovingKeys else {
            DDLogInfo("WebClientManager/removeOldKeys/skipping [in-progress]")
            return
        }

        isRemovingKeys = true
        let group = DispatchGroup()
        group.notify(queue: webQueue) { [weak self] in
            self?.isRemovingKeys = false
        }
        for key in keysToRemove {
            DDLogInfo("WebClientManager/removeOldKeys/start [\(key.base64PrefixForLogs())]")
            group.enter()
            service.removeWebClient(staticKey: key) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .failure(let error):
                    DDLogError("WebClientManager/removeOldKeys/error [\(key.base64PrefixForLogs())] [\(error)]")
                    group.leave()
                case .success:
                    DDLogInfo("WebClientManager/removeOldKeys/success [\(key.base64PrefixForLogs())]")
                    self.webQueue.async {
                        self.keysToRemove.remove(key)
                        group.leave()
                    }
                }
            }
        }
    }

    // MARK: Receipts

    private func handleReceiptUpdate(_ update: Web_ReceiptUpdate) {
        if let post = AppContext.shared.coreFeedData.feedPost(with: update.contentID, in: AppContext.shared.mainDataStore.viewContext) {
            switch update.receipt.status {
            case .delivered, .played, .UNRECOGNIZED:
                DDLogError("WebClientManager/handleReceiptUpdate/post/error [invalid-status] [\(update.receipt.status)] [\(post.id)]")
            case .seen:
                DDLogInfo("WebClientManager/handleReceiptUpdate/post/seen [\(post.id)]")
                AppContext.shared.coreFeedData.sendSeenReceiptIfNecessary(for: post)
            }
        } else if let message = AppContext.shared.coreChatData.chatMessage(with: update.contentID, in: AppContext.shared.mainDataStore.viewContext) {
            switch update.receipt.status {
            case .delivered, .UNRECOGNIZED:
                DDLogError("WebClientManager/handleReceiptUpdate/message/error [invalid-status] [\(update.receipt.status)] [\(message.id)]")
            case .seen:
                DDLogInfo("WebClientManager/handleReceiptUpdate/message/seen [\(message.id)]")
                AppContext.shared.coreChatData.markSeenMessage(for: message.id)
            case .played:
                DDLogInfo("WebClientManager/handleReceiptUpdate/message/played [\(message.id)]")
                AppContext.shared.coreChatData.markPlayedMessage(for: message.id)
            }
        } else {
            DDLogError("WebClientManager/handleReceiptUpdate/error [content-not-found] [\(update.contentID)]")
        }
    }

    // MARK: Privacy Lists

    private func privacyListResponse(for request: Web_PrivacyListRequest) -> Web_PrivacyListResponse {
        let privacy = AppContext.shared.privacySettings

        var serverLists = Server_PrivacyLists()
        if let activeType = privacy.activeType,
            let serverType = Server_PrivacyLists.TypeEnum(activeType)
        {
            serverLists.activeType = serverType
        }
        serverLists.lists = privacy.allLists.map { serverPrivacyList(for: $0) }

        var response = Web_PrivacyListResponse()
        response.id = request.id
        response.privacyLists = serverLists

        return response
    }

    private func serverPrivacyList(for list: PrivacyList) -> Server_PrivacyList {
        var serverList = Server_PrivacyList()
        serverList.type = .init(list.type)
        serverList.uidElements = list.items.compactMap {
            guard let userID = Int64($0.userId), $0.state != .deleted else { return nil }
            var element = Server_UidElement()
            element.uid = userID
            return element
        }
        serverList.usingPhones = false
        if let hash = list.hash {
            serverList.hash = hash
        }
        return serverList
    }

    // MARK: Feed

    private lazy var homeFeedDataSource: FeedDataSource = {
        return FeedDataSource(fetchRequest: FeedDataSource.homeFeedRequest())
    }()

    private func feedUpdate(for managedObjectIDs: Set<NSManagedObjectID>) -> Web_FeedUpdate? {
        let currentUserID = AppContext.shared.userData.userId

        var posts = [FeedPost]()
        var comments = [FeedPostComment]()
        for id in managedObjectIDs {
            let obj = dataStore.viewContext.object(with: id)
            if let comment = obj as? FeedPostComment {
                comments.append(comment)
            } else if let post = obj as? FeedPost {
                posts.append(post)
            }
        }

        let items = posts.compactMap { Self.feedItem(from: $0) } + comments.compactMap { Self.feedItem(from: $0)}
        guard !items.isEmpty else {
            DDLogInfo("WebClientManager/feedUpdate/aborting [no items]")
            return nil
        }

        let groupIDs = posts.compactMap { $0.groupID } + comments.compactMap { $0.post.groupID }
        let userIDs = Self.usersReferenced(in: posts).union(Self.usersReferenced(in: comments))

        var update = Web_FeedUpdate()
        update.items = items
        update.groupDisplayInfo = groupDisplayInfo(for: Set(groupIDs))
        update.userDisplayInfo = userDisplayInfo(for: userIDs)
        update.postDisplayInfo = posts.map { Self.postDisplayInfo(for: $0, currentUserID: currentUserID) }
        return update
    }

    private func groupResponse(for request: Web_GroupRequest) -> Web_GroupResponse {
        let groups = AppContext.shared.mainDataStore.feedGroups(in: AppContext.shared.mainDataStore.viewContext)
        var response = Web_GroupResponse()
        response.id = request.id
        response.groups = groups.compactMap { groupDisplayInfo(for: $0) }
        return response
    }

    private func feedResponse(for request: Web_FeedRequest) -> Web_FeedResponse? {
        let cursor = request.cursor.isEmpty ? nil : request.cursor
        var response: Web_FeedResponse
        switch request.type {
        case .home:
            DDLogInfo("WebClientManager/handleIncoming/feedRequest/home")
            response = homeFeed(cursor: cursor, limit: Int(request.limit))
        case .group:
            DDLogInfo("WebClientManager/handleIncoming/feedRequest/group/\(request.contentID)")
            response = groupFeed(id: request.contentID, cursor: cursor, limit: Int(request.limit))
        case .postComments:
            DDLogInfo("WebClientManager/handleIncoming/feedRequest/comment/\(request.contentID)")
            response = commentFeed(id: request.contentID, cursor: cursor, limit: Int(request.limit))
        case .moments, .UNRECOGNIZED:
            DDLogInfo("WebClientManager/handleIncoming/feedRequest/unsupported [\(request.type.rawValue)]")
            return nil
        }
        response.id = request.id
        return response
    }

    private func homeFeed(cursor: String? = nil, limit: Int) -> Web_FeedResponse {
        let dataSource = homeFeedDataSource
        dataSource.setup()
        let allPosts: [FeedPost] = dataSource.displayItems.compactMap {
            guard case .post(let post) = $0 else {
                return nil
            }
            return post
        }
        switch paginate(posts: allPosts, cursor: cursor, limit: limit) {
        case .success(let page):
            return feedResponse(with: page.items, type: .home, nextCursor: page.nextCursor)
        case .failure(.invalidCursor):
            var response = Web_FeedResponse()
            response.error = .invalidCursor
            response.type = .home
            return response
        }
    }

    private func groupFeed(id: GroupID, cursor: String? = nil, limit: Int) -> Web_FeedResponse {
        let dataSource = FeedDataSource(fetchRequest: FeedDataSource.groupFeedRequest(groupID: id))
        dataSource.setup()
        let allPosts: [FeedPost] = dataSource.displayItems.compactMap {
            guard case .post(let post) = $0 else {
                return nil
            }
            return post
        }
        switch paginate(posts: allPosts, cursor: cursor, limit: limit) {
        case .success(let page):
            return feedResponse(with: page.items, type: .group, nextCursor: page.nextCursor)
        case .failure(.invalidCursor):
            var response = Web_FeedResponse()
            response.error = .invalidCursor
            response.type = .group
            return response
        }
    }

    private func commentFeed(id: FeedPostID, cursor: String? = nil, limit: Int) -> Web_FeedResponse {

        let fetchRequest: NSFetchRequest<FeedPostComment> = FeedPostComment.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "post.id = %@", id)
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPostComment.timestamp, ascending: false) ]

        let frc = NSFetchedResultsController<FeedPostComment>(
            fetchRequest: fetchRequest,
            managedObjectContext: AppContext.shared.mainDataStore.viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil)

        do {
            try frc.performFetch()
        } catch {
            DDLogError("WebClientManager/commentFeed/error [\(error)]")
        }

        switch paginate(comments: frc.fetchedObjects ?? [], cursor: cursor, limit: limit) {
        case .success(let page):
            return commentFeedResponse(with: page.items, type: .postComments, nextCursor: page.nextCursor)
        case .failure(.invalidCursor):
            var response = Web_FeedResponse()
            response.error = .invalidCursor
            response.type = .postComments
            return response
        }
    }

    private func commentFeedResponse(with comments: [FeedPostComment], type: Web_FeedType, nextCursor: String?) -> Web_FeedResponse {
        var response = Web_FeedResponse()
        response.type = type
        response.userDisplayInfo = userDisplayInfo(for: Self.usersReferenced(in: comments))
        if let nextCursor = nextCursor {
            response.nextCursor = nextCursor
        }
        response.items = comments.compactMap { Self.feedItem(from: $0) }

        return response
    }

    private func feedResponse(with posts: [FeedPost], type: Web_FeedType, nextCursor: String?) -> Web_FeedResponse {
        let currentUserID = AppContext.shared.userData.userId

        var response = Web_FeedResponse()
        response.type = type
        response.userDisplayInfo = userDisplayInfo(for: Self.usersReferenced(in: posts))
        response.postDisplayInfo = posts.map { Self.postDisplayInfo(for: $0, currentUserID: currentUserID) }
        response.groupDisplayInfo = groupDisplayInfo(for: Set(posts.compactMap { $0.groupID }))
        if let nextCursor = nextCursor {
            response.nextCursor = nextCursor
        }
        response.items = posts.compactMap { Self.feedItem(from: $0) }

        return response
    }

    private static func feedItem(from comment: FeedPostComment) -> Web_FeedItem? {
        let commentData = comment.commentData

        guard var serverComment = commentData.serverComment else {
            DDLogError("WebClientManager/commentFeed/comment/\(comment.id)/error [could-not-create-server-comment]")
            return nil
        }

        do {
            // Set unencrypted payload
            serverComment.payload = try commentData.clientContainer.serializedData()
        } catch {
            DDLogError("WebClientManager/commentFeed/comment/\(comment.id)/error [\(error)]")
            return nil
        }

        var feedItem = Web_FeedItem()
        feedItem.content = .comment(serverComment)
        return feedItem
    }

    private static func feedItem(from post: FeedPost) -> Web_FeedItem? {
        let postContainerData: Data
        do {
            postContainerData = try post.postData.clientContainer.serializedData()
        } catch {
            DDLogError("WebClientManager/homeFeed/post/\(post.id)/error [\(error)]")
            return nil
        }
        var serverPost = Server_Post()
        // TODO: audience, media counters, tag, psa tag, moment unlock uid?
        serverPost.payload = postContainerData
        serverPost.id = post.id
        serverPost.timestamp = Int64(post.timestamp.timeIntervalSince1970)
        if let publisherUserID = Int64(post.userID) {
            serverPost.publisherUid = publisherUserID
        }

        var feedItem = Web_FeedItem()
        feedItem.content = .post(serverPost)
        if let expiryTimestamp = post.expiration?.timeIntervalSince1970 {
            feedItem.expiryTimestamp = Int64(expiryTimestamp)
        }
        if let groupID = post.groupID {
            feedItem.groupID = groupID
        }
        return feedItem
    }

    private static func usersReferenced(in posts: [FeedPost]) -> Set<UserID> {
        var usersToInclude = Set<UserID>()
        // Include info for all users who have posted.
        usersToInclude.formUnion(posts.map { $0.userID })
        // Include info for all users who are mentioned in posts.
        usersToInclude.formUnion(posts.flatMap { $0.mentions }.map { $0.userID })
        // Include info for all users who have seen your posts.
        usersToInclude.formUnion(posts.flatMap { AppContext.shared.coreFeedData.seenReceipts(for: $0) }.map { $0.userId })
        return usersToInclude
    }

    private static func usersReferenced(in comments: [FeedPostComment]) -> Set<UserID> {
        var usersToInclude = Set<UserID>()
        // Include info for all users who have commented.
        usersToInclude.formUnion(comments.map { $0.userID })
        // Include info for all users who are mentioned in comments.
        usersToInclude.formUnion(comments.flatMap { $0.mentions }.map { $0.userID })
        return usersToInclude
    }

    // MARK: DisplayInfo

    func userDisplayInfo(for userIDs: Set<UserID>) -> [Web_UserDisplayInfo] {
        let contactNames = AppContext.shared.contactStore.fullNames(forUserIds: userIDs)
        let avatarIDs = AppContext.shared.avatarStore.avatarIDs(forUserIDs: userIDs)

        return userIDs.compactMap {
            guard let userID = Int64($0) else { return nil }
            var info = Web_UserDisplayInfo()
            info.uid = userID
            if let avatarID = avatarIDs[$0] {
                info.avatarID = avatarID
            }
            if let contactName = contactNames[$0] {
                info.contactName = contactName
            }
            return info
        }
    }

    func groupDisplayInfo(for groupIDs: Set<GroupID>) -> [Web_GroupDisplayInfo] {
        return groupIDs.compactMap { groupID in
            guard let group = self.dataStore.group(id: groupID, in: self.dataStore.viewContext) else {
                DDLogError("WebClientManager/groupDisplayInfo/group/error [not-found] [id: \(groupID)]")
                return nil
            }
            return self.groupDisplayInfo(for: group)
        }
    }

    func groupDisplayInfo(for group: Group) -> Web_GroupDisplayInfo {
        let currentUserID = AppContext.shared.userData.userId

        var info = Web_GroupDisplayInfo()
        info.id = group.id
        info.name = group.name
        if let avatarID = group.avatarID {
            info.avatarID = avatarID
        }
        if let description = group.desc {
            info.description_p = description
        }
        let member = group.members?.first { $0.userID == currentUserID }
        switch member?.type {
        case .member:
            info.membershipStatus = .member
        case .admin:
            info.membershipStatus = .admin
        case .none:
            info.membershipStatus = .notMember
        }
        var background = Clients_Background()
        background.theme = group.background
        if let backgroundData = try? background.serializedData() {
            info.background = String(decoding: backgroundData, as: UTF8.self)
        }
        var expiry = Server_ExpiryInfo()
        expiry.expiryTimestamp = group.expirationTime
        expiry.expiryType = group.expirationType.serverExpiryType
        info.expiryInfo = expiry

        return info
    }

    private static func postDisplayInfo(for post: FeedPost, currentUserID: UserID) -> Web_PostDisplayInfo {
        var info = Web_PostDisplayInfo()
        info.id = post.id
        info.isUnsupported = post.status == .unsupported
        info.retractState = {
            switch post.status {
            case .retracting:
                return .retracting
            case .retracted:
                return .retracted
            default:
                return .unretracted
            }
        }()
        info.transferState = {
            switch post.status {
            case .sent, .retracting:
                return .sent
            case .sending:
                return .sending
            case .incoming, .seenSending, .seen:
                return .received
            case .sendError:
                return .sendError
            case .rerequesting:
                return .decryptionError
            case .none:
                return .unknown
            case .retracted, .unsupported, .expired:
                return post.userID == currentUserID ? .sent : .received
            }
        }()
        info.seenState = {
            switch post.status {
            case .incoming:
                return .unseen
            case .seenSending:
                return .seenSending
            default:
                return .seen
            }
        }()
        info.unreadComments = post.unreadCount
        info.userReceipts = AppContext.shared.coreFeedData.seenReceipts(for: post).compactMap {
            guard let userID = Int64($0.userId) else { return nil }
            var receipt = Web_ReceiptInfo()
            receipt.timestamp = Int64($0.timestamp.timeIntervalSince1970)
            receipt.status = .seen
            receipt.uid = userID
            return receipt
        }
        return info
    }

    // MARK: Pagination

    private struct Page<T> {
        var items: [T]
        var nextCursor: String?
    }

    enum PaginationError: Error {
        case invalidCursor
    }

    private func paginate(posts: [FeedPost], cursor: String?, limit: Int) -> Result<Page<FeedPost>, PaginationError> {
        let cappedLimit: Int = {
            if limit <= 0 { return 20 }
            return limit > 50 ? 50 : limit
        }()

        let startIndex: Int
        if let cursor = cursor, !cursor.isEmpty {
            guard let cursorIndex = posts.firstIndex(where: { $0.id == cursor }) else {
                return .failure(.invalidCursor)
            }
            startIndex = cursorIndex
        } else {
            startIndex = 0
        }

        let (currentPosts, nextPost) = paginate(posts, startIndex: startIndex, limit: cappedLimit)
        return .success(Page(items: currentPosts, nextCursor: nextPost?.id))
    }

    private func paginate(comments: [FeedPostComment], cursor: String?, limit: Int) -> Result<Page<FeedPostComment>, PaginationError> {
        let cappedLimit: Int = {
            if limit <= 0 { return 20 }
            return limit > 50 ? 50 : limit
        }()

        let startIndex: Int
        if let cursor = cursor, !cursor.isEmpty {
            guard let cursorIndex = comments.firstIndex(where: { $0.id == cursor }) else {
                return .failure(.invalidCursor)
            }
            startIndex = cursorIndex
        } else {
            startIndex = 0
        }

        let (currentComments, nextComment) = paginate(comments, startIndex: startIndex, limit: cappedLimit)
        return .success(Page(items: currentComments, nextCursor: nextComment?.id))
    }

    private func paginate<T>(_ elements: [T], startIndex: Int, limit: Int) -> ([T], T?) {
        let nextIndex = startIndex + limit

        if elements.count > nextIndex {
            return (Array(elements[startIndex..<nextIndex]), elements[nextIndex])
        } else {
            return (Array(elements[startIndex...]), nil)
        }
    }

}

public enum WebClientQRCodeResult {
    case unsupportedOrInvalid
    case invalid
    case valid(Data)

    public static func from(qrCodeData: Data) -> WebClientQRCodeResult {
        // NB: Website QR code currently encoded as base 64 string
        let bytes: [UInt8] = Data(base64Encoded: qrCodeData)?.bytes ?? qrCodeData.bytes
        if let version = bytes.first, version != 1 {
            return .unsupportedOrInvalid
        } else if bytes.count != 33 {
            return .invalid
        } else {
            return .valid(Data(bytes[1...32]))
        }
    }
}

public extension Data {
    func base64PrefixForLogs() -> String {
        return String(base64EncodedString().prefix(8))
    }
}
