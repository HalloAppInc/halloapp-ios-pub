//
//  VideoUtils.swift
//  Halloapp
//
//  Created by Tony Jiang on 3/12/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVFoundation
import AVKit
import CocoaLumberjackSwift
import CoreCommon
import Foundation
import SwiftUI
import UIKit
import VideoToolbox

// TODO: Temporarily turn off and potentially remove
//final class VideoSettings: ObservableObject {
//
//    private enum UserDefaultsKeys {
//        static var resolution: String { "VideoSettings.resolution" }
//        static var bitrate: String { "VideoSettings.bitrate" }
//    }
//
//    private init() {
//        let userDefaults = AppContext.shared.userDefaults!
//        // Set defaults
//        userDefaults.register(defaults: [
//            UserDefaultsKeys.resolution: AVOutputSettingsPreset.preset960x540.rawValue,
//            UserDefaultsKeys.bitrate: 50
//        ])
//        // Load settings
//        if let value = userDefaults.string(forKey: UserDefaultsKeys.resolution) {
//            preset = AVOutputSettingsPreset(rawValue: value)
//        } else {
//            preset = AVOutputSettingsPreset.preset960x540
//        }
//        resolution = VideoSettings.resolution(from: preset)
//
//        let bitrateSetting = userDefaults.integer(forKey: UserDefaultsKeys.bitrate)
//        if bitrateSetting > 0 {
//            bitrateMultiplier = min(max(bitrateSetting, 30), 100)
//        } else {
//            bitrateMultiplier = 50
//        }
//    }
//
//    private static let sharedInstance = VideoSettings()
//
//    static var shared: VideoSettings {
//        sharedInstance
//    }
//
//    // MARK: Settings
//
//    static func resolution(from preset: AVOutputSettingsPreset) -> String {
//        // AVOutputSettingsPreset960x540 -> 960x540
//        return preset.rawValue.trimmingCharacters(in: .letters)
//    }
//
//    @Published var resolution: String
//
//    var preset: AVOutputSettingsPreset {
//        didSet {
//            AppContext.shared.userDefaults.setValue(preset.rawValue, forKey: UserDefaultsKeys.resolution)
//            resolution = VideoSettings.resolution(from: preset)
//        }
//    }
//
//    @Published var bitrateMultiplier: Int {
//        didSet {
//            AppContext.shared.userDefaults.setValue(bitrateMultiplier, forKey: UserDefaultsKeys.bitrate)
//        }
//    }
//}

public enum VideoUtilsError: Error, CustomStringConvertible {
    case missingVideoTrack
    case setupFailure
    case processingFailure

    public var description: String {
        get {
            switch self {
            case .setupFailure:
                return "Setup failure"
            case .missingVideoTrack:
                return "Missing video track"
            case .processingFailure:
                return "Processing failure"
            }
        }
    }
}

public final class VideoUtils {

    public static func maxVideoResolution(for targetResolution: CGFloat) -> CGFloat {
        switch(targetResolution) {
        case 480, 640:
            return 640
        case 540, 960:
            return 960
        case 720, 1280:
            return 1280
        case 1080, 1920:
            return 1920
        case 2160, 3840:
            return 3840
        default:
            return targetResolution
        }
    }

    public static func resizeVideo(inputUrl: URL, progress: ((Float) -> Void)? = nil, completion: @escaping (Swift.Result<(URL, CGSize), Error>) -> Void) -> CancelableExporter {

        let avAsset = AVURLAsset(url: inputUrl, options: nil)
        
        let exporter = CancelableExporter(withAsset: avAsset)
        exporter.outputFileType = AVFileType.mp4
        // todo: remove temporary files manually with a timestamp format in the filename
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(ProcessInfo().globallyUniqueString)
            .appendingPathExtension("mp4")
        exporter.outputURL = tmpURL

        var videoOutputConfiguration: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: ServerProperties.targetVideoBitRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel
            ] as [String : Any]
        ]
        let audioOutputConfiguration: [String: Any] =  [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVEncoderBitRateKey: 96000,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100
        ]

        let maxVideoResolution = maxVideoResolution(for: ServerProperties.targetVideoResolution)

        // TODO: Temporarily turn off and potentially remove
//        if let assistant = AVOutputSettingsAssistant(preset: VideoSettings.shared.preset), useDeveloperSettings {
//            if let videoSettings = assistant.videoSettings {
//                videoOutputConfiguration.merge(videoSettings) { (_, new) in new }
//
//                if let presetVideoWidth = videoSettings[AVVideoWidthKey] as? CGFloat,
//                   let presetVideoHeight = videoSettings[AVVideoHeightKey] as? CGFloat {
//                    maxVideoResolution = max(presetVideoWidth, presetVideoHeight)
//                }
//            }
//            if let audioSettings = assistant.audioSettings {
//                audioOutputConfiguration.merge(audioSettings, uniquingKeysWith: { (_, new) in new })
//            }
//        }

        // Adjust video bitrate.
