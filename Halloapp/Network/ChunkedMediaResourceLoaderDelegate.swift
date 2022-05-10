//
//  ChunkedMediaResourceLoaderDelegate.swift
//  Core
//
//  Created by Vasil Lyutskanov on 28.02.22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//


import Alamofire
import AVFoundation
import CocoaLumberjackSwift
import Core
import Foundation

public class ChunkedMediaInfo {
    public let feedPostID: FeedPostID
    public let order: Int16
    public let remoteURL: URL?
    public let key: String
    public let blobVersion: BlobVersion
    public let chunkSize: Int32
    public let blobSize: Int64

    public init(feedPostID: FeedPostID, order: Int16, remoteURL: URL?, key: String, blobVersion: BlobVersion, chunkSize: Int32, blobSize: Int64) {
        self.feedPostID = feedPostID
        self.order = order
        self.remoteURL = remoteURL
        self.key = key
        self.blobVersion = blobVersion
        self.chunkSize = chunkSize
        self.blobSize = blobSize
    }

    convenience public init?(commonMedia: CommonMedia) {
        guard let feedPost = commonMedia.post, commonMedia.blobVersion == .chunked, commonMedia.status == .downloadedPartial else {
            return nil
        }
        self.init(feedPostID: feedPost.id,
                  order: commonMedia.order,
                  remoteURL: commonMedia.url,
                  key: commonMedia.key,
                  blobVersion: commonMedia.blobVersion,
                  chunkSize: commonMedia.chunkSize,
                  blobSize: commonMedia.blobSize)
    }
}

protocol RemoteChunkedMediaSessionDelegate: AnyObject {
    func chunkAvailable(index: Int32)
    func chunkError(_ error: Error)
}

public class ChunkedMediaResourceLoaderDelegate: NSObject {
    public static let resourceLoadingingQueue = DispatchQueue(label: "com.halloapp.resource-loading", qos: .userInitiated)
    public static let resourceStreamingQueue = DispatchQueue(label: "com.halloapp.resource-streaming", qos: .userInitiated)
    public static let resourceCachingQueue = DispatchQueue(label: "com.halloapp.resource-caching", qos: .userInitiated)

    public static let HTTPS_SCHEME = "https"
    public static let PLACEHOLDER_SCHEME = "halloapp-streaming"

    enum Error: Swift.Error {
        case invalidBlobVersion
        case missingRemoteURL
        case invalidMediaKey
        case zeroSizeChunkRead
        case invalidActiveRequest
    }

    public static func remoteURLToPlaceholderURL(from remoteURL: URL) -> URL? {
        guard remoteURL.scheme == ChunkedMediaResourceLoaderDelegate.HTTPS_SCHEME else { return nil }
        let urlComponents = NSURLComponents(url: remoteURL, resolvingAgainstBaseURL: true)
        urlComponents?.scheme = ChunkedMediaResourceLoaderDelegate.PLACEHOLDER_SCHEME
        return urlComponents?.url
    }

    public static func placeholderURLToRemoteURL(from placeholderURL: URL) -> URL? {
        guard placeholderURL.scheme == ChunkedMediaResourceLoaderDelegate.PLACEHOLDER_SCHEME else { return nil }
        let urlComponents = NSURLComponents(url: placeholderURL, resolvingAgainstBaseURL: true)
        urlComponents?.scheme = ChunkedMediaResourceLoaderDelegate.HTTPS_SCHEME
        return urlComponents?.url
    }

    private let feedPostID: FeedPostID
    private let mediaOrder: Int16
    private let mediaKey: Data
    private let chunkedParameters: ChunkedMediaParameters
    private let fileURL: URL
    private let remoteURL: URL
    private let cachedResource: ThreadSafeCachedChunkedMediaResource
    private var remoteResource: RemoteChunkedMediaResource?

