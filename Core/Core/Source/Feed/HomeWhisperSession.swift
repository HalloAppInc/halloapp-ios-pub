//
//  GroupWhisperSession.swift
//  Core
//
//  Created by Garrett on 8/18/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import Foundation
import CoreCommon
import CocoaLumberjackSwift

public enum HomeSessionType: Int16 {
    case all = 0
    case favorites = 1
}

public enum HomeSessionState: Int16 {
    case awaitingSetup = 0
    case ready = 1
}


