//
//  HACrypto.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import CryptoSwift

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
    
    func generateExpandedKey() -> [UInt8] {

        // generate key
        let key = generateKey(numBytes: 32)
        
        let info = "HalloApp image".bytes
        
//        let result = try! HMAC(key: key, variant: .sha256).authenticate(message.bytes)
        
        let expandedKey = try! HKDF(password: key, info: info, keyLength: 80, variant: .sha256).calculate()

//        print("expandedKey:")
//        print("\(expandedKey)")
        
        return expandedKey
    }
    
    func encrypt(med: FeedMedia) -> FeedMedia {
        
        guard let data = med.image.pngData() as Data? else { return med }
        
        let med2 = med
        
        let target: [UInt8] = [UInt8](data)
        print("target: \(target.count)")
        
        let expandedKey = generateExpandedKey()
        
        let randomIV = Array(expandedKey[0...15])
        let AESKey = Array(expandedKey[16...47])
        let SHAKey = Array(expandedKey[48...79])

//        print("randomIV: \(randomIV)")
//        print("AESKey: \(AESKey)")
//        print("SHAKey: \(SHAKey)")
        
        do {
            let aes = try AES(key: AESKey, blockMode: CBC(iv: randomIV), padding: .pkcs5)
        
            let encrypted = try aes.encrypt(target)
//            let strToBe = "Tony is here"
//            print("strToBe: \(strToBe.count)")
//            let encrypted = try aes.encrypt(Array(strToBe.utf8))
            
            print("encrypted: \(encrypted.count)")
            
//            let MAC = try HMAC(key: SHAKey, variant: .sha256).authenticate(encrypted)
//
//            print("MAC:")
//            print("\(MAC)")
            
            let decrypted = try AES(key: AESKey, blockMode: CBC(iv: randomIV), padding: .pkcs5).decrypt(encrypted)
            
//            if let encryptedString = String(bytes: encrypted, encoding: .utf8) {
//                print(encryptedString)
//            } else {
//                print("not a valid UTF-8 sequence")
//            }
            
//            if let string = String(bytes: decrypted, encoding: .utf8) {
//                print(string)
//            } else {
//                print("not a valid UTF-8 sequence")
//            }
            
            let data2 = Data(bytes: decrypted, count: decrypted.count)

            
            print("decrypted: \(decrypted.count)")
            
            let image = UIImage(data: data2)
            
            print("image size: \(image!.size.width)")

            if image != nil {
                print("hit")
                med2.image = image!
            } else {
                print("miss")
            }
            
            
        } catch {
            
        }
        
        

        
        
        return med2
    }
    

    
}