    private var cachedChunkIndex: Int32 = -1
    private var chunkPtData: Data = Data()
    private var requestStack: [AVAssetResourceLoadingRequest] = []
    private var activeRequest: AVAssetResourceLoadingRequest? {
        requestStack.last(where: { request in request.dataRequest != nil && !request.isFinished && !request.isCancelled })
    }

    public convenience init(chunkedInfo: ChunkedMediaInfo, fileURL: URL) throws {
        guard chunkedInfo.blobVersion == .chunked else {
            DDLogError("ChunkedMediaResourceLoaderDelegate/init/error Blob version is not chunked")
            throw Error.invalidBlobVersion
        }
        guard let remoteURL = chunkedInfo.remoteURL else {
            DDLogError("ChunkedMediaResourceLoaderDelegate/init/error Missing remote url")
            throw Error.missingRemoteURL
        }
        guard let mediaKey = Data(base64Encoded: chunkedInfo.key) else {
            DDLogError("ChunkedMediaResourceLoaderDelegate/init/error Invalid media key")
            throw Error.invalidMediaKey
        }
        let chunkedParameters = try ChunkedMediaParameters(blobSize: chunkedInfo.blobSize, chunkSize: chunkedInfo.chunkSize)
        self.init(feedPostID: chunkedInfo.feedPostID, mediaOrder: chunkedInfo.order, mediaKey: mediaKey, chunkedParameters: chunkedParameters, fileURL: fileURL, remoteURL: remoteURL)
    }

    private init(feedPostID: FeedPostID, mediaOrder: Int16, mediaKey: Data, chunkedParameters: ChunkedMediaParameters, fileURL: URL, remoteURL: URL) {
        DDLogDebug("ChunkedMediaResourceLoaderDelegate/init")
        self.feedPostID = feedPostID
        self.mediaOrder = mediaOrder
        self.mediaKey = mediaKey
        self.chunkedParameters = chunkedParameters
        self.fileURL = fileURL
        self.remoteURL = remoteURL
        let cachedResource = CachedChunkedMediaResource(feedPostID: feedPostID, mediaOrder: mediaOrder, chunkedParameters: chunkedParameters, fileURL: fileURL)
        self.cachedResource = ThreadSafeCachedChunkedMediaResource(cachedMediaResource: cachedResource, resourceCachingQueue: ChunkedMediaResourceLoaderDelegate.resourceCachingQueue)
    }

    deinit {
        DDLogDebug("ChunkedMediaResourceLoaderDelegate/deinit")
        remoteResource?.stopTransfer()
        cachedResource.close()
    }

    private func filterRequests() {
        DDLogDebug("ChunkedMediaResourceLoaderDelegate/filterRequests")
        requestStack = requestStack.filter({ request in request.dataRequest != nil && !request.isFinished && !request.isCancelled })
    }

    private func handleContentInformationRequest(loadingRequest: AVAssetResourceLoadingRequest) {
        DDLogDebug("ChunkedMediaResourceLoaderDelegate/handleContentInformationRequest")
        loadingRequest.contentInformationRequest?.contentType = AVFileType.mp4.rawValue
        loadingRequest.contentInformationRequest?.contentLength = chunkedParameters.estimatedPtSize
        loadingRequest.contentInformationRequest?.isByteRangeAccessSupported = true
        loadingRequest.finishLoading()
    }

    private func getChunkPtData(at chunkIndex: Int32) throws -> Data? {
        DDLogDebug("ChunkedMediaResourceLoaderDelegate/getChunkPtData chunkIndex=[\(chunkIndex)]")
        if chunkIndex != cachedChunkIndex {
            if cachedResource.isChunkCached(at: chunkIndex) {
                chunkPtData = try cachedResource.readChunk(at: chunkIndex)
                cachedChunkIndex = chunkIndex
            } else {
                if remoteResource == nil {
                    remoteResource = RemoteChunkedMediaResource(remoteURL: remoteURL,
                                                                chunkedParameters: chunkedParameters,
                                                                mediaKey: mediaKey,
                                                                cachedMediaResource: cachedResource,
                                                                resourceStreamingQueue: ChunkedMediaResourceLoaderDelegate.resourceStreamingQueue,
                                                                delegate: self)
                }
                remoteResource?.requestChunk(at: chunkIndex)
                return nil
            }
        }
        return chunkPtData
    }

