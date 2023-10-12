//
//  PHAssetMediaSubtype.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 11/1/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import Photos

extension PHAssetMediaSubtype {
    static let photoAnimated = PHAssetMediaSubtype(rawValue: 1 << 6)
    static let videoScreenRecording = PHAssetMediaSubtype(rawValue: 1 << 15)
}
