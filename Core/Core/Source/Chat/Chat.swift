//
//  Chat.swift
//  Core
//
//  Created by Igor Solomennikov on 8/18/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CoreCommon
import CocoaLumberjackSwift
import UIKit
import CoreLocation
import Contacts

public typealias ChatType = ThreadType

public enum ChatState: String {
    case available = "available"
    case typing = "typing"
}

public struct MediaCounters {
    var numImages: Int32 = 0
    var numVideos: Int32 = 0
    var numAudio: Int32 = 0
    var numFiles: Int32 = 0

    mutating func count(_ mediaType: CommonMediaType) {
        switch mediaType {
        case .image: numImages += 1
        case .video: numVideos += 1
        case .audio: numAudio += 1
        case .document: numFiles += 1
        }
    }
}

extension MediaCounters {
    static func +=(lhs: inout MediaCounters, rhs: MediaCounters) {
        lhs.numImages += rhs.numImages
        lhs.numVideos += rhs.numVideos
        lhs.numAudio += rhs.numAudio
        lhs.numFiles += rhs.numFiles
    }
}

public enum IncomingChatMessage {
    case notDecrypted(ChatMessageTombstone)
    case decrypted(ChatMessageProtocol)
}

public enum ChatMessageRecipient {
    case oneToOneChat(toUserId: UserID, fromUserId: UserID)
    case groupChat(toGroupId: GroupID, fromUserId: UserID)

    public var toUserId: String? {
        switch self {
        case .oneToOneChat(let toUserId, _):
            return toUserId
        default:
            return nil
        }
    }

    public var toGroupId: String? {
        switch self {
        case .groupChat(let groupId, _):
            return groupId
        default:
            return nil
        }
    }

    public var fromUserId: String {
        switch self {
        case .oneToOneChat(_, let fromUserId):
            return fromUserId
        case .groupChat(_, let fromUserId):
            return fromUserId
        }
    }

    public var chatType: ChatType {
        switch self {
        case .oneToOneChat(_, _):
            return .oneToOne
        case .groupChat(_, _):
            return .groupChat
        }
    }

    public var recipientId: String? {
        // 1:1 message
        if let toUserId = toUserId {
            // incoming chats recipientId = fromUserId
            // outgoing chats recipientId = toUserId
            let threadId = (toUserId == AppContext.shared.userData.userId) ? fromUserId : toUserId
            return threadId
        }
        // group message
        return toGroupId
    }
}

public protocol ChatMessageProtocol {
    var id: String { get }
    var fromUserId: UserID { get }
    var chatMessageRecipient: ChatMessageRecipient { get }

    /// 1 and higher means it's an offline message and that server has sent out a push notification already
    var retryCount: Int32? { get }

    /// 0 when the message is first sent, incrementing each time the message is rerequested
    var rerequestCount: Int32 { get }

    var content: ChatContent { get }
    var context: ChatContext { get }

    var timeIntervalSince1970: TimeInterval? { get }

    var orderedMedia: [ChatMediaProtocol] { get }
    var linkPreviewData: [LinkPreviewProtocol] { get }
}

public enum ChatContent {
    case text(String, [LinkPreviewProtocol])
    case album(String?, [ChatMediaProtocol])
    case reaction(String)
    case voiceNote(ChatMediaProtocol)
    case location(any ChatLocationProtocol)
    case files([ChatMediaProtocol])
    case unsupported(Data)
}

public struct ChatContext {
    public init(feedPostID: String? = nil, feedPostMediaIndex: Int32 = 0, chatReplyMessageID: String? = nil, chatReplyMessageMediaIndex: Int32 = 0, chatReplyMessageSenderID: String? = nil, forwardCount: Int32 = 0) {
        self.feedPostID = feedPostID
        self.feedPostMediaIndex = feedPostMediaIndex
        self.chatReplyMessageID = chatReplyMessageID
        self.chatReplyMessageMediaIndex = chatReplyMessageMediaIndex
        self.chatReplyMessageSenderID = chatReplyMessageSenderID
        self.forwardCount = forwardCount
    }

