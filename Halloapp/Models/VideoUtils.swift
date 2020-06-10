//
//  VideoUtils.swift
//  Halloapp
//
//  Created by Tony Jiang on 3/12/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Foundation
import AVFoundation
import SwiftUI
import Core

import UIKit
import AVKit

import VideoToolbox
import NextLevelSessionExporter

class VideoUtils {

    var desiredSize = CGSize(width: 854, height: 480)
    var desiredVideoBitrate = 2000000
    var desiredAudioBitrate = 96000
    
    func resizeVideo(inputUrl: URL, completion: @escaping (_ outputUrl: URL, _ videoSize: CGSize?) -> Void) {

        let avAsset = AVURLAsset(url: inputUrl, options: nil)
        
        let exporter = NextLevelSessionExporter(withAsset: avAsset)
        exporter.outputFileType = AVFileType.mp4
        // todo: remove temporary files manually with a timestamp format in the filename
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(ProcessInfo().globallyUniqueString)
            .appendingPathExtension("mp4")
        exporter.outputURL = tmpURL

        let compressionDict: [String: Any] = [
            AVVideoAverageBitRateKey: NSNumber(integerLiteral: desiredVideoBitrate),
//            AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel as String
            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main_AutoLevel as String
        ]

        let track = avAsset.tracks(withMediaType: AVMediaType.video).first
        let size = track!.naturalSize.applying(track!.preferredTransform)

        var videoWidth = Int(abs(size.width))
        var videoHeight = Int(abs(size.height))

        DDLogInfo("Original Video Resolution: \(videoWidth) x \(videoHeight)")

        // portrait
        if videoHeight > videoWidth {
            if videoHeight > Int(desiredSize.width) {
                DDLogInfo("Portrait taller than \(Int(desiredSize.width)), need to rescale")

                let ratio = Double(videoWidth)/Double(videoHeight)
                let resizedWidth = ratio*854

                videoHeight = Int(desiredSize.width)
                videoWidth = Int(resizedWidth)

                DDLogInfo("New Video Resolution: \(videoWidth) x \(videoHeight)")
            }
        // landscape or square
        } else {
            if videoWidth > Int(desiredSize.width) {
                DDLogInfo("Landscape wider than \(Int(desiredSize.width)), need to rescale")

                let ratio = Double(videoWidth)/Double(videoHeight)
                let resizedHeight = Double(desiredSize.width)/ratio

                videoWidth = Int(desiredSize.width)
                videoHeight = Int(resizedHeight)

                DDLogInfo("New Video Resolution: \(videoWidth) x \(videoHeight)")
            }
        }

        exporter.videoOutputConfiguration = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
//            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: NSNumber(integerLiteral: videoWidth),
            AVVideoHeightKey: NSNumber(integerLiteral: videoHeight),
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoCompressionPropertiesKey: compressionDict
        ]
        exporter.audioOutputConfiguration = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVEncoderBitRateKey: NSNumber(integerLiteral: desiredAudioBitrate),
            AVNumberOfChannelsKey: NSNumber(integerLiteral: 2),
            AVSampleRateKey: NSNumber(value: Float(44100))
        ]

        exporter.export(progressHandler: { (progress) in
//            print(progress)
        }, completionHandler: { result in
            switch result {
            case .success(let status):
                switch status {
                case .completed:
                    print("NextLevelSessionExporter, export completed, \(exporter.outputURL?.description ?? "")")

                    if let outputUrl = exporter.outputURL {
                        completion(outputUrl, CGSize(width: abs(videoWidth), height: abs(videoHeight)))
                    }
                        
                    break
                default:
                    print("NextLevelSessionExporter, did not complete")
                    //todo: take care of error case
                    break
                }
                break
            case .failure(let error):
                print("NextLevelSessionExporter, failed to export \(error)")
                //todo: take care of error case
                break
            }
        })

    }
    
    func resolutionForLocalVideo(url: URL) -> CGSize? {
        guard let track = AVURLAsset(url: url).tracks(withMediaType: AVMediaType.video).first else { return nil }
        let size = track.naturalSize.applying(track.preferredTransform)
        return CGSize(width: abs(size.width), height: abs(size.height))
    }
    
}
