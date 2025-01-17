//
//  UIDevice.swift
//  Core
//
//  Created by Tony Jiang on 12/16/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import UIKit

extension UIDevice {

    public func getModelName() -> String {

        var identifierStr = "unknown"

#if targetEnvironment(simulator)
        if let simulatorIdentifier = ProcessInfo().environment["SIMULATOR_MODEL_IDENTIFIER"] {
            identifierStr = simulatorIdentifier
        }
#else
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        identifierStr = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
#endif

        switch identifierStr {
        case "iPhone8,1":                               return "iPhone 6s"
        case "iPhone8,2":                               return "iPhone 6s Plus"
        case "iPhone9,1", "iPhone9,3":                  return "iPhone 7"
        case "iPhone9,2", "iPhone9,4":                  return "iPhone 7 Plus"
        case "iPhone8,4":                               return "iPhone SE"
        case "iPhone10,1", "iPhone10,4":                return "iPhone 8"
        case "iPhone10,2", "iPhone10,5":                return "iPhone 8 Plus"
        case "iPhone10,3", "iPhone10,6":                return "iPhone X"
        case "iPhone11,2":                              return "iPhone XS"
        case "iPhone11,4", "iPhone11,6":                return "iPhone XS Max"
        case "iPhone11,8":                              return "iPhone XR"
        case "iPhone12,1":                              return "iPhone 11"
        case "iPhone12,3":                              return "iPhone 11 Pro"
        case "iPhone12,5":                              return "iPhone 11 Pro Max"
        case "iPhone12,8":                              return "iPhone SE (2nd generation)"
        case "iPhone13,1":                              return "iPhone 12 mini"
        case "iPhone13,2":                              return "iPhone 12"
        case "iPhone13,3":                              return "iPhone 12 Pro"
        case "iPhone13,4":                              return "iPhone 12 Pro Max"
        case "iPhone14,2":                              return "iPhone 13 Pro"
        case "iPhone14,3":                              return "iPhone 13 Pro Max"
        case "iPhone14,4":                              return "iPhone 13 Mini"
        case "iPhone14,5":                              return "iPhone 13"
        default:                                        return identifierStr
        }
    }

    /*
     Returns whether the device has completed its first unlock, meaning data protected with default protection levels is available
     There doesn't seem to be a system API to check for this, so try writing and reading from the keychain
     */
    public static var hasCompletedFirstUnlock: Bool {
        let data = "firstUnlock".data(using: .utf8)!
        let service = "com.halloapp.tmp.firstUnlockCompleted"

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrSynchronizable as String: false,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data,
            kSecAttrService as String: service,
        ]

        var status: OSStatus

        status = SecItemAdd(addQuery as CFDictionary, nil)

        defer {
            SecItemDelete(addQuery as CFDictionary)
        }

        guard status == errSecSuccess else {
            return false
        }

        let copyMatchingQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: false,
            kSecReturnData as String: true,
            kSecAttrService as String: service,
        ]

        var item: CFTypeRef?
        status = SecItemCopyMatching(copyMatchingQuery as CFDictionary, &item)
        guard status == errSecSuccess,
              data == item as? Data else {
            return false
        }

        return true
    }
}
