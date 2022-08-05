//
//  UIViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import UIKit
import Photos

protocol UIViewControllerScrollsToTop {

    func scrollToTop(animated: Bool)
}

extension UIViewController {

    func installAvatarBarButton() {
        let diameter: CGFloat = 30
        let avatar = LargeHitAvatarButton()
        avatar.configure(userId: MainAppContext.shared.userData.userId, using: MainAppContext.shared.avatarStore)
        avatar.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            avatar.heightAnchor.constraint(equalToConstant: diameter),
            avatar.widthAnchor.constraint(equalToConstant: diameter),
        ])

        avatar.addTarget(self, action: #selector(presentProfile), for: .touchUpInside)
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: avatar)
    }

    @objc
    private func presentProfile(_ sender: AnyObject) {
        let profile = ProfileViewController(nibName: nil, bundle: nil)
        let nav = UINavigationController(rootViewController: profile)
        present(nav, animated: true)
    }
    
    func proceedIfConnected() -> Bool {
        guard MainAppContext.shared.service.isConnected else {
            let alert = UIAlertController(title: Localizations.alertNoInternetTitle, message: Localizations.alertNoInternetTryAgain, preferredStyle: .alert)
            alert.addAction(.init(title: Localizations.buttonOK, style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
            return false
        }
        return true
    }
    
    func getFailedCallAlert() -> UIAlertController {
        let alert = UIAlertController(title: Localizations.failedCallTitle,
                                    message: Localizations.failedCallNoticeText,
                             preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default) { action in
            self.dismiss(animated: true, completion: nil)
        })
        
        return alert
    }

    // returns the topmost view controller in the app
    class var currentViewController: UIViewController? {
        var keyWindow: UIWindow?
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            if [.foregroundInactive, .foregroundActive].contains(scene.activationState) {
                for window in scene.windows {
                    if window.isKeyWindow {
                        keyWindow = window
                        break
                    }
                }
            }
        }

        var viewController = keyWindow?.rootViewController
        while let presentedViewController = viewController?.presentedViewController {
            viewController = presentedViewController
        }

        return viewController
    }
}

protocol UIViewControllerHandleTapNotification {
    func processNotification(metadata: NotificationMetadata)
}

fileprivate class LargeHitAvatarButton: AvatarViewButton {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return bounds.insetBy(dx: -12, dy: -12).contains(point)
    }
}

protocol UIViewControllerMediaSaving: UIViewController {
    /// Attempt to save the media provided by `mediaInfoProvider` to Photos.
    /// Handles requesting authorization and informing users about the result.
    ///
    /// - Parameters:
    ///   - source: Source of the media.
    ///   - mediaInfoProvider: Provides media types and urls. Managed objects from **view contexts** are safe to access in the closure.
    /// - Returns: A boolean indicating whether saving was successful.
    @discardableResult @MainActor
    func saveMedia(source: MediaItemSource, _ mediaInfoProvider: @MainActor @Sendable () async throws -> [(type: CommonMediaType, url: URL)]) async -> Bool
}

extension UIViewControllerMediaSaving {
    @discardableResult @MainActor
    func saveMedia(source: MediaItemSource, _ mediaInfoProvider: @MainActor @Sendable () async throws -> [(type: CommonMediaType, url: URL)]) async -> Bool {
        do {
            let isAuthorizedToSave: Bool = await {
                if #available(iOS 14, *) {
                    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                    return status == .authorized || status == .limited
                } else {
                    let status = await withCheckedContinuation { continuation in
                        PHPhotoLibrary.requestAuthorization { continuation.resume(returning: $0) }
                    }
                    return status == .authorized
                }
            }()
            
            guard isAuthorizedToSave else {
                DDLogInfo("UIViewControllerMediaSaving/saveMedia: User denied media saving permissions")
                
                let alert = UIAlertController(title: Localizations.mediaPermissionsError, message: Localizations.mediaPermissionsErrorDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: nil))
                present(alert, animated: true)
                return false
            }
            
            let mediaInfo = try await mediaInfoProvider()
            
            try await PHPhotoLibrary.shared().performChanges {
                for (type, url) in mediaInfo {
                    if type == .image {
                        PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                        AppContext.shared.eventMonitor.count(.mediaSaved(type: .image, source: source))
                    } else {
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                        AppContext.shared.eventMonitor.count(.mediaSaved(type: .video, source: source))
                    }
                }
            }

            if case let .post(id) = source, let fd = MainAppContext.shared.feedData, let post = fd.feedPost(with: id, in: fd.viewContext) {
                fd.sendSavedReceipt(for: post)
            }
            
            let toast = Toast(type: .icon(UIImage(named: "CheckmarkLong")?.withTintColor(.white)), text: Localizations.buttonDone)
            toast.show(viewController: self, shouldAutodismiss: true)
            
            return true
        } catch {
            DDLogError("UIViewControllerMediaSaving/saveMedia/error: \(error)")
            
            // TODO: Remove switching to MainActor when adopting Swift 5.7
            _ = { @MainActor in
                let alert = UIAlertController(title: nil, message: Localizations.mediaSaveError, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: nil))
                present(alert, animated: true)
            }()
            
            return false
        }
    }
}
