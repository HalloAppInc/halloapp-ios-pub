//
//  ViewfinderLayout.swift
//  HalloApp
//
//  Created by Tanveer on 11/6/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import AVFoundation

typealias CameraPosition = AVCaptureDevice.Position

enum ViewfinderLayout: Equatable {

    case fullPortrait(CameraPosition)
    case fullLandscape(CameraPosition)
    case splitPortrait(leading: CameraPosition)
    case splitLandscape(top: CameraPosition)

    var positions: (primary: ViewfinderPosition, secondary: ViewfinderPosition) {
        let primaryPosition: ViewfinderPosition

        switch (self, primaryCameraPosition) {
        case (.fullPortrait(_), .back):
            primaryPosition = .fullPortrait
        case (.fullPortrait(_), _):
            primaryPosition = .collapsedPortrait

        case (.fullLandscape(_), .back):
            primaryPosition = .fullLandscape
        case (.fullLandscape(_), _):
            primaryPosition = .collapsedLandscape

        case (.splitPortrait(leading: _), .back):
            primaryPosition = .leading
        case (.splitPortrait(leading: _), _):
            primaryPosition = .trailing

        case (.splitLandscape(top: _), .back):
            primaryPosition = .top
        case (.splitLandscape(top: _), _):
            primaryPosition = .bottom
        }

        return (primaryPosition, primaryPosition.flipped)
    }

    var next: Self? {
        let next: Self?
        let cameraPosition = primaryCameraPosition

        switch self {
        case .splitPortrait(leading: _):
            next = .splitLandscape(top: cameraPosition)
        case .splitLandscape(top: _):
            next = .splitPortrait(leading: cameraPosition.opposite)
        default:
            next = nil
        }

        return next
    }

    var flipped: Self {
        let flipped: Self
        let flippedPosition = primaryCameraPosition.opposite

        switch self {
        case .splitPortrait(leading: _):
            flipped = .splitPortrait(leading: flippedPosition)
        case .splitLandscape(top: _):
            flipped = .splitLandscape(top: flippedPosition)
        case .fullPortrait(_):
            flipped = .fullPortrait(flippedPosition)
        case .fullLandscape(_):
            flipped = .fullLandscape(flippedPosition)
        }

        return flipped
    }

    var toggled: Self {
        let toggled: Self
        let cameraPosition = primaryCameraPosition

        switch self {
        case .splitPortrait(leading: _):
            toggled = .fullPortrait(cameraPosition)
        case .fullPortrait(_):
            toggled = .splitPortrait(leading: cameraPosition)
        case .splitLandscape(top: _):
            toggled = .fullLandscape(cameraPosition)
        case .fullLandscape(_):
            toggled = .splitLandscape(top: cameraPosition)
        }

        return toggled
    }

    var primaryCameraPosition: CameraPosition {
        let primary: CameraPosition

        switch self {
        case .splitPortrait(leading: let position):
            primary = position
        case .splitLandscape(top: let position):
            primary = position
        case .fullPortrait(let position):
            primary = position
        case .fullLandscape(let position):
            primary = position
        }

        return primary
    }
}

// MARK: - ViewfinderPosition

enum ViewfinderPosition {

    case fullPortrait, fullLandscape
    case collapsedPortrait, collapsedLandscape
    case leading, top, trailing, bottom
    case topLeading, topTrailing, bottomTrailing, bottomLeading

    var next: Self? {
        let next: Self?
        switch self {
        case .fullPortrait, .fullLandscape, .collapsedPortrait, .collapsedLandscape:
            next = nil

        case .leading:
            next = .topLeading
        case .trailing:
            next = .bottomTrailing
        case .top:
            next = .topTrailing
        case .bottom:
            next = .bottomLeading

        case .topLeading:
            next = .top
        case .topTrailing:
            next = .trailing
        case .bottomTrailing:
            next = .bottom
        case .bottomLeading:
            next = .leading
        }

        return next
    }

    var toggled: Self? {
        let toggled: Self?
        switch self {
        case .leading:
            toggled = .fullPortrait
        case .trailing:
            toggled = .collapsedPortrait
        case .fullPortrait:
            toggled = .leading
        case .collapsedPortrait:
            toggled = .trailing

        case .top:
            toggled = .fullLandscape
        case .bottom:
            toggled = .collapsedLandscape
        case .fullLandscape:
            toggled = .top
        case .collapsedLandscape:
            toggled = .bottom

        default:
            toggled = nil
        }

        return toggled
    }

    var flipped: Self {
        let flipped: Self
        switch self {
        case .fullPortrait:
            flipped = .collapsedPortrait
        case .fullLandscape:
            flipped = .collapsedLandscape
        case .collapsedPortrait:
            flipped = .fullPortrait
        case .collapsedLandscape:
            flipped = .fullLandscape

        case .leading:
            flipped = .trailing
        case .trailing:
            flipped = .leading
        case .top:
            flipped = .bottom
        case .bottom:
            flipped = .top

        case .topLeading:
            flipped = .bottomTrailing
        case .topTrailing:
            flipped = .bottomLeading
        case .bottomTrailing:
            flipped = .topLeading
        case .bottomLeading:
            flipped = .topTrailing
        }

        return flipped
    }

    var isIntermediate: Bool {
        switch self {
        case .topLeading, .topTrailing, .bottomTrailing, .bottomLeading:
            return true
        default:
            return false
        }
    }
}

// MARK: - CameraPosition extension

extension CameraPosition {

    var opposite: Self {
        switch self {
        case .back:
            return .front
        case .front:
            return .back
        case .unspecified:
            return .unspecified
        @unknown default:
            return self
        }
    }
}
