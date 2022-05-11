//
//  LinkPreviewMetadataProvider.swift
//  Core
//
//  Created by Nandini Shetty on 3/29/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//
import Foundation
import CocoaLumberjackSwift
import SwiftSoup
import UIKit

public enum PreviewFetchError: Error {
    case timeout
    case urlNotFound
    case htmlNotFound
    case htmlParsingError
    case dataFetchError
    case previewError
}

public class LinkPreviewMetadataProvider {

    // We're setting the user agent to WhatsApp to get mobile optimized metadata.
    static let userAgent = "WhatsApp/2"

    // If the scheme is missing / if the scheme is http, we convert to https to be able to make a request
    private static func processURLIfNecessary(url: URL?) -> URL? {
        guard let url = url else {
            return nil
        }
        if url.scheme != nil, url.scheme?.lowercased() != "http" {
            return url
        }

        if var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false), urlComponents != nil, let newScheme = fallbackScheme(currentScheme: url.scheme?.lowercased()) {
            urlComponents.scheme = newScheme
            return urlComponents.url
        }
        return nil
    }

    private static func fallbackScheme(currentScheme: String?) -> String? {
        switch currentScheme {
        case nil, "http", "https":
            return "https"
        case .some(_):
            return nil
        }
    }

    public static func startFetchingMetadata(for url: URL?, completion: ((LinkPreviewData?, UIImage?, PreviewFetchError?) -> ())?) {
        var timeoutWorkItem: DispatchWorkItem?
        let previewFetchWorkItem: DispatchWorkItem = DispatchWorkItem {
            guard let requestURL = processURLIfNecessary(url: url) else {
                DDLogInfo("LinkPreviewMetadataProvider/startFetchingMetadata/ no url found")
                handleCompletion(linkPreviewData: nil, previewImage: nil, error: PreviewFetchError.urlNotFound, dispatchWorkItemToCancel: timeoutWorkItem, completion: completion)
                return
            }
            DDLogInfo("LinkPreviewMetadataProvider/startFetchingMetadata/ url \(requestURL)")
            var request = URLRequest(url: requestURL)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                guard let data = data, error == nil else {
                    DDLogError("LinkPreviewMetadataProvider/startFetchingMetadata/ error \(String(describing: error))")
                    handleCompletion(linkPreviewData: nil, previewImage: nil, error: PreviewFetchError.dataFetchError, dispatchWorkItemToCancel: timeoutWorkItem, completion: completion)
                    return
                }

                if let httpStatus = response as? HTTPURLResponse, httpStatus.statusCode != 200 {
                    DDLogInfo("LinkPreviewMetadataProvider/startFetchingMetadata/status code : \(httpStatus.statusCode) response: \(String(describing: response))")
                }

                let html = String(data: data, encoding: .utf8)
                guard let html = html else {
                    DDLogError("LinkPreviewMetadataProvider/startFetchingMetadata/ error no html found")
                    handleCompletion(linkPreviewData: nil, previewImage: nil, error: PreviewFetchError.htmlNotFound, dispatchWorkItemToCancel: timeoutWorkItem, completion: completion)
                    return
                }
                do {
                    let document: Document = try SwiftSoup.parse(html, "https://" + (url.host ?? ""))
                    let title = parseTitle(document: document)
                    let description = parseDescription(document: document)
                    let imageUrl = parseImageURL(document: document)

                    let linkPreviewData = LinkPreviewData(id: nil, url: requestURL, title: title ?? "", description: description ?? "", previewImages: [])
                    if let imageUrl = imageUrl, imageUrl != "" {
                        downloadImage(imageUrl: imageUrl) { previewImage in
                            if let completion = completion {
                                DDLogInfo("LinkPreviewMetadataProvider/startFetchingMetadata/ finished fetcing metadata with image")
                                handleCompletion(linkPreviewData: linkPreviewData, previewImage: previewImage, error: nil, dispatchWorkItemToCancel: timeoutWorkItem, completion: completion)
                            }
                        }
                    } else {
                        if let completion = completion {
                            DDLogInfo("LinkPreviewMetadataProvider/startFetchingMetadata/ finished fetcing metadata, no image")
                            handleCompletion(linkPreviewData: linkPreviewData, previewImage: nil, error: nil, dispatchWorkItemToCancel: timeoutWorkItem, completion: completion)
                        }
                    }
                } catch Exception.Error(_, let message) {
                    DDLogError("LinkPreviewMetadataProvider/startFetchingMetadata/error parsing html \(message)")
                    handleCompletion(linkPreviewData: nil, previewImage: nil, error: PreviewFetchError.htmlParsingError, dispatchWorkItemToCancel: timeoutWorkItem, completion: completion)
                } catch {
                    DDLogError("LinkPreviewMetadataProvider/startFetchingMetadata/error")
                    handleCompletion(linkPreviewData: nil, previewImage: nil, error: PreviewFetchError.previewError, dispatchWorkItemToCancel: timeoutWorkItem, completion: completion)
                }
            }
            task.resume()
        }
        DispatchQueue.main.async(execute: previewFetchWorkItem)
        // timeout if we are not able to fetch link preview in 10 seconds
        timeoutWorkItem = DispatchWorkItem {
            DDLogInfo("LinkPreviewMetadataProvider/startFetchingMetadata/ error timeout")
            handleCompletion(linkPreviewData: nil, previewImage: nil, error: PreviewFetchError.timeout, dispatchWorkItemToCancel: previewFetchWorkItem, completion: completion)
        }
        if let timeoutWorkItem = timeoutWorkItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeoutWorkItem)
        }
    }

    private static func handleCompletion(linkPreviewData: LinkPreviewData?, previewImage: UIImage?, error: PreviewFetchError?, dispatchWorkItemToCancel: DispatchWorkItem?, completion: ((LinkPreviewData?, UIImage?, PreviewFetchError?) -> ())?) {
        dispatchWorkItemToCancel?.cancel()
        completion?(linkPreviewData, previewImage, error)
    }

    private static func downloadImage(imageUrl: String, completion: ((UIImage?) -> ())?) {
        DDLogInfo("LinkPreviewMetadataProvider/parseImageURL/fetching image")
        let imageUrl = URL(string: imageUrl)
        guard let imageUrl = imageUrl else {
            DDLogInfo("LinkPreviewMetadataProvider/parseImageURL/fetching image error/invalid url")
            if let completion = completion {
                completion(nil)
            }
            return
        }
        let task = URLSession.shared.dataTask(with: imageUrl) { (data, response, error) in
            guard let data = data, let image = UIImage(data: data) else {
                DDLogError("LinkPreviewMetadataProvider/parseImageURL/unable to fetch image")
                if let completion = completion {
                    completion(nil)
                }
                return
            }
            DDLogInfo("LinkPreviewMetadataProvider/downloadImage/success")
            if let completion = completion {
                completion(image)
            }
        }
        task.resume()
    }

    private static func parseTitle(document: Document) -> String? {
        do {
            if let title = parseContent(element: try document.select("meta[property=og:title]").first()), !title.isEmpty {
                return title
            }

            if let title = parseContent(element: try document.select("meta[name=twitter:title]").first()), !title.isEmpty {
                return title
            }

            if let title = parseContent(element: try document.select("meta[itemprop=name]").first()), !title.isEmpty {
                return title
            }
            return try document.title()
        } catch {
            DDLogError("LinkPreviewMetadataProvider/parseTitle/error")
        }
        return nil
    }

    private static func parseDescription(document: Document) -> String? {
        do {
            if let description = parseContent(element: try document.select("meta[property=og:description]").first()), !description.isEmpty {
                return description
            }
            if let description = parseContent(element: try document.select("meta[name=twitter:description]").first()), !description.isEmpty {
                return description
            }
            if let description = parseContent(element: try document.select("meta[itemprop=description]").first()), !description.isEmpty {
                return description
            }
        } catch {
            DDLogError("LinkPreviewMetadataProvider/parseDescription/error")
        }
        return nil
    }

    private static func parseContent(element: Element?) -> String? {
        return try? element?.attr("content")
    }
    
    private static func parseImageURL(document: Document) -> String? {
        do {
            if let imageUrl = parseUrl(element: try document.select("meta[property=og:image]").first(), key: "content"), !imageUrl.isEmpty {
                return imageUrl
            }
            if let imageUrl = parseUrl(element: try document.select("link[rel=image_src]").first(), key: "href"), !imageUrl.isEmpty {
                return imageUrl
            }
            if let imageUrl = parseUrl(element: try document.select("link[rel=apple-touch-icon]").first(), key: "href"), !imageUrl.isEmpty {
                return imageUrl
            }
            if let imageUrl = parseUrl(element: try document.select("link[rel=icon]").first(), key: "href"), !imageUrl.isEmpty {
                return imageUrl
            }
            if let imageUrl = parseUrl(element: try document.select("link[rel=shortcut icon]").first(), key: "href"), !imageUrl.isEmpty {
                return imageUrl
            }
        } catch {
            DDLogError("LinkPreviewMetadataProvider/parseImageURL/error")
        }
        return nil
    }

    private static func parseUrl(element: Element?, key: String) -> String? {
        guard let attribute = try? element?.attr(key) else {
            return nil
        }
        if !attribute.isEmpty {
            return try? element?.absUrl(key)
        }
        return nil
    }
}