    public var feedPostID: String? = nil
    public var feedPostMediaIndex: Int32 = 0
    public var chatReplyMessageID: String? = nil
    public var chatReplyMessageMediaIndex: Int32 = 0
    public var chatReplyMessageSenderID: String? = nil
    public var forwardCount: Int32 = 0
}

public extension ChatContext {
    var clientContext: Clients_ChatContext {
        var context = Clients_ChatContext()
        if let feedPostID = feedPostID {
            context.feedPostID = feedPostID
            context.feedPostMediaIndex = feedPostMediaIndex
        }
        if let chatReplyMessageID = chatReplyMessageID, let chatReplyMessageSenderID = chatReplyMessageSenderID {
            context.chatReplyMessageID = chatReplyMessageID
            context.chatReplyMessageMediaIndex = chatReplyMessageMediaIndex
            context.chatReplyMessageSenderID = chatReplyMessageSenderID
        }
        context.forwardCount = UInt32(forwardCount)
        return context
    }
}

public extension ChatMessageProtocol {
    var protoContainer: Clients_Container? {
        get {
            var ready = false
            var protoContainer = Clients_Container()

            if let clientChatContainer = clientChatContainer {
                protoContainer.chatContainer = clientChatContainer
                ready = true
            }

            return ready ? protoContainer : nil
        }
    }

    var clientChatContainer: Clients_ChatContainer? {
        var container = Clients_ChatContainer()
        container.context = context.clientContext
        switch content {
        case .album(let text, let media):
            var album = Clients_Album()
            album.media = media.compactMap { $0.albumMedia }
            album.text = Clients_Text(text: text ?? "")
            container.message = .album(album)
        case .text(let text, let linkPreviewData):
            var clientsText = Clients_Text(text: text)
            linkPreviewData.forEach { linkPreview in
                clientsText.link.url = linkPreview.url.description
                clientsText.link.title = linkPreview.title
                clientsText.link.description_p = linkPreview.description

                linkPreview.previewImages.forEach { previewImage in
                    if let downloadURL = previewImage.url?.absoluteString,
                          let encryptionKey = Data(base64Encoded: previewImage.key),
                          let cipherTextHash = Data(base64Encoded: previewImage.sha256)
                    {
                        var res = Clients_EncryptedResource()
                        res.ciphertextHash = cipherTextHash
                        res.downloadURL = downloadURL
                        res.encryptionKey = encryptionKey
                        var img = Clients_Image()
                        img.img = res
                        img.width = Int32(previewImage.size.width)
                        img.height = Int32(previewImage.size.height)
                        clientsText.link.preview = [img]
                    }
                }
            }
            container.message = .text(clientsText)
        case .reaction(let emoji):
            var reaction = Clients_Reaction()
            reaction.emoji = emoji
            container.reaction = reaction
        case .voiceNote(let media):
            guard let protoResource = media.protoResource else { return nil }
            var vn = Clients_VoiceNote()
            vn.audio = protoResource
            container.message = .voiceNote(vn)
        case .location(let location):
            container.message = .location(location.protoMessage)
        case .files(let files):
            var protoFiles = Clients_Files()
            protoFiles.files = files.compactMap {
                guard let protoResource = $0.protoResource else { return nil }
                var protoFile = Clients_File()
                protoFile.data = protoResource
                if let name = $0.name {
                    protoFile.filename = name
                }
                return protoFile
            }
            container.message = .files(protoFiles)
        case .unsupported(_):
            return nil
        }
        return container
    }

    var mediaCounters: MediaCounters {
        switch content {
        case .album(_, let media):
            var counters = MediaCounters()
            media.forEach { mediaItem in
                counters.count(mediaItem.mediaType)
            }
            return counters
        case .voiceNote(_):
            return MediaCounters(numImages: 0, numVideos: 0, numAudio: 1, numFiles: 0)
        case .files(let files):
            return MediaCounters(numImages: 0, numVideos: 0, numAudio: 0, numFiles: Int32(files.count))
        case .text, .reaction, .location, .unsupported:
            return MediaCounters()
        }
    }

