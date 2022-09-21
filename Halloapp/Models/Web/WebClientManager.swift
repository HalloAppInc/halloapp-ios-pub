//
//  WebClientManager.swift
//  HalloApp
//
//  Created by Garrett on 6/6/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import Foundation
import SwiftNoise
import CoreData

protocol WebClientManagerDelegate: AnyObject {
    func webClientManager(_ manager: WebClientManager, didUpdateWebStaticKey staticKey: Data?)
}

final class WebClientManager {

    init(
        service: CoreServiceCommon,
        dataStore: MainDataStore,
        noiseKeys: NoiseKeys,
        webStaticKey: Data? = nil)
    {
        self.service = service
        self.dataStore = dataStore
        self.noiseKeys = noiseKeys
        self.webStaticKey = webStaticKey
    }

    enum State {
        case disconnected
        case registering(Data)
        case handshaking(HandshakeState)
        case connected(CipherState, CipherState)
    }

    weak var delegate: WebClientManagerDelegate?
    var state = CurrentValueSubject<State, Never>(.disconnected)

    private let service: CoreServiceCommon
    private let dataStore: MainDataStore
    private let noiseKeys: NoiseKeys
    private let webQueue = DispatchQueue(label: "hallo.web", qos: .userInitiated)

    private(set) var webStaticKey: Data?
    private var keysToRemove = Set<Data>()
    private var isRemovingKeys = false

    func connect(staticKey: Data) {
        webQueue.async {
            switch self.state.value {
            case .disconnected, .connected:
                // OK to start new connection
                break
            case .registering, .handshaking:
                DDLogInfo("WebClientManager/connect/aborting [state: \(self.state.value)]")
                return
            }
            if let oldKey = self.webStaticKey {
                if oldKey == staticKey {
                    DDLogInfo("WebClientManager/connect/skipping-to-handshake [key-already-registered]")
                    self.initiateHandshake(useKK: true)
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

                case .failure:
                    self.disconnect(shouldRemoveOldKey: false)
                }
            }
            self.removeOldKeysIfNecessary()
        }
    }

