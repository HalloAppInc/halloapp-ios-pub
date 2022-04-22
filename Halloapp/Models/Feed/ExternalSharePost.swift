//
//  ExternalSharePost.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 4/5/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Combine
import CocoaLumberjackSwift
import Core
import CoreCommon
import CryptoSwift
import UIKit

// MARK: - Encryption Helpers

struct ExternalSharePost {

    enum ExternalSharePostError: Error {
        case invalidData
        case invalidHmac
        case keygen
    }

    static func decrypt(encryptedBlob: Data, key: Data) throws -> Clients_PostContainerBlob {
        guard encryptedBlob.count > 32 else {
            throw ExternalSharePostError.invalidData
        }

        let encryptedPostData = [UInt8](encryptedBlob[0 ..< encryptedBlob.count - 32])
        let hmac = [UInt8](encryptedBlob[encryptedBlob.count - 32 ..< encryptedBlob.count])
        let (iv, aesKey, hmacKey) = try externalShareKeys(from: [UInt8](key))

        // Calculate and compare HMAC
        let calculatedHmac = try HMAC(key: hmacKey, variant: .sha256).authenticate(encryptedPostData)

        guard hmac == calculatedHmac else {
            throw ExternalSharePostError.invalidHmac
        }

        let postData = try AES(key: aesKey, blockMode: CBC(iv: iv), padding: .pkcs5).decrypt(encryptedPostData)

        return try Clients_PostContainerBlob(contiguousBytes: postData)
    }

    static func encypt(blob: Clients_PostContainerBlob) throws -> (encryptedBlob: Data, key: Data) {
        let data = try blob.serializedData()

        var attachmentKey = [UInt8](repeating: 0, count: 15)
        guard SecRandomCopyBytes(kSecRandomDefault, 15, &attachmentKey) == errSecSuccess else {
            throw ExternalSharePostError.keygen
        }

        let (iv, aesKey, hmacKey) = try Self.externalShareKeys(from: attachmentKey)
        let encryptedPostData = try AES(key: aesKey, blockMode: CBC(iv: iv), padding: .pkcs5).encrypt(data.bytes)
        let hmac = try HMAC(key: hmacKey, variant: .sha256).authenticate(encryptedPostData)

        return (encryptedBlob: Data(encryptedPostData + hmac), key: Data(attachmentKey))
    }

    private static func externalShareKeys(from key: [UInt8]) throws -> (iv: [UInt8], aesKey: [UInt8], hmacKey: [UInt8]) {
        let fullKey = try HKDF(password: key, info: "HalloApp Share Post".bytes, keyLength: 80, variant: .sha256).calculate()
        let iv = Array(fullKey[0..<16])
        let aesKey = Array(fullKey[16..<48])
        let hmacKey = Array(fullKey[48..<80])
        return (iv, aesKey, hmacKey)
    }
}
