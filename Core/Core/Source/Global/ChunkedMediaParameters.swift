//
//  ChunkedMediaParameters.swift
//  Core
//
//  Created by Vasil Lyutskanov on 1.12.21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import Foundation

public struct ChunkedMediaTestConstants {
    public static let STREAMING_FEED_GROUP_IDS = ["gmYchx3MBOXerd7QTmWqsO", "gGSFDZYubalo4izDKhE-Vv"]
}

enum ChunkedMediaParametersError: Error {
    case chunkSizeNotAligned
    case chunkSizeTooSmall
    case plaintextSizeTooBig
    case blobSizeTooBig
    case trailingChunkSizeNotAligned
    case trailingChunkSizeTooSmall
    case plaintextPositionTooBig
}

public class ChunkedMediaParameters: CustomStringConvertible {
    public static let BLOCK_SIZE: Int32 = 16
    public static let MAC_SIZE: Int32 = 32

    public let estimatedPtSize: Int64
    public let blobSize: Int64
    public let chunkSize: Int32
    public let regularChunkPtSize: Int32
    public let regularChunkCount: Int32
    public let estimatedTrailingChunkPtSize: Int32
    public let trailingChunkSize: Int32

    public var totalChunkCount: Int32 {
        return regularChunkCount + (trailingChunkSize != 0 ? 1 : 0)
    }

    public var description: String {
        return "StreamingMediaParameters(chunkSize: \(chunkSize) estimatedPtSize: \(estimatedPtSize) blobSize: \(blobSize) regularChunkPtSize: \(regularChunkPtSize) regularChunkCount: \(regularChunkCount) estimatedTrailingChunkPtSize: \(estimatedTrailingChunkPtSize) trailingChunkSize: \(trailingChunkSize))"
    }

    private init(estimatedPtSize: Int64, blobSize: Int64, chunkSize: Int32, regularChunkPtSize: Int32, regularChunkCount: Int32, estimatedTrailingChunkPtSize: Int32, trailingChunkSize: Int32) {
        self.estimatedPtSize = estimatedPtSize
        self.blobSize = blobSize
        self.chunkSize = chunkSize
        self.regularChunkPtSize = regularChunkPtSize
        self.regularChunkCount = regularChunkCount
        self.estimatedTrailingChunkPtSize = estimatedTrailingChunkPtSize
        self.trailingChunkSize = trailingChunkSize
    }

    public convenience init(plaintextSize: Int64, chunkSize: Int32) throws {
        if ((chunkSize - ChunkedMediaParameters.MAC_SIZE) % ChunkedMediaParameters.BLOCK_SIZE != 0) {
            throw ChunkedMediaParametersError.chunkSizeNotAligned
        }
        if (chunkSize <= ChunkedMediaParameters.MAC_SIZE + ChunkedMediaParameters.BLOCK_SIZE) {
            throw ChunkedMediaParametersError.chunkSizeTooSmall
        }
        if (plaintextSize / Int64(chunkSize - ChunkedMediaParameters.MAC_SIZE - ChunkedMediaParameters.BLOCK_SIZE) > Int32.max) {
            throw ChunkedMediaParametersError.plaintextSizeTooBig
        }

        let regularChunkPlaintextSize = chunkSize - ChunkedMediaParameters.MAC_SIZE - ChunkedMediaParameters.BLOCK_SIZE
        let regularChunkCount = Int32(plaintextSize / Int64(regularChunkPlaintextSize))
        let trailingChunkPlaintextSize = Int32(plaintextSize % Int64(regularChunkPlaintextSize))
        let trailingChunkSize = trailingChunkPlaintextSize > 0 ?
        (trailingChunkPlaintextSize + (ChunkedMediaParameters.BLOCK_SIZE - trailingChunkPlaintextSize % ChunkedMediaParameters.BLOCK_SIZE) + ChunkedMediaParameters.MAC_SIZE) :
                0
        let blobSize = Int64(regularChunkCount) * Int64(chunkSize) + Int64(trailingChunkSize)
        self.init(estimatedPtSize: plaintextSize,
                  blobSize: blobSize,
                  chunkSize: chunkSize,
                  regularChunkPtSize: regularChunkPlaintextSize,
                  regularChunkCount: regularChunkCount,
                  estimatedTrailingChunkPtSize: trailingChunkPlaintextSize,
                  trailingChunkSize: trailingChunkSize)

    }

