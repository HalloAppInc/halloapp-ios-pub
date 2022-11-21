//
//  CameraModel.swift
//  HalloApp
//
//  Created by Tanveer on 6/7/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Foundation
import UIKit
import Combine
import AVFoundation
import CoreMotion
import CocoaLumberjackSwift

protocol CameraSessionManagerDelegate: AnyObject {
    @MainActor func sessionManager(_ sessionManager: CameraSessionManager, couldNotStart withError: Error)
    /// This method is called just before the session's `startRunning()` method is called.
    /// It's a good place to attach a preview layer to the session.
    @MainActor func sessionManagerWillStart(_ sessionManager: CameraSessionManager)
    @MainActor func sessionManagerDidStart(_ sessionManager: CameraSessionManager)
    @MainActor func sessionManagerDidStop(_ sessionManager: CameraSessionManager)
    @MainActor func sessionManager(_ sessionManager: CameraSessionManager, didRecordVideoTo url: URL, error: Error?)
}

class CameraSessionManager: NSObject {

    weak var delegate: CameraSessionManagerDelegate?

    let session: AVCaptureSession
    /// For capturing audio during video recording.
    ///
    /// We use a seperate session for audio for a couple of reasons:
    /// 1. Prevent the orange status bar dot from appearing when there is no recording taking place
    /// 2. Only pause the user's audio if they're recording video. Adding the input to the main capture
    ///    session at record time causes a stutter in the preview.
    private(set) lazy var audioSession: AVCaptureSession = AVCaptureSession()
    private lazy var sessionQueue = DispatchQueue(label: "camera.queue", qos: .userInteractive)

    let isUsingMultipleCameras: Bool
    private var sessionIsSetup = false

    private var backCamera: AVCaptureDevice?
    private var frontCamera: AVCaptureDevice?
    private var microphone: AVCaptureDevice?

    private var backInput: AVCaptureDeviceInput?
    private var frontInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?

    private var primaryPhotoOutput: AVCapturePhotoOutput?
    private var secondaryPhotoOutput: AVCapturePhotoOutput?

    private var captureRequest: CaptureRequest?

// MARK: - video recording properties

    private lazy var videoQueue = DispatchQueue(label: "video.writing.queue", qos: .userInitiated)
    private var hasWrittenVideo = false
    private var assetWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var audioOuput: AVCaptureAudioDataOutput?

    var maximumVideoDuration: TimeInterval = 60
    private var videoTimeout: DispatchWorkItem?


// MARK: - published properties

    @Published private(set) var activeCamera: CameraPosition = .unspecified

    @Published private(set) var isTakingPhoto = false
    @Published private(set) var isRecordingVideo = false

    @Published private(set) var videoDuration: TimeInterval?
    private var videoRecordingStartTime: TimeInterval?

    private var cancellables: Set<AnyCancellable> = []

    override init() {
        isUsingMultipleCameras = AVCaptureMultiCamSession.isMultiCamSupported
        session = isUsingMultipleCameras ? AVCaptureMultiCamSession() : AVCaptureSession()

        super.init()
        formSubscriptions()
    }

