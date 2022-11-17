//
//  InstagramStoriesShareProvider.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 10/11/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import UIKit

class InstagramStoriesShareProvider: PostShareProvider {

    private static let appID = "5856403147724250"

    static var analyticsShareDestination: String {
        return "instagram_stories"
    }

    static var title: String {
        return NSLocalizedString("shareprovider.instagramstories.title", value: "Instagram Stories", comment: "Title for sharing to instagram stories")
    }

    static var canShare: Bool {
        guard let url = URL(string: "instagram-stories://") else {
            return false
        }
        return UIApplication.shared.canOpenURL(url)
    }

    static func share(text: String?, image: UIImage?, completion: ShareProviderCompletion?) {
        share(stickerImage: nil, backgroundImage: image, backgroundVideoURL: nil, completion: completion)
    }

    static func share(post: FeedPost, mediaIndex: Int?, completion: ShareProviderCompletion?) {
        let stickerImage = ExternalSharePreviewImageGenerator.image(for: post, mediaIndex: mediaIndex)

        if let orderedMedia = post.media?.sorted(by: { $0.order < $1.order }), !orderedMedia.isEmpty {
            if mediaIndex ?? 0 < orderedMedia.count {
                let media = orderedMedia[mediaIndex ?? 0]
                if media.type == .video, let mediaURL = media.mediaURL {
                    let toast = Toast(type: .activityIndicator, text: Localizations.exporting)
                    toast.show(shouldAutodismiss: false)

                    Task {
                        let videoURL = await ExternalSharePreviewImageGenerator.video(for: mediaURL)
                        DispatchQueue.main.async {
                            toast.hide()

                            if let videoURL {
                                share(stickerImage: nil, backgroundImage: nil, backgroundVideoURL: videoURL) { result in
                                    do {
                                        try FileManager.default.removeItem(at: videoURL)
                                    } catch {
                                        DDLogError("InstagramShareStoriesProvider/Error deleting shared video: \(error)")
                                    }
                                    completion?(result)
                                }
                            } else {
                                share(stickerImage: stickerImage, backgroundImage: nil, backgroundVideoURL: nil, completion: completion)
                            }
                        }
                    }
                    return
                }
            }
        }

        share(stickerImage: stickerImage, backgroundImage: nil, backgroundVideoURL: nil, completion: completion)
    }

    static func share(stickerImage: UIImage?, backgroundImage: UIImage?, backgroundVideoURL: URL?, completion: ShareProviderCompletion?) {
        guard let url = URL(string: "instagram-stories://share?source_application=\(Self.appID)") else {
            completion?(.failed)
            return
        }

        var pasteboardItems: [String: Any] = [:]

        if let stickerImage = stickerImage {
            pasteboardItems["com.instagram.sharedSticker.stickerImage"] = stickerImage
        }

        if let backgroundVideoURL = backgroundVideoURL, let videoData = try? Data(contentsOf: backgroundVideoURL) {
            pasteboardItems["com.instagram.sharedSticker.backgroundVideo"] = videoData
        } else if let backgroundImage = backgroundImage {
            pasteboardItems["com.instagram.sharedSticker.backgroundImage"] = backgroundImage
        } else {
            pasteboardItems["com.instagram.sharedSticker.backgroundTopColor"] = "#000000"
            pasteboardItems["com.instagram.sharedSticker.backgroundBottomColor"] = "#000000"
        }

        if !pasteboardItems.isEmpty {
            UIPasteboard.general.setItems([pasteboardItems], options: [.expirationDate: Date(timeIntervalSinceNow: 5 * 60)])
        }

        UIApplication.shared.open(url) { completed in
            completion?(completed ? .success : .failed)
        }
    }
}