    private func processPendingDataRequests() {
        do {
            while let pendingRequest = activeRequest {
                guard let dataRequest = pendingRequest.dataRequest else {
                    DDLogError("ChunkedMediaResourceLoaderDelegate/processPendingDataRequests error Non data request at the top of the request stack")
                    pendingRequest.finishLoading(with: Error.invalidActiveRequest)
                    return
                }
                let toReadLength = dataRequest.requestedOffset + Int64(dataRequest.requestedLength) - dataRequest.currentOffset
                precondition(toReadLength > 0)
                DDLogDebug("ChunkedMediaResourceLoaderDelegate/processPendingDataRequests dataRequest=[\(dataRequest)] toReadLength=[\(toReadLength)]")

                let index: Int32
                let ptOffset = chunkedParameters.getChunkPtOffset(ptPosition: dataRequest.currentOffset)
                do {
                    index = try chunkedParameters.getChunkIndex(ptPosition: dataRequest.currentOffset)
                } catch {
                    DDLogError("ChunkedMediaResourceLoaderDelegate/processPendingDataRequests error \(error)")
                    pendingRequest.finishLoading(with: error)
                    return
                }
                guard let chunkPtData = try getChunkPtData(at: index) else {
                    DDLogDebug("ChunkedMediaResourceLoaderDelegate/processPendingDataRequests waiting for chunk [\(index)]")
                    return
                }
                precondition(chunkPtData.count > 0)

                var finished = false
                if chunkPtData.count > ptOffset {
                    let toCopySize = Int32(min(Int64(chunkPtData.count) - Int64(ptOffset), toReadLength))
                    dataRequest.respond(with: chunkPtData.subdata(in: Int(ptOffset)..<Int(ptOffset + toCopySize)))
                    finished = (dataRequest.requestedOffset + Int64(dataRequest.requestedLength) - dataRequest.currentOffset == 0)
                } else {
                    precondition(index + 1 == chunkedParameters.totalChunkCount)
                    // The last chunk size is only estimated and after decrypting the chunk size can be less or equal to ptOffset.
                    // To satisfy the dataRequest in this case, return zeroed bytes.
                    dataRequest.respond(with: Data(count: Int(toReadLength)))
                    finished = true
                }
                if finished {
                    DDLogDebug("ChunkedMediaResourceLoaderDelegate/processPendingDataRequests finish loading [\(index)]")
                    pendingRequest.finishLoading()
                    filterRequests()
                }
            }
        } catch {
            DDLogError("ChunkedMediaResourceLoaderDelegate/processPendingDataRequests error \(error)")
            handleError(error)
        }
    }

    private func handleError(_ error: Swift.Error) {
        DDLogError("ChunkedMediaResourceLoaderDelegate/handleError \(error)")
        self.remoteResource?.stopTransfer()
        guard let pendingRequest = self.activeRequest else {
            DDLogDebug("ChunkedMediaResourceLoaderDelegate/handleError no active requests")
            self.filterRequests()
            return
        }
        pendingRequest.finishLoading(with: error)
    }
}

extension ChunkedMediaResourceLoaderDelegate: AVAssetResourceLoaderDelegate {
    public func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        if loadingRequest.contentInformationRequest != nil {
            handleContentInformationRequest(loadingRequest: loadingRequest)
        } else if loadingRequest.dataRequest != nil {
            requestStack.append(loadingRequest)
            processPendingDataRequests()
        }
        return true
    }

    public func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        requestStack.removeAll(where: { request in request == loadingRequest })
        processPendingDataRequests()
    }
}