    private func formSubscriptions() {
        NotificationCenter.default.publisher(for: .AVCaptureSessionRuntimeError)
            .receive(on: sessionQueue)
            .sink { [weak self] notification in
                let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError
                DDLogError("CameraModel/session-runtime-error [\(String(describing: error))]")

                if case .sessionHardwareCostOverage = error?.code {
                    self?.checkMultiCamPerformanceCost()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVCaptureSessionDidStartRunning)
            .receive(on: sessionQueue)
            .sink { [weak self] _ in
                DDLogInfo("CameraModel/session-did-start")
                self?.checkMultiCamPerformanceCost()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVCaptureSessionDidStopRunning)
            .receive(on: sessionQueue)
            .sink { _ in
                DDLogInfo("CameraModel/session-did-stop")
            }
            .store(in: &cancellables)
    }

    private func updatePhoto(orientation: UIDeviceOrientation) {
        guard
            let connection = primaryPhotoOutput?.connection(with: .video),
            connection.isVideoOrientationSupported
        else {
            return
        }

        switch orientation {
        case .portrait:
            connection.videoOrientation = .portrait
        case .landscapeLeft:
            connection.videoOrientation = .landscapeRight
        case .portraitUpsideDown:
            connection.videoOrientation = .portraitUpsideDown
        case .landscapeRight:
            connection.videoOrientation = .landscapeLeft
        default:
            // retain the previous orientation
            break
        }

        if let secondaryConnection = secondaryPhotoOutput?.connection(with: .video), connection.isVideoOrientationSupported {
            secondaryConnection.videoOrientation = connection.videoOrientation
        }
    }

    private func updateVideoMirroring(for camera: AVCaptureDevice.Position) {
        guard camera != .unspecified else {
            return
        }

        if let connection = primaryPhotoOutput?.connection(with: .video), connection.isVideoMirroringSupported {
            connection.isVideoMirrored = camera == .front
        }

        if let connection = videoOutput?.connection(with: .video), connection.isVideoMirroringSupported {
            connection.isVideoMirrored = camera == .front

            if connection.isVideoOrientationSupported {
                videoOutput?.connection(with: .video)?.videoOrientation = .landscapeRight
            }
        }
    }
}

// MARK: - using the session's queue

extension CameraSessionManager {
    /// Await a throwing block that is performed on `sessionQueue`.
    private func perform(_ block: @escaping () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) -> Void in
            sessionQueue.async {
                do {
                    try block()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Await a non-throwing block that is performed on `sessionQueue`.
    private func perform(_ block: @escaping () -> Void) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                block()
                continuation.resume()
            }
        }
    }
}

// MARK: - methods for session setup

extension CameraSessionManager {

    @discardableResult
    private func hasPermissions(for type: AVMediaType) async -> Bool {
        return await AVCaptureDevice.permissions(for: type)
    }

    /// Sets up and starts the underlying capture session.
    ///
    /// Assign a delegate prior to calling this method in order to receive possible errors.
    func start() {
        Task {
            if sessionIsSetup {
                await startSession()
            } else {
                await setupAndStartSession()
            }
        }
    }

    /// - Parameter teardown: `true` if the inputs and outputs for the capture sessions should be removed.
    ///                       Passing `false` simply stops the capture sessions, and allows for quicker resumption
    ///                       when subsequently calling `start()`.
    func stop(teardown: Bool) {
        Task { await stopCaptureSession(teardown: teardown) }
    }

    private func setupAndStartSession() async {
        do {
            try await setupSession()
            sessionIsSetup = true
            await startSession()
        } catch {
            await delegate?.sessionManager(self, couldNotStart: error)
        }
    }

    private func setupSession() async throws {
        if await !hasPermissions(for: .video) {
            throw CameraSessionError.permissions(.video)
        }

        if await !hasPermissions(for: .audio) {
            throw CameraSessionError.permissions(.audio)
        }

        try await perform { [weak self, session] in
            session.beginConfiguration()
            defer { session.commitConfiguration() }

            try self?.setupPhotoOutput()
            try self?.setupInputs()
            try self?.setupVideoOutput()
        }
    }

    private func startSession() async {
        guard !session.isRunning else {
            return
        }

        await delegate?.sessionManagerWillStart(self)
        await perform { [weak self] in
            self?.setFormats()

            if let back = self?.backCamera, let front = self?.frontCamera {
                self?.focus(camera: back)
                self?.focus(camera: front)
                self?.resetZoom(on: back)
                self?.resetZoom(on: front)
            }

            self?.checkMultiCamPerformanceCost()
            self?.session.startRunning()
        }

        await delegate?.sessionManagerDidStart(self)
    }

    /// - note: Only called from `sessionQueue`.
    private func setupInputs() throws {
        try setupBackCamera()
        try setupFrontCamera()
        try setupMicrophone()

        if isUsingMultipleCameras {
            try setupMultiCamInputs()
        } else {
            try setupSingleCamInputs()
        }

        if let input = audioInput {
            audioSession.addInput(input)
        }
    }

    private func setupSingleCamInputs() throws {
        if let input = backInput {
            session.addInput(input)
            activeCamera = .back
        }
    }

