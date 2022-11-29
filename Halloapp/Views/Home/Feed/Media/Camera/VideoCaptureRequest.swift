//
//  VideoCaptureRequest.swift
//  HalloApp
//
//  Created by Tanveer on 11/22/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import UIKit

class VideoCaptureRequest: CaptureRequest {

    typealias DurationStream = AsyncThrowingStream<Double, Error>

    let identifier = UUID()
    let layout: ViewfinderLayout
    let orientation: UIDeviceOrientation

    let duration: DurationStream
    private let continuation: DurationStream.Continuation?

    private(set) var result: URL?

    var isFulfilled: Bool {
        result != nil
    }

    init?(layout: ViewfinderLayout, orientation: UIDeviceOrientation) {
        guard layout.primaryCameraPosition != .unspecified else {
            return nil
        }

        self.layout = layout
        self.orientation = orientation

        var continuation: DurationStream.Continuation?
        duration = DurationStream {
            continuation = $0
        }

        self.continuation = continuation
    }

    func set(url: URL) {
        result = url
        continuation?.finish()
    }

    func set(error: Error) {
        continuation?.finish(throwing: error)
    }
}
