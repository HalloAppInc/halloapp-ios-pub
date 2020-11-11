//
//  XMPPError.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 3/11/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation

public enum XMPPError: Error {
    case notConnected
    case timeout
    case canceled
    case aborted
    case malformed
    case serverError(String)
}