//        if var compressionProperties = videoOutputConfiguration[AVVideoCompressionPropertiesKey] as? [String: Any],
//           let avgBitrate = compressionProperties[AVVideoAverageBitRateKey] as? Double, useDeveloperSettings {
//            let multiplier = Double(VideoSettings.shared.bitrateMultiplier) * 0.01
//            compressionProperties[AVVideoAverageBitRateKey] = Int(round(avgBitrate * multiplier))
//            videoOutputConfiguration[AVVideoCompressionPropertiesKey] = compressionProperties
//        }

        // Resize video (if necessary) keeping aspect ratio.
        let track = avAsset.tracks(withMediaType: AVMediaType.video).first
        var targetVideoSize = CGSize.zero

        if let track = track {
            let videoResolution: CGSize = {
                let size = track.naturalSize.applying(track.preferredTransform)
                return CGSize(width: abs(size.width), height: abs(size.height))
            }()
            targetVideoSize = videoResolution
            let videoAspectRatio = videoResolution.width / videoResolution.height

            DDLogInfo("video-processing/ Original video resolution: \(videoResolution)")

            if videoResolution.height > videoResolution.width {
                // portrait
                if videoResolution.height > maxVideoResolution {
                    DDLogInfo("video-processing/ Portrait taller than \(maxVideoResolution), need to resize")

                    targetVideoSize.height = maxVideoResolution
                    targetVideoSize.width = round(videoAspectRatio * targetVideoSize.height)
                }
            } else {
                // landscape or square
                if videoResolution.width > maxVideoResolution {
                    DDLogInfo("video-processing/ Landscape wider than \(maxVideoResolution), need to resize")

                    targetVideoSize.width = maxVideoResolution
                    targetVideoSize.height = round(targetVideoSize.width / videoAspectRatio)
                }
            }
        } else {
            DDLogError("video-processing/ Could not find video track")
        }
        DDLogInfo("video-processing/ New video resolution: \(targetVideoSize)")
        videoOutputConfiguration[AVVideoWidthKey] = targetVideoSize.width
        videoOutputConfiguration[AVVideoHeightKey] = targetVideoSize.height
        videoOutputConfiguration[AVVideoScalingModeKey] = AVVideoScalingModeResizeAspectFill // this is different from the value provided by assistant


        DDLogInfo("video-processing/ Video output config: [\(videoOutputConfiguration)]")
        exporter.videoOutputConfiguration = videoOutputConfiguration

        DDLogInfo("video-processing/ Audio output config: [\(audioOutputConfiguration)]")
        exporter.audioOutputConfiguration = audioOutputConfiguration

        exporter.optimizeForNetworkUse = true

        DDLogInfo("video-processing/export/start")
        exporter.export(retryOnCancel: 2, progressHandler: { (exporterProgress) in
            DDLogInfo("video-processing/export/progress [\(exporterProgress)] input=[\(inputUrl.description)]")

            if let progress = progress {
                progress(exporterProgress)
            }
        }) { (result) in
            switch result {
            case .success(let status):
                switch status {
                case .completed:
                    DDLogInfo("video-processing/export/completed url=[\(exporter.outputURL?.description ?? "")] input=[\(inputUrl.description)]")
                    completion(.success((exporter.outputURL!, targetVideoSize)))

                default:
                    DDLogWarn("video-processing/export/finished status=[\(status)] url=[\(exporter.outputURL?.description ?? "")] input=[\(inputUrl.description)]")
                    //todo: take care of error case
                }
                break

            case .failure(let error):
                DDLogError("video-processing/export/failed error=[\(error)] input=[\(inputUrl.description)]")
                completion(.failure(error))
            }
        }

        return exporter
    }
    
    public static func resolutionForLocalVideo(url: URL) -> CGSize? {
        guard let track = AVURLAsset(url: url).tracks(withMediaType: AVMediaType.video).first else { return nil }
        let size = track.naturalSize.applying(track.preferredTransform)
        return CGSize(width: abs(size.width), height: abs(size.height))
    }

    static let videoPreviewCache = NSCache<NSString, UIImage>()

    private static func videoPreviewCacheKey(for videoURL: URL, size: CGSize?, animated: Bool) -> NSString {
        let cacheKey: String
        if let size = size {
            cacheKey = "\(videoURL)-\(size)-\(animated)"
        } else {
            cacheKey = "\(videoURL)-\(animated)"
        }
        return cacheKey as NSString
    }

    public static func videoPreviewImage(url: URL, size: CGSize? = nil) -> UIImage? {
        let cacheKey = videoPreviewCacheKey(for: url, size: size, animated: false)
        if let image = videoPreviewCache.object(forKey: cacheKey) {
            DDLogDebug("VideoUtils/videoPreviewImage/returning from cache for \(cacheKey)")
            return image
        }
        let asset = AVURLAsset(url: url)
        guard asset.duration.value > 0 else { return nil }
        let seekTime = getThumbnailTime(duration: asset.duration)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let preferredSize = size {
            generator.maximumSize = preferredSize
        }
        do {
            let img = try generator.copyCGImage(at: seekTime, actualTime: nil)
            let thumbnail = UIImage(cgImage: img)
            videoPreviewCache.setObject(thumbnail, forKey: cacheKey)
            return thumbnail
        } catch {
            DDLogDebug("VideoUtils/videoPreviewImage/error \(error.localizedDescription) - [\(url)]")
            return nil
        }
    }

    public static func animatedPreviewImage(for videoURL: URL, size: CGSize? = nil, completion: @escaping (UIImage?) -> Void) {
        let cacheKey = videoPreviewCacheKey(for: videoURL, size: nil, animated: true)
        if let image = videoPreviewCache.object(forKey: cacheKey) {
            DDLogDebug("VideoUtils/animatedPreviewImage/returning from cache for \(cacheKey)")
            completion(image)
            return
        }

        let asset = AVURLAsset(url: videoURL)
        guard asset.duration.value > 0 else {
            return
        }

        // Generate a list of snapshot times
        var snapshotTimes: [NSValue] = []
        var snapshotTime = getThumbnailTime(duration: asset.duration)
        let maxTime = CMTimeMinimum(asset.duration, CMTime(seconds: 20, preferredTimescale: 1))
        while CMTimeCompare(snapshotTime, maxTime) <= 0 {
            snapshotTimes.append(snapshotTime as NSValue)
            snapshotTime = CMTimeAdd(snapshotTime, CMTime(value: 2, timescale: 1))
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let size = size {
            generator.maximumSize = size
        }

        let expectedCompletions = snapshotTimes.count
        var currentCompletions = 0
        var generatedImages = [TimeInterval: UIImage]()
        generator.generateCGImagesAsynchronously(forTimes: snapshotTimes) { [generator] requestedTime, image, actualTime, result, error in
            if result == .succeeded, let image = image {
                generatedImages[actualTime.seconds] = UIImage(cgImage: image)
            }
            currentCompletions += 1
            if currentCompletions == expectedCompletions {
                let sortedImages = generatedImages.keys.sorted().compactMap { generatedImages[$0] }
                let animatedImage = UIImage.animatedImage(with: sortedImages, duration: TimeInterval(sortedImages.count) * 0.5)
                if let animatedImage = animatedImage {
                    videoPreviewCache.setObject(animatedImage, forKey: cacheKey)
                }
                DispatchQueue.main.async {
                    completion(animatedImage)
                }
                // No use continuing if we think we're complete
                generator.cancelAllCGImageGeneration()
            }
        }
    }

    public static func getThumbnailTime(duration: CMTime) -> CMTime {
        if duration.seconds < 1 {
            return CMTimeMultiplyByRatio(duration, multiplier: 1, divisor: 2)
        } else {
            return CMTime(value: 1, timescale: 1)
        }
    }

    public static func previewImageData(image: UIImage, size: CGSize? = nil) -> Data? {
        guard let preview = image.resized(to: CGSize(width: 128, height: 128), contentMode: .scaleAspectFill, downscaleOnly: false) else {
            DDLogError("VideoUtils/previewImage/error  Failed to generate preview")
            return nil
        }
        guard let imageData = preview.jpegData(compressionQuality: 0.5) else {
            DDLogError("VideoUtils/previewImage/error  Failed to generate jpeg data")
            return nil
        }
        return imageData
    }

    public static func trim(start: CMTime, end: CMTime, url: URL, mute: Bool, completion: @escaping (Swift.Result<URL, Error>) -> Void) {
        var asset: AVAsset = AVURLAsset(url: url, options: nil)

        if mute {
            DDLogInfo("video-processing/trim/mute")

            let originalVideoTracks = asset.tracks(withMediaType: .video)
            guard originalVideoTracks.count > 0 else {
                completion(.failure(VideoUtilsError.missingVideoTrack))
                return
            }

            let composition = AVMutableComposition()
            guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                completion(.failure(VideoUtilsError.setupFailure))
                return
            }

            videoTrack.preferredTransform = originalVideoTracks[0].preferredTransform

            do {
                try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: originalVideoTracks[0], at: CMTime.zero)
            } catch {
                completion(.failure(error))
                return
            }

            asset = composition
        }

        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            completion(.failure(VideoUtilsError.setupFailure))
            return
        }

        exporter.outputFileType = AVFileType.mp4
        exporter.outputURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(ProcessInfo().globallyUniqueString)
            .appendingPathExtension("mp4")
        exporter.timeRange = CMTimeRange(start: start, end: end)

        DDLogInfo("video-processing/trim/start")
        exporter.exportAsynchronously {
             switch exporter.status {
                case .completed:
                    DDLogInfo("video-processing/trim/completed url=[\(exporter.outputURL?.description ?? "")] input=[\(url.description)]")
                    completion(.success(exporter.outputURL!))
                default:
                    if let error = exporter.error {
                        DDLogWarn("video-processing/trim/error status=[\(exporter.status)] url=[\(exporter.outputURL?.description ?? "")] input=[\(url.description)] error=[\(error.localizedDescription)]")
                        completion(.failure(error))
                    } else {
                        DDLogWarn("video-processing/trim/finished status=[\(exporter.status)] url=[\(exporter.outputURL?.description ?? "")] input=[\(url.description)]")
                        completion(.failure(VideoUtilsError.processingFailure))
                    }
                }

         }
    }

    public static func save(composition: AVComposition, to outputURL: URL, slowMotion: Bool = false, completion: @escaping (Swift.Result<URL, Error>) -> Void) {
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            completion(.failure(VideoUtilsError.setupFailure))
            return
        }

        exporter.outputFileType = AVFileType.mp4
        exporter.outputURL = outputURL
        exporter.shouldOptimizeForNetworkUse = true

        if slowMotion {
            exporter.audioTimePitchAlgorithm = .varispeed
        }

        DDLogInfo("video-processing/saving-composition/start")
        exporter.exportAsynchronously {
            switch exporter.status {
            case .completed:
                DDLogInfo("video-processing/saving-composition/completed url=[\(exporter.outputURL?.description ?? "")]")
                completion(.success(exporter.outputURL!))
            default:
                if let error = exporter.error {
                    DDLogWarn("video-processing/saving-composition/error status=[\(exporter.status)] url=[\(exporter.outputURL?.description ?? "")] error=[\(error.localizedDescription)]")
                    completion(.failure(error))
                } else {
                    DDLogWarn("video-processing/saving-composition/finished status=[\(exporter.status)] url=[\(exporter.outputURL?.description ?? "")]")
                    completion(.failure(VideoUtilsError.processingFailure))
                }
            }
        }
    }

    public static func optimizeForStreaming(url: URL, completion: @escaping (Swift.Result<URL, Error>) -> Void) {
        let asset: AVAsset = AVURLAsset(url: url, options: nil)

        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            completion(.failure(VideoUtilsError.setupFailure))
            return
        }

        exporter.shouldOptimizeForNetworkUse = true
        exporter.outputFileType = AVFileType.mp4
        exporter.outputURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(ProcessInfo().globallyUniqueString)
            .appendingPathExtension("mp4")

        DDLogInfo("video-processing/optimizeForStreaming/start")
        exporter.exportAsynchronously {
             switch exporter.status {
                case .completed:
                    DDLogInfo("video-processing/optimizeForStreaming/completed url=[\(exporter.outputURL?.description ?? "")] input=[\(url.description)]")
                    completion(.success(exporter.outputURL!))
                default:
                    if let error = exporter.error {
                        DDLogWarn("video-processing/optimizeForStreaming/error status=[\(exporter.status)] url=[\(exporter.outputURL?.description ?? "")] input=[\(url.description)] error=[\(error.localizedDescription)]")
                        completion(.failure(error))
                    } else {
                        DDLogWarn("video-processing/optimizeForStreaming/finished status=[\(exporter.status)] url=[\(exporter.outputURL?.description ?? "")] input=[\(url.description)]")
                        completion(.failure(VideoUtilsError.processingFailure))
                    }
                }

         }
    }
}

public class CancelableExporter : NextLevelSessionExporter {
    private var canceledByUser = false

    func cancel() {
        canceledByUser = true
        cancelExport()
    }

    // Sometimes iOS sends a cancel event while processing videos even on
    // videos which otherwise are processed without problems. This function
    // adds basic retry functionality.
    func export(retryOnCancel times: Int,
                renderHandler: RenderHandler? = nil,
                progressHandler: ProgressHandler? = nil,
                completionHandler: CompletionHandler? = nil) {

        export(renderHandler: renderHandler, progressHandler: progressHandler) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error as NextLevelSessionExporterError) where error == NextLevelSessionExporterError.cancelled && times > 0 && !self.canceledByUser:
                DDLogWarn("VideoUtils/export/retryOnCancel times=[\(times)] url=[\(self.outputURL?.description ?? "")]")
                self.export(retryOnCancel: times - 1, renderHandler: renderHandler, progressHandler: progressHandler, completionHandler: completionHandler)
            default:
                if let handler = completionHandler {
                    handler(result)
                }
            }
        }
    }
}
