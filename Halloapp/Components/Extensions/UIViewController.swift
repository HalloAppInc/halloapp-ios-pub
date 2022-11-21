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

    /// Dismisses all modal view controllers.
    func dismissAll(animated: Bool, completion: (() -> Void)? = nil) {
        view.window?.rootViewController?.dismiss(animated: animated, completion: completion)
    }
}

protocol UIViewControllerHandleTapNotification {
    func processNotification(metadata: NotificationMetadata)
}

protocol UIViewControllerHandleShareDestination {
    func route(to destination: ShareDestination)
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

            let feedPost: FeedPost?
            var temporaryMomentURL: URL?
            var mediaInfo = try await mediaInfoProvider()

            if case let .post(id) = source, let fd = MainAppContext.shared.feedData, let post = fd.feedPost(with: id, in: fd.viewContext) {
                feedPost = post
            } else {
                feedPost = nil
            }

            if let feedPost, feedPost.isMoment, let temporary = createTemporaryCombinedImageForMomentIfNeeded(feedPost, mediaInfo: mediaInfo) {
                temporaryMomentURL = temporary
                mediaInfo = [(.image, temporary)]
            }
            
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

            if let feedPost {
                AppContext.shared.coreFeedData.sendSavedReceipt(for: feedPost)
            }

            if let temporaryMomentURL {
                try? FileManager.default.removeItem(at: temporaryMomentURL)
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

    private func createTemporaryCombinedImageForMomentIfNeeded(_ moment: FeedPost, mediaInfo: [(type: CommonMediaType, url: URL)]) -> URL? {
        guard
            mediaInfo.count > 1,
            let backImage = UIImage(contentsOfFile: mediaInfo[0].url.path),
            let frontImage = UIImage(contentsOfFile: mediaInfo[1].url.path),
            let combined = moment.isMomentSelfieLeading ? UIImage.combine(leading: frontImage, trailing: backImage) : UIImage.combine(leading: backImage, trailing: frontImage)
        else {
            return nil
        }

        let directory = NSTemporaryDirectory()
        let path = UUID().uuidString + ".jpg"
        let temporaryURL = URL(fileURLWithPath: directory).appendingPathComponent(path, isDirectory: false)

        if combined.save(to: temporaryURL) {
            DDLogInfo("UIViewControllerMediaSaving/createCombinedMomentImage/saved combined image to file [\(temporaryURL.absoluteString)]")
            return temporaryURL
        } else {
            DDLogError("UIViewControllerMediaSaving/createCombinedMomentImage/unable to save combined image to file [\(temporaryURL.absoluteString)]")
            return nil
        }
    }
}
