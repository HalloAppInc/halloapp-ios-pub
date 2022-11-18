//
//  CaptureRequest.swift
//  HalloApp
//
//  Created by Tanveer on 9/5/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import AVFoundation

class CaptureRequest {

    typealias ProgressStream = AsyncThrowingStream<CaptureResult, Error>

    let identifier = UUID()
    let layout: ViewfinderLayout
    let orientation: UIDeviceOrientation
    let shouldTakeDelayedPhoto: Bool

    private var directions: [Int64: CameraPosition] = [:]
    private var settings: [CameraPosition: AVCapturePhotoSettings] = [:]
    private var results: [CaptureResult] = []
    private(set) var error: Error?

    let progress: ProgressStream
    private let continuation: ProgressStream.Continuation?

    var isFulfilled: Bool {
        results.count == resultsNeeded
    }

    var resultsNeeded: Int {
        let needed: Int
        switch layout {
        case .splitLandscape(top: _), .splitPortrait(leading: _):
            needed = 2
        case .fullPortrait(_) where shouldTakeDelayedPhoto, .fullLandscape(_) where shouldTakeDelayedPhoto:
            needed = 2
        default:
            needed = 1
        }

        return needed
    }

    init?(layout: ViewfinderLayout, orientation: UIDeviceOrientation, takeDelayedSecondPhoto: Bool) {
        guard layout.primaryCameraPosition != .unspecified else {
            return nil
        }

        self.layout = layout
        self.orientation = orientation
        self.shouldTakeDelayedPhoto = takeDelayedSecondPhoto

        var continuation: ProgressStream.Continuation?
        progress = ProgressStream {
            continuation = $0
        }

        self.continuation = continuation
    }

    deinit {
        continuation?.finish()
    }

    func set(settings: AVCapturePhotoSettings, for position: CameraPosition) {
        self.settings[position] = settings
        directions[settings.uniqueID] = position
    }

    func set(photo: AVCapturePhoto) -> CameraPosition? {
        guard
            let image = photo.uiImage,
            let direction = directions[photo.resolvedSettings.uniqueID]
        else {
            return nil
        }

        let result = CaptureResult(identifier: identifier,
                                        image: image,
                               cameraPosition: direction,
                                  orientation: orientation,
                                       layout: layout,
                   resultsNeededForCompletion: resultsNeeded)

        results.append(result)
        continuation?.yield(result)

        if isFulfilled {
            continuation?.finish()
        }

        return direction
    }

    func set(error: Error) {
        self.error = error
        continuation?.finish(throwing: error)
    }

    func settings(for position: CameraPosition) -> AVCapturePhotoSettings? {
        settings[position]
    }
}

// MARK: - CaptureResult implementation

struct CaptureResult {
    /// Equal to the identifier of the capture request.
    let identifier: UUID
    let image: UIImage
    let cameraPosition: CameraPosition
    let orientation: UIDeviceOrientation
    let layout: ViewfinderLayout
    let resultsNeededForCompletion: Int

    var isPrimary: Bool {
        cameraPosition == layout.primaryCameraPosition
    }
}