extension ChunkedMediaResourceLoaderDelegate: RemoteChunkedMediaSessionDelegate {
    func chunkAvailable(index: Int32) {
        ChunkedMediaResourceLoaderDelegate.resourceLoadingingQueue.async {
            DDLogDebug("ChunkedMediaResourceLoaderDelegate/chunkAvailable index=[\(index)]")

            guard let pendingRequest = self.activeRequest else {
                DDLogDebug("ChunkedMediaResourceLoaderDelegate/chunkAvailable no active requests")
                return
            }
            let requestChunkIndex: Int32
            do {
                guard let dataRequest = pendingRequest.dataRequest else {
                    throw Error.invalidActiveRequest
                }
                requestChunkIndex = try self.chunkedParameters.getChunkIndex(ptPosition: dataRequest.currentOffset)
            } catch {
                DDLogError("ChunkedMediaResourceLoaderDelegate/chunkAvailable error \(error)")
                pendingRequest.finishLoading(with: error)
                self.filterRequests()
                return
            }
            if requestChunkIndex == index {
                DDLogDebug("ChunkedMediaResourceLoaderDelegate/chunkAvailable resume")
                self.processPendingDataRequests()
            }
        }
    }

    func chunkError(_ error: Swift.Error) {
        ChunkedMediaResourceLoaderDelegate.resourceLoadingingQueue.async { self.handleError(error) }
    }
}

