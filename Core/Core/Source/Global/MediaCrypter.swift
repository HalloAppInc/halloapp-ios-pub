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

public class MediaCrypter {

    fileprivate static let attachedKeyLength = 32
    fileprivate static let expandedKeyLength = 80

    fileprivate class func randomKey(_ count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let result = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard result == errSecSuccess else {
            DDLogError("HAC/generateKey error=[\(result)]")
            throw MediaDownloadError.keyGenerationFailed
        }
        return Data(bytes: bytes, count: count)
    }

    private class func HKDFInfo(for mediaType: FeedMediaType, chunkIndex: Int? = nil) -> [UInt8] {
        switch mediaType {
        case .image:
            return "HalloApp image".bytes
        case .video:
            let index = chunkIndex ?? -1
            return (index >= 0 ? "HalloApp video \(index)" : "HalloApp video").bytes
        case .audio:
            return "HalloApp audio".bytes
        }
    }

    fileprivate class func expandedKey(from key: Data, mediaType: FeedMediaType, chunkIndex: Int? = nil) throws -> Data {
        let expandedKeyBytes = try HKDF(password: key.bytes, info: HKDFInfo(for: mediaType, chunkIndex: chunkIndex), keyLength: MediaCrypter.expandedKeyLength, variant: .sha256).calculate()
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
            throw MediaDownloadError.hashMismatch
        }

        let attachedMAC = data.suffix(32)
        let encryptedData = data.dropLast(32)

