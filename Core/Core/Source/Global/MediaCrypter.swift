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

    mutating func encryptInit() throws {
        return try cryptorInit(operation: CCOperation(kCCEncrypt))
    }

    mutating func decryptInit() throws {
        return try cryptorInit(operation: CCOperation(kCCDecrypt))
    }

    func update(_ encrypted: Data) throws -> Data {
        return try cryptorUpdate(input: encrypted)
    }

    func finalize() throws -> Data {
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

    private class func HKDFInfo(for mediaType: CommonMediaType, chunkIndex: Int? = nil) -> [UInt8] {
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

    fileprivate class func expandedKey(from key: Data, mediaType: CommonMediaType, chunkIndex: Int? = nil) throws -> Data {
        let expandedKeyBytes = try HKDF(password: key.bytes, info: HKDFInfo(for: mediaType, chunkIndex: chunkIndex), keyLength: MediaCrypter.expandedKeyLength, variant: .sha256).calculate()
        return Data(bytes: expandedKeyBytes, count: expandedKeyBytes.count)
    }
    
    public class func encrypt(data: Data, mediaType: CommonMediaType) throws -> (Data, Data, Data) {
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
    
    public class func decrypt(data: Data, mediaKey: Data, sha256hash: Data, mediaType: CommonMediaType) throws -> Data {
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
        let chunkSize = 512 * 1024 // 0.5MB

        let file = try FileHandle(forReadingFrom: url)
        defer {
            file.closeFile()
        }

        var hashContext = CC_SHA256_CTX.init()
        CC_SHA256_Init(&hashContext)

        while true {
            var size = 0

            autoreleasepool {
                let chunk = file.readData(ofLength: chunkSize)
                size = chunk.count

                chunk.withUnsafeBytes { (inputBytes: UnsafeRawBufferPointer) -> () in
                    CC_SHA256_Update(
                        &hashContext,
                        inputBytes.baseAddress,
                        CC_LONG(chunk.count))
                }
            }

            if size < chunkSize {
                break
            }
        }

        let outLength = 32
        var outBytes = [UInt8](repeating: 0, count: outLength)
        CC_SHA256_Final(&outBytes, &hashContext)
        return Data(bytes: outBytes, count: outLength)
    }

    public class func hash(data: Data) -> Data {
        return Data(SHA256.hash(data: data))
    }

}

public class MediaChunkCrypter: MediaCrypter {
    enum CrypterError: Error {
        case missingMediaKey
    }

    private var aesCrypter: AES256Crypter
    private var sha256hash: Data?
    private var mediaKey: Data?
    private var hashContext: CC_SHA256_CTX
    private var hmacContext: CCHmacContext

    // MARK: initialization
    public init(mediaKey: Data, sha256hash: Data, mediaType: CommonMediaType) throws {
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

    public init(mediaType: CommonMediaType) throws {
        let mediaKey = try MediaCrypter.randomKey(MediaCrypter.attachedKeyLength)
        let expandedKey = try MediaCrypter.expandedKey(from: mediaKey, mediaType: mediaType)
        let IV = expandedKey[0...15]
        let AESKey = expandedKey[16...47]
        let SHA256Key = expandedKey[48...79]

        self.mediaKey = mediaKey
        aesCrypter = try AES256Crypter(key: AESKey, iv: IV)

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
        guard let sha256hash = sha256hash else { return }

        let outLength = 32
        var outBytes = [UInt8](repeating: 0, count: outLength)
        CC_SHA256_Final(&outBytes, &hashContext)
        let digest = Data(bytes: outBytes, count: outLength)
        guard digest == sha256hash else {
            DDLogError("MediaCrypter/hashFinalizeAndVerify/failed/expected: \(sha256hash.bytes)/actual: \(digest.bytes)")
            throw MediaDownloadError.hashMismatch
        }
    }

    public func hashFinalize() -> Data {
        let outLength = 32
        var outBytes = [UInt8](repeating: 0, count: outLength)
        CC_SHA256_Final(&outBytes, &hashContext)
        return Data(bytes: outBytes, count: outLength)
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

    public func hmacFinalize() -> Data {
        let macLength = 32
        var macBytes = [UInt8](repeating: 0, count: macLength)
        CCHmacFinal(&hmacContext, &macBytes)
        return Data(bytes: macBytes, count: macLength)
    }

    // MARK: Chunk based encryption & decryption

    public func encryptInit() throws {
        guard mediaKey != nil else { return }
        try aesCrypter.encryptInit()
    }

    public func decryptInit() throws {
        try aesCrypter.decryptInit()
    }

    public func decryptUpdate(dataChunk: Data) throws -> Data {
        try aesCrypter.update(dataChunk)
    }

    public func decryptFinalize() throws -> Data {
        try aesCrypter.finalize()
    }

    public func encryptUpdate(dataChunk: Data) throws -> Data {
        let encryptedData = try aesCrypter.update(dataChunk)
        try hashUpdate(input: encryptedData)
        try hmacUpdate(input: encryptedData)

        return encryptedData
    }

    public func encryptFinalize() throws -> (Data, Data, Data) {
        guard let mediaKey = mediaKey else { throw CrypterError.missingMediaKey }

        var encryptedData = try aesCrypter.finalize()
        try hashUpdate(input: encryptedData)
        try hmacUpdate(input: encryptedData)

        let hmac = hmacFinalize()
        try hashUpdate(input: hmac)

        encryptedData.append(hmac)

        return (encryptedData, mediaKey, hashFinalize())
    }

}


public class ChunkedMediaCrypter: MediaCrypter {
    public typealias ReadChunkData = ((chunkOffset: Int, chunkSize: Int)) throws -> Data
    public typealias WriteChunkData = ((chunkData: Data, chunkOffset: Int)) throws -> Void
    public struct EncryptionResult {
        public var mediaKey: Data
        public var sha256: Data
    }

    public enum Error: Swift.Error {
        case encryptedChunkSizeMismatch(expected: Int, actual: Int)
        case plaintextChunkSizeMismatch(estmated: Int, actual: Int)
    }

    public static func encryptChunkedMedia(mediaType: CommonMediaType,
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
                    DDLogError("ChunkedMedia/encryptChunkedMedia/error Unexpected plaintext size got=[\(plaintextChunk.count)] estimated=[\(chunkPlaintextSize)]")
                    throw Error.plaintextChunkSizeMismatch(estmated: Int(chunkPlaintextSize), actual: plaintextChunk.count)
                }

                let encryptedChunk = try encrypter.encrypt(plaintextChunk: plaintextChunk, chunkIndex: Int(chunkIndex))
                if encryptedChunk.count != chunkCiphertextSize {
                    DDLogError("ChunkedMedia/encryptChunkedMedia/error Unexpected ciphertext size got=[\(encryptedChunk.count)] expected=[\(chunkCiphertextSize)]")
                    throw Error.encryptedChunkSizeMismatch(expected: Int(chunkCiphertextSize), actual: encryptedChunk.count)
                }
                try writeChunkData((chunkData: encryptedChunk, chunkOffset: chunkCiphertextOffset))
            }
        }
        return EncryptionResult(mediaKey: encrypter.mediaKey, sha256: try encrypter.hashFinalize())
    }

    public static func decryptChunkedMedia(mediaType: CommonMediaType,
                                           mediaKey: Data,
                                           sha256Hash: Data,
                                           chunkedParameters: ChunkedMediaParameters,
                                           readChunkData: ReadChunkData,
                                           writeChunkData: WriteChunkData,
                                           toDecryptChunkCount: Int32? = nil) throws {

        let toProcessChunkCount: Int32 = {
            if let initialChunkCount = toDecryptChunkCount, initialChunkCount < chunkedParameters.totalChunkCount {
                return initialChunkCount
            } else {
                return chunkedParameters.totalChunkCount
            }
        }()
        let shouldValidateHash = toProcessChunkCount == chunkedParameters.totalChunkCount
        let decrypter = ChunkedMediaCrypter(mediaType: mediaType, mediaKey: mediaKey)
        for chunkIndex in 0..<toProcessChunkCount {
            let chunkPlaintextSize = chunkedParameters.getChunkPtSize(chunkIndex: chunkIndex)
            let chunkPlaintextOffset = Int(chunkIndex) * Int(chunkedParameters.regularChunkPtSize)
            let chunkCiphertextSize = chunkedParameters.getChunkSize(chunkIndex: chunkIndex)
            let chunkCiphertextOffset = Int(chunkIndex) * Int(chunkedParameters.chunkSize)

            try autoreleasepool {
                let encryptedChunk = try readChunkData((chunkOffset: chunkCiphertextOffset, chunkSize: Int(chunkCiphertextSize)))
                if encryptedChunk.count != chunkCiphertextSize {
                    DDLogError("ChunkedMedia/decryptChunkedMedia/error Unexpected ciphertext chunk size got=[\(encryptedChunk.count)] expected=[\(chunkCiphertextSize)]")
                    throw Error.encryptedChunkSizeMismatch(expected: Int(chunkCiphertextSize), actual: encryptedChunk.count)
                }

                let decryptedChunk = try decrypter.decrypt(encryptedChunk: encryptedChunk, chunkIndex: Int(chunkIndex), shouldUpdateHash: shouldValidateHash)
                if (chunkIndex < chunkedParameters.regularChunkCount && decryptedChunk.count != Int(chunkPlaintextSize)) ||
                    (chunkIndex == chunkedParameters.regularChunkCount && abs(decryptedChunk.count - Int(chunkPlaintextSize)) >= ChunkedMediaParameters.BLOCK_SIZE) {
                    DDLogError("ChunkedMedia/decryptChunkedMedia/error Unexpected plaintext chunk size got=[\(decryptedChunk.count)] expected=[\(chunkPlaintextSize)]")
                    throw Error.plaintextChunkSizeMismatch(estmated: Int(chunkPlaintextSize), actual: decryptedChunk.count)
                }
                try writeChunkData((chunkData: decryptedChunk, chunkOffset: chunkPlaintextOffset))
            }
        }
        if shouldValidateHash {
            try decrypter.hashFinalizeAndVerify(sha256Hash: sha256Hash)
        }
    }

    private let mediaType: CommonMediaType
    public let mediaKey: Data
    private var hashContext: CC_SHA256_CTX

    public init(mediaType: CommonMediaType, mediaKey: Data) {
        self.mediaType = mediaType
        self.mediaKey = mediaKey
        self.hashContext = CC_SHA256_CTX.init()
        CC_SHA256_Init(&hashContext)
    }

    fileprivate convenience init(mediaType: CommonMediaType) throws {
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

    public func decrypt(encryptedChunk: Data, chunkIndex: Int, shouldUpdateHash: Bool = true) throws -> Data {
        DDLogInfo("StreamingMediaChunkDecrypter/decrypt chunkIndex=[\(chunkIndex)] encryptedChunkLength=[\(encryptedChunk.count)]")
        let expandedKey = try expandedKey(chunkIndex: chunkIndex)

        let IV = expandedKey[0...15]
        let AESKey = expandedKey[16...47]
        let SHA256Key = expandedKey[48...79]

        if shouldUpdateHash {
            try hashUpdate(input: encryptedChunk)
        }

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
