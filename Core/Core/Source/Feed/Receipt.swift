//
//  Receipt.swift
//  Core
//
//  Created by Garrett on 3/23/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import Foundation

public struct Receipt {
    public init(deliveredDate: Date? = nil, seenDate: Date? = nil, screenshotDate: Date? = nil) {
        self.deliveredDate = deliveredDate
        self.seenDate = seenDate
        self.screenshotDate = screenshotDate
    }

    public var deliveredDate: Date? = nil
    public var seenDate: Date? = nil
    public var screenshotDate: Date? = nil
}
