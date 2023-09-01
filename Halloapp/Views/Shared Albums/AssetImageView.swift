//
//  AssetImageView.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 7/13/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import Photos
import UIKit

class AssetImageView: UIImageView {

    private struct Constants {
        static let thumbnailSize = CGSize(width: 256, height: 256)
    }

    enum AssetMode {
        case thumbnail
        case fullSize
    }

    private static let imageManager = PHCachingImageManager()

    private var currentImageRequestID: PHImageRequestID?
    private var currentAssetLocalIdentifier: String?

    var assetMode: AssetMode = .thumbnail

    var asset: PHAsset? {
        didSet {
            if let asset, asset.localIdentifier == currentAssetLocalIdentifier {
                return
            }
            currentAssetLocalIdentifier = asset?.localIdentifier

            image = nil

            if let currentImageRequestID {
                Self.imageManager.cancelImageRequest(currentImageRequestID)
            }

            guard let asset else {
                return
            }

            let targetSize: CGSize
            switch assetMode {
            case .thumbnail:
                targetSize = Constants.thumbnailSize
            case .fullSize:
                targetSize = PHImageManagerMaximumSize
            }

            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true

            var requestID: PHImageRequestID?
            requestID = Self.imageManager.requestImage(for: asset,
                                                       targetSize: targetSize,
                                                       contentMode: contentMode.imageContentMode,
                                                       options: options) { [weak self] image, metadata in
                guard let self, let requestID, requestID == self.currentImageRequestID else {
                    return
                }

                self.image = image
            }
            currentImageRequestID = requestID
        }
    }
}

fileprivate extension UIView.ContentMode {

    var imageContentMode: PHImageContentMode {
        switch self {
        case .scaleAspectFit:
            return .aspectFit
        case .scaleAspectFill:
            return .aspectFill
        default:
            return .default
        }
    }
}