    private func setupMultiCamInputs() throws {
        func addConnection(_ connection: AVCaptureConnection) throws {
            if session.canAddConnection(connection) {
                session.addConnection(connection)
            } else {
                throw CameraSessionError.cameraInitialization(.back)
            }
        }

        if let input = backInput, session.canAddInput(input), let port = input.ports.first, let output = primaryPhotoOutput {
            session.addInputWithNoConnections(input)

            let connection = AVCaptureConnection(inputPorts: [port], output: output)
            try addConnection(connection)
        }

        if let input = frontInput, session.canAddInput(input), let port = input.ports.first, let output = secondaryPhotoOutput {
            session.addInputWithNoConnections(input)

            let connection = AVCaptureConnection(inputPorts: [port], output: output)
            try addConnection(connection)
            connection.isVideoMirrored = true
        }
    }

    private func setFormats() {
        if isUsingMultipleCameras, let back = backCamera, let front = frontCamera {
            setMultiCamFormat(for: back)
            setMultiCamFormat(for: front)
        } else {
            setSingleCamFormat()
        }
    }

    private func setMultiCamFormat(for camera: AVCaptureDevice) {
        DDLogInfo("CameraModel/setMultiCamFormat for device [\(camera.position)]")
        guard let format = camera.preferredMulticamFormat else {
            DDLogError("CameraModel/unable to get optimal format for camera [\(camera.position)]")
            return
        }

        DDLogInfo("CameraModel/setMultiCamFormat format [\(format.description)]")

        configure(camera) { camera in
            camera.activeFormat = format
        }
    }

    private func setSingleCamFormat() {
        DDLogInfo("CameraModel/setSingleCamFormat")
        let preset: AVCaptureSession.Preset = .photo
        if session.canSetSessionPreset(preset) {
            session.sessionPreset = preset
        }
    }

    func connect(preview: AVCaptureVideoPreviewLayer, to direction: AVCaptureDevice.Position) {
        guard direction != .unspecified else {
            return
        }

        if !isUsingMultipleCameras {
            return preview.session = session
        }

        preview.setSessionWithNoConnection(session)
        let input = direction == .back ? backInput : frontInput

        if let port = input?.ports.first {
            let connection = AVCaptureConnection(inputPort: port, videoPreviewLayer: preview)
            if session.canAddConnection(connection) {
                session.addConnection(connection)
            }
        } else {
            DDLogError("CameraModel/connect-preview/unable to get port for [\(direction)]")
        }
    }

    private func setupBackCamera() throws {
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            throw CameraSessionError.cameraInitialization(.back)
        }

        backCamera = device
        backInput = input
    }

    private func setupFrontCamera() throws {
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            throw CameraSessionError.cameraInitialization(.front)
        }

        frontCamera = device
        frontInput = input
    }

    private func setupMicrophone() throws {
        guard
            let device = AVCaptureDevice.default(.builtInMicrophone, for: .audio, position: .unspecified),
            let input = try? AVCaptureDeviceInput(device: device),
            audioSession.canAddInput(input)
        else {
            throw CameraSessionError.cameraInitialization(.front)
        }

        microphone = device
        audioInput = input
    }

    private func setupPhotoOutput() throws {
        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else {
            throw CameraSessionError.photoOutput
        }

        session.addOutputWithNoConnections(output)
        output.maxPhotoQualityPrioritization = .quality
        primaryPhotoOutput = output

        if isUsingMultipleCameras {
            try setupSecondPhotoOutput()
        }

        updatePhoto(orientation: .portrait)
        updateVideoMirroring(for: activeCamera)
    }

    private func setupSecondPhotoOutput() throws {
        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else {
            throw CameraSessionError.photoOutput
        }

        session.addOutputWithNoConnections(output)
        output.maxPhotoQualityPrioritization = .quality
        output.isDepthDataDeliveryEnabled = false
        output.isPortraitEffectsMatteDeliveryEnabled = false

        secondaryPhotoOutput = output
        updatePhoto(orientation: .portrait)
    }

    private func setupVideoOutput() throws {
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            self.videoOutput = videoOutput
        } else {
            throw CameraSessionError.videoOutput
        }

        let audioOutput = AVCaptureAudioDataOutput()
        audioOutput.setSampleBufferDelegate(self, queue: videoQueue)

        if audioSession.canAddOutput(audioOutput) {
            audioSession.addOutput(audioOutput)
            self.audioOuput = audioOutput
        } else {
            throw CameraSessionError.audioOutput
        }
    }

    private func stopCaptureSession(teardown: Bool = true) async {
        await perform { [session, audioSession] in
            session.stopRunning()
            audioSession.stopRunning()

            if teardown {
                session.inputs.forEach { session.removeInput($0) }
                session.outputs.forEach { session.removeOutput($0) }
                audioSession.inputs.forEach { audioSession.removeInput($0) }
                audioSession.outputs.forEach { audioSession.removeOutput($0) }
            }
        }

        await delegate?.sessionManagerDidStop(self)
    }
}

