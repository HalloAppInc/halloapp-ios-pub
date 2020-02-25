//
//  HACrypto.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import CryptoSwift
import CryptoKit


class HAC {
    
    func generateKey(numBytes: Int) -> [UInt8] {
        var key = [UInt8](repeating: 0, count: numBytes)
    
        let generateKeyResult = SecRandomCopyBytes(kSecRandomDefault, numBytes, &key)
        
        if(generateKeyResult == 0) {
//            print("success generating key:")
//            print("\(key)")
        } else {
            print("failed at generating key")
        }
        return key
    }
    
    func base64ToByteArray(base64String: String) -> [UInt8]? {
        if let nsdata = Data(base64Encoded: base64String) {
            var bytes = [UInt8](repeating: 0, count: nsdata.count)
            nsdata.copyBytes(to: &bytes, count: nsdata.count)
              return bytes
          }
          return nil // Invalid input
    }
    
    func generateExpandedKeyFrom(fromKey:String, type: String) -> [UInt8] {

        print("generateExpandedKeyFrom: \(fromKey)")
        
        if let key = base64ToByteArray(base64String: fromKey) {
        
            var info = "HalloApp image".bytes
            
            if type == "video" {
                info = "HalloApp video".bytes
            }
            
            let expandedKey = try! HKDF(password: key, info: info, keyLength: 80, variant: .sha256).calculate()

    //        print("expandedKey:")
    //        print("\(expandedKey)")
            
            return expandedKey
        }
        return []
    }
    
    func generateNewExpandedKey(type: String) -> (String, [UInt8]) {

        // generate key
        let key = generateKey(numBytes: 32)
        
        var info = "HalloApp image".bytes
        
        if type == "video" {
            info = "HalloApp video".bytes
        }
        
//        let result = try! HMAC(key: key, variant: .sha256).authenticate(message.bytes)
        
        let expandedKey = try! HKDF(password: key, info: info, keyLength: 80, variant: .sha256).calculate()

//        print("expandedKey:")
//        print("\(expandedKey)")
        
        let keyData = Data(bytes: key, count: key.count)
        
        // Convert to Base64
        let base64StringKey = keyData.base64EncodedString()
        
        return (base64StringKey, expandedKey)
    }
    
    func encryptData(data: Data, type: String) -> (Data?, String, String) {
        
        let target: [UInt8] = [UInt8](data)

        let (base64Key, expandedKey) = generateNewExpandedKey(type: "image")
        
        let randomIV = Array(expandedKey[0...15])
        let AESKey = Array(expandedKey[16...47])
        let SHAKey = Array(expandedKey[48...79])
        
        do {
            let aes = try AES(key: AESKey, blockMode: CBC(iv: randomIV), padding: .pkcs5)
        
            var encrypted = try aes.encrypt(target)

            let MAC = try HMAC(key: SHAKey, variant: .sha256).authenticate(encrypted)
            
            print("MAC: \(MAC.count)")
            
            encrypted.append(contentsOf: MAC)
            
            print("encrypted w/authen: \(encrypted.count)")
            
            let digest = SHA256.hash(data: encrypted)
            
            let base64Hash = digest.data.base64EncodedString()
            
            let encryptedData = Data(bytes: encrypted, count: encrypted.count)
            
            return (encryptedData, base64Key, base64Hash)
            
        } catch {
            
        }
        
        return (nil, "", "")
    }
    
    func decryptData(data: Data, key: String, hash: String, type: String) -> Data? {
                
        var target: [UInt8] = [UInt8](data)
        
        let expandedKey = generateExpandedKeyFrom(fromKey: key, type: type)
        
        let randomIV = Array(expandedKey[0...15])
        let AESKey = Array(expandedKey[16...47])
        let SHAKey = Array(expandedKey[48...79])

        do {
            
            let digest = SHA256.hash(data: target)
            let base64String = digest.data.base64EncodedString()
            
            if base64String != hash {
                print(base64String)
                print("sha256 hash does not match, abort")
                return nil
            }
            
            let attachedMAC = Array(target.suffix(32))
            
            target.removeLast(32)
            
            let MAC = try HMAC(key: SHAKey, variant: .sha256).authenticate(target)
            
            print("\(attachedMAC)")
            print("\(MAC)")
            
            if attachedMAC != MAC {
                print("MAC does not match, abort")
                return nil
            }
            
            let decrypted = try AES(key: AESKey, blockMode: CBC(iv: randomIV), padding: .pkcs5).decrypt(target)
            
            let decryptedData = Data(bytes: decrypted, count: decrypted.count)

            print("decrypted: \(decryptedData.count)")
            
            return decryptedData
            
        } catch {
            
        }
        
        return nil
    }
    
}
