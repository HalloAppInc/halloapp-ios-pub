//
//  LogArchives.swift
//  HalloApp
//
//  Created by Garrett on 4/5/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjack
import Foundation
import Zip

extension MainAppContext {

    public func archiveLogs(to archiveURL: URL) throws {
        var logfileURLs = fileLogger.logFileManager.sortedLogFilePaths.compactMap { URL(fileURLWithPath: $0) }
        if let directoryListingURL = createOrUpdateDirectoryListing() {
            logfileURLs.append(directoryListingURL)
        }
        try Zip.zipFiles(paths: logfileURLs, zipFilePath: archiveURL, password: nil, progress: nil)
    }

    private func createOrUpdateDirectoryListing() -> URL? {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ls", isDirectory: false)
            .appendingPathExtension("txt")
        do {
            try makeDirectoryListing().write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            DDLogError("createOrUpdateFileListing/error [\(error)]")
            return nil
        }
    }

    private func fileDetails(name: String?, size: Int?, depth: Int) -> String {
        var str = String(repeating: "| ", count: depth)
        str += name ?? "[unknown]"
        if let size = size {
            let sizeString = "[\(size)]"
            str += String(repeating: ".", count: max(0, 80 - str.count - sizeString.count))
            str += sizeString
        }
        return str
    }

    private func directoryContents(at url: URL, depth: Int = 0) -> String {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .nameKey, .isDirectoryKey],
                options: .includesDirectoriesPostOrder)
            return contents
                .compactMap { url in
                    guard let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .nameKey, .isDirectoryKey]) else {
                        return nil
                    }
                    let line = fileDetails(name: resourceValues.name, size: resourceValues.fileSize, depth: depth)
                    let children = resourceValues.isDirectory ?? false ? directoryContents(at: url, depth: depth + 1) : ""
                    return children.isEmpty ? line : [line, children].joined(separator: "\n")
                }
                .joined(separator: "\n")
        } catch {
            DDLogError("directoryContents/\(url.absoluteString)/error [\(error)]")
            return ""
        }
    }

    private func makeDirectoryListing() -> String {
        return [
            "TEMPORARY",
            directoryContents(at: URL(fileURLWithPath: NSTemporaryDirectory())),
            "DOCUMENTS",
            directoryContents(at: MainAppContext.documentsDirectoryURL),
            "LIBRARY",
            directoryContents(at: MainAppContext.libraryDirectoryURL),
        ]
        .joined(separator: "\n\n")
    }
}
