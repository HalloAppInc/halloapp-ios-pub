//
//  LogArchives.swift
//  HalloApp
//
//  Created by Garrett on 4/5/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CoreCommon
import CocoaLumberjackSwift
import Foundation
import Zip

extension AppContext {

    public func archiveLogs(to archiveURL: URL) throws {
        var logfileURLs = fileLogger.logFileManager.sortedLogFilePaths.compactMap { URL(fileURLWithPath: $0) }
        if let directoryListingURL = createOrUpdateDirectoryListing() {
            logfileURLs.append(directoryListingURL)
        }
        try Zip.zipFiles(paths: logfileURLs, zipFilePath: archiveURL, password: nil, progress: nil)
    }

    public func uploadLogsToServer(completion: @escaping (Result<Void, Error>) -> Void) {
        // Run on a low priority queue.
        DispatchQueue.global(qos: .default).async { [weak self] in
            guard let self = self else {
                completion(.failure(RequestError.aborted))
                return
            }
            do {
                DDLogInfo("AppContext/uploadLogsToServer/begin")
                let tempDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                let archiveURL = tempDirectoryURL.appendingPathComponent("logs.zip")
                try self.archiveLogs(to: archiveURL)

                let queryItems = [
                    URLQueryItem(name: "uid", value: self.userData.userId),
                    URLQueryItem(name: "phone", value: self.userData.normalizedPhoneNumber),
                    URLQueryItem(name: "version", value: "ios\(AppContext.appVersionForService)"),
                ]
                var urlComps = URLComponents(string: "https://api.halloapp.net/api/logs/device/")
                urlComps?.queryItems = queryItems
                guard let url = urlComps?.url else {
                    DDLogError("AppContext/uploadLogsToServer/failed to get url: \(String(describing: urlComps))")
                    completion(.failure(RequestError.aborted))
                    return
                }
                guard let logData = try? Data(contentsOf: archiveURL) else {
                    DDLogError("AppContext/uploadLogsToServer/failed to get logData: \(archiveURL)")
                    completion(.failure(RequestError.malformedRequest))
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.httpBody = logData
                request.setValue(AppContext.userAgent, forHTTPHeaderField: "User-Agent")
                let task = URLSession.shared.dataTask(with: request) { (data, urlResponse, error) in
                    guard let httpResponse = urlResponse as? HTTPURLResponse else {
                        DDLogError("AppContext/uploadLogsToServer/error Invalid response. [\(String(describing: urlResponse))]")
                        completion(.failure(RequestError.malformedResponse))
                        return
                    }
                    guard let data = data,
                          let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                              DDLogError("AppContext/uploadLogsToServer/error Invalid response. [\(data ?? Data())]")
                              completion(.failure(RequestError.malformedResponse))
                              return
                    }
                    if let error = error {
                        DDLogError("AppContext/uploadLogsToServer/error [\(error)]")
                        completion(.failure(NSError(domain: "com.halloapp.uploadLogs", code: httpResponse.statusCode, userInfo: nil)))
                    } else {
                        completion(.success(()))
                    }
                    DDLogInfo("AppContext/uploadLogsToServer/response: \(httpResponse) - \(response)")
                }
                task.resume()
            } catch {
                DDLogError("AppContext/uploadLogsToServer/Failed to archive log files: \(error)")
                completion(.failure(RequestError.aborted))
            }
        }
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
            directoryContents(at: AppContext.documentsDirectoryURL),
            "LIBRARY",
            directoryContents(at: AppContext.libraryDirectoryURL),
        ]
        .joined(separator: "\n\n")
    }
}
