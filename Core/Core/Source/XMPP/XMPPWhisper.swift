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

    // init incoming key bundle
    public init?(itemElement item: XMLElement) {
        guard let whisperKeys = item.element(forName: "whisper_keys") else { return nil }

        var protoIdentity: Data?, protoSigned: PreKey?, protoSignature: Data?

        guard let identityKey = whisperKeys.element(forName: "identity_key")?.stringValue else { return nil }
        guard let identityKeyData = Data(base64Encoded: identityKey, options: .ignoreUnknownCharacters) else { return nil }
        
        do {
            let protoContainer = try Clients_IdentityKey(serializedData: identityKeyData)
            protoIdentity = protoContainer.publicKey
        }
        catch {
            DDLogError("xmpp/chatmessage/invalid-protobuf")
        }
        
        guard let signedKey = whisperKeys.element(forName: "signed_key")?.stringValue else { return nil }
        guard let signedKeyData = Data(base64Encoded: signedKey, options: .ignoreUnknownCharacters) else { return nil }

        do {
            let protoContainer = try Clients_SignedPreKey(serializedData: signedKeyData)
            protoSigned = PreKey(id: protoContainer.id, privateKey: nil, publicKey: protoContainer.publicKey)
            protoSignature = protoContainer.signature
        }
        catch {
            DDLogError("xmpp/chatmessage/invalid-protobuf")
        }

        // ideally there should be an one time key but there might not be
        if let oneTimeKey = whisperKeys.element(forName: "one_time_key")?.stringValue {
            if let oneTimeKeyData = Data(base64Encoded: oneTimeKey, options: .ignoreUnknownCharacters) {
                do {
                    let protoContainer = try Clients_OneTimePreKey(serializedData: oneTimeKeyData)
                    self.oneTime.append(PreKey(id: protoContainer.id, privateKey: nil, publicKey: protoContainer.publicKey))
                }
                catch {
                    DDLogError("xmpp/chatmessage/invalid-protobuf")
                }
            }
        }
        
        guard let identity = protoIdentity else { return nil }
        guard let signed = protoSigned else { return nil }
        guard let signature = protoSignature else { return nil }
        
        self.type = .set
        self.identity = identity
        self.signed = signed
        self.signature = signature
    }
    
    public var xmppElement: XMPPElement {
        get {
            let whisperKeys = XMPPElement(name: "whisper_keys", xmlns: "halloapp:whisper:keys")
            
            whisperKeys.addAttribute(withName: "type", stringValue: self.type.rawValue)
            
            if (self.type == .set) {
                
                var protoIdentityKey = Clients_IdentityKey()
                guard let identity = self.identity else { return whisperKeys }
                protoIdentityKey.publicKey = identity
                
                if let protoIdentityKeyData = try? protoIdentityKey.serializedData() {
                    whisperKeys.addChild(XMPPElement(name: "identity_key", stringValue: protoIdentityKeyData.base64EncodedString()))
                }
                
                var protoSignedPreKey = Clients_SignedPreKey()
                guard let signed = self.signed else { return whisperKeys }
                protoSignedPreKey.id = signed.id
                protoSignedPreKey.publicKey = signed.publicKey
                guard let signature = self.signature else { return whisperKeys }
                protoSignedPreKey.signature = signature
                
                if let protoSignedPreKeyData = try? protoSignedPreKey.serializedData() {
                    whisperKeys.addChild(XMPPElement(name: "signed_key", stringValue: protoSignedPreKeyData.base64EncodedString()))
                }
                
            }
            
            for oneTimeKey in oneTime {
            
                var protoOneTimePreKey = Clients_OneTimePreKey()
                protoOneTimePreKey.id = oneTimeKey.id
                protoOneTimePreKey.publicKey = oneTimeKey.publicKey
                if let protoOneTimePreKeyData = try? protoOneTimePreKey.serializedData() {
                    whisperKeys.addChild(XMPPElement(name: "one_time_key", stringValue: protoOneTimePreKeyData.base64EncodedString()))
                }
                
            }
            return whisperKeys
        }
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

