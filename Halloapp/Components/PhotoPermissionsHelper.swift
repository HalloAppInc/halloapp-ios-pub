//
//  PhotoPermissionsHelper.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 9/5/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import Photos

extension PHAuthorizationStatus {

    var hasAnyAuthorization: Bool {
        switch self {
        case .authorized, .limited:
            return true
        default:
            return false
        }
    }
}

class PhotoPermissionsHelper {

    enum AccessLevel {
        case addOnly
        case readWrite

        @available(iOS 14, *)
        fileprivate var phAccessLevel: PHAccessLevel {
            switch self {
            case .addOnly:
                return .addOnly
            case .readWrite:
                return .readWrite
            }
        }
    }

    class var photoAuthorizationDidChange: Notification.Name {
        return Notification.Name(rawValue: "photoAuthorizationDidChange")
    }

    class func authorizationStatus(for accessLevel: AccessLevel) -> PHAuthorizationStatus {
        return PHPhotoLibrary.authorizationStatus(for: accessLevel.phAccessLevel)
    }

    class func requestAuthorization(for accessLevel: AccessLevel, handler: ((PHAuthorizationStatus) -> Void)? = nil) {
        let notificationHandler: (PHAuthorizationStatus) -> Void = { status in
            NotificationCenter.default.post(Notification(name: PhotoPermissionsHelper.photoAuthorizationDidChange))
            handler?(status)
        }

        PHPhotoLibrary.requestAuthorization(for: accessLevel.phAccessLevel, handler: notificationHandler)
    }

    class func requestAuthorization(for accessLevel: AccessLevel) async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            self.requestAuthorization(for: accessLevel) { status in
                continuation.resume(returning: status)
            }
        }
    }
}
