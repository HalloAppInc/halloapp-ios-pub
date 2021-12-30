//
//  Sodium.swift
//  Core
//
//  Created by Chris Leonavicius on 12/29/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import Clibsodium
import Sodium

/*
 Adds in functionalty from https://github.com/HalloAppInc/swift-sodium/commit/e8997517e65ab4ec2766869977cd1bb7f666e905
 so we don't have to maintain our own fork.
 */
public class KeyAgreement {

     public typealias PublicKey = Data
     public typealias SecretKey = Data
     public typealias SharedSecret = Data
     public let SecretKeyBytes = Int(crypto_scalarmult_scalarbytes())
     public let PublicKeyBytes = Int(crypto_scalarmult_bytes())
     public let SharedSecretBytes = Int(crypto_scalarmult_bytes())

     /**
     Generates an Diffie-Hellman (ECDH) shared secret, such that sharedSecret(aliceSecretKey, bobPublicKey) == sharedSecret(bobSecretKey, alicePublicKey). Fails silently in case of error.

     - Parameter secretKey: the value of the secret key of your sending account (typically local)
     - Parameter publicKey: the value of the public key of your receiving account (typically remote)
     - Returns: the ECDH shared secret for the specified public and private keys
      */
     public func sharedSecret(secretKey: SecretKey, publicKey: PublicKey) -> SharedSecret? {
         if publicKey.count != PublicKeyBytes ||
             secretKey.count != SecretKeyBytes  {
             return nil
         }

         var sharedSecret = SharedSecret(count: SharedSecretBytes)
         let result = sharedSecret.withUnsafeMutableBytes { rawSharedSecretPtr -> Int32 in
             let sharedSecretPtr = rawSharedSecretPtr.bindMemory(to: UInt8.self)
             guard let sharedSecretPtrAddress = sharedSecretPtr.baseAddress else { return -1 }
             return publicKey.withUnsafeBytes { rawPublicKeyPtr -> Int32 in
                 let publicKeyPtr = rawPublicKeyPtr.bindMemory(to: UInt8.self)
                 guard let publicKeyPtrAddress = publicKeyPtr.baseAddress else { return -1 }
                 return secretKey.withUnsafeBytes { rawSecretKeyPtr -> Int32 in
                     let secretKeyPtr = rawSecretKeyPtr.bindMemory(to: UInt8.self)
                     guard let secretKeyPtrAddress = secretKeyPtr.baseAddress else { return -1 }
                     return crypto_scalarmult(sharedSecretPtrAddress, secretKeyPtrAddress, publicKeyPtrAddress)
                 }
             }
         }

         if result != 0 {
             return nil
         }

         return sharedSecret
     }

     /**
     Generates a public key from a secret key. Fails silently in case of error.

     - Parameter secretKey: the value from which to derive the public key (typically 32 randomly-generated bytes)
     - Returns: a PublicKey (Data) object that contains the Curve25519 public key corresponding to the secret key
      */
     public func publicKey(secretKey: SecretKey) -> PublicKey? {
         if secretKey.count != SecretKeyBytes {
             return nil
         }

         var publicKey = PublicKey(count: PublicKeyBytes)
         let result = publicKey.withUnsafeMutableBytes { (rawPublicKeyPtr) -> Int32 in
             let publicKeyPtr = rawPublicKeyPtr.bindMemory(to: UInt8.self)
             guard let publicKeyPtrAddress = publicKeyPtr.baseAddress else { return -1 }
             return secretKey.withUnsafeBytes { (rawSecretKeyPtr) -> Int32 in
                 let secretKeyPtr = rawSecretKeyPtr.bindMemory(to: UInt8.self)
                 guard let secretKeyPtrAddress = secretKeyPtr.baseAddress else { return -1 }
                 return crypto_scalarmult_base(publicKeyPtrAddress, secretKeyPtrAddress)
             }
         }

         if result != 0 {
             return nil
         }

         return Data(publicKey)
     }
 }

extension Sign {
     public func convertToX25519PublicKey(publicKey: PublicKey) -> Box.PublicKey? {
         var x25519Bytes = Array<UInt8>(repeating: 0, count: crypto_box_publickeybytes())
         if crypto_sign_ed25519_pk_to_curve25519(&x25519Bytes, publicKey) == 0 {
             return Box.PublicKey(x25519Bytes)
         } else {
             return nil
         }
     }

     public func convertToX25519PrivateKey(secretKey: SecretKey) -> Box.SecretKey? {
         var x25519Bytes = Array<UInt8>(repeating: 0, count: crypto_box_secretkeybytes())
         if crypto_sign_ed25519_sk_to_curve25519(&x25519Bytes, secretKey) == 0 {
             return Box.SecretKey(x25519Bytes)
         } else {
             return nil
         }
     }

     public func convertToX25519KeyPair(keyPair: KeyPair) -> Box.KeyPair? {
         let x25519PublicKey = convertToX25519PublicKey(publicKey: keyPair.publicKey)
         let x25519PrivateKey = convertToX25519PrivateKey(secretKey: keyPair.secretKey)

         if let publicKey = x25519PublicKey, let privateKey = x25519PrivateKey {
             return Box.KeyPair(publicKey: publicKey, secretKey: privateKey)
         } else {
             return nil
         }
     }
 }

extension Sodium {

    var keyAgreement: KeyAgreement {
        return KeyAgreement()
    }
}