// MARK: - changing the model's state

extension CameraSessionManager {
    func flipCamera() {
        Task {
            guard activeCamera != .unspecified else {
                return
            }

            let side: AVCaptureDevice.Position = activeCamera == .back ? .front: .back
            await flipCamera(to: side)
        }
    }

    private func flipCamera(to side: AVCaptureDevice.Position) async {
        activeCamera = .unspecified
        await perform { [weak self, backInput, frontInput, session] in
            guard
                let self = self,
                let currentCamera = side == .front ? backInput : frontInput,
                let flippedCamera = side == .front ? frontInput : backInput
            else {
                return
            }

            DDLogInfo("CameraModel/flipCamera/flipping to side [\(side)]")
            session.beginConfiguration()
            defer { session.commitConfiguration() }

            session.removeInput(currentCamera)
            session.addInput(flippedCamera)

            if let camera = side == .front ? self.frontCamera : self.backCamera {
                self.focus(camera: camera)
                self.activeCamera = side
            }

            self.updateVideoMirroring(for: side)
        }
    }

    func focus(_ position: AVCaptureDevice.Position, on point: CGPoint) {
        guard
            position != .unspecified,
            let camera = position == .back ? backCamera : frontCamera
        else {
            return
        }

        DDLogInfo("CameraModel/focus/focusing [\(position)] on [\(point)]")
        focus(camera: camera, on: point)
    }

    private func focus(camera: AVCaptureDevice, on point: CGPoint? = nil) {
        DDLogInfo("CameraModel/focus-camera position [\(camera.position)]")

        configure(camera) { camera in
            if camera.isSmoothAutoFocusSupported {
                camera.isSmoothAutoFocusEnabled = true
            }

            if let point = point, camera.isFocusPointOfInterestSupported, camera.isExposurePointOfInterestSupported {
                camera.focusPointOfInterest = point
                camera.exposurePointOfInterest = point
                camera.focusMode = .autoFocus
                camera.exposureMode = .autoExpose

                return
            }

            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            } else if camera.isFocusModeSupported(.autoFocus) {
                camera.focusMode = .autoFocus
            }

            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            } else if camera.isExposureModeSupported(.autoExpose) {
                camera.exposureMode = .autoExpose
            }
        }
    }

    private func resetZoom(on camera: AVCaptureDevice) {
        configure(camera) { camera in
            camera.videoZoomFactor = camera.minAvailableVideoZoomFactor
        }
    }

    func zoom(_ position: AVCaptureDevice.Position, to scale: CGFloat) {
        guard
            position != .unspecified,
            let camera = position == .back ? backCamera : frontCamera
        else {
            return
        }

        let zoom = camera.videoZoomFactor * scale
        configure(camera) { camera in
            if camera.minAvailableVideoZoomFactor <= zoom, zoom <= camera.maxAvailableVideoZoomFactor {
                camera.videoZoomFactor = zoom
            }
        }
    }

    private func configure(_ device: AVCaptureDevice, block: (AVCaptureDevice) -> Void) {
        do {
            try device.lockForConfiguration()
            block(device)
            device.unlockForConfiguration()
        } catch {
            DDLogError("CameraModel/configure-device/unable to lock device for configuration")
        }
    }
}

// MARK: - taking photos

extension CameraSessionManager: AVCapturePhotoCaptureDelegate {

    private var defaultPhotoSettings: AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings.init(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        return settings
    }

    func takePhoto(with request: CaptureRequest) -> Bool {
        guard !isTakingPhoto else {
            return false
        }

        isTakingPhoto = true
        captureRequest = request

        if isUsingMultipleCameras {
            takeMultiCamPhoto(request)
        } else {
            takeSingleCamPhoto(request)
        }

        return true
    }

