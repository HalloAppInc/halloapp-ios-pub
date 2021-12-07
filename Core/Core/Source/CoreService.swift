//
//  HalloService.swift
//  Core
//
//  Created by Garrett on 8/17/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Combine
import Foundation

public enum ConnectionState {
    case notConnected
    case connecting
    case connected
    case disconnecting
}

public enum ReachablilityState {
    case reachable
    case unreachable
}

public enum Feed {
    case personal(FeedAudience)
    case group(GroupID)
}

public typealias ServiceRequestCompletion<T> = (Result<T, RequestError>) -> Void

public typealias AvatarInfo = (userID: UserID, avatarID: AvatarID)
public typealias ServerPropertiesResponse = (version: String, properties: [String: String])

/// Core aspects of the service available in extensions
public protocol CoreService {

    // MARK: App expiration
    var isAppVersionKnownExpired: CurrentValueSubject<Bool, Never> { get }
    var isAppVersionCloseToExpiry: CurrentValueSubject<Bool, Never> { get }

    // MARK: Connection
    var credentials: Credentials? { get set }
    var useTestServer: Bool { get set }
    var hostName: String { get }
    var didConnect: PassthroughSubject<Void, Never> { get }
    var didDisconnect: PassthroughSubject<Void, Never> { get }
    var connectionState: ConnectionState { get }
    var isConnected: Bool { get }
    var isDisconnected: Bool { get }
    var reachabilityState: ReachablilityState { get set }
    var reachabilityConnectionType: String { get set }
    var isReachable: Bool { get }
    func startConnectingIfNecessary()
    func disconnectImmediately()
    func disconnect()
    func connect()
    func execute(whenConnectionStateIs state: ConnectionState, onQueue queue: DispatchQueue, work: @escaping @convention(block) () -> Void)

    // MARK: Feed
    func requestMediaUploadURL(size: Int, downloadURL: URL?, completion: @escaping ServiceRequestCompletion<MediaURLInfo?>)
    func publishPost(_ post: PostData, feed: Feed, completion: @escaping ServiceRequestCompletion<Date>)
    func publishComment(_ comment: CommentData, groupId: GroupID?, completion: @escaping ServiceRequestCompletion<Date>)
    func resendPost(_ post: PostData, feed: Feed, rerequestCount: Int32, to toUserID: UserID, completion: @escaping ServiceRequestCompletion<Void>)
    func resendComment(_ comment: CommentData, groupId: GroupID?, rerequestCount: Int32, to toUserID: UserID, completion: @escaping ServiceRequestCompletion<Void>)
    func decryptGroupFeedPayload(for item: Server_GroupFeedItem, in groupID: GroupID, completion: @escaping (FeedContent?, GroupDecryptionFailure?) -> Void)
    func processGroupFeedRetract(for item: Server_GroupFeedItem, in groupID: GroupID, completion: @escaping () -> Void)
    func rerequestGroupFeedItemIfNecessary(id contentID: String, groupID: GroupID, failure: GroupDecryptionFailure, completion: @escaping ServiceRequestCompletion<Void>)

    // MARK: Keys
    func getGroupMemberIdentityKeys(groupID: GroupID, completion: @escaping ServiceRequestCompletion<Server_GroupStanza>)
    func requestWhisperKeyBundle(userID: UserID, completion: @escaping ServiceRequestCompletion<WhisperKeyBundle>)
    func requestCountOfOneTimeKeys(completion: @escaping ServiceRequestCompletion<Int32>)
    func requestAddOneTimeKeys(_ keys: [PreKey], completion: @escaping ServiceRequestCompletion<Void>)

    // MARK: Chat
    func sendChatMessage(_ message: ChatMessageProtocol, completion: @escaping ServiceRequestCompletion<Void>)
    func sendAck(messageId: String, completion: @escaping ServiceRequestCompletion<Void>)
    func decryptChat(_ serverChat: Server_ChatStanza, from fromUserID: UserID, completion: @escaping (ChatContent?, ChatContext?, DecryptionFailure?) -> Void)
    func rerequestMessage(_ messageID: String, senderID: UserID, failedEphemeralKey: Data?, contentType: Server_Rerequest.ContentType, completion: @escaping ServiceRequestCompletion<Void>)

    // MARK: Groups
    func getGroupPreviewWithLink(inviteLink: String, completion: @escaping ServiceRequestCompletion<Server_GroupInviteLink>)
    func joinGroupWithLink(inviteLink: String, completion: @escaping ServiceRequestCompletion<Server_GroupInviteLink>)

    // MARK: Event Logging
    func log(countableEvents: [CountableEvent], discreteEvents: [DiscreteEvent], completion: @escaping ServiceRequestCompletion<Void>)

    // MARK: Delegates
    var avatarDelegate: ServiceAvatarDelegate? { get set }
    var keyDelegate: ServiceKeyDelegate? { get set }
}

public protocol ServiceAvatarDelegate: AnyObject {
    func service(_ service: CoreService, didReceiveAvatarInfo avatarInfo: AvatarInfo)
}

public protocol ServiceKeyDelegate: AnyObject {
    func service(_ service: CoreService, didReceiveWhisperMessage message: WhisperMessage)
    func service(_ service: CoreService, didReceiveRerequestWithRerequestCount retryCount: Int)
}

public struct RerequestData {
    public init(identityKey: Data, signedPreKeyID: Int, oneTimePreKeyID: Int? = nil, sessionSetupEphemeralKey: Data, messageEphemeralKey: Data? = nil) {
        self.identityKey = identityKey
        self.signedPreKeyID = signedPreKeyID
        self.oneTimePreKeyID = oneTimePreKeyID
        self.sessionSetupEphemeralKey = sessionSetupEphemeralKey
        self.messageEphemeralKey = messageEphemeralKey
    }

    public var identityKey: Data
    public var signedPreKeyID: Int
    public var oneTimePreKeyID: Int?
    public var sessionSetupEphemeralKey: Data
    public var messageEphemeralKey: Data?
}

public struct EncryptedData {
    public init(data: Data, identityKey: Data? = nil, oneTimeKeyId: Int) {
        self.data = data
        self.identityKey = identityKey
        self.oneTimeKeyId = oneTimeKeyId
    }

    public var data: Data
    public var identityKey: Data?
    public var oneTimeKeyId: Int
}
