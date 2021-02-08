//
//  Keys.swift
//  Core
//
//  Created by Garrett on 2/5/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import Foundation

/// Empty protocol used to annotate keypairs
public protocol KeyType { }
public enum X25519: KeyType { }
public enum Ed: KeyType { }

public struct TypedKeyPair<T> {
    public init(privateKey: Data, publicKey: Data) {
        self.privateKey = privateKey
        self.publicKey = publicKey
    }

    public var privateKey: Data
    public var publicKey: Data
}

/// Public key with identifier
public struct PreKey {
    public init(id: Int32, publicKey: Data) {
        self.id = id
        self.publicKey = publicKey
    }

    public let id: Int32
    public let publicKey: Data
}

/// Keypair with identifier
public struct PreKeyPair<T> {
    public init(id: Int32, keyPair: TypedKeyPair<T>) {
        self.id = id
        self.keyPair = keyPair
    }

    public let id: Int32
    public let keyPair: TypedKeyPair<T>
    public var publicPreKey: PreKey {
        PreKey(id: id, publicKey: keyPair.publicKey)
    }
}

public struct UserKeys {
    public init?(
        identityEd: TypedKeyPair<Ed>,
        identityX25519: TypedKeyPair<X25519>,
        signed: PreKeyPair<X25519>,
        signature: Data,
        oneTimeKeyPairs:[PreKeyPair<X25519>])
    {
        self.identityEd = identityEd
        self.identityX25519 = identityX25519
        self.signed = signed
        self.signature = signature
        self.oneTimeKeyPairs = oneTimeKeyPairs
    }

    public var identityEd: TypedKeyPair<Ed>
    public var identityX25519: TypedKeyPair<X25519>
    public var signed: PreKeyPair<X25519>
    public var signature: Data
    public var oneTimeKeyPairs: [PreKeyPair<X25519>]

    public var whisperKeys: WhisperKeyBundle {
        WhisperKeyBundle(
            identity: identityEd.publicKey,
            signed: signed.publicPreKey,
            signature: signature,
            oneTime: oneTimeKeyPairs.map { $0.publicPreKey }
        )
    }
}

public struct WhisperKeyBundle {
    public init(identity: Data, signed: PreKey, signature: Data, oneTime: [PreKey]) {
        self.identity = identity
        self.signedPreKey = (key: signed, signature: signature)
        self.oneTime = oneTime
    }

    public var identity: Data
    public var signedPreKey: (key: PreKey, signature: Data)
    public var oneTime: [PreKey]
}

// MARK: - WhisperKeyBundle: Protobufs

public extension WhisperKeyBundle {
    var protoIdentityKey: Clients_IdentityKey {
        get {
            var protoIdentityKey = Clients_IdentityKey()
            protoIdentityKey.publicKey = identity
            return protoIdentityKey
        }
    }

    var protoSignedPreKey: Clients_SignedPreKey {
        get {
            var protoSignedPreKey = Clients_SignedPreKey()
            protoSignedPreKey.id = signedPreKey.key.id
            protoSignedPreKey.publicKey = signedPreKey.key.publicKey
            protoSignedPreKey.signature = signedPreKey.signature
            return protoSignedPreKey
        }
    }
}

// MARK: PreKey: Protobufs

public extension PreKey {
    var protoOneTimePreKey: Clients_OneTimePreKey {
        var key = Clients_OneTimePreKey()
        key.id = id
        key.publicKey = publicKey
        return key
    }
}
