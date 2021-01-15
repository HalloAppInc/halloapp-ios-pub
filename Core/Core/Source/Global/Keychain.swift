//
//  Keychain.swift
//  Core
//
//  Created by Garrett on 12/16/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjack
import Foundation

final class Keychain {

    enum ServiceIdentifier: String, RawRepresentable {
        case password = "hallo"
        case noiseServer = "noise.server"
        case noiseUser = "noise.user"
    }

    @discardableResult
    static func savePassword(userID: UserID, password: String) -> Bool {
        guard needsKeychainUpdate(userID: userID, password: password) else {
            // Existing entry is up to date
            return true
        }

        guard let passwordData = password.data(using: .utf8), !password.isEmpty else {
            return false
        }

        return saveOrUpdateKeychainItem(userID: userID, data: passwordData, service: .password)
    }

    @discardableResult
    static func removePassword(userID: UserID) -> Bool {
        return removeKeychainItem(userID: userID, service: .password)
    }

    static func needsKeychainUpdate(userID: UserID, password: String) -> Bool {
        guard let item = loadKeychainItem(userID: userID, service: .password) as? NSDictionary,
              let data = item[kSecValueData] as? Data,
              let accesibleSetting = item[kSecAttrAccessible] as? String,
              let keychainPassword = String(data: data, encoding: .utf8),
              keychainPassword == password,
              accesibleSetting == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
              else
        {
            return true
        }
        return false
    }

    static func loadPassword(userID: UserID) -> String? {
        guard let item = loadKeychainItem(userID: userID, service: .password) as? NSDictionary,
              let data = item[kSecValueData] as? Data,
              let password = String(data: data, encoding: .utf8) else
        {
            return nil
        }

        return password.isEmpty ? nil : password
    }

    @discardableResult
    static func saveServerStaticKey(_ key: Data, for userID: UserID) -> Bool {
        return saveOrUpdateKeychainItem(userID: userID, data: key, service: .noiseServer)
    }

    @discardableResult
    static func removeServerStaticKey(for userID: UserID) -> Bool {
        return removeKeychainItem(userID: userID, service: .noiseServer)
    }

    static func loadServerStaticKey(for userID: UserID) -> Data? {
        guard let item = loadKeychainItem(userID: userID, service: .noiseServer) as? NSDictionary,
              let data = item[kSecValueData] as? Data else
        {
            return nil
        }

        return data.isEmpty ? nil : data
    }

    @discardableResult
    static func saveNoiseUserKeypair(_ keypair: NoiseKeys, for userID: UserID) -> Bool {
        do {
            let data = try PropertyListEncoder().encode(keypair)
            return saveOrUpdateKeychainItem(userID: userID, data: data, service: .noiseUser)
        } catch {
            DDLogError("Keychain/saveNoiseUserKeypair/error [\(error)]")
            return false
        }
    }

    @discardableResult
    static func removeNoiseUserKeypair(for userID: UserID) -> Bool {
        return removeKeychainItem(userID: userID, service: .noiseUser)
    }

    static func loadNoiseUserKeypair(for userID: UserID) -> NoiseKeys? {
        guard let item = loadKeychainItem(userID: userID, service: .noiseUser) as? NSDictionary,
              let data = item[kSecValueData] as? Data else
        {
            return nil
        }
        do {
            let keys = try PropertyListDecoder().decode(NoiseKeys.self, from: data)
            return keys
        } catch {
            DDLogError("Keychain/loadNoiseUserKeypair/error [\(error)]")
            return nil
        }
    }

    // MARK: Private

    private static func loadKeychainItem(userID: UserID, service: ServiceIdentifier) -> AnyObject? {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: userID,
            kSecAttrService: service.rawValue,
            kSecReturnAttributes: true,
            kSecReturnData: true,
        ] as CFDictionary

        var result: AnyObject?
        let status = SecItemCopyMatching(query, &result)
        DDLogInfo("Keychain/load status [\(status)]")

        return result
    }

    private static func saveOrUpdateKeychainItem(userID: UserID, data: Data, service: ServiceIdentifier) -> Bool {
        guard let kFalse = kCFBooleanFalse else {
            DDLogError("Keychain/error kCFBooleanFalse not defined")
            return false
        }

        if loadKeychainItem(userID: userID, service: service) == nil {
            // Add new entry
            let keychainItem = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrAccount: userID,
                kSecAttrService: service.rawValue,
                kSecAttrSynchronizable: kFalse,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                kSecValueData: data,
            ] as CFDictionary
            let status = SecItemAdd(keychainItem, nil)
            return status == errSecSuccess
        } else {
            // Update existing entry
            let query = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrAccount: userID,
                kSecAttrService: service.rawValue,
            ] as CFDictionary

            let update = [
                kSecValueData: data,
                kSecAttrSynchronizable: kFalse,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ] as CFDictionary

            let status = SecItemUpdate(query, update)
            return status == errSecSuccess
        }
    }

    private static func removeKeychainItem(userID: UserID, service: ServiceIdentifier) -> Bool {
        let keychainItem = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: userID,
            kSecAttrService: service.rawValue,
        ] as CFDictionary
        let status = SecItemDelete(keychainItem)
        return status == errSecSuccess
    }
}
