//
//  String.swift
//  HalloApp
//
//  Created by Tony Jiang on 6/18/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation

extension String {
    var containsOnlyEmoji: Bool { !isEmpty && !contains { !$0.isEmoji } }
}
