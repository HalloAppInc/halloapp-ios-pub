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

    typealias Position = AVCaptureDevice.Position

    let identifier = UUID()
    let type: CaptureType
    let isMultiCam: Bool

    private var directions: [Int64: Position] = [:]
    private var settings: [Position: AVCapturePhotoSettings] = [:]
    private var results: [CaptureResult] = []

    let progress: ([CaptureResult], Bool) -> Void

    var isFulfilled: Bool {
        let needed: Int
        switch type {
        case .both(_):
            needed = 2
        default:
            needed = 1
        }

        return results.count == needed
    }

    init(type: CaptureType, isMultiCam: Bool, progress: @escaping ([CaptureResult], Bool) -> Void) {
        self.type = type
        self.isMultiCam = isMultiCam
        self.progress = progress
    }

    func set(settings: AVCapturePhotoSettings, for direction: Position) {
        self.settings[direction] = settings
        directions[settings.uniqueID] = direction
    }

    func set(photo: AVCapturePhoto) -> Position? {
        guard
            let image = photo.uiImage,
            let direction = directions[photo.resolvedSettings.uniqueID]
        else {
            return nil
        }

        let result = CaptureResult(identifier: identifier,
                                        image: image.correctlyOrientedImage(),
                                    direction: direction,
                                    isPrimary: direction == type.primaryPosition)
        results.append(result)

        if isMultiCam {
            if isFulfilled {
                progress(results, true)
            }
        } else {
            progress([result], isFulfilled)
        }

        return direction
    }

    func settings(for direction: Position) -> AVCapturePhotoSettings? {
        settings[direction]
    }
}

// MARK: - CaptureType enum

extension CaptureRequest {

    enum CaptureType {
        case single(Position), both(primary: Position)

        var primaryPosition: Position {
            switch self {
            case .single(let position):
                return position
            case .both(primary: let position):
                return position
            }
        }
    }
}

// MARK: - Position extension

extension CaptureRequest.Position {

    var opposite: Self? {
        switch self {
        case .back:
            return .front
        case .front:
            return .back
        case .unspecified:
            return nil
        @unknown default:
            return nil
        }
    }
}

// MARK: - CaptureResult implementation

struct CaptureResult {
    /// Equal to the identifier of the capture request.
    let identifier: UUID
    let image: UIImage
    let direction: CaptureRequest.Position
    let isPrimary: Bool
}
