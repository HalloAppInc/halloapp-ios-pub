//
//  MediaCrypter.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
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
    private var cryptor: CCCryptorRef?

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

    mutating func cryptorInit(operation: CCOperation) throws {
        var status: CCCryptorStatus = CCCryptorStatus(kCCSuccess)
        iv.withUnsafeBytes { (ivBytes: UnsafeRawBufferPointer) in
            key.withUnsafeBytes { (keyBytes: UnsafeRawBufferPointer) -> () in
                status = CCCryptorCreate(
                                operation,
                                CCAlgorithm(kCCAlgorithmAES),           // algorithm
                                CCOptions(kCCOptionPKCS7Padding),       // options
                                keyBytes.baseAddress,                   // key
                                key.count,                              // keylength
                                ivBytes.baseAddress,                    // iv
                                &cryptor)                               // crypterContext
            }
        }
        guard status == kCCSuccess else {
            throw Error.cryptoFailed(status: status)
        }
    }

    func cryptorUpdate(input: Data) throws -> Data {
        var outLength = Int(0)
        var outBytes = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var status: CCCryptorStatus = CCCryptorStatus(kCCSuccess)
        input.withUnsafeBytes { (inputBytes: UnsafeRawBufferPointer) -> () in
            status = CCCryptorUpdate(
                cryptor,                                    // crypterContext
                inputBytes.baseAddress,                     // dataIn
                input.count,                                // dataInLength
                &outBytes,                                  // dataOut
                outBytes.count,                             // dataOutAvailable
                &outLength)                                 // dataOutMoved
        }
        guard status == kCCSuccess else {
            throw Error.cryptoFailed(status: status)
        }
        return Data(bytes: outBytes, count: outLength)
    }

    func cryptorFinal() throws -> Data {
        var outLength = CCCryptorGetOutputLength(cryptor, 0, true)
        var outBytes = [UInt8](repeating: 0, count: outLength)
        var status: CCCryptorStatus = CCCryptorStatus(kCCSuccess)
        status = CCCryptorFinal(
            cryptor,                                    // crypterContext
            &outBytes,                                  // dataOut
            outBytes.count,                             // dataOutAvailable
            &outLength)                                 // dataOutMoved
        guard status == kCCSuccess else {
            throw Error.cryptoFailed(status: status)
        }
        status = CCCryptorRelease(cryptor)
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

    mutating func decryptInit() throws {
        return try cryptorInit(operation: CCOperation(kCCDecrypt))
    }

    func decryptUpdate(_ encrypted: Data) throws -> Data {
        return try cryptorUpdate(input: encrypted)
    }

    func decryptFinal() throws -> Data {
        return try cryptorFinal()
    }

}

public enum MediaCrypterError: Error {
    case keyGeneration(status: Int)
    case hashMismatch
    case MACMismatch
}

public class MediaCrypter {

    private static let attachedKeyLength = 32
    private static let expandedKeyLength = 80

    private class func randomKey(_ count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let result = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard result == errSecSuccess else {
            DDLogError("HAC/generateKey error=[\(result)]")
            throw MediaCrypterError.keyGeneration(status: Int(result))
        }
        return Data(bytes: bytes, count: count)
    }

    private class func HKDFInfo(for mediaType: FeedMediaType) -> [UInt8] {
        switch mediaType {
        case .image:
            return "HalloApp image".bytes
        case .video:
            return "HalloApp video".bytes
        case .audio:
            return "HalloApp audio".bytes
        }
    }

    fileprivate class func expandedKey(from key: Data, mediaType: FeedMediaType) throws -> Data {
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
            throw MediaCrypterError.hashMismatch
        }

        let attachedMAC = data.suffix(32)
        let encryptedData = data.dropLast(32)

        let MAC = CryptoKit.HMAC<SHA256>.authenticationCode(for: encryptedData, using: SymmetricKey(data: SHA256Key))
        guard MAC == attachedMAC.bytes else {
            throw MediaCrypterError.MACMismatch
        }

        let decryptedData = try AES256Crypter(key: AESKey, iv: IV).decrypt(encryptedData)
        return decryptedData
    }

    public class func hash(url: URL) throws -> Data {
        return hash(data: try Data(contentsOf: url))
    }

    public class func hash(data: Data) -> Data {
        return Data(SHA256.hash(data: data))
    }

}


// TODO(murali@): extend this for encryption as well?
public class MediaChunkCrypter: MediaCrypter {
    private var aesCrypter: AES256Crypter
    private var sha256hash: Data
    private var hashContext: CC_SHA256_CTX
    private var hmacContext: CCHmacContext

    // MARK: initialization
    init(mediaKey: Data, sha256hash: Data, mediaType: FeedMediaType) throws {
        // derive and extract keys
        let expandedKey = try MediaChunkCrypter.expandedKey(from: mediaKey, mediaType: mediaType)
        let IV = expandedKey[0...15]
        let AESKey = expandedKey[16...47]
        let SHA256Key = expandedKey[48...79]

        // initialize crypter with key and initial value.
        self.aesCrypter = try AES256Crypter(key: AESKey, iv: IV)
        // store the hash to verify the hash of the entire file later.
        self.sha256hash = sha256hash
        // create sha256 context
        hashContext = CC_SHA256_CTX.init()
        // create hmac context
        hmacContext = CCHmacContext.init()

        super.init()

        // initialize sha256 hash
        CC_SHA256_Init(&hashContext)
        // initialize hmac-sha256
        SHA256Key.withUnsafeBytes { (symmetricKey: UnsafeRawBufferPointer) -> () in
            CCHmacInit(
                &hmacContext,
                CCHmacAlgorithm(kCCHmacAlgSHA256),
                symmetricKey.baseAddress,
                symmetricKey.count)
        }

    }

    // MARK: Hash verification
    // Update sha256
    public func hashUpdate(input: Data) throws {
        input.withUnsafeBytes { (inputBytes: UnsafeRawBufferPointer) -> () in
            CC_SHA256_Update(
                &hashContext,
                inputBytes.baseAddress,
                CC_LONG(input.count))
        }
    }

    // Finalize and verify hash
    public func hashFinalizeAndVerify() throws {
        let outLength = 32
        var outBytes = [UInt8](repeating: 0, count: outLength)
        CC_SHA256_Final(&outBytes, &hashContext)
        let digest = Data(bytes: outBytes, count: outLength)
        guard digest == sha256hash else {
            throw MediaCrypterError.hashMismatch
        }
    }

    // MARK: Hmac Verification
    // Update hmac-sha256
    public func hmacUpdate(input: Data) throws {
        input.withUnsafeBytes { (inputBytes: UnsafeRawBufferPointer) -> () in
            CCHmacUpdate(
                &hmacContext,
                inputBytes.baseAddress,
                inputBytes.count)
        }
    }

    // Finalize and verify hmac-sha256 signature
    public func hmacFinalizeAndVerify(attachedMAC: Data) throws {
        let macLength = 32
        var macBytes = [UInt8](repeating: 0, count: macLength)
        CCHmacFinal(&hmacContext, &macBytes)
        guard macBytes == attachedMAC.bytes else {
            throw MediaCrypterError.MACMismatch
        }
    }

    // MARK: Chunk based decryption

    public func decryptInit() throws {
        try aesCrypter.decryptInit()
    }

    public func decryptUpdate(dataChunk: Data) throws -> Data {
        try aesCrypter.decryptUpdate(dataChunk)
    }

    public func decryptFinalize() throws -> Data {
        try aesCrypter.decryptFinal()
    }

}
