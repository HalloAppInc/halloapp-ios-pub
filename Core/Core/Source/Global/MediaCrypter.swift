//
//  MediaCrypter.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import CommonCrypto
import CryptoKit
import CryptoSwift
import Foundation

fileprivate protocol Crypter {
    func encrypt(_ plaintext: Data) throws -> Data
    func decrypt(_ encrypted: Data) throws -> Data
}

fileprivate struct AES256Crypter {

    private let key: Data
    private let iv: Data

    init(key: Data, iv: Data) throws {
        guard key.count == kCCKeySizeAES256 else {
            throw Error.badKeyLength
        }
        guard iv.count == kCCBlockSizeAES128 else {
            throw Error.badInputVectorLength
        }
        self.key = key
        self.iv = iv
    }

    enum Error: Swift.Error {
        case cryptoFailed(status: CCCryptorStatus)
        case badKeyLength
        case badInputVectorLength
    }

    func crypt(input: Data, operation: CCOperation) throws -> Data {
        var outLength = Int(0)
        var outBytes = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var status: CCCryptorStatus = CCCryptorStatus(kCCSuccess)
        input.withUnsafeBytes { (inputBytes: UnsafeRawBufferPointer) -> () in
            iv.withUnsafeBytes { (ivBytes: UnsafeRawBufferPointer) in
                key.withUnsafeBytes { (keyBytes: UnsafeRawBufferPointer) -> () in
                    status = CCCrypt(
                        operation,
                        CCAlgorithm(kCCAlgorithmAES),            // algorithm
                        CCOptions(kCCOptionPKCS7Padding),        // options
                        keyBytes.baseAddress,                    // key
                        key.count,                               // keylength
                        ivBytes.baseAddress,                     // iv
                        inputBytes.baseAddress,                  // dataIn
                        input.count,                             // dataInLength
                        &outBytes,                               // dataOut
                        outBytes.count,                          // dataOutAvailable
                        &outLength)                              // dataOutMoved
                }
            }
        }
        guard status == kCCSuccess else {
            throw Error.cryptoFailed(status: status)
        }
        return Data(bytes: outBytes, count: outLength)
    }
}

extension AES256Crypter: Crypter {

    func encrypt(_ plaintext: Data) throws -> Data {
        return try crypt(input: plaintext, operation: CCOperation(kCCEncrypt))
    }

    func decrypt(_ encrypted: Data) throws -> Data {
        return try crypt(input: encrypted, operation: CCOperation(kCCDecrypt))
    }

}

public class MediaCrypter {

    private static let attachedKeyLength = 32
    private static let expandedKeyLength = 80

    enum Error: Swift.Error {
        case keyGeneration(status: Int)
        case hashMismatch
        case MACMismatch
    }

    private class func randomKey(_ count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let result = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard result == errSecSuccess else {
            DDLogError("HAC/generateKey error=[\(result)]")
            throw Error.keyGeneration(status: Int(result))
        }
        return Data(bytes: bytes, count: count)
    }

    private class func HKDFInfo(for mediaType: FeedMediaType) -> [UInt8] {
        return (mediaType == .image ? "HalloApp image" : "HalloApp video").bytes
    }

    private class func expandedKey(from key: Data, mediaType: FeedMediaType) throws -> Data {
        let expandedKeyBytes = try HKDF(password: key.bytes, info: HKDFInfo(for: mediaType), keyLength: MediaCrypter.expandedKeyLength, variant: .sha256).calculate()
        return Data(bytes: expandedKeyBytes, count: expandedKeyBytes.count)
    }
    
    public class func encrypt(data: Data, mediaType: FeedMediaType) throws -> (Data, Data, Data) {
        let mediaKey = try MediaCrypter.randomKey(MediaCrypter.attachedKeyLength)
        let expandedKey = try MediaCrypter.expandedKey(from: mediaKey, mediaType: mediaType)

        let IV = expandedKey[0...15]
        let AESKey = expandedKey[16...47]
        let SHA256Key = expandedKey[48...79]

        var encryptedData = try AES256Crypter(key: AESKey, iv: IV).encrypt(data)
        encryptedData.append(contentsOf: CryptoKit.HMAC<SHA256>.authenticationCode(for: encryptedData, using: SymmetricKey(data: SHA256Key)))

        let sha256Hash = SHA256.hash(data: encryptedData).data
        return (encryptedData, mediaKey, sha256Hash)
    }
    
    public class func decrypt(data: Data, mediaKey: Data, sha256hash: Data, mediaType: FeedMediaType) throws -> Data {
        let expandedKey = try MediaCrypter.expandedKey(from: mediaKey, mediaType: mediaType)

        let IV = expandedKey[0...15]
        let AESKey = expandedKey[16...47]
        let SHA256Key = expandedKey[48...79]

        let digest = SHA256.hash(data: data)
        guard digest == sha256hash else {
            throw Error.hashMismatch
        }

        let attachedMAC = data.suffix(32)
        let encryptedData = data.dropLast(32)

        let MAC = CryptoKit.HMAC<SHA256>.authenticationCode(for: encryptedData, using: SymmetricKey(data: SHA256Key))
        guard MAC == attachedMAC.bytes else {
            throw Error.MACMismatch
        }

        let decryptedData = try AES256Crypter(key: AESKey, iv: IV).decrypt(encryptedData)
        return decryptedData
    }

}
