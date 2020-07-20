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
import Foundation
import NextLevelSessionExporter
import SwiftUI
import UIKit
import VideoToolbox

class VideoUtils {

    private struct Constants {
        static let maximumVideoSize: CGFloat = 854 // either width or height
        static let videoBitrate = 2000000
        static let audioBitrate = 96000
    }

    static func resizeVideo(inputUrl: URL, completion: @escaping (Swift.Result<(URL, CGSize), Error>) -> Void) {

        let avAsset = AVURLAsset(url: inputUrl, options: nil)
        
        let exporter = NextLevelSessionExporter(withAsset: avAsset)
        exporter.outputFileType = AVFileType.mp4
        // todo: remove temporary files manually with a timestamp format in the filename
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(ProcessInfo().globallyUniqueString)
            .appendingPathExtension("mp4")
        exporter.outputURL = tmpURL

        let compressionDict: [String: Any] = [
            AVVideoAverageBitRateKey: NSNumber(integerLiteral: Constants.videoBitrate),
//            AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel as String
            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel as String
        ]

        let track = avAsset.tracks(withMediaType: AVMediaType.video).first
        let videoResolution: CGSize = {
            let size = track!.naturalSize.applying(track!.preferredTransform)
            return CGSize(width: abs(size.width), height: abs(size.height))
        }()
        let videoAspectRatio = videoResolution.width / videoResolution.height
        var targetVideoSize = videoResolution

        DDLogInfo("video-processing/ Original Video Resolution: \(videoResolution)")

        // portrait
        if videoResolution.height > videoResolution.width {
            if videoResolution.height > Constants.maximumVideoSize {
                DDLogInfo("video-processing/ Portrait taller than \(Constants.maximumVideoSize), need to rescale")

                targetVideoSize.height = Constants.maximumVideoSize
                targetVideoSize.width = round(videoAspectRatio * targetVideoSize.height)
            }
        // landscape or square
        } else {
            if videoResolution.width > Constants.maximumVideoSize {
                DDLogInfo("video-processing/ Landscape wider than \(Constants.maximumVideoSize), need to rescale")

                targetVideoSize.width = Constants.maximumVideoSize
                targetVideoSize.height = round(targetVideoSize.width / videoAspectRatio)
            }
        }
        DDLogInfo("video-processing/ New Video Resolution: \(targetVideoSize)")

        exporter.videoOutputConfiguration = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: NSNumber(integerLiteral: Int(targetVideoSize.width)),
            AVVideoHeightKey: NSNumber(integerLiteral: Int(targetVideoSize.height)),
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoCompressionPropertiesKey: compressionDict
        ]
        exporter.audioOutputConfiguration = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVEncoderBitRateKey: NSNumber(integerLiteral: Constants.audioBitrate),
            AVNumberOfChannelsKey: NSNumber(integerLiteral: 2),
            AVSampleRateKey: NSNumber(value: Float(44100))
        ]

        DDLogInfo("video-processing/export/start")
        exporter.export(progressHandler: { (progress) in
            DDLogInfo("video-processing/export/progress [\(progress)]")
        }) { (result) in
            switch result {
            case .success(let status):
                switch status {
                case .completed:
                    DDLogInfo("video-processing/export/completed url=[\(exporter.outputURL?.description ?? "")]")
                    completion(.success((exporter.outputURL!, targetVideoSize)))

                default:
                    DDLogWarn("video-processing/export/finished status=[\(status)] url=[\(exporter.outputURL?.description ?? "")]")
                    //todo: take care of error case
                }
                break

            case .failure(let error):
                DDLogError("video-processing/export/failed error=[\(error)]")
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
}
