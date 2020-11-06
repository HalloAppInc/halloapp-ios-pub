//
//  XMPPWhisper.swift
//  Core
//
//  Created by Tony Jiang on 8/6/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation
import XMPPFramework

public struct PreKey {
    public let id: Int32
    public let privateKey: Data?
    public let publicKey: Data
    
    public init(id: Int32, privateKey: Data? = nil, publicKey: Data) {
        self.id = id
        self.privateKey = privateKey
        self.publicKey = publicKey
    }
}

public struct XMPPWhisperKey {
    enum XMPPWhisperType: String {
        case set = "set"
        case add = "add"
    }
    
    public var identity: Data? = nil
    public var signed: PreKey? = nil
    public var signature: Data? = nil
    public var oneTime: [PreKey] = []
    let type: XMPPWhisperType

    // init outgoing key bundle
    public init(identity: Data, signed: PreKey, signature: Data, oneTime: [PreKey]) {
        self.type = .set
        self.identity = identity
        self.signed = signed
        self.signature = signature
        self.oneTime = oneTime
    }
    
    // init outgoing one time keys upload
    public init(oneTime: [PreKey]) {
        self.type = .add
        self.oneTime = oneTime
    }
    
    var protoIdentityKey: Clients_IdentityKey {
        get {
            var protoIdentityKey = Clients_IdentityKey()
            guard let identity = self.identity else { return protoIdentityKey }
            protoIdentityKey.publicKey = identity
            return protoIdentityKey
        }
    }
    
    var protoSignedPreKey: Clients_SignedPreKey {
        get {
            var protoSignedPreKey = Clients_SignedPreKey()
            guard let signed = self.signed else { return protoSignedPreKey }
            protoSignedPreKey.id = signed.id
            protoSignedPreKey.publicKey = signed.publicKey
            return protoSignedPreKey
        }
    }
    
}

