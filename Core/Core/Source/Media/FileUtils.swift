//
//  FileUtils.swift
//  Core
//
//  Created by Garrett on 9/6/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import Foundation
import QuickLookThumbnailing
import UIKit

public final class FileUtils {
    public static let thumbnailSizeDefault = CGSize(width: 238, height: 124)
    static let scale = UIScreen.main.scale
    static var thumbnailGenerator: QLThumbnailGenerator = {
        return QLThumbnailGenerator()
    }()

    public static func generateThumbnail(for url: URL, size: CGSize, completion: @escaping (Result<UIImage, Error>) -> Void) {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .thumbnail)
        thumbnailGenerator.generateBestRepresentation(for: request) { (thumbnail, error) in
            if let error = error {
                completion(.failure(error))
            } else if let thumbnail = thumbnail {
                completion(.success(thumbnail.uiImage))
            }
        }
    }
}