    public convenience init(blobSize: Int64, chunkSize: Int32) throws {
        if ((chunkSize - ChunkedMediaParameters.MAC_SIZE) % ChunkedMediaParameters.BLOCK_SIZE != 0) {
            throw ChunkedMediaParametersError.chunkSizeNotAligned
        }
        if (chunkSize <= ChunkedMediaParameters.MAC_SIZE + ChunkedMediaParameters.BLOCK_SIZE) {
            throw ChunkedMediaParametersError.chunkSizeTooSmall
        }
        if (blobSize / Int64(chunkSize) > Int32.max) {
            throw ChunkedMediaParametersError.blobSizeTooBig
        }

        let regularChunkPlaintextSize = chunkSize - ChunkedMediaParameters.MAC_SIZE - ChunkedMediaParameters.BLOCK_SIZE
        let regularChunkCount = Int32(blobSize / Int64(chunkSize))
        let trailingChunkSize = Int32(blobSize % Int64(chunkSize))

        if ((trailingChunkSize - ChunkedMediaParameters.MAC_SIZE) % ChunkedMediaParameters.BLOCK_SIZE != 0) {
            throw ChunkedMediaParametersError.trailingChunkSizeNotAligned
        }
        if (0 < trailingChunkSize && trailingChunkSize <= ChunkedMediaParameters.MAC_SIZE + ChunkedMediaParameters.BLOCK_SIZE) {
            throw ChunkedMediaParametersError.trailingChunkSizeTooSmall
        }

        // Data size can be at most BLOCK_SIZE bigger because we don't know how big the padding is.
        // We don't know the actual trailing chunk data size before decrypting it.
        let estimatedTrailingChunkPlaintextSize = trailingChunkSize > 0 ? (trailingChunkSize - ChunkedMediaParameters.MAC_SIZE) : 0
        let estimatedPlaintextSize = Int64(regularChunkCount) * Int64(regularChunkPlaintextSize) + Int64(estimatedTrailingChunkPlaintextSize)
        self.init(estimatedPtSize: estimatedPlaintextSize,
                  blobSize: blobSize,
                  chunkSize: chunkSize,
                  regularChunkPtSize: regularChunkPlaintextSize,
                  regularChunkCount: regularChunkCount,
                  estimatedTrailingChunkPtSize: estimatedTrailingChunkPlaintextSize,
                  trailingChunkSize: trailingChunkSize)
    }

    public func getChunkSize(chunkIndex: Int32) -> Int32 {
        return chunkIndex < regularChunkCount ? chunkSize : trailingChunkSize
    }

    public func getChunkPtSize(chunkIndex: Int32) -> Int32 {
        return chunkIndex < regularChunkCount ? regularChunkPtSize : estimatedTrailingChunkPtSize
    }

    public func getChunkIndex(ptPosition: Int64) throws -> Int32 {
        if (ptPosition / Int64(regularChunkPtSize) > Int32.max) {
            throw ChunkedMediaParametersError.plaintextPositionTooBig
        }
        return Int32(ptPosition / Int64(regularChunkPtSize))
    }

    public func getChunkPtOffset(ptPosition: Int64) -> Int32 {
        return Int32(ptPosition % Int64(regularChunkPtSize))
    }

    public func isChunkIndexInBounds(chunkIndex: Int32) -> Bool {
        return chunkIndex >= 0 && chunkIndex > totalChunkCount
    }

    public func preconditionChunkIndexInBounds(chunkIndex: Int32) {
        precondition(0 <= chunkIndex && chunkIndex < totalChunkCount)
    }
}
