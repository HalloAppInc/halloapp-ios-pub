//
//  SnapchatShareProvider.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 11/10/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import SCSDKCoreKit
import SCSDKCreativeKit
import UIKit

class SnapchatShareProvider: PostShareProvider {

    // Must hold a reference to snapAPI
    private static var snapAPI: SCSDKSnapAPI?

    static var analyticsShareDestination: String {
        return "snapchat"
    }

    static var title: String {
        return "Snapchat"
    }

    static var canShare: Bool {
        // Disable until we get prod API keys
        return false
        // return URL(string: "snapchat://").flatMap { UIApplication.shared.canOpenURL($0) } ?? false
    }

    static func share(text: String?, image: UIImage?, completion: ShareProviderCompletion?) {
        share(text: text, stickerImage: image, backgroundImage: nil, backgroundVideoURL: nil, completion: completion)
    }

    static func share(post: FeedPost, mediaIndex: Int?, completion: ShareProviderCompletion?) {
        let image = ExternalSharePreviewImageGenerator.image(for: post, mediaIndex: mediaIndex, addBottomPadding: true)

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
                                share(text: nil, stickerImage: nil, backgroundImage: nil, backgroundVideoURL: videoURL) { result in
                                    do {
                                        try FileManager.default.removeItem(at: videoURL)
                                    } catch {
                                        DDLogError("InstagramShareStoriesProvider/Error deleting shared video: \(error)")
                                    }
                                    completion?(result)
                                }
                            } else {
                                share(text: nil, stickerImage: nil, backgroundImage: image, backgroundVideoURL: nil, completion: completion)
                            }
                        }
                    }
                    return
                }
            }
        }

        share(text: nil, stickerImage: nil, backgroundImage: image, backgroundVideoURL: nil, completion: completion)
    }

    static func share(text: String?, stickerImage: UIImage?, backgroundImage: UIImage?, backgroundVideoURL: URL?, completion: ShareProviderCompletion?) {
        SCSDKSnapKit.initSDK()

        let content: SCSDKSnapContent
        if let backgroundVideoURL = backgroundVideoURL {
            let video = SCSDKSnapVideo(videoUrl: backgroundVideoURL)
            content = SCSDKVideoSnapContent(snapVideo: video)
        } else if let backgroundImage = backgroundImage {
            let photo = SCSDKSnapPhoto(image: backgroundImage)
            content = SCSDKPhotoSnapContent(snapPhoto: photo)
        } else {
            content = SCSDKNoSnapContent()
        }

        if let stickerImage = stickerImage {
            content.sticker = SCSDKSnapSticker(stickerImage: stickerImage)
        }

        content.caption = text

        let snapAPI = SCSDKSnapAPI()
        self.snapAPI = snapAPI
        snapAPI.startSending(content) { error in
            self.snapAPI = nil
            SCSDKSnapKit.deinitialize()
            completion?(error == nil ? .success : .failed)
        }
    }
}

