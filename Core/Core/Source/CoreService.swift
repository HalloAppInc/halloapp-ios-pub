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

public enum Feed {
    case personal(FeedAudience)
    case group(GroupID)
}

public typealias ServiceRequestCompletion<T> = (Result<T, Error>) -> Void

public typealias AvatarInfo = (userID: UserID, avatarID: AvatarID)
public typealias EncryptedData = (data: Data?, identityKey: Data?, oneTimeKeyId: Int32)
public typealias EncryptOperation = (_ data: Data, _ completion: @escaping (EncryptedData) -> Void) -> Void
public typealias ServerPropertiesResponse = (version: String, properties: [String: String])

/// Core aspects of the service available in extensions
public protocol CoreService {

    // MARK: Connection
    var didConnect: PassthroughSubject<Void, Never> { get }
    var connectionState: ConnectionState { get }
    var isConnected: Bool { get }
    var isDisconnected: Bool { get }
    func startConnectingIfNecessary()
    func disconnectImmediately()
    func disconnect()
    func connect()
    func execute(whenConnectionStateIs state: ConnectionState, onQueue queue: DispatchQueue, work: @escaping @convention(block) () -> Void)

    // MARK: Feed
    func requestMediaUploadURL(size: Int, completion: @escaping ServiceRequestCompletion<MediaURLInfo>)
    func publishPost(_ post: FeedPostProtocol, feed: Feed, completion: @escaping ServiceRequestCompletion<Date?>)
    func publishComment(_ comment: FeedCommentProtocol, completion: @escaping ServiceRequestCompletion<Date?>)

    // MARK: Chat
    func sendChatMessage(_ message: ChatMessageProtocol, encryption: EncryptOperation?)

    // MARK: Delegates
    var avatarDelegate: ServiceAvatarDelegate? { get set }
}

public protocol ServiceAvatarDelegate: AnyObject {
    func service(_ service: CoreService, didReceiveAvatarInfo avatarInfo: AvatarInfo)
}

