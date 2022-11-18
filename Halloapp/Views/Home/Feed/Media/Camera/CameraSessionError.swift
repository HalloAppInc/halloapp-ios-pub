//
//  CameraSessionError.swift
//  HalloApp
//
//  Created by Tanveer on 11/14/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import AVFoundation
import CoreCommon

enum CameraSessionError: Error {

    case permissions(AVMediaType)
    case cameraInitialization(CameraPosition)
    case microphoneInitialization
    case photoOutput
    case videoOutput
    case audioOutput

    var title: String {
        let title: String
        switch self {
        case .permissions(_):
            title = Localizations.cameraPermissionsTitle
        case .cameraInitialization(_), .microphoneInitialization, .photoOutput, .videoOutput, .audioOutput:
            title = Localizations.cameraInitializationErrorTitle
        }

        return title
    }

    var description: String? {
        let description: String?
        switch self {
        case .permissions(let format) where format == .video:
            description = Localizations.cameraPermissionsBody
        case .permissions(let format) where format == .audio:
            description = Localizations.microphonePermissionsBody

        case .cameraInitialization(let side) where side == .back:
            description = Localizations.backCameraInitializationFailure
        case .cameraInitialization(let side) where side == .front:
            description = Localizations.frontCameraInitializationFailure
        case .microphoneInitialization:
            description = Localizations.microphoneInitializationFailure

        case .photoOutput:
            description = Localizations.photoOutputInitializationFailure
        case .videoOutput:
            description = Localizations.videoOutputInitializationFailure
        case .audioOutput:
            description = Localizations.audioOutputInitializationFailure
        default:
            description = nil
        }

        return description
    }

    var isPermissionsError: Bool {
        if case .permissions(_) = self {
            return true
        }

        return false
    }
}

// MARK: - localizations

extension Localizations {

    // MARK: permission errors

    static var cameraPermissionsTitle: String {
        NSLocalizedString("camera.permissions.title",
                   value: "Camera Access",
                 comment: "Title of alert for when the app does not have permissions to access the camera.")
    }

    static var cameraPermissionsBody: String {
        NSLocalizedString("media.camera.access.request",
                   value: "HalloApp does not have access to your camera. To enable access, tap Settings and turn on Camera",
                 comment: "Alert asking to enable Camera permission after attempting to use in-app camera.")
    }

    static var microphonePermissionsTitle: String {
        NSLocalizedString("media.mic.access.request.title",
                   value: "Microphone Access",
                 comment: "Alert asking to enable Microphone permission after attempting to use in-app camera.")
    }

    static var microphonePermissionsBody: String {
        NSLocalizedString("media.mic.access.request.body",
                   value: "To record videos with sound, HalloApp needs microphone access. To enable access, tap Settings and turn on Microphone.",
                 comment: "Alert asking to enable Camera permission after attempting to use in-app camera.")
    }

    // MARK: setup errors

    static var cameraInitializationErrorTitle: String {
        NSLocalizedString("camera.init.error.title",
                   value: "Setup Error",
                 comment: "Title for a popup alerting about camera initialization error.")
    }

    static var backCameraInitializationFailure: String {
        NSLocalizedString("camera.init.error.1",
                   value: "Unable to use the back camera.",
                 comment: "Error shown when the back camera isn't available.")
    }

    static var frontCameraInitializationFailure: String {
        NSLocalizedString("camera.init.error.2",
                   value: "Unable to use the front camera.",
                 comment: "Error shown when the front camera isn't available.")
    }

    static var microphoneInitializationFailure: String {
        NSLocalizedString("camera.init.error.3",
                   value: "Unable to use the microphone.",
                 comment: "Error shown when the microphone isn't available.")
    }

    static var photoOutputInitializationFailure: String {
        NSLocalizedString("camera.init.error.4",
                   value: "Photo capture is unavailable. Please try again later.",
                 comment: "Error shown when photo output setup failed.")
    }

    static var videoOutputInitializationFailure: String {
        NSLocalizedString("camera.init.error.5",
                   value: "Video recording is unavailable. Please try again later.",
                 comment: "Error shown when video recording setup failed.")
    }

    static var audioOutputInitializationFailure: String {
        NSLocalizedString("camera.init.error.6",
                   value: "Audio recording is unavailable. Please try again later.",
                 comment: "Error shown when audio recording setup failed.")
    }
}
