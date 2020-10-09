//
//  CountableEvent.swift
//  Core
//
//  Created by Garrett on 9/29/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation

public class CountableEvent {

    public init(
        namespace: String,
        metric: String,
        count: Int = 1,
        appVersion: String = AppContext.appVersionForXMPP,
        extraDimensions: [String: String] = [:])
    {
        self.namespace = namespace
        self.metric = metric
        self.count = count
        self.dimensions = extraDimensions
        self.dimensions["version"] = appVersion
    }

    public var namespace: String
    public var metric: String
    public var count: Int
    public var dimensions: [String: String]
}
