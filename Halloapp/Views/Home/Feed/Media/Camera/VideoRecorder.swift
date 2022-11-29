//
//  VideoRecorder.swift
//  HalloApp
//
//  Created by Tanveer on 11/22/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import AVFoundation
import CocoaLumberjackSwift

class VideoRecorder {

    private(set) var request: VideoCaptureRequest?
    private var isRecording = false

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var hasWrittenVideo = false
    private var shouldMergeVideo = false

    private lazy var videoMerger = VideoMerger()
    private var latestSecondaryBuffer: CVImageBuffer?

    private static var fileURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID().uuidString).mp4")
    }

    func start(with request: VideoCaptureRequest, videoSettings: [String: Any], audioSettings: [String: Any]) -> Bool {
        guard !isRecording else {
            DDLogInfo("VideoRecorder/start called when already recording")
            return false
        }

        let shouldMerge: Bool
        switch request.layout {
        case .splitPortrait(_), .splitLandscape(_):
            shouldMerge = true
        default:
            shouldMerge = false
        }

        var videoSettings = videoSettings
        if !shouldMerge {
            videoSettings[AVVideoScalingModeKey] = AVVideoScalingModeResizeAspectFill
        }

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)

        videoInput.expectsMediaDataInRealTime = true
        audioInput.expectsMediaDataInRealTime = true
        videoInput.transform = transform(from: request.orientation)

        guard
            let writer = try? AVAssetWriter(outputURL: Self.fileURL, fileType: .mp4),
            writer.canAdd(videoInput),
            writer.canAdd(audioInput)
        else {
            DDLogError("VideoRecorder/start/could not create asset writer and add inputs")
            return false
        }

        writer.add(videoInput)
        writer.add(audioInput)

        self.request = request
        self.writer = writer
        self.videoInput = videoInput
        self.audioInput = audioInput
        self.shouldMergeVideo = shouldMerge

        isRecording = true
        return true
    }

    func stop() async {
        isRecording = false
        Task { await finishRecording() }
    }

    private func finishRecording() async {
        defer {
            videoInput = nil
            audioInput = nil
            request = nil
            writer = nil
            latestSecondaryBuffer = nil
            hasWrittenVideo = false
            shouldMergeVideo = false
        }

        guard let writer, writer.status != .unknown else {
            return
        }

        await writer.finishWriting()
        if let error = writer.error {
            request?.set(error: error)
            return
        }

        request?.set(url: writer.outputURL)
    }

    func update(primaryBuffer: CMSampleBuffer) {
        guard
            isRecording, let writer, let videoInput,
            let outputBuffer = shouldMergeVideo ? createMergedBuffer(primaryBuffer: primaryBuffer) : primaryBuffer
        else {
            return
        }

        switch writer.status {
        case .unknown:
            writer.startWriting()
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(outputBuffer))
            fallthrough
        case .writing:
            if videoInput.isReadyForMoreMediaData {
                videoInput.append(outputBuffer)
                hasWrittenVideo = true
            }
        default:
            break
        }
    }

    func update(secondaryBuffer: CMSampleBuffer) {
        guard isRecording else {
            return
        }

        latestSecondaryBuffer = CMSampleBufferGetImageBuffer(secondaryBuffer)
    }

    func update(audioBuffer: CMSampleBuffer) {
        guard let writer, case .writing = writer.status, let audioInput, audioInput.isReadyForMoreMediaData, hasWrittenVideo else {
            return
        }

        audioInput.append(audioBuffer)
    }

    private func createMergedBuffer(primaryBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard
            let primaryImageBuffer = CMSampleBufferGetImageBuffer(primaryBuffer), let latestSecondaryBuffer,
            let formatDescription = CMSampleBufferGetFormatDescription(primaryBuffer)
        else {
            return nil
        }

        if !videoMerger.isReady {
            videoMerger.prepare(formatDescription: formatDescription)
        }

        var shouldFlipBuffers = false
        var portraitLayout = true

        switch request?.layout {
        case .splitLandscape(top: let position):
            shouldFlipBuffers = position == .front
            portraitLayout = false
        case .splitPortrait(leading: let position):
            shouldFlipBuffers = position == .front
        default:
            break
        }

        let primaryBufferToMerge = shouldFlipBuffers ? primaryImageBuffer : latestSecondaryBuffer
        let secondaryBufferToMerge = shouldFlipBuffers ? latestSecondaryBuffer : primaryImageBuffer

        guard
            let mergedBuffer = videoMerger.merge(primaryBuffer: primaryBufferToMerge,
                                               secondaryBuffer: secondaryBufferToMerge,
                                                      portrait: portraitLayout),
            let outputFormatDescription = videoMerger.outputFormatDescription
        else {
            return nil
        }

        var outputBuffer: CMSampleBuffer?
        var outputBufferTime = CMSampleTimingInfo(duration: .invalid,
                                     presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(primaryBuffer),
                                           decodeTimeStamp: .invalid)

        let error = CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                     imageBuffer: mergedBuffer,
                                                       dataReady: true,
                                           makeDataReadyCallback: nil,
                                                          refcon: nil,
                                               formatDescription: outputFormatDescription,
                                                    sampleTiming: &outputBufferTime,
                                                 sampleBufferOut: &outputBuffer)

        guard let outputBuffer else {
            DDLogError("VideoRecorder/update-primaryBuffer/allocating output buffer failed with code \(error)")
            return nil
        }

        return outputBuffer
    }

    private func transform(from orientation: UIDeviceOrientation) -> CGAffineTransform {
        var rotation = CGAffineTransform.identity
        switch orientation {
        case .portraitUpsideDown:
            rotation = rotation.rotated(by: -.pi / 2)
        case .landscapeLeft:
            // this seems to be the default; the other angles are based on this
            break
        case .landscapeRight:
            rotation = rotation.rotated(by: .pi)
        default:
            rotation = rotation.rotated(by: .pi / 2)
        }

        return rotation
    }
}
