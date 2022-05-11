//
//  CommonMedia.swift
//  HalloApp
//
//  Created by Garrett on 4/2/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core

extension CommonMedia {
    var mediaURL: URL? {
        guard let relativeFilePath = relativeFilePath else { return nil }
        return mediaDirectory.fileURL(forRelativePath: relativeFilePath)
    }
}

extension MediaDirectory {
    var url: URL {
        switch self {
        case .chatMedia:
            return MainAppContext.chatMediaDirectoryURL
        case .media:
            return MainAppContext.mediaDirectoryURL
        case .shareExtensionMedia:
            return ShareExtensionDataStore.dataDirectoryURL
        case .notificationExtensionMedia:
            return NotificationServiceExtensionDataStore.dataDirectoryURL
        case .commonMedia:
            return AppContext.commonMediaStoreURL
        }
    }

    func fileURL(forRelativePath relativePath: String) -> URL {
        return url.appendingPathComponent(relativePath, isDirectory: false)
    }
}