fileprivate class RemoteChunkedMediaResource {
    public static let MAX_CHUNK_COUNT_TO_WAIT_FOR = 10
    enum Error: Swift.Error {
        case chunkIndexOutOfBound
    }

    private let remoteURL: URL
    private let resourceStreamingQueue: DispatchQueue
    private let chunkedParameters: ChunkedMediaParameters
    private let decrypter: ChunkedMediaCrypter
    private let cachedMediaResource: ThreadSafeCachedChunkedMediaResource
    weak private var delegate: RemoteChunkedMediaSessionDelegate?

    private var currentIndex: Int32 = -1
    private var requestedIndex: Int32 = -1
    private var encryptedData = Data()

    private var streamRequest: DataStreamRequest?

    init(remoteURL: URL,
         chunkedParameters: ChunkedMediaParameters,
         mediaKey: Data,
         cachedMediaResource: ThreadSafeCachedChunkedMediaResource,
         resourceStreamingQueue: DispatchQueue,
         delegate: RemoteChunkedMediaSessionDelegate) {
        self.remoteURL = remoteURL
        self.chunkedParameters = chunkedParameters
        self.decrypter = ChunkedMediaCrypter(mediaType: .video, mediaKey: mediaKey)
        self.cachedMediaResource = cachedMediaResource
        self.resourceStreamingQueue = resourceStreamingQueue
        self.delegate = delegate
    }

    deinit {
        DDLogDebug("RemoteChunkedMediaResource/deinit")
        cancelRequest()
    }

    func requestChunk(at chunkIndex: Int32) {
        resourceStreamingQueue.async {
            DDLogDebug("RemoteChunkedMediaResource/requestChunk index=[\(chunkIndex)]")
            self.requestedIndex = chunkIndex
            if self.cachedMediaResource.isChunkCached(at: chunkIndex) {
                self.reportChunkAvailable(at: chunkIndex)
            } else if self.streamRequest == nil || self.currentIndex > chunkIndex || chunkIndex - self.currentIndex >= RemoteChunkedMediaResource.MAX_CHUNK_COUNT_TO_WAIT_FOR {
                self.changeRequestPosition(newIndex: chunkIndex)
            }
        }
    }

    func stopTransfer() {
        resourceStreamingQueue.async {
            DDLogDebug("RemoteChunkedMediaResource/stopTransfer")
            self.cancelRequest()
        }
    }

    private func makeRequest(initialIndex: Int32) {
        guard streamRequest == nil else { return }
        DDLogDebug("RemoteChunkedMediaResource/makeRequest index=[\(initialIndex)]")
        currentIndex = initialIndex
        encryptedData = Data()
        let rangeStart = currentIndex * chunkedParameters.chunkSize
        let headers: HTTPHeaders = rangeStart > 0 ? ["Range": "bytes=\(rangeStart)-"] : []
        streamRequest = AF.streamRequest(remoteURL, method: .get, headers: headers).responseStream(on: resourceStreamingQueue) { stream in
            switch stream.event {
            case let .stream(result):
                switch result {
                case let .success(data):
                    DDLogDebug("RemoteChunkedMediaResource/stream/result success")
                    self.handleData(data)
                case let .failure(error):
                    DDLogDebug("RemoteChunkedMediaResource/stream/result failure")
                    self.reportError(error)
                }
            case let.complete(completion):
                DDLogDebug("RemoteChunkedMediaResource/stream/complete")
                if let error = completion.error, error.asAFError?.isExplicitlyCancelledError != true {
                    DDLogError("RemoteChunkedMediaResource/stream/complete error \(error)")
                    self.reportError(error)
                } else {
                    self.handleData(Data())
                }
            }
        }
    }

    private func cancelRequest() {
        guard let streamRequest = streamRequest else { return }
        DDLogDebug("RemoteChunkedMediaResource/cancelRequest")
        streamRequest.cancel()
        self.streamRequest = nil
    }

    private func changeRequestPosition(newIndex: Int32) {
        DDLogDebug("RemoteChunkedMediaResource/changeRequestPosition currentIndex=[\(currentIndex)] newIndex=[\(newIndex)]")
        cancelRequest()
        if newIndex < chunkedParameters.totalChunkCount {
            resourceStreamingQueue.async {
                self.makeRequest(initialIndex: newIndex)
            }
        }
    }

    private func reportError(_ error: Swift.Error) {
        DDLogError("RemoteChunkedMediaResource/reportError \(error)")
        delegate?.chunkError(error)
    }

    private func reportChunkAvailable(at chunkIndex: Int32) {
        DDLogDebug("RemoteChunkedMediaResource/reportChunkAvailable requestedIndex=[\(requestedIndex)] availableIndex=[\(chunkIndex)]")
        guard requestedIndex == chunkIndex else {
            DDLogError("RemoteChunkedMediaResource/reportChunkAvailable missmatch requestedIndex=[\(requestedIndex)] availableIndex=[\(chunkIndex)]")
            return
        }
        requestedIndex = -1
        delegate?.chunkAvailable(index: chunkIndex)
    }

    private func handleData(_ data: Data) {
        DDLogDebug("RemoteChunkedMediaResource/handleData [\(data)]")
        guard delegate != nil else {
            cancelRequest()
            return
        }
        encryptedData.append(data)
        if encryptedData.count >= chunkedParameters.getChunkSize(chunkIndex: currentIndex) {
            processEncryptedData()
        }
    }

    private func processEncryptedData() {
        DDLogDebug("RemoteChunkedMediaResource/processEncryptedData")
        do {
            while encryptedData.count >= chunkedParameters.getChunkSize(chunkIndex: currentIndex) {
                let currentChunkSize = chunkedParameters.getChunkSize(chunkIndex: currentIndex)
                DDLogDebug("RemoteChunkedMediaResource/processEncryptedData encryptedChunkLength=[\(encryptedData.count)] currentChunkSize=[\(currentChunkSize)] chunkIndex=[\(currentIndex)]")
                let chunkIndexRange = 0..<(chunkedParameters.totalChunkCount)
                guard chunkIndexRange.contains(currentIndex) else {
                    throw Error.chunkIndexOutOfBound
                }

                let estimatedPtChunkSize = chunkedParameters.getChunkPtSize(chunkIndex: currentIndex)
                let plaintextChunk = try decrypter.decrypt(encryptedChunk: encryptedData.prefix(Int(currentChunkSize)), chunkIndex: Int(currentIndex), shouldUpdateHash: false)
                if (currentIndex < chunkedParameters.regularChunkCount && plaintextChunk.count != Int(estimatedPtChunkSize)) ||
                    (currentIndex == chunkedParameters.regularChunkCount && abs(plaintextChunk.count - Int(estimatedPtChunkSize)) >= ChunkedMediaParameters.BLOCK_SIZE) {
                    throw ChunkedMediaCrypter.Error.plaintextChunkSizeMismatch(estmated: Int(estimatedPtChunkSize), actual: plaintextChunk.count)
                }

                cachedMediaResource.writeChunkIfUncached(at: currentIndex, chunkData: plaintextChunk) { [weak self] availableIndex, nextUncachedIndex, writeError in
                    guard let self = self else { return }
                    self.resourceStreamingQueue.async {
                        if let error = writeError {
                            self.reportError(error)
                        } else {
                            DDLogDebug("RemoteChunkedMediaResource/processEncryptedData/writeCallback availableIndex=[\(availableIndex)] nextUncachedIndex[\(nextUncachedIndex)]")
                            self.reportChunkAvailable(at: availableIndex)
                            if nextUncachedIndex - self.currentIndex >= RemoteChunkedMediaResource.MAX_CHUNK_COUNT_TO_WAIT_FOR {
                                self.changeRequestPosition(newIndex: nextUncachedIndex)
                            }
                        }
                    }
                }
                encryptedData = encryptedData.dropFirst(Int(currentChunkSize))
                currentIndex += 1
            }
        } catch {
            DDLogError("RemoteChunkedMediaResource/processEncryptedData error chunkIndex=[\(currentIndex)] \(error)")
            reportError(error)
        }
    }
}

