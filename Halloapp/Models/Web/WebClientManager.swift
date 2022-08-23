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

final class WebClientManager {

    init(service: CoreServiceCommon, noiseKeys: NoiseKeys) {
        self.service = service
        self.noiseKeys = noiseKeys
    }

    enum State {
        case disconnected
        case registering
        case handshaking(HandshakeState)
        case connected(CipherState, CipherState)
    }

    let service: CoreServiceCommon
    let noiseKeys: NoiseKeys
    var state = CurrentValueSubject<State, Never>(.disconnected)

    private let webQueue = DispatchQueue(label: "hallo.web", qos: .userInitiated)
    // TODO: Persist keys
    private(set) var webStaticKey: Data?
    private var keysToRemove = Set<Data>()
    private var isRemovingKeys = false


    func connect(staticKey: Data) {
        webQueue.async {
            if let oldKey = self.webStaticKey {
                if oldKey == staticKey {
                    DDLogInfo("WebClientManager/connect/skipping [matches-current-key] [\(oldKey)]")
                    return
                } else {
                    DDLogInfo("WebClientManager/connect/will-remove-old-key [\(oldKey)]")
                    self.keysToRemove.insert(oldKey)
                }
            }
            self.webStaticKey = staticKey
            self.state.value = .registering
            self.service.authenticateWebClient(staticKey: staticKey) { [weak self] result in
                switch result {
                case .success:
                    self?.startHandshake()

                case .failure:
                    self?.disconnect(shouldRemoveOldKey: false)
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
            self.removeOldKeysIfNecessary()
        }
    }

    func handleIncomingData(_ data: Data, from staticKey: Data) {
        webQueue.async {
            guard staticKey == self.webStaticKey else {
                DDLogError("WebClientManager/handleIncoming/error [unrecognized-static-key: \(staticKey.base64EncodedString())] [expected: \(self.webStaticKey?.base64EncodedString() ?? "nil")]")
                return
            }
            guard case .connected(_, let recv) = self.state.value else {
                DDLogError("WebClientManager/handleIncoming/error [not-connected]")
                return
            }
            guard let decryptedData = try? recv.decryptWithAd(ad: Data(), ciphertext: data) else {
                DDLogError("WebClientManager/handleIncoming/error could not decrypt auth result [\(data.base64EncodedString())]")
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
            case .feedRequest(let request):
                DDLogInfo("WebClientManager/handleIncoming/feedRequest")
                let cursor = request.cursor.isEmpty ? nil : request.cursor
                DispatchQueue.main.async {
                    var webContainer = Web_WebContainer()
                    let feed = self.homeFeed(cursor: cursor, limit: Int(request.limit))
                    webContainer.payload = .feedResponse(feed)
                    do {
                        DDLogInfo("WebClientManager/handleIncoming/feedRequest/sending [\(feed.items.count)]")
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
            DDLogError("WebClientManager/handleIncoming/error [unrecognized-static-key: \(staticKey.base64EncodedString())] [expected: \(self.webStaticKey?.base64EncodedString() ?? "nil")]")
            return
        }
        continueHandshake(noiseMessage)
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

    private func startHandshake() {
        guard let ephemeralKeys = NoiseKeys() else {
            DDLogError("WebClientManager/startHandshake/error [keygen-failure]")
            disconnect()
            return
        }
        let handshake: HandshakeState
        do {
            handshake = try HandshakeState(
                pattern: .IK,
                initiator: true,
                prologue: Data(),
                s: noiseKeys.makeX25519KeyPair(),
                e: ephemeralKeys.makeX25519KeyPair(),
                rs: webStaticKey)
        } catch {
            DDLogError("WebClientManager/startHandshake/error [\(error)]")
            disconnect()
            return
        }
        self.state.value = .handshaking(handshake)
        do {
            let msgA = try handshake.writeMessage(payload: Data())
            self.sendNoiseMessage(msgA, type: .ikA)
            // TODO: Set timeout
        } catch {
            DDLogError("WebClientManager/startHandshake/error [\(error)]")
        }
    }

    private func continueHandshake(_ noiseMessage: Server_NoiseMessage) {
        guard case .handshaking(let handshake) = state.value else {
            DDLogError("WebClientManager/handshake/error [state: \(state.value)]")
            return
        }
        do {
            let data = try handshake.readMessage(message: noiseMessage.content)
            DDLogInfo("WebClientManager/handshake/reading data [\(data.count) bytes]")
        } catch {
            DDLogError("WebClientManager/handshake/error [\(error)]")
            return
        }
        switch noiseMessage.messageType {
        case .ikA, .xxA, .xxB, .xxC, .xxFallbackA, .xxFallbackB, .UNRECOGNIZED:
            DDLogError("WebClientManager/handshake/error [message-type: \(noiseMessage.messageType)]")
        case .ikB:
            do {
                let (send, receive) = try handshake.split()
                self.state.value = .connected(send, receive)
            } catch {
                DDLogError("WebClientManager/handshake/ikB/error [\(error)]")
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
            DDLogInfo("WebClientManager/removeOldKeys/start [\(key.base64EncodedString())]")
            group.enter()
            service.removeWebClient(staticKey: key) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .failure(let error):
                    DDLogError("WebClientManager/removeOldKeys/error [\(key.base64EncodedString())] [\(error)]")
                    group.leave()
                case .success:
                    DDLogInfo("WebClientManager/removeOldKeys/success [\(key.base64EncodedString())]")
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

    private func homeFeed(cursor: String? = nil, limit: Int) -> Web_FeedResponse {

        let cappedLimit: Int = {
            if limit <= 0 { return 20 }
            return limit > 50 ? 50 : limit
        }()

        homeFeedDataSource.setup()
        let allPosts: [FeedPost] = homeFeedDataSource.displayItems.compactMap {
            guard case .post(let post) = $0 else {
                return nil
            }
            return post
        }
        let startIndex: Int
        if let cursor = cursor, !cursor.isEmpty {
            guard let cursorIndex = allPosts.firstIndex(where: { $0.id == cursor }) else {
                var response = Web_FeedResponse()
                response.error = .invalidCursor
                response.type = .home
                return response
            }
            startIndex = cursorIndex
        } else {
            startIndex = 0
        }
        let nextIndex = startIndex + cappedLimit

        let postsForRequest: [FeedPost]
        let nextCursor: String?
        if allPosts.count > nextIndex {
            postsForRequest = Array(allPosts[startIndex..<nextIndex])
            nextCursor = allPosts[nextIndex].id
        } else {
            postsForRequest = Array(allPosts[startIndex...])
            nextCursor = nil
        }

        let currentUserID = MainAppContext.shared.userData.userId
        let postDisplayInfo: [Web_PostDisplayInfo] = postsForRequest.map { post in
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

        var usersToInclude = Set<UserID>()
        // Include info for all users who have posted.
        usersToInclude.formUnion(postsForRequest.map { $0.userID })
        // Include info for all users who are mentioned in posts.
        usersToInclude.formUnion(postsForRequest.flatMap { $0.mentions }.map { $0.userID })
        // Include info for all users who have seen your posts.
        usersToInclude.formUnion(postsForRequest.flatMap { $0.seenReceipts }.map { $0.userId })

        let contactNames = MainAppContext.shared.contactStore.fullNames(forUserIds: usersToInclude)
        let avatarIDs = MainAppContext.shared.avatarStore.avatarIDs(forUserIDs: usersToInclude)

        let userDisplayInfo: [Web_UserDisplayInfo] = usersToInclude.compactMap {
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

        var response = Web_FeedResponse()
        response.type = .home
        response.userDisplayInfo = userDisplayInfo
        response.postDisplayInfo = postDisplayInfo
        if let nextCursor = nextCursor {
            response.nextCursor = nextCursor
        }
        response.items = postsForRequest.compactMap { post in
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
            return feedItem
        }

        return response
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
