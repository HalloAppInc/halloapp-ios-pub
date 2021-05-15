//
//  SafetyNumber.swift
//  HalloApp
//
//  Created by Garrett on 5/14/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import CryptoKit
import Foundation
import Sodium

struct SafetyNumberData {
    var userID: UserID
    var identityKey: Data
}

extension SafetyNumberData {
    init?(keyBundle: KeyBundle) {
        guard let identityKey = Sodium().sign.convertToX25519PublicKey(publicKey: [UInt8](keyBundle.inboundIdentityPublicEdKey)) else {
            return nil
        }
        self.userID = keyBundle.userId
        self.identityKey = Data(identityKey)
    }
}

extension SafetyNumberData {
    var safetyNumber: String? {
        let inputString = "\(userID);\(identityKey.base64EncodedString())"
        guard var data = inputString.data(using: .utf8) else { return nil }
        var i = 0
        while i < 5200 {
            data = SHA512.hash(data: data).data
            i += 1
        }

        guard data.bytes.count >= 30 else {
            return nil
        }

        let chunks = (0...5)
            .map { i in 5*i }
            .map { offset in Data(bytes: [0,0,0] + Array(data.bytes[offset..<offset+5]), count: 8) }
            .map { chunk in UInt64(bigEndian: chunk.withUnsafeBytes { $0.load(as: UInt64.self)})}
            .map { number in
                String(format: "%05u", number % 100000)
            }

        return chunks.joined()
    }
}

enum SafetyNumberVerificationResult {
    case success
    case unsupportedOrInvalid
    case invalid
}

final class SafetyNumberManager {

    init(currentUser: SafetyNumberData, otherUser: SafetyNumberData) {
        self.currentUser = currentUser
        self.otherUser = otherUser
    }

    private let currentUser: SafetyNumberData
    private let otherUser: SafetyNumberData

    var safetyNumber: String? {
        guard let numberA = currentUser.safetyNumber, let numberB = otherUser.safetyNumber else {
            return nil
        }
        return [numberA,numberB].sorted().joined()
    }

    /// Data to show in QR code. This is not symmetric and cannot be used to verify contact's QR code.
    var qrCodeDataToDisplay: Data? {
        return Self.qrCodeData(generator: currentUser, scanner: otherUser)
    }

    func verify(qrCodeData: Data) -> SafetyNumberVerificationResult {
        guard !qrCodeData.isEmpty else {
            return .invalid
        }

        // We can compare directly to expectation since we only accept one version
        if qrCodeData == Self.qrCodeData(generator: otherUser, scanner: currentUser) {
            return .success
        }

        if let version = qrCodeData.bytes.first, version != 0 {
            return .unsupportedOrInvalid
        } else {
            return .invalid
        }
    }

    private static func qrCodeData(generator: SafetyNumberData, scanner: SafetyNumberData) -> Data? {
        guard let generatorID = UInt64(generator.userID), let scannerID = UInt64(scanner.userID) else {
            return nil
        }
        guard generator.identityKey.count == 32 && scanner.identityKey.count == 32 else {
            return nil
        }

        return Data([0]) + generatorID.asBigEndianData + scannerID.asBigEndianData + generator.identityKey + scanner.identityKey
    }
}

private extension UInt64 {
    var asBigEndianData: Data {
        withUnsafeBytes(of: bigEndian) { Data($0) }
    }
}
