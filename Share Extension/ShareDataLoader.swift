//
//  ShareDataLoader.swift
//  Share Extension
//
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import AVFoundation
import CocoaLumberjackSwift
import Combine
import Core
import Foundation

class ShareDataLoader {
    static let shared = ShareDataLoader()

    private enum AttachmentType: String {
        case image = "public.image"
        case propertyList = "com.apple.property-list"
        case text = "public.plain-text"
        case url = "public.url"
        case video = "public.movie"
    }

    private var cancellableSet: Set<AnyCancellable> = []

    var ready = CurrentValueSubject<Bool, Never>(false)
    var media: [PendingMedia] = []
    var text: String = ""

    private init() {}

    public func load(from context: NSExtensionContext?) {
        guard let items = context?.inputItems else { return }

        media = []
        text = ""

        let loadingGroup = DispatchGroup()

        for item in items {
            guard let item = item as? NSExtensionItem else { continue }
            guard let attachments = item.attachments else { continue }

            for (order, provider) in attachments.enumerated() {
                loadingGroup.enter()

                if provider.hasItemConformingToTypeIdentifier(AttachmentType.image.rawValue) {
                    load(image: provider, order: order) {
                        if let error = $0 {
                            DDLogError("ShareComposerViewController/load/image/error [\(error)]")
                        }
                        loadingGroup.leave()
                    }
                } else if provider.hasItemConformingToTypeIdentifier(AttachmentType.video.rawValue) {
                    load(video: provider, order: order) {
                        if let error = $0 {
                            DDLogError("ShareComposerViewController/load/video/error [\(error)]")
                        }
                        loadingGroup.leave()
                    }
                } else if provider.hasItemConformingToTypeIdentifier(AttachmentType.text.rawValue) {
                    load(text: provider) {
                        if let error = $0 {
                            DDLogError("ShareComposerViewController/load/text/error [\(error)]")
                        }
                        loadingGroup.leave()
                    }
                } else if provider.hasItemConformingToTypeIdentifier(AttachmentType.url.rawValue) {
                    load(url: provider, order: order) {
                        if let error = $0 {
                            DDLogError("ShareComposerViewController/load/url/error [\(error)]")
                        }
                        loadingGroup.leave()
                    }
                } else if provider.hasItemConformingToTypeIdentifier(AttachmentType.propertyList.rawValue) {
                    load(webpage: provider) {
                        if let error = $0 {
                            DDLogError("ShareComposerViewController/load/webpage/error [\(error)]")
                        }
                        loadingGroup.leave()
                    }
                } else {
                    DDLogWarn("ShareComposerViewController/load/error unknown attachment")
                    loadingGroup.leave()
                }
            }
        }

        loadingGroup.notify(queue: DispatchQueue.main) {
            self.ready.send(true)
        }
    }

    private func load(image provider: NSItemProvider, order: Int, completion: @escaping (Error?) -> ()) {
        provider.loadItem(forTypeIdentifier: AttachmentType.image.rawValue, options: nil) { [weak self] (item, error) in
            guard let self = self else { return }
            guard error == nil else {
                return completion(error)
            }

            var image: UIImage?
            switch item {
            case let tmp as UIImage:
                image = tmp
            case let data as Data:
                image = UIImage(data: data)
            case let url as URL:
                guard let data = try? Data(contentsOf: url) else { break }
                image = UIImage(data: data)
            default:
                break
            }

            guard image != nil else {
                return completion(ShareError.invalidData)
            }

            let mediaItem = PendingMedia(type: .image)
            self.cancellableSet.insert(
                mediaItem.ready.sink { [weak self] ready in
                    guard let self = self else { return }
                    guard ready else { return }

                    self.media.append(mediaItem)
                    completion(nil)
                }
            )

            mediaItem.order = order
            mediaItem.image = image
        }
    }

    private func load(video provider: NSItemProvider, order: Int, completion: @escaping (Error?) -> ()) {
        provider.loadItem(forTypeIdentifier: AttachmentType.video.rawValue, options: nil) { [weak self] (item, error) in
            guard let self = self else { return }
            guard error == nil else {
                return completion(error)
            }
            guard let url = item as? URL else {
                return completion(ShareError.invalidData)
            }

            let mediaItem = PendingMedia(type: .video)
            self.cancellableSet.insert(
                mediaItem.ready.sink { [weak self] ready in
                    guard let self = self else { return }
                    guard ready else { return }

                    self.media.append(mediaItem)
                    completion(nil)
                }
            )

            mediaItem.order = order
            mediaItem.originalVideoURL = url
            mediaItem.fileURL = url
        }
    }

    private func load(text provider: NSItemProvider, completion: @escaping (Error?) -> ()) {
        provider.loadItem(forTypeIdentifier: AttachmentType.text.rawValue, options: nil) { [weak self] (item, error) in
            guard let self = self else { return }
            guard error == nil else {
                return completion(error)
            }
            guard let text = item as? String else {
                return completion(ShareError.invalidData)
            }

            self.text = self.text + (self.text.isEmpty ? "" : "\n") + text.trimmingCharacters(in: .whitespacesAndNewlines)

            completion(nil)
        }
    }

    private func load(webpage provider: NSItemProvider, completion: @escaping (Error?) -> ()) {
        provider.loadItem(forTypeIdentifier: AttachmentType.propertyList.rawValue, options: nil) { [weak self] (item, error) in
            guard let self = self else { return }
            guard error == nil else {
                return completion(error)
            }
            guard let dictionary = item as? NSDictionary,
                let results = dictionary[NSExtensionJavaScriptPreprocessingResultsKey] as? NSDictionary,
                let title = results["title"] as? String,
                let url = results["url"] as? String else {
                    return completion(ShareError.invalidData)
            }

            self.text = self.text + (self.text.isEmpty ? "" : "\n") + "\(title)\n\(url)"

            completion(nil)
        }
    }

    private func load(url provider: NSItemProvider, order: Int, completion: @escaping (Error?) -> ()) {
        provider.loadItem(forTypeIdentifier: AttachmentType.url.rawValue, options: nil) { [weak self] (url, error) in
            guard let self = self else { return }
            guard error == nil else {
                return completion(error)
            }
            guard let url = url as? URL else {
                return completion(ShareError.invalidData)
            }

            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                let mediaItem = PendingMedia(type: .image)
                self.cancellableSet.insert(
                    mediaItem.ready.sink { [weak self] ready in
                        guard let self = self else { return }
                        guard ready else { return }

                        self.media.append(mediaItem)
                        completion(nil)
                    }
                )

                mediaItem.order = order
                mediaItem.image = image
            } else if AVURLAsset(url: url).isPlayable {
                let mediaItem = PendingMedia(type: .video)
                self.cancellableSet.insert(
                    mediaItem.ready.sink { [weak self] ready in
                        guard let self = self else { return }
                        guard ready else { return }

                        self.media.append(mediaItem)
                        completion(nil)
                    }
                )

                mediaItem.order = order
                mediaItem.originalVideoURL = url
                mediaItem.fileURL = url
            } else {
                self.text = self.text + (self.text.isEmpty ? "" : "\n") + url.absoluteString
                completion(nil)
            }
        }
    }

}