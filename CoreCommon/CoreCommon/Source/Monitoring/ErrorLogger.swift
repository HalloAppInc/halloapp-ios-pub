//
//  ErrorLogger.swift
//  Core
//
//  Created by Garrett on 12/8/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation

public protocol ErrorLogger {
    func logError(_ error: Error)
}
