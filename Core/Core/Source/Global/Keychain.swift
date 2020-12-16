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

    static private let serviceIdentifier = "hallo"

    static func loadKeychainItem(userID: UserID) -> AnyObject? {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: userID,
            kSecAttrService: serviceIdentifier,
            kSecReturnAttributes: true,
            kSecReturnData: true,
        ] as CFDictionary

        var result: AnyObject?
        let status = SecItemCopyMatching(query, &result)
        DDLogInfo("UserData/Keychain/load status [\(status)]")

        return result
    }

    @discardableResult
    static func savePassword(userID: UserID, password: String) -> Bool {

        guard needsKeychainUpdate(userID: userID, password: password) else {
            // Existing entry is up to date
            return true
        }

        guard let passwordData = password.data(using: .utf8), let kFalse = kCFBooleanFalse, !password.isEmpty else {
            return false
        }

        if loadKeychainItem(userID: userID) == nil {
            // Add new entry
            let keychainItem = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrAccount: userID,
                kSecAttrService: serviceIdentifier,
                kSecAttrSynchronizable: kFalse,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                kSecValueData: passwordData,
            ] as CFDictionary
            let status = SecItemAdd(keychainItem, nil)
            return status == errSecSuccess
        } else {
            // Update existing entry
            let query = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrAccount: userID,
                kSecAttrService: serviceIdentifier,
            ] as CFDictionary

            let update = [
                kSecValueData: passwordData,
                kSecAttrSynchronizable: kFalse,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ] as CFDictionary

            let status = SecItemUpdate(query, update)
            return status == errSecSuccess
        }
    }

    @discardableResult
    static func removePassword(userID: UserID) -> Bool {
        let keychainItem = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: userID,
            kSecAttrService: serviceIdentifier,
        ] as CFDictionary
        let status = SecItemDelete(keychainItem)
        return status == errSecSuccess
    }

    static func needsKeychainUpdate(userID: UserID, password: String) -> Bool {
        guard let item = loadKeychainItem(userID: userID) as? NSDictionary,
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
        guard let item = loadKeychainItem(userID: userID) as? NSDictionary,
              let data = item[kSecValueData] as? Data,
              let password = String(data: data, encoding: .utf8) else
        {
            return nil
        }

        return password.isEmpty ? nil : password
    }
}