fileprivate class CachedChunkedMediaResource {
    private let fileURL: URL
    private let feedPostID: FeedPostID
    private let mediaOrder: Int16
    private let chunkedParameters: ChunkedMediaParameters
    private var fileHandle: FileHandle?
    private var chunkBitSet: BitSet
    private var isFullyCached = false

    public init(feedPostID: FeedPostID, mediaOrder: Int16, chunkedParameters: ChunkedMediaParameters, fileURL: URL) {
        self.feedPostID = feedPostID
        self.mediaOrder = mediaOrder
        self.chunkedParameters = chunkedParameters
        self.fileURL = fileURL

        if let post = MainAppContext.shared.feedData.feedPost(with: feedPostID),
           let media = post.media?.first(where: { $0.order == mediaOrder }),
           let chunkSetData = media.chunkSet {
            self.chunkBitSet = BitSet(from: chunkSetData, count: Int(chunkedParameters.totalChunkCount))
        } else {
            DDLogError("CachedChunkedMediaResource/init could not read chunk bitset data from the database")
            self.chunkBitSet = BitSet(count: Int(chunkedParameters.totalChunkCount))
        }
        DDLogDebug("CachedChunkedMediaResource/init chunkSetState=[\(chunkBitSet)]")
    }

    deinit {
        close()
    }

    private func getFileHandle() throws -> FileHandle {
        if fileHandle == nil {
            fileHandle = try FileHandle(forUpdating: fileURL)
        }
        return fileHandle!
    }

    private func checkFullyCached() {
        DDLogDebug("CachedChunkedMediaResource/checkFullyCached chunkSetState=[\(chunkBitSet)]")
        guard !isFullyCached else { return }
        if chunkBitSet.areAllBitsSet() {
            DDLogInfo("CachedChunkedMediaResource/checkFullyCached mark as fully cached")
            MainAppContext.shared.feedData.markStreamingMediaAsDownloaded(feedPostID: feedPostID, order: mediaOrder)
            isFullyCached = true
        }
    }

    public func nextUncachedIndex(from chunkIndex: Int32) -> Int32 {
        let nextUncachedIndex = (Int(chunkIndex)..<chunkBitSet.count).first(where: { chunkBitSet[$0] == false }) ?? chunkBitSet.count
        DDLogDebug("CachedChunkedMediaResource/nextUncachedIndex from=[\(chunkIndex)] nextUncached=[\(nextUncachedIndex)]")
        return Int32(nextUncachedIndex)
    }

    public func isChunkCached(at chunkIndex: Int32) -> Bool {
        let isCached = chunkBitSet[Int(chunkIndex)]
        DDLogDebug("CachedChunkedMediaResource/isChunkCached index=[\(chunkIndex)] isCached=[\(isCached)]")
        return isCached
    }

    public func readChunk(at chunkIndex: Int32) throws -> Data {
        chunkedParameters.preconditionChunkIndexInBounds(chunkIndex: chunkIndex)
        let offset = UInt64(chunkIndex) * UInt64(chunkedParameters.regularChunkPtSize)
        do {
            return try autoreleasepool {
                let fileHandle = try getFileHandle()
                try fileHandle.seek(toOffset: offset)
                let chunkData = fileHandle.readData(ofLength: Int(chunkedParameters.regularChunkPtSize))
                DDLogDebug("CachedChunkedMediaResource/readChunk index=[\(chunkIndex)] offset=[\(offset)] size=[\(chunkData.count)]")
                return chunkData
            }
        } catch {
            DDLogError("CachedChunkedMediaResource/readChunk error index=[\(chunkIndex)] \(error)")
            throw error
        }
    }

    public func writeChunk(at chunkIndex: Int32, chunkData: Data) throws {
        chunkedParameters.preconditionChunkIndexInBounds(chunkIndex: chunkIndex)
        precondition(chunkData.count <= chunkedParameters.regularChunkPtSize)
        let offset = UInt64(chunkIndex) * UInt64(chunkedParameters.regularChunkPtSize)
        do {
            try autoreleasepool {
                DDLogDebug("CachedChunkedMediaResource/writeChunk index=[\(chunkIndex)] offset=[\(offset)] size=[\(chunkData.count)]")
                let fileHandle = try getFileHandle()
                try fileHandle.seek(toOffset: offset)
                fileHandle.write(chunkData)
                try fileHandle.synchronize()
            }
            chunkBitSet[Int(chunkIndex)] = true
            MainAppContext.shared.feedData.updateStreamingMediaChunks(feedPostID: feedPostID, order: mediaOrder, chunkSetData: chunkBitSet.data)
            checkFullyCached()
        } catch {
            DDLogError("CachedChunkedMediaResource/writeChunk error index=[\(chunkIndex)] \(error)")
            throw error
        }
    }

    public func close() {
        DDLogDebug("CachedChunkedMediaResource/close")
        fileHandle?.closeFile()
        fileHandle = nil
    }
}