    func disconnect(shouldRemoveOldKey: Bool = true) {
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

    func handleIncomingData(_ data: Data, from staticKey: Data) {
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
            switch container.payload {
            case .feedResponse:
                DDLogError("WebClientManager/handleIncoming/feedResponse/error [invalid-payload]")
            case .feedUpdate:
                DDLogError("WebClientManager/handleIncoming/feedUpdate/error [invalid-payload]")
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
    }

    func handleIncomingNoiseMessage(_ noiseMessage: Server_NoiseMessage, from staticKey: Data) {
        guard staticKey == self.webStaticKey else {
            DDLogError("WebClientManager/handleIncomingNoiseMessage/error [unrecognized-static-key: \(staticKey.base64EncodedString())] [expected: \(self.webStaticKey?.base64EncodedString() ?? "nil")]")
            return
        }
        switch state.value {
        case .handshaking(let handshake):
            continueHandshake(handshake, with: noiseMessage)
        case .connected, .disconnected, .registering:
            receiveHandshake(with: noiseMessage)
        }
    }

    func send(_ data: Data) {
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
            let msgB = try handshake.writeMessage(payload: Data())
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
    private func initiateHandshake(useKK: Bool = false) {
        guard let ephemeralKeys = NoiseKeys() else {
            DDLogError("WebClientManager/initiateHandshake/error [keygen-failure]")
            disconnect()
            return
        }
        let handshake: HandshakeState
        do {
            handshake = try HandshakeState(
                pattern: useKK ? .KK : .IK,
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
            let msgA = try handshake.writeMessage(payload: Data())
            self.sendNoiseMessage(msgA, type: useKK ? .kkA : .ikA)
            // TODO: Set timeout
        } catch {
            DDLogError("WebClientManager/initiateHandshake/error [\(error)]")
        }
    }

    private func continueHandshake(_ handshake: HandshakeState, with noiseMessage: Server_NoiseMessage) {
        do {
            let data = try handshake.readMessage(message: noiseMessage.content)
            DDLogInfo("WebClientManager/handshake/reading data [\(data.count) bytes]")
        } catch {
            DDLogError("WebClientManager/handshake/error [\(error)]")
            return
        }
        switch noiseMessage.messageType {
        case .ikA, .xxA, .xxB, .xxC, .kkA, .xxFallbackA, .xxFallbackB, .UNRECOGNIZED:
            DDLogError("WebClientManager/handshake/error [message-type: \(noiseMessage.messageType)]")
        case .kkB, .ikB:
            do {
                let (send, receive) = try handshake.split()
                self.state.value = .connected(send, receive)
            } catch {
                DDLogError("WebClientManager/handshake/error [message-type: \(noiseMessage.messageType)] [\(error)]")
            }
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

    // MARK: Feed

    private lazy var homeFeedDataSource: FeedDataSource = {
        return FeedDataSource(fetchRequest: FeedDataSource.homeFeedRequest())
    }()

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
        case .UNRECOGNIZED:
            DDLogInfo("WebClientManager/handleIncoming/feedRequest/unsupported [\(request.type)]")
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
        fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPostComment.timestamp, ascending: true) ]

        let frc = NSFetchedResultsController<FeedPostComment>(
            fetchRequest: fetchRequest,
            managedObjectContext: MainAppContext.shared.mainDataStore.viewContext,
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

        var usersToInclude = Set<UserID>()
        // Include info for all users who have commented.
        usersToInclude.formUnion(comments.map { $0.userID })
        // Include info for all users who are mentioned in comments.
        usersToInclude.formUnion(comments.flatMap { $0.mentions }.map { $0.userID })

        var response = Web_FeedResponse()
        response.type = type
        response.userDisplayInfo = userDisplayInfo(for: usersToInclude)
        if let nextCursor = nextCursor {
            response.nextCursor = nextCursor
        }
        response.items = comments.compactMap { comment in
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

        return response
    }

    private func feedResponse(with posts: [FeedPost], type: Web_FeedType, nextCursor: String?) -> Web_FeedResponse {
        let currentUserID = MainAppContext.shared.userData.userId

        var usersToInclude = Set<UserID>()
        // Include info for all users who have posted.
        usersToInclude.formUnion(posts.map { $0.userID })
        // Include info for all users who are mentioned in posts.
        usersToInclude.formUnion(posts.flatMap { $0.mentions }.map { $0.userID })
        // Include info for all users who have seen your posts.
        usersToInclude.formUnion(posts.flatMap { $0.seenReceipts }.map { $0.userId })

        let groupsToInclude = Set<GroupID>(posts.compactMap { $0.groupID })
        let groupDisplayInfo: [Web_GroupDisplayInfo] = groupsToInclude.compactMap { groupID in
            guard let group = self.dataStore.group(id: groupID, in: self.dataStore.viewContext) else {
                DDLogError("WebClientManager/homeFeed/group/error [not-found] [id: \(groupID)]")
                return nil
            }
            return self.groupDisplayInfo(for: group)
        }

        var response = Web_FeedResponse()
        response.type = type
        response.userDisplayInfo = userDisplayInfo(for: usersToInclude)
        response.postDisplayInfo = posts.map { self.postDisplayInfo(for: $0, currentUserID: currentUserID) }
        response.groupDisplayInfo = groupDisplayInfo
        if let nextCursor = nextCursor {
            response.nextCursor = nextCursor
        }
        response.items = posts.compactMap { post in
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
            if let groupID = post.groupID {
                feedItem.groupID = groupID
            }
            return feedItem
        }

        return response
    }

    // MARK: DisplayInfo

    func userDisplayInfo(for userIDs: Set<UserID>) -> [Web_UserDisplayInfo] {
        let contactNames = MainAppContext.shared.contactStore.fullNames(forUserIds: userIDs)
        let avatarIDs = MainAppContext.shared.avatarStore.avatarIDs(forUserIDs: userIDs)

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

    func groupDisplayInfo(for group: Group) -> Web_GroupDisplayInfo {
        var info = Web_GroupDisplayInfo()
        info.id = group.id
        info.name = group.name
        if let avatarID = group.avatarID {
            info.avatarID = avatarID
        }
        if let description = group.desc {
            info.description_p = description
        }
        var background = Clients_Background()
        background.theme = group.background
        if let backgroundData = try? background.serializedData() {
            info.background = String(decoding: backgroundData, as: UTF8.self)
        }

        return info
    }

    func postDisplayInfo(for post: FeedPost, currentUserID: UserID) -> Web_PostDisplayInfo {
        var info = Web_PostDisplayInfo()
        info.id = post.id
        info.isUnsupported = post.isUnsupported
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
        info.userReceipts = post.seenReceipts.compactMap {
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

    static func from(qrCodeData: Data) -> WebClientQRCodeResult {
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

extension Data {
    func base64PrefixForLogs() -> String {
        return String(base64EncodedString().prefix(8))
    }
}
