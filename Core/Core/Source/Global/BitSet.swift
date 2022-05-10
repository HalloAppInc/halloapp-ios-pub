//
//  BitSet.swift
//  Core
//
//  Created by Vasil Lyutskanov on 6.04.22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import Foundation

public class BitSet: CustomStringConvertible {
    private static let WORD_MAX = UINT8_MAX
    private static let WORD_SIZE = 8
    private static let WORD_BYTE_COUNT = WORD_SIZE / 8
    private typealias Word = UInt8

    public let count: Int
    private var words: [Word]

    public var data: Data {
        let data = words.withUnsafeBufferPointer { Data(buffer: $0) }
        return data
    }

    public var description: String {
        return String((0..<count).map{ self[$0] ? "1" : "0" })
    }

    public init(count: Int) {
        self.count = count
        let wordCount = (count - 1) / BitSet.WORD_SIZE + 1
        self.words = Array(repeating: 0, count: wordCount)
    }

    public init(from data: Data, count: Int) {
        self.count = min(count, data.count * 8)
        let array = data.withUnsafeBytes { Array<Word>($0) }
        self.words = Array(array.prefix(self.count))
    }

    public convenience init(from data: Data) {
        self.init(from: data, count: data.count * 8)
    }

    public subscript(index: Int) -> Bool {
        get {
            return words[index / BitSet.WORD_SIZE] & (1 << (index % BitSet.WORD_SIZE)) > 0
        }
        set(value) {
            if value {
                words[index / BitSet.WORD_SIZE] |= 1 << (index % BitSet.WORD_SIZE)
            } else {
                words[index / BitSet.WORD_SIZE] &= ~(1 << (index % BitSet.WORD_SIZE))
            }
        }
    }

    public func areAllBitsSet() -> Bool {
        guard words.count > 0 else { return false }
        for i in 0..<(words.count - 1) {
            if words[i] != BitSet.WORD_MAX {
                return false
            }
        }
        let leapBit = count % BitSet.WORD_SIZE
        return words[words.count - 1] == BitSet.Word((1 << leapBit) - 1)
    }
}
