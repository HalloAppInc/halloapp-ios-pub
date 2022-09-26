//
//  CMDeviceMotion.swift
//  HalloApp
//
//  Created by Tanveer on 9/26/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CoreMotion
import UIKit

extension CMDeviceMotion {
    /// Emits the device's orientation based on its motion data.
    static var orientations: AsyncStream<UIDeviceOrientation> {
        AsyncStream<UIDeviceOrientation>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let manager = CMMotionManager()
            let queue = OperationQueue()

            manager.deviceMotionUpdateInterval = 0.5
            queue.qualityOfService = .userInitiated

            manager.startDeviceMotionUpdates(to: queue) { data, _ in
                guard let data = data, let orientation = orientation(from: data) else {
                    return
                }

                continuation.yield(orientation)
            }

            continuation.onTermination = { _ in
                manager.stopDeviceMotionUpdates()
            }
        }
    }

    private static func orientation(from data: CMDeviceMotion) -> UIDeviceOrientation? {
        let gravity = data.gravity
        let threshold = 0.75

        if gravity.x >= threshold {
            return .landscapeRight
        }
        if gravity.x <= -threshold {
            return .landscapeLeft
        }
        if gravity.y <= -threshold {
            return .portrait
        }
        if gravity.y >= threshold {
            return .portraitUpsideDown
        }

        // same as before
        return nil
    }
}
