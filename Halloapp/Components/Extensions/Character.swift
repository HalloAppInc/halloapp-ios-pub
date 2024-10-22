//
//  Character.swift
//  HalloApp
//
//  Created by Tony Jiang on 6/18/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation

extension Character {

    private func isSimpleEmoji() -> Bool {
        guard let firstScalar = unicodeScalars.first else { return false }
        return firstScalar.properties.isEmoji && firstScalar.value > 0x238C
    }

    private func isCombinedIntoEmoji() -> Bool {
        return unicodeScalars.count > 1 && unicodeScalars.first?.properties.isEmoji ?? false
    }

    var isEmoji: Bool {
        isSimpleEmoji() || isCombinedIntoEmoji()
    }
}

