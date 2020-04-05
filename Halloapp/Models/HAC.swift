//
//  HACrypto.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import CryptoKit
import CryptoSwift
import Foundation

class HAC {

    private static let keyLength = 80

    class func generateKey(_ count: Int) -> [UInt8]? {
        var key = [UInt8](repeating: 0, count: count)
        let result = SecRandomCopyBytes(kSecRandomDefault, count, &key)
        guard result == errSecSuccess else {
            DDLogError("HAC/generateKey error=[\(result)]")
            return nil
        }
        return key
    }

    class func byteArray(fromBase64 base64String: String) -> [UInt8]? {
        guard let data = Data(base64Encoded: base64String) else {
            DDLogError("HAC/byteArray Invalid base64 input")
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: data.count)
        data.copyBytes(to: &bytes, count: data.count)
        return bytes
    }

    class func HKDFInfo(for mediaType: FeedMediaType) -> [UInt8] {
        return (mediaType == .image ? "HalloApp image" : "HalloApp video").bytes
    }
    
    class func expandedKey(from base64Key: String, mediaType: FeedMediaType) -> [UInt8]? {
        guard let key = byteArray(fromBase64: base64Key) else {
            return nil
        }
        var expandedKey: [UInt8]
        do {
            expandedKey = try HKDF(password: key, info: HKDFInfo(for: mediaType), keyLength: HAC.keyLength, variant: .sha256).calculate()
        }
        catch {
            DDLogError("HAC/HKDF/calculate/error [\(error)]")
            return nil
        }
        return expandedKey
    }

    class func newExpandedKey(for mediaType: FeedMediaType) -> (String, [UInt8])? {
        guard let key = generateKey(32) else {
            return nil
        }
        var expandedKey: [UInt8]
        do {
            expandedKey = try HKDF(password: key, info: HKDFInfo(for: mediaType), keyLength: HAC.keyLength, variant: .sha256).calculate()
        }
        catch {
            DDLogError("HAC/HKDF/calculate/error [\(error)]")
            return nil
        }
        let base64StringKey = Data(bytes: key, count: key.count).base64EncodedString()
        return (base64StringKey, expandedKey)
    }
    
    class func encrypt(data: Data, mediaType: FeedMediaType) -> (Data, String, String)? {
        let target: [UInt8] = [UInt8](data)

        guard let (base64Key, expandedKey) = newExpandedKey(for: mediaType) else {
            return nil
        }
        
        let randomIV = Array(expandedKey[0...15])
        let AESKey = Array(expandedKey[16...47])
        let SHAKey = Array(expandedKey[48...79])
        do {
            let aes = try AES(key: AESKey, blockMode: CBC(iv: randomIV), padding: .pkcs5)
            var encrypted = try aes.encrypt(target)
            let MAC = try HMAC(key: SHAKey, variant: .sha256).authenticate(encrypted)
            DDLogDebug("HAC/encrypt MAC=[\(MAC.count)]")
            encrypted.append(contentsOf: MAC)
            DDLogDebug("HAC/encrypt w/authen=[\(encrypted.count)]")
            
            let digest = SHA256.hash(data: encrypted)
            let base64Hash = digest.data.base64EncodedString()
            let encryptedData = Data(bytes: encrypted, count: encrypted.count)
            return (encryptedData, base64Key, base64Hash)
        } catch {
            DDLogError("HAC/encrypt/error [\(error)")
            return nil
        }
    }
    
    class func decrypt(data: Data, key: String, sha256hash: String, mediaType: FeedMediaType) -> Data? {
        var target: [UInt8] = [UInt8](data)
        
        guard let expandedKey = expandedKey(from: key, mediaType: mediaType) else {
            return nil
        }
        
        let randomIV = Array(expandedKey[0...15])
        let AESKey = Array(expandedKey[16...47])
        let SHAKey = Array(expandedKey[48...79])
        do {
            let digest = SHA256.hash(data: target)
            let base64String = digest.data.base64EncodedString()
            guard base64String == sha256hash else {
                DDLogError("HAC/decrypt/error sha256 mismatch [\(base64String)]")
                return nil
            }
            
            let attachedMAC = Array(target.suffix(32))
            target.removeLast(32)

            let MAC = try HMAC(key: SHAKey, variant: .sha256).authenticate(target)
            guard attachedMAC == MAC else {
                DDLogError("HAC/decrypt/error MAC mismatch")
                return nil
            }
            
            let decrypted = try AES(key: AESKey, blockMode: CBC(iv: randomIV), padding: .pkcs5).decrypt(target)
            let decryptedData = Data(bytes: decrypted, count: decrypted.count)
            return decryptedData
        } catch {
            DDLogError("HAC/decrypt/error [\(error)")
            return nil
        }
    }
}
