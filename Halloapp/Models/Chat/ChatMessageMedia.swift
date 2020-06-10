//
//  HalloApp
//
//  Created by Tony Jiang on 4/28/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//


import CocoaLumberjack
import Combine
import Foundation
import Core

enum ChatMessageMediaType: Int {
    case image = 0
    case video = 1
}

class ChatMessageMedia: Identifiable, ObservableObject, Hashable {
    static let chatImageLoadingQueue = DispatchQueue(label: "com.halloapp.chat-media-loading", qos: .userInitiated)

    var id: String

    var chatMessageId: ChatMessageID
    var order: Int = 0
    var type: ChatMessageMediaType
    var size: CGSize
    private var incomingStatus: ChatMedia.IncomingStatus
    private var outgoingStatus: ChatMedia.OutgoingStatus

    @Published var isMediaAvailable: Bool = false

    var image: UIImage?
    private var isImageLoaded: Bool = false

    /**
     Setting this for images will trigger loading of an image on a background queue.
     */
    var fileURL: URL? {
        didSet {
            switch type {
            case .image:
                guard self.image == nil else { return }
                // TODO: investigate if loading is only necessary for some objects.
                if (fileURL != nil) {
                    isImageLoaded = false
                    self.loadImage()
                } else {
                    isMediaAvailable = false
                }
            case .video:
                isMediaAvailable = fileURL != nil
            }
        }
    }

    var displayAspectRatio: CGFloat {
        get {
            return max(self.size.width/self.size.height, 4/5)
        }
    }

    func loadImage() {
        guard !self.isImageLoaded else {
            return
        }
        guard self.type == .image else { return }
        guard let path = self.fileURL?.path else {
            return
        }

        DDLogDebug("ChatMessageMedia/image/load [\(path)]")
        ChatMessageMedia.chatImageLoadingQueue.async {
            let image = UIImage(contentsOfFile: path)
            DispatchQueue.main.async {
                self.image = image
                self.isImageLoaded = true
                self.isMediaAvailable = true
            }
        }
    }

    // ChatMedia is from Core Data
    init(_ chatMedia: ChatMedia) {
        chatMessageId = chatMedia.message.id
        order = Int(chatMedia.order)
        type = chatMedia.type
        size = chatMedia.size
        if let relativePath = chatMedia.relativeFilePath {
            fileURL = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(relativePath, isDirectory: false)
        }
        if type == .video {
            isMediaAvailable = fileURL != nil
        }
        id = "\(chatMessageId)-\(order)"
        incomingStatus = chatMedia.incomingStatus
        outgoingStatus = chatMedia.outgoingStatus
    }

    func reload(from chatMedia: ChatMedia) {
        assert(chatMedia.order == self.order)
        assert(chatMedia.message.id == self.chatMessageId)
        assert(chatMedia.type == self.type)
        assert(chatMedia.size == self.size)
        guard chatMedia.incomingStatus != self.incomingStatus else { return }
        guard chatMedia.outgoingStatus != self.outgoingStatus else { return }
        // Media was downloaded
        if self.fileURL == nil && chatMedia.relativeFilePath != nil {
            self.fileURL = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(chatMedia.relativeFilePath!, isDirectory: false)
        }

        // TODO: other kinds of updates possible?

        self.incomingStatus = chatMedia.incomingStatus
        self.outgoingStatus = chatMedia.outgoingStatus
    }

    init(_ media: PendingChatMessageMedia, chatMessageId: String) {
        self.id = "\(chatMessageId)-\(media.order)"
        self.incomingStatus = .none
        self.outgoingStatus = .none
        self.chatMessageId = chatMessageId
        self.order = media.order
        self.type = media.type
        self.image = media.image
        self.size = media.size!
        self.fileURL = media.fileURL ?? media.videoURL
        self.isMediaAvailable = true
    }
    
    static func == (lhs: ChatMessageMedia, rhs: ChatMessageMedia) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(self.id)
    }
}


class PendingChatMessageMedia {
    var order: Int = 0
    var type: ChatMessageMediaType
    var url: URL?
    var size: CGSize?
    var key: String?
    var sha256: String?
    var image: UIImage?
    var videoURL: URL?
    var fileURL: URL?

    init(type: ChatMessageMediaType) {
        self.type = type
    }
}

