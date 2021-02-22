//
//  VideoUtils.swift
//  Halloapp
//
//  Created by Tony Jiang on 3/12/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVFoundation
import AVKit
import CocoaLumberjack
import Core
import Foundation
import SwiftUI
import UIKit
import VideoToolbox

final class VideoSettings: ObservableObject {

    private enum UserDefaultsKeys {
        static var resolution: String { "VideoSettings.resolution" }
        static var bitrate: String { "VideoSettings.bitrate" }
    }

    private init() {
        let userDefaults = AppContext.shared.userDefaults!
        // Set defaults
        userDefaults.register(defaults: [
            UserDefaultsKeys.resolution: AVOutputSettingsPreset.preset960x540.rawValue,
            UserDefaultsKeys.bitrate: 50
        ])
        // Load settings
        if let value = userDefaults.string(forKey: UserDefaultsKeys.resolution) {
            preset = AVOutputSettingsPreset(rawValue: value)
        } else {
            preset = AVOutputSettingsPreset.preset960x540
        }
        resolution = VideoSettings.resolution(from: preset)
        
        let bitrateSetting = userDefaults.integer(forKey: UserDefaultsKeys.bitrate)
        if bitrateSetting > 0 {
            bitrateMultiplier = min(max(bitrateSetting, 30), 100)
        } else {
            bitrateMultiplier = 50
        }
    }

    private static let sharedInstance = VideoSettings()

    static var shared: VideoSettings {
        sharedInstance
    }

    // MARK: Settings

    static func resolution(from preset: AVOutputSettingsPreset) -> String {
        // AVOutputSettingsPreset960x540 -> 960x540
        return preset.rawValue.trimmingCharacters(in: .letters)
    }

    @Published var resolution: String

    var preset: AVOutputSettingsPreset {
        didSet {
            AppContext.shared.userDefaults.setValue(preset.rawValue, forKey: UserDefaultsKeys.resolution)
            resolution = VideoSettings.resolution(from: preset)
        }
    }

    @Published var bitrateMultiplier: Int {
        didSet {
            AppContext.shared.userDefaults.setValue(bitrateMultiplier, forKey: UserDefaultsKeys.bitrate)
        }
    }
}

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

final class VideoUtils {

    static func resizeVideo(inputUrl: URL, completion: @escaping (Swift.Result<(URL, CGSize), Error>) -> Void) {

        let avAsset = AVURLAsset(url: inputUrl, options: nil)
        
        let exporter = NextLevelSessionExporter(withAsset: avAsset)
        exporter.outputFileType = AVFileType.mp4
        // todo: remove temporary files manually with a timestamp format in the filename
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(ProcessInfo().globallyUniqueString)
            .appendingPathExtension("mp4")
        exporter.outputURL = tmpURL

        var videoOutputConfiguration: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 5250000, // avg bitrate from `preset960x540`
                AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel
            ]
        ]
        var audioOutputConfiguration: [String: Any] =  [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVEncoderBitRateKey: 96000,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100
        ]

        var maxVideoResolution: CGFloat = 960 // match value from `preset960x540`
        if let assistant = AVOutputSettingsAssistant(preset: VideoSettings.shared.preset) {
            if let videoSettings = assistant.videoSettings {
                videoOutputConfiguration.merge(videoSettings) { (_, new) in new }

                if let presetVideoWidth = videoSettings[AVVideoWidthKey] as? CGFloat,
                   let presetVideoHeight = videoSettings[AVVideoHeightKey] as? CGFloat {
                    maxVideoResolution = max(presetVideoWidth, presetVideoHeight)
                }
            }
            if let audioSettings = assistant.audioSettings {
                audioOutputConfiguration.merge(audioSettings, uniquingKeysWith: { (_, new) in new })
            }
        }

        // Adjust video bitrate.
        if var compressionProperties = videoOutputConfiguration[AVVideoCompressionPropertiesKey] as? [String: Any],
           let avgBitrate = compressionProperties[AVVideoAverageBitRateKey] as? Double {
            let multiplier = Double(VideoSettings.shared.bitrateMultiplier) * 0.01
            compressionProperties[AVVideoAverageBitRateKey] = Int(round(avgBitrate * multiplier))
            videoOutputConfiguration[AVVideoCompressionPropertiesKey] = compressionProperties
        }

        // Resize video (if necessary) keeping aspect ratio.
        let track = avAsset.tracks(withMediaType: AVMediaType.video).first
        let videoResolution: CGSize = {
            let size = track!.naturalSize.applying(track!.preferredTransform)
            return CGSize(width: abs(size.width), height: abs(size.height))
        }()
        let videoAspectRatio = videoResolution.width / videoResolution.height
        var targetVideoSize = videoResolution

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
        DDLogInfo("video-processing/ New video resolution: \(targetVideoSize)")
        videoOutputConfiguration[AVVideoWidthKey] = targetVideoSize.width
        videoOutputConfiguration[AVVideoHeightKey] = targetVideoSize.height
        videoOutputConfiguration[AVVideoScalingModeKey] = AVVideoScalingModeResizeAspectFill // this is different from the value provided by assistant


        DDLogInfo("video-processing/ Video output config: [\(videoOutputConfiguration)]")
        exporter.videoOutputConfiguration = videoOutputConfiguration

        DDLogInfo("video-processing/ Audio output config: [\(audioOutputConfiguration)]")
        exporter.audioOutputConfiguration = audioOutputConfiguration

        DDLogInfo("video-processing/export/start")
        exporter.export(retryOnCancel: 2, progressHandler: { (progress) in
            DDLogInfo("video-processing/export/progress [\(progress)] input=[\(inputUrl.description)]")
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
    }
    
    static func resolutionForLocalVideo(url: URL) -> CGSize? {
        guard let track = AVURLAsset(url: url).tracks(withMediaType: AVMediaType.video).first else { return nil }
        let size = track.naturalSize.applying(track.preferredTransform)
        return CGSize(width: abs(size.width), height: abs(size.height))
    }
    
    static func videoPreviewImage(url: URL, size: CGSize?) -> UIImage? {
        let asset = AVURLAsset(url: url)
        guard asset.duration.value > 0 else { return nil }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        if let preferredSize = size {
            generator.maximumSize = preferredSize
        }
        let time = CMTimeMakeWithSeconds(2.0, preferredTimescale: 600)
        do {
            let img = try generator.copyCGImage(at: time, actualTime: nil)
            let thumbnail = UIImage(cgImage: img)
            return thumbnail
        } catch {
            DDLogDebug("VideoUtils/videoPreviewImage/error \(error.localizedDescription) - [\(url)]")
            return nil
        }
    }

    static func trim(start: CMTime, end: CMTime, url: URL, mute: Bool, completion: @escaping (Swift.Result<URL, Error>) -> Void) {
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
}

private extension NextLevelSessionExporter {
    func export(retryOnCancel times: Int,
                renderHandler: RenderHandler? = nil,
                progressHandler: ProgressHandler? = nil,
                completionHandler: CompletionHandler? = nil) {

        export(renderHandler: renderHandler, progressHandler: progressHandler) { [weak self] result in
            switch result {
            case .failure(let error as NextLevelSessionExporterError) where error == NextLevelSessionExporterError.cancelled && times > 0:
                DDLogWarn("VideoUtils/export/retryOnCancel times=[\(times)] url=[\(self?.outputURL?.description ?? "")]")
                self?.export(retryOnCancel: times - 1, renderHandler: renderHandler, progressHandler: progressHandler, completionHandler: completionHandler)
            default:
                if let handler = completionHandler {
                    handler(result)
                }
            }
        }
    }

}
