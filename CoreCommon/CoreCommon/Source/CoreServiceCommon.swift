//
//  CoreServiceCommon.swift
//  CoreCommon
//
//  Created by Nandini Shetty on 3/2/22.
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

public enum PresenceType: String {
    case available = "available"
    case away = "away"
}

public typealias ServiceRequestCompletion<T> = (Result<T, RequestError>) -> Void

public typealias ServerPropertiesResponse = (version: String, properties: [String: String])

/// Core aspects of the service available in extensions
public protocol CoreServiceCommon {

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

    // MARK: Keys
    func requestWhisperKeyBundle(userID: UserID, completion: @escaping ServiceRequestCompletion<WhisperKeyBundle>)
    func requestCountOfOneTimeKeys(completion: @escaping ServiceRequestCompletion<Int32>)
    func requestAddOneTimeKeys(_ keys: [PreKey], completion: @escaping ServiceRequestCompletion<Void>)

    // MARK: Groups
    func getGroupPreviewWithLink(inviteLink: String, completion: @escaping ServiceRequestCompletion<Server_GroupInviteLink>)
    func joinGroupWithLink(inviteLink: String, completion: @escaping ServiceRequestCompletion<Server_GroupInviteLink>)

    // MARK: Delegates
    var keyDelegate: ServiceKeyDelegate? { get set }
}

public protocol ServiceKeyDelegate: AnyObject {
    func service(_ service: CoreServiceCommon, didReceiveWhisperMessage message: WhisperMessage)
    func service(_ service: CoreServiceCommon, didReceiveRerequestWithRerequestCount retryCount: Int)
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