    private func takeMultiCamPhoto(_ request: CaptureRequest) {
        let primaryCameraPosition = request.layout.primaryCameraPosition
        let output1: AVCapturePhotoOutput?
        let output2: AVCapturePhotoOutput?
        let s1 = defaultPhotoSettings
        var s2: AVCapturePhotoSettings?

        switch primaryCameraPosition {
        case .back:
            output1 = primaryPhotoOutput
            output2 = secondaryPhotoOutput
        default:
            output1 = secondaryPhotoOutput
            output2 = primaryPhotoOutput
        }

        request.set(settings: s1, for: primaryCameraPosition)
        output1?.capturePhoto(with: s1, delegate: self)

        switch request.layout {
        case .splitPortrait(leading: _), .splitLandscape(top: _):
            let settings = defaultPhotoSettings
            request.set(settings: settings, for: primaryCameraPosition.opposite)
            s2 = settings
        default:
            break
        }

        if let s2 {
            output2?.capturePhoto(with: s2, delegate: self)
        }
    }

    private func takeSingleCamPhoto(_ request: CaptureRequest) {
        let primaryCameraPosition = request.layout.primaryCameraPosition
        let settings = defaultPhotoSettings

        request.set(settings: settings, for: primaryCameraPosition)
        if request.shouldTakeDelayedPhoto {
            request.set(settings: defaultPhotoSettings, for: primaryCameraPosition.opposite)
        }

        primaryPhotoOutput?.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            isTakingPhoto = false
            captureRequest?.set(error: error)
            return
        }

        updateCaptureRequest(with: photo)
    }

    private func updateCaptureRequest(with photo: AVCapturePhoto) {
        guard let request = captureRequest else {
            DDLogError("CameraModel/updateCaptureRequest/no request for incoming photo")
            return
        }

        if let direction = request.set(photo: photo)?.opposite,
           !request.isFulfilled,
           let settings = request.settings(for: direction),
           !isUsingMultipleCameras
        {
            Task { await takeDelayedSecondPhoto(settings) }
        }

        if request.isFulfilled {
            captureRequest = nil
            isTakingPhoto = false
        }
    }

    private func takeDelayedSecondPhoto(_ settings: AVCapturePhotoSettings) async {
        guard let output = primaryPhotoOutput else {
            return
        }

        await flipCamera(to: activeCamera == .back ? .front : .back)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            if let self = self {
                output.capturePhoto(with: settings, delegate: self)
            }
        }
    }
}

// MARK: - recording videos

