
import CryptoKit

public extension Digest {

    var bytes: [UInt8] { Array(makeIterator()) }

    var data: Data { Data(bytes) }

    var hexStr: String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }
}