fileprivate class ThreadSafeCachedChunkedMediaResource {
    private let cachedMediaResource: CachedChunkedMediaResource
    private let resourceCachingQueue: DispatchQueue

    init(cachedMediaResource: CachedChunkedMediaResource, resourceCachingQueue: DispatchQueue) {
        self.cachedMediaResource = cachedMediaResource
        self.resourceCachingQueue = resourceCachingQueue
    }

    func isChunkCached(at chunkIndex: Int32) -> Bool {
        return resourceCachingQueue.sync { cachedMediaResource.isChunkCached(at: chunkIndex) }
    }

    func readChunk(at chunkIndex: Int32) throws -> Data {
        return try resourceCachingQueue.sync { try cachedMediaResource.readChunk(at: chunkIndex) }
    }

    func writeChunkIfUncached(at chunkIndex: Int32, chunkData: Data, _ completion: @escaping (Int32, Int32, Swift.Error?) -> Void ) {
        resourceCachingQueue.async {
            var writeError: Swift.Error?
            if !self.cachedMediaResource.isChunkCached(at: chunkIndex) {
                do {
                    try self.cachedMediaResource.writeChunk(at: chunkIndex, chunkData: chunkData)
                } catch {
                    writeError = error
                }
            }
            let nextUncachedIndex = self.cachedMediaResource.nextUncachedIndex(from: chunkIndex)
            completion(chunkIndex, nextUncachedIndex, writeError)
        }
    }

    func close() {
        resourceCachingQueue.async { self.cachedMediaResource.close() }
    }
}