        let MAC = CryptoKit.HMAC<SHA256>.authenticationCode(for: encryptedData, using: SymmetricKey(data: SHA256Key))
        guard MAC == attachedMAC.bytes else {
            throw MediaDownloadError.macMismatch
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
            DDLogError("MediaCrypter/hashFinalizeAndVerify/failed/expected: \(sha256hash.bytes)/actual: \(digest.bytes)")
            throw MediaDownloadError.hashMismatch
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
            DDLogError("MediaCrypter/hmacFinalizeAndVerify/failed/expected: \(attachedMAC.bytes)/actual: \(macBytes)")
            throw MediaDownloadError.macMismatch
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


public class ChunkedMediaCrypter: MediaCrypter {
    public typealias ReadChunkData = ((chunkOffset: Int, chunkSize: Int)) throws -> Data
    public typealias WriteChunkData = ((chunkData: Data, chunkOffset: Int)) throws -> Void
    public struct EncryptionResult {
        public var mediaKey: Data
        public var sha256: Data
    }

    public static func encryptChunkedMedia(mediaType: FeedMediaType,
                                           chunkedParameters: ChunkedMediaParameters,
                                           readChunkData: ReadChunkData,
                                           writeChunkData: WriteChunkData) throws -> EncryptionResult {
        let encrypter = try ChunkedMediaCrypter(mediaType: mediaType)
        for chunkIndex in 0..<chunkedParameters.totalChunkCount {
            let chunkPlaintextSize = chunkedParameters.getChunkPtSize(chunkIndex: chunkIndex)
            let chunkPlaintextOffset = Int(chunkIndex) * Int(chunkedParameters.regularChunkPtSize)
            let chunkCiphertextSize = chunkedParameters.getChunkSize(chunkIndex: chunkIndex)
            let chunkCiphertextOffset = Int(chunkIndex) * Int(chunkedParameters.chunkSize)

            try autoreleasepool {
                let plaintextChunk = try readChunkData((chunkOffset: chunkPlaintextOffset, chunkSize: Int(chunkPlaintextSize)))
                if (chunkIndex < chunkedParameters.regularChunkCount && plaintextChunk.count != Int(chunkPlaintextSize)) ||
                    (chunkIndex == chunkedParameters.regularChunkCount && abs(plaintextChunk.count - Int(chunkPlaintextSize)) >= ChunkedMediaParameters.BLOCK_SIZE) {
                    DDLogDebug("ChunkedMedia/encryptChunkedMedia/debug  Unexpected plaintext size got=[\(plaintextChunk.count)] estimated=[\(chunkPlaintextSize)]")
                }

                let encryptedChunk = try encrypter.encrypt(plaintextChunk: plaintextChunk, chunkIndex: Int(chunkIndex))
                if encryptedChunk.count != chunkCiphertextSize {
                    DDLogDebug("ChunkedMedia/encryptChunkedMedia/debug  Unexpected ciphertext size got=[\(encryptedChunk.count)] expected=[\(chunkCiphertextSize)]")
                }
                try writeChunkData((chunkData: encryptedChunk, chunkOffset: chunkCiphertextOffset))
            }
        }
        return EncryptionResult(mediaKey: encrypter.mediaKey, sha256: try encrypter.hashFinalize())
    }

    public static func decryptChunkedMedia(mediaType: FeedMediaType,
                                           mediaKey: Data,
                                           sha256Hash: Data,
                                           chunkedParameters: ChunkedMediaParameters,
                                           readChunkData: ReadChunkData,
                                           writeChunkData: WriteChunkData) throws {
        let decrypter = ChunkedMediaCrypter(mediaType: mediaType, mediaKey: mediaKey)
        for chunkIndex in 0..<chunkedParameters.totalChunkCount {
            let chunkPlaintextSize = chunkedParameters.getChunkPtSize(chunkIndex: chunkIndex)
            let chunkPlaintextOffset = Int(chunkIndex) * Int(chunkedParameters.regularChunkPtSize)
            let chunkCiphertextSize = chunkedParameters.getChunkSize(chunkIndex: chunkIndex)
            let chunkCiphertextOffset = Int(chunkIndex) * Int(chunkedParameters.chunkSize)

            try autoreleasepool {
                let encryptedChunk = try readChunkData((chunkOffset: chunkCiphertextOffset, chunkSize: Int(chunkCiphertextSize)))
                if encryptedChunk.count != chunkCiphertextSize {
                    DDLogDebug("ChunkedMedia/decryptChunkedMedia/debug Unexpected ciphertext chunk size got=[\(encryptedChunk.count)] expected=[\(chunkCiphertextSize)]")
                }

                let decryptedChunk = try decrypter.decrypt(encryptedChunk: encryptedChunk, chunkIndex: Int(chunkIndex))
                if (chunkIndex < chunkedParameters.regularChunkCount && decryptedChunk.count != Int(chunkPlaintextSize)) ||
                    (chunkIndex == chunkedParameters.regularChunkCount && abs(decryptedChunk.count - Int(chunkPlaintextSize)) >= ChunkedMediaParameters.BLOCK_SIZE) {
                    DDLogDebug("ChunkedMedia/decryptChunkedMedia/debug Unexpected plaintext chunk size got=[\(decryptedChunk.count)] expected=[\(chunkPlaintextSize)]")
                }
                try writeChunkData((chunkData: decryptedChunk, chunkOffset: chunkPlaintextOffset))
            }
        }
        try decrypter.hashFinalizeAndVerify(sha256Hash: sha256Hash)
    }

    private let mediaType: FeedMediaType
    public let mediaKey: Data
    private var hashContext: CC_SHA256_CTX

    fileprivate init(mediaType: FeedMediaType, mediaKey: Data) {
        self.mediaType = mediaType
        self.mediaKey = mediaKey
        self.hashContext = CC_SHA256_CTX.init()
        CC_SHA256_Init(&hashContext)
    }

    fileprivate convenience init(mediaType: FeedMediaType) throws {
        let mediaKey = try MediaCrypter.randomKey(MediaCrypter.attachedKeyLength)
        self.init(mediaType: mediaType, mediaKey: mediaKey)
    }

    fileprivate func expandedKey(chunkIndex: Int) throws -> Data {
        return try MediaCrypter.expandedKey(from: mediaKey, mediaType: mediaType, chunkIndex: chunkIndex)
    }

    fileprivate func hashUpdate(input: Data) throws {
        input.withUnsafeBytes { (inputBytes: UnsafeRawBufferPointer) -> () in
            CC_SHA256_Update(
                &hashContext,
                inputBytes.baseAddress,
                CC_LONG(input.count))
        }
    }

    fileprivate func hashFinalize() throws -> Data {
        let outLength = 32
        var outBytes = [UInt8](repeating: 0, count: outLength)
        CC_SHA256_Final(&outBytes, &hashContext)
        return Data(bytes: outBytes, count: outLength)
    }

    fileprivate func hashFinalizeAndVerify(sha256Hash: Data) throws {
        let digest = try hashFinalize()
        guard digest == sha256Hash else {
            DDLogError("StreamingMediaChunkDecrypter/hashFinalizeAndVerify/failed/expected: \(sha256Hash.bytes)/actual: \(digest.bytes)")
            throw MediaDownloadError.hashMismatch
        }
    }

    fileprivate func encrypt(plaintextChunk: Data, chunkIndex: Int) throws -> Data {
        let expandedKey = try expandedKey(chunkIndex: chunkIndex)

        let IV = expandedKey[0...15]
        let AESKey = expandedKey[16...47]
        let SHA256Key = expandedKey[48...79]

        var encryptedChunk = try AES256Crypter(key: AESKey, iv: IV).encrypt(plaintextChunk)
        encryptedChunk.append(contentsOf: CryptoKit.HMAC<SHA256>.authenticationCode(for: encryptedChunk, using: SymmetricKey(data: SHA256Key)))

        try hashUpdate(input: encryptedChunk)
        return encryptedChunk
    }

    fileprivate func decrypt(encryptedChunk: Data, chunkIndex: Int) throws -> Data {
        let expandedKey = try expandedKey(chunkIndex: chunkIndex)

        let IV = expandedKey[0...15]
        let AESKey = expandedKey[16...47]
        let SHA256Key = expandedKey[48...79]

        try hashUpdate(input: encryptedChunk)

        let attachedMAC = encryptedChunk.suffix(32)
        let encryptedData = encryptedChunk.dropLast(32)

        let MAC = CryptoKit.HMAC<SHA256>.authenticationCode(for: encryptedData, using: SymmetricKey(data: SHA256Key))
        guard MAC == attachedMAC.bytes else {
            throw MediaDownloadError.macMismatch
        }

        let plaintextChunk = try AES256Crypter(key: AESKey, iv: IV).decrypt(encryptedData)
        return plaintextChunk
    }
}