    var serverMediaCounters: Server_MediaCounters {
        var counters = Server_MediaCounters()
        let mediaCounters = mediaCounters
        counters.numImages = mediaCounters.numImages
        counters.numVideos = mediaCounters.numVideos
        counters.numAudio = mediaCounters.numAudio
        // TODO-DOC add files to server media counters
        return counters
    }
}

public protocol ChatMediaProtocol {
    var url: URL? { get }
    var mediaType: CommonMediaType { get }
    var size: CGSize { get }
    var key: String { get }
    var sha256: String { get }
    var blobVersion: BlobVersion { get }
    var chunkSize: Int32 { get }
    var blobSize: Int64 { get }
    var name: String? { get }
}

public extension ChatMediaProtocol {
    var protoMessage: Clients_Media? {
        get {
            guard let url = url else {
                DDLogError("ChatMediaProtocol/protoMessage/error missing url!")
                return nil
            }
            guard let encryptionKey = Data(base64Encoded: key) else {
                DDLogError("ChatMediaProtocol/protoMessage/error encryption key")
                return nil
            }
            guard let ciphertextHash = Data(base64Encoded: sha256) else {
                DDLogError("ChatMediaProtocol/protoMessage/error ciphertext hash")
                return nil
            }

            var media = Clients_Media()
            media.type = Clients_MediaType(commonMediaType: mediaType)
            media.width = Int32(size.width)
            media.height = Int32(size.height)
            media.encryptionKey = encryptionKey
            media.ciphertextHash = ciphertextHash
            media.downloadURL = url.absoluteString
            media.blobVersion = blobVersion.protoBlobVersion
            media.chunkSize = chunkSize
            media.blobSize = blobSize
            return media
        }
    }

    var protoResource: Clients_EncryptedResource? {
        get {
            guard let url = url else {
                DDLogError("ChatMediaProtocol/protoResource/error missing url")
                return nil
            }
            guard let encryptionKey = Data(base64Encoded: key) else {
                DDLogError("ChatMediaProtocol/protoResource/error encryption key")
                return nil
            }
            guard let ciphertextHash = Data(base64Encoded: sha256) else {
                DDLogError("ChatMediaProtocol/protoResource/error ciphertext hash")
                return nil
            }

            var resource = Clients_EncryptedResource()
            resource.encryptionKey = encryptionKey
            resource.ciphertextHash = ciphertextHash
            resource.downloadURL = url.absoluteString

            return resource
        }
    }

    var albumMedia: Clients_AlbumMedia? {
        guard let downloadURL = url?.absoluteString,
              let encryptionKey = Data(base64Encoded: key),
              let cipherTextHash = Data(base64Encoded: sha256) else
        {
            return nil
        }
        var albumMedia = Clients_AlbumMedia()
        var res = Clients_EncryptedResource()
        res.ciphertextHash = cipherTextHash
        res.downloadURL = downloadURL
        res.encryptionKey = encryptionKey
        switch mediaType {
        case .image:
            var img = Clients_Image()
            img.img = res
            img.width = Int32(size.width)
            img.height = Int32(size.height)
            albumMedia.media = .image(img)
        case .video:
            var vid = Clients_Video()
            vid.video = res
            vid.width = Int32(size.width)
            vid.height = Int32(size.height)
            var streamingInfo = Clients_StreamingInfo()
            streamingInfo.blobVersion = blobVersion.protoBlobVersion
            streamingInfo.chunkSize = chunkSize
            streamingInfo.blobSize = blobSize
            vid.streamingInfo = streamingInfo
            albumMedia.media = .video(vid)
        case .audio, .document:
            return nil
        }
        return albumMedia
    }
}

public struct ChatMessageTombstone {
    public init(id: String, chatMessageRecipient: ChatMessageRecipient, timestamp: Date) {
        self.id = id
        self.chatMessageRecipient = chatMessageRecipient
        self.timestamp = timestamp
    }

    public var id: String
    public var timestamp: Date
    public var chatMessageRecipient: ChatMessageRecipient
}

