//
//  XMPPWhisper.swift
//  Core
//
//  Created by Tony Jiang on 8/6/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation

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

public struct WhisperKeyBundle {
    
    public var identity: Data? = nil
    public var signed: PreKey? = nil
    public var signature: Data? = nil
    public var oneTime: [PreKey] = []

    // init outgoing key bundle
    public init(identity: Data, signed: PreKey, signature: Data, oneTime: [PreKey]) {
        self.identity = identity
        self.signed = signed
        self.signature = signature
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