extension CameraSessionManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    private typealias Dimensions = (height: Int32, width: Int32)

    private var videoURL: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID().uuidString).mp4")
    }

    func startRecording() {
        guard !isRecordingVideo else {
            return
        }

        Task {
            DDLogInfo("CameraModel/startRecording")
            await perform { [audioSession] in
                audioSession.startRunning()
            }

            prepareForVideoRecording()
            isRecordingVideo = true
        }
    }

    func prepareForVideoRecording() {
        prepareVideoRecordingInputs()

        let timeout = DispatchWorkItem { [weak self] in self?.stopRecording() }
        DispatchQueue.main.asyncAfter(deadline: .now() + maximumVideoDuration, execute: timeout)
        videoTimeout = timeout

        videoDuration = 0
    }

    func stopRecording() {
        guard isRecordingVideo, let writer = assetWriter else {
            return
        }

        DDLogInfo("CameraModel/stopRecording")
        isRecordingVideo = false

        videoDuration = nil
        videoTimeout?.cancel()
        videoTimeout = nil

        Task {
            guard writer.status != .unknown else {
                DDLogError("CameraModel/stopRecording task/asset writer has unknown status")
                return
            }

            await writer.finishWriting()
            if let error = writer.error {
                DDLogError("CameraModel/stopRecording task/asset writer finished with error: \(String(describing: error))")
            }

            let viewError = writer.error == nil ? nil : CameraSessionError.videoOutput
            await delegate?.sessionManager(self, didRecordVideoTo: writer.outputURL, error: viewError)
        }

        cleanUpAfterRecordingVideo()
    }

    private func cleanUpAfterRecordingVideo() {
        assetWriter = nil
        videoWriterInput = nil
        audioWriterInput = nil
        hasWrittenVideo = false

        sessionQueue.async { [audioSession] in
            audioSession.stopRunning()
        }
    }

    private func prepareVideoRecordingInputs() {
        guard
            let writer = try? AVAssetWriter(outputURL: videoURL, fileType: AVFileType.mp4),
            let format = backCamera?.activeFormat.formatDescription
        else {
            DDLogError("CameraModel/prepareForVideoRecording/unable to create asset writer")
            return
        }

        assetWriter = writer
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        setupWriterInputs((dimensions.height, dimensions.width))

        guard
            let videoInput = videoWriterInput,
            let audioInput = audioWriterInput,
            writer.canAdd(videoInput),
            writer.canAdd(audioInput)
        else {
            DDLogError("CameraModel/prepareForVideoRecording/unable to add inputs to asset writer")
            return
        }

        writer.add(videoInput)
        writer.add(audioInput)
    }

    private func setupWriterInputs(_ dimensions: Dimensions) {
        let videoSettings = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoHeightKey: dimensions.height,
            AVVideoWidthKey: dimensions.width,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
        ] as [String : Any]

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        videoInput.transform = videoTransform

        let audioSettings = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 64000
        ] as [String: Any]

        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true

        self.videoWriterInput = videoInput
        self.audioWriterInput = audioInput
    }

    private func scaleVideoDimensionsIfNecessary(_ dimensions: Dimensions) -> Dimensions {
        let maxWidth: CGFloat = 1024
        let ogHeight = CGFloat(dimensions.height)
        let ogWidth = CGFloat(dimensions.width)

        if ogWidth <= maxWidth {
            return dimensions
        }

        let scaleFactor = maxWidth / ogWidth
        let scaledHeight = Int32(ogHeight * scaleFactor)
        let scaledWidth = Int32(ogWidth * scaleFactor)

        return (scaledHeight, scaledWidth)
    }

    /// Used for rotating video according to the device's orientation.
    ///
    /// - note: Far more efficient than setting the orientation on the output, which causes the actual
    ///         buffers to be rotated as they come in.
    private var videoTransform: CGAffineTransform {
        var rotation = CGAffineTransform.identity
        switch UIDevice.current.orientation {
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

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard
            isRecordingVideo,
            let writer = assetWriter,
            let videoInput = videoWriterInput,
            let audioInput = audioWriterInput
        else {
            return
        }

        if case .unknown = writer.status, output === videoOutput {
            // make sure we start writing on a video sample buffer to avoid the initial frames being black
            writer.startWriting()
            writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)

            let currentTimestamp = sampleBuffer.presentationTimeStamp
            let currentTime = Double(currentTimestamp.value) / Double(currentTimestamp.timescale)
            videoRecordingStartTime = currentTime
        }

        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        if output === videoOutput, videoInput.isReadyForMoreMediaData {
            videoInput.append(sampleBuffer)
            hasWrittenVideo = true
        }

        if output === audioOuput, hasWrittenVideo, audioInput.isReadyForMoreMediaData {
            let correctedTimestamp = convertTimestamp(for: sampleBuffer)
            CMSampleBufferSetOutputPresentationTimeStamp(sampleBuffer, newValue: correctedTimestamp)
            audioInput.append(sampleBuffer)
        }

        let currentTimestamp = sampleBuffer.presentationTimeStamp
        let currentTime = Double(currentTimestamp.value) / Double(currentTimestamp.timescale)
        sessionQueue.async { [weak self] in
            self?.videoDuration = currentTime - (self?.videoRecordingStartTime ?? currentTime)
        }
    }

    private func convertTimestamp(for buffer: CMSampleBuffer) -> CMTime {
        // since we use a seperate capture session for audio, we need to synchronize their clocks.
        let clock: CMClock?
        if #available(iOS 15.4, *) {
            clock = session.synchronizationClock
        } else {
            clock = session.masterClock
        }

        let timestamp = buffer.presentationTimeStamp
        if let clock = clock {
            return clock.convertTime(timestamp, to: clock)
        }

        return timestamp
    }
}

// MARK: - monitoring multi-cam system pressure