extension Clients_Text {
    init(text: String) {
        self.init()
        self.text = text
    }
}

extension Clients_MediaType {
    init(commonMediaType: CommonMediaType) {
        switch commonMediaType {
        case .image:
            self = .image
        case .video:
            self = .video
        case .audio:
            self = .audio
        case .document:
            DDLogWarn("ClientsMediaType/init/warn [document-type-not-available-in-schema]")
            self = .unspecified
        }
    }
}

extension Clients_ChatContainer {
    public init?(containerData: Data) {
        guard let protoContainer = try? Clients_Container(serializedData: containerData),
              protoContainer.hasChatContainer else
        {
            return nil
        }
        self = protoContainer.chatContainer
    }

    public var chatContext: ChatContext {
        return ChatContext(
            feedPostID: context.feedPostID.isEmpty ? nil : context.feedPostID,
            feedPostMediaIndex: context.feedPostMediaIndex,
            chatReplyMessageID: context.chatReplyMessageID.isEmpty ? nil : context.chatReplyMessageID,
            chatReplyMessageMediaIndex: context.chatReplyMessageMediaIndex,
            chatReplyMessageSenderID: context.chatReplyMessageSenderID.isEmpty ? nil : context.chatReplyMessageSenderID,
            forwardCount: Int32(context.forwardCount))
    }

    public var chatContent: ChatContent {
        switch message {
        case .text(let clientText):
            return .text(clientText.text, clientText.linkPreviewData)
        case .album(let album):
            return .album(
                album.text.text.isEmpty ? nil : album.text.text,
                album.media.compactMap {  XMPPChatMedia(albumMedia: $0) })
        case .reaction(let reaction):
            return .reaction(reaction.emoji)
        case .location(let location):
            return .location(ChatLocation(location))
        case .voiceNote(let voiceNote):
            guard let media = XMPPChatMedia(audio: voiceNote.audio) else
            {
                let data = try? serializedData()
                return .unsupported(data ?? Data())
            }
            return .voiceNote(media)
        case .files(let files):
            guard let file = files.files.first,
                  files.files.count == 1,
                  let media = XMPPChatMedia(file: file) else
            {
                let data = try? serializedData()
                return .unsupported(data ?? Data())
            }
            return .files([media])
        case .contactCard, .none:
            let data = try? serializedData()
            return .unsupported(data ?? Data())
        }
    }
}

public struct XMPPChatMedia {
    public var url: URL?
    public var type: CommonMediaType
    public var size: CGSize
    public var key: String
    public var sha256: String
    public var blobVersion: BlobVersion
    public var chunkSize: Int32
    public var blobSize: Int64
    public var name: String?

    public init(name: String? = nil, url: URL? = nil, type: CommonMediaType, size: CGSize, key: String, sha256: String, blobVersion: BlobVersion, chunkSize: Int32, blobSize: Int64) {
        self.url = url
        self.type = type
        self.size = size
        self.key = key
        self.sha256 = sha256
        self.blobVersion = blobVersion
        self.chunkSize = chunkSize
        self.blobSize = blobSize
        self.name = name
    }

    public init?(protoMedia: Clients_Media) {
        guard let type = CommonMediaType(clientsMediaType: protoMedia.type) else { return nil }
        guard let url = URL(string: protoMedia.downloadURL) else { return nil }
        let width = CGFloat(protoMedia.width)
        let height = CGFloat(protoMedia.height)
        guard (width > 0 && height > 0) || type == .audio  else { return nil }

        self.url = url
        self.type = type
        self.size = CGSize(width: width, height: height)
        self.key = protoMedia.encryptionKey.base64EncodedString()
        self.sha256 = protoMedia.ciphertextHash.base64EncodedString()
        self.blobVersion = BlobVersion.init(fromProto: protoMedia.blobVersion)
        self.chunkSize = protoMedia.chunkSize
        self.blobSize = protoMedia.blobSize
    }

