import Foundation
import CryptoSwift

// https://noiseprotocol.org/noise.html#hash-functions
protocol Hash {
  // Hashes some arbitrary-length data with a collision-resistant cryptographic hash function and
  // returns an output of HASHLEN bytes.
  func hash(data: Data) -> Data

  // Applies HMAC from [3] using the HASH() function. This function is only called as part of
  // HKDF().
  func hmac(key: Data, data: Data) throws -> Data

  // Takes a chaining_key byte sequence of length HASHLEN, and an input_key_material byte sequence
  // with length either zero bytes, 32 bytes, or DHLEN bytes. Returns a pair or triple of byte
  // sequences each of length HASHLEN, depending on whether num_outputs is two or three.
  func hkdf(chainingKey: Data, inputKeyMaterial: Data, numOutputs: UInt8) throws -> [Data]

  // = A constant specifying the size in bytes of the hash output. Must be 32 or 64.
  var hashlen: Int { get }

  // = A constant specifying the size in bytes that the hash function uses internally to divide its
  // input for iterative processing. This is needed to use the hash function with HMAC (BLOCKLEN is
  // B in [3]).
  var blocklen: Int { get }
}

class SHA256: Hash {
  func hash(data: Data) -> Data {
    return Data(Digest.sha256(data.bytes))
  }

  func hmac(key: Data, data: Data) throws -> Data {
    return Data(try HMAC(key: key.bytes, variant: .sha256).authenticate(data.bytes))
  }

  func hkdf(chainingKey: Data, inputKeyMaterial: Data, numOutputs: UInt8) throws -> [Data] {
    if numOutputs < 2 {
      throw HashError.tooLittleOutputs
    }
    if numOutputs > 3 {
      throw HashError.tooManyOutputs
    }
    let tempKey = Data(try self.hmac(key: chainingKey, data: inputKeyMaterial))
    var lastOutput: Data = Data()
    var outputs: [Data] = []
    for index in 1...numOutputs {
      lastOutput = Data(try self.hmac(key: tempKey, data: lastOutput + [index]))
      outputs.append(lastOutput)
    }
    return outputs
  }

  var hashlen: Int = 32
  var blocklen: Int = 64
}