extension CameraSessionManager {
    /// Checks and adjusts the performance cost of running a multi-cam session.
    ///
    /// We want to keep the session's `hardwareCost` and `systemPressureCost` values between 0 and 1.
    /// This method is called prior to the session starting, and will recursively lower frame rate and
    /// resolution if the pressure values are too high.
    private func checkMultiCamPerformanceCost() {
        guard
            isUsingMultipleCameras,
            let backInput, let frontInput,
            let session = session as? AVCaptureMultiCamSession
        else {
            return
        }

        let exceededHardwareCost = session.hardwareCost > 1
        let exceededSystemCost = session.systemPressureCost > 1
        DDLogInfo("CameraModel/checkMultiCamPerformanceCost/hardware: [\(session.hardwareCost)] system: [\(session.systemPressureCost)]")

        if exceededSystemCost || exceededHardwareCost {
            // prioritize changing frame rate since we're only taking photos
            if reduceFrameRate(for: backInput) {
                checkMultiCamPerformanceCost()
            } else if reduceFrameRate(for: frontInput) {
                checkMultiCamPerformanceCost()

            } else if binVideo(for: backInput) {
                checkMultiCamPerformanceCost()
            } else if binVideo(for: frontInput) {
                checkMultiCamPerformanceCost()

            } else if reduceResolution(for: backInput) {
                checkMultiCamPerformanceCost()
            } else if reduceResolution(for: frontInput) {
                checkMultiCamPerformanceCost()

            } else {
                DDLogInfo("CameraModel/checkMultiCamPerformanceCost/unable to further reduce costs")
            }
        }
    }

    private func reduceFrameRate(for input: AVCaptureDeviceInput) -> Bool {
        let minFrameDuration = input.device.activeVideoMinFrameDuration
        var activeMaxFrameRate: Double = Double(minFrameDuration.timescale) / Double(minFrameDuration.value)

        DDLogInfo("CameraModel/reduceFrameRate/current: [\(activeMaxFrameRate)]")
        activeMaxFrameRate -= 5

        if activeMaxFrameRate >= 15 {
            configure(input.device) { camera in
                input.videoMinFrameDurationOverride = CMTimeMake(value: 1, timescale: Int32(activeMaxFrameRate))
            }

            DDLogInfo("CameraModel/reduceFrameRate/reduced to \(activeMaxFrameRate)")
            return true
        }

        return false
    }

    private func reduceResolution(for input: AVCaptureDeviceInput) -> Bool {
        let formats = input.device.formats
        let activeFormat = input.device.activeFormat
        let dimensions = CMVideoFormatDescriptionGetDimensions(activeFormat.formatDescription)
        let currentWidth = dimensions.width
        let currentHeight = dimensions.height

        guard
            currentWidth > 640 || currentHeight > 480,
            let index = formats.firstIndex(of: activeFormat)
        else {
            return false
        }

        for index in (0..<index).reversed() {
            let format = formats[index]
            guard format.isMultiCamSupported else { continue }

            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            if dimensions.width < currentWidth || dimensions.height < currentHeight {
                configure(input.device) { camera in
                    camera.activeFormat = format
                }

                DDLogInfo("CameraModel/reduceResolution/reduced to width: [\(dimensions.width)] height: [\(dimensions.height)]")
                return true
            }
        }

        return false
    }

    private func binVideo(for input: AVCaptureDeviceInput) -> Bool {
        let formats = input.device.formats
        let activeFormat = input.device.activeFormat

        guard !activeFormat.isVideoBinned, let index = formats.firstIndex(of: activeFormat) else {
            return false
        }

        for index in (0..<index).reversed() {
            let format = formats[index]
            guard format.isMultiCamSupported, format.isVideoBinned else { continue }

            configure(input.device) { camera in
                camera.activeFormat = format
            }

            DDLogInfo("CameraModel/binVideo/changed to binned format")
            return true
        }

        return false
    }
}

extension AVCaptureDevice {

    static func permissions(for type: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: type)
        case .denied,
             .restricted:
            return false
        @unknown default:
            DDLogError("AVCaptureDevice/permissions for \(type)/unknown AVAuthorizationStatus")
            return false
        }
    }

    var preferredMulticamFormat: Format? {
        formats
            .filter {
                if #available(iOS 15, *), position == .front {
                    return $0.isMultiCamSupported && $0.isPortraitEffectSupported && !$0.isVideoBinned
                }

                return $0.isMultiCamSupported && !$0.isVideoBinned
            }
            .first {
                let dim = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
                return dim.width >= 1200 || dim.height >= 1000
            }
    }
}

extension AVCapturePhoto {

    var uiImage: UIImage? {
        guard let data = fileDataRepresentation() else {
            return nil
        }

        return UIImage(data: data)
    }
}