    public init?(albumMedia: Clients_AlbumMedia) {
        guard let media = albumMedia.media else { return nil }

        switch media {
        case .image(let image):
            guard let downloadURL = URL(string: image.img.downloadURL) else { return nil }
            let width = CGFloat(image.width), height = CGFloat(image.height)
            guard width > 0 && height > 0 else { return nil }

            type = .image
            url = downloadURL
            size = CGSize(width: width, height: height)
            key = image.img.encryptionKey.base64EncodedString()
            sha256 = image.img.ciphertextHash.base64EncodedString()
            blobVersion = .default
            chunkSize = 0
            blobSize = 0
        case .video(let video):
            guard let downloadURL = URL(string: video.video.downloadURL) else { return nil }
            let width = CGFloat(video.width), height = CGFloat(video.height)
            guard width > 0 && height > 0 else { return nil }

            type = .video
            url = downloadURL
            size = CGSize(width: width, height: height)
            key = video.video.encryptionKey.base64EncodedString()
            sha256 = video.video.ciphertextHash.base64EncodedString()
            blobVersion = BlobVersion.init(fromProto: video.streamingInfo.blobVersion)
            self.chunkSize = video.streamingInfo.chunkSize
            self.blobSize = video.streamingInfo.blobSize
        }
    }

    public init?(audio: Clients_EncryptedResource) {
        guard let downloadURL = URL(string: audio.downloadURL) else { return nil }

        type = .audio
        url = downloadURL
        size = .zero
        key = audio.encryptionKey.base64EncodedString()
        sha256 = audio.ciphertextHash.base64EncodedString()
        blobVersion = .default
        chunkSize = 0
        blobSize = 0
    }

    public init?(file: Clients_File) {
        guard let downloadURL = URL(string: file.data.downloadURL) else { return nil }

        type = .document
        url = downloadURL
        size = .zero
        key = file.data.encryptionKey.base64EncodedString()
        sha256 = file.data.ciphertextHash.base64EncodedString()
        blobVersion = .default
        chunkSize = 0
        blobSize = 0
        name = file.filename
    }
}

extension XMPPChatMedia: ChatMediaProtocol {
    public var mediaType: CommonMediaType {
        type
    }
}

public extension CommonMediaType {
    init?(clientsMediaType: Clients_MediaType) {
        switch clientsMediaType {
        case .image:
            self = .image
        case .video:
            self = .video
        case .audio:
            self = .audio
        case .unspecified, .UNRECOGNIZED:
            return nil
        }
    }
}

public protocol ChatLocationProtocol {
    var latitude: Double { get }
    var longitude: Double { get }
    var name: String { get }
    var formattedAddressLines: [String] { get }
}

public struct ChatLocation: ChatLocationProtocol {
    public let latitude: Double
    public let longitude: Double
    public let name: String
    public let formattedAddressLines: [String]
    
    public init(_ protoMessage: Clients_Location) {
        latitude = protoMessage.latitude
        longitude = protoMessage.longitude
        name = protoMessage.name
        formattedAddressLines = protoMessage.address.formattedAddressLines
    }
    
    public init(_ commonLocation: CommonLocation) {
        latitude = commonLocation.latitude
        longitude = commonLocation.longitude
        name = commonLocation.name ?? ""
        formattedAddressLines = commonLocation.addressString?.split(separator: "\n").map(String.init) ?? []
    }
    
    public init(placemark: CLPlacemark) {
        latitude = placemark.location?.coordinate.latitude ?? 0
        longitude = placemark.location?.coordinate.longitude ?? 0
        name = placemark.name ?? ""
        formattedAddressLines = placemark.postalAddress
            .map { CNPostalAddressFormatter.string(from: $0, style: .mailingAddress) }
            .map { $0.split(separator: "\n").map(String.init) } ?? []
    }
    
    public init(latitude: Double, longitude: Double, name: String, formattedAddressLines: [String]) {
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
        self.formattedAddressLines = formattedAddressLines
    }
}

extension ChatLocationProtocol {
    var protoMessage: Clients_Location {
        .with {
            $0.latitude = latitude
            $0.longitude = longitude
            $0.name = name
            $0.address.formattedAddressLines = formattedAddressLines
        }
    }
}
