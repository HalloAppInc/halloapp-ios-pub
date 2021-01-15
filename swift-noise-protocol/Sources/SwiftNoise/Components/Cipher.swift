import Foundation
import CryptoSwift

// https://noiseprotocol.org/noise.html#cipher-functions
protocol Cipher {
  // Encrypts plaintext using the cipher key k of 32 bytes and an 8-byte unsigned integer nonce n
  // which must be unique for the key k. Returns the ciphertext. Encryption must be done with an
  // "AEAD" encryption mode with the associated data ad (using the terminology from [1]) and
  // returns a ciphertext that is the same size as the plaintext plus 16 bytes for authentication
  // data. The entire ciphertext must be indistinguishable from random if the key is secret (note
  // that this is an additional requirement that isn't necessarily met by all AEAD schemes).
  func encrypt(k: Data, n: Nonce, ad: Data, plaintext: Data) throws -> Data

  // Decrypts ciphertext using a cipher key k of 32 bytes, an 8-byte unsigned integer nonce n, and
  // associated data ad. Returns the plaintext, unless authentication fails, in which case an error
  // is signaled to the caller.
  func decrypt(k: Data, n: Nonce, ad: Data, ciphertext: Data) throws -> Data

  // Returns a new 32-byte cipher key as a pseudorandom function of k. If this function is not
  // specifically defined for some set of cipher functions, then it defaults to returning the first
  // 32 bytes from ENCRYPT(k, maxnonce, zerolen, zeros), where maxnonce equals 2^64-1, zerolen is a
  // zero-length byte sequence, and zeros is a sequence of 32 bytes filled with zeros.
  func rekey(k: Data) throws -> Data
}

class AESGCM: Cipher {
  // A helper method to convert Nonce (which is a 64-bit unsigned integer) to Data.
  func nonceToData(n: Nonce) -> Data {
    return Data([
      0, 0, 0, 0,
      UInt8(truncatingIfNeeded: n>>56),
      UInt8(truncatingIfNeeded: n>>48),
      UInt8(truncatingIfNeeded: n>>40),
      UInt8(truncatingIfNeeded: n>>32),
      UInt8(truncatingIfNeeded: n>>24),
      UInt8(truncatingIfNeeded: n>>16),
      UInt8(truncatingIfNeeded: n>>8),
      UInt8(truncatingIfNeeded: n>>0)
    ])
  }

  func encrypt(k: Data, n: Nonce, ad: Data, plaintext: Data) throws -> Data {
    let nData = nonceToData(n: n)
    let gcm = GCM(iv: nData.bytes, additionalAuthenticatedData: ad.bytes, mode: .combined)
    var cipher: AES
    do {
      cipher = try AES(key: k.bytes, blockMode: gcm, padding: .noPadding)
    } catch {
      throw CipherError.cannotInstantiateCipher(error: error)
    }
    var ciphertext: Data
    do {
      ciphertext = Data(try cipher.encrypt(plaintext.bytes))
    } catch {
      throw CipherError.invalidPlaintext(error: error)
    }
    return ciphertext
  }

  func decrypt(k: Data, n: Nonce, ad: Data, ciphertext: Data) throws -> Data {
    let nData = nonceToData(n: n)
    let gcm = GCM(iv: nData.bytes, additionalAuthenticatedData: ad.bytes, mode: .combined)
    var cipher: AES
    do {
      cipher = try AES(key: k.bytes, blockMode: gcm, padding: .noPadding)
    } catch {
      throw CipherError.cannotInstantiateCipher(error: error)
    }
    var plaintext: Data
    do {
      plaintext = Data(try cipher.decrypt(ciphertext.bytes))
    } catch {
      throw CipherError.invalidCiphertext(error: error)
    }
    return plaintext
  }

  func rekey(k: Data) throws -> Data {
    return try self.encrypt(k: k, n: 0xffffffffffffffff, ad: Data(), plaintext: Data(repeating: 0, count: 32))
  }
}
