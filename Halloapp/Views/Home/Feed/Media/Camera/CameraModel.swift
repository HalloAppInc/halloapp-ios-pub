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

protocol CameraModelDelegate: AnyObject {
    @MainActor func modelCouldNotStart(_ model: CameraModel, with error: Error)
    /// This method is called just before the session's `startRunning()` method is called.
    /// It's a good place to attach a preview layer to the session.
    @MainActor func modelWillStart(_ model: CameraModel)
    @MainActor func modelDidStart(_ model: CameraModel)
    @MainActor func modelDidStop(_ model: CameraModel)
    @MainActor func model(_ model: CameraModel, didRecordVideoTo url: URL, error: Error?)
}

extension CameraModel {

    enum CameraModelError: Swift.Error {
        case permissions(AVMediaType)
        case cameraInitialization(AVCaptureDevice.Position)
        case microphoneInitialization
        case photoOutput
        case videoOutput
        case audioOutput

        var description: String? {
            switch self {
            case .permissions(let format) where format == .video:
                break
            case .permissions(let format) where format == .audio:
                break
            case .cameraInitialization(let side) where side == .back:
                return NSLocalizedString("camera.init.error.1", value: "Cannot initialize the back camera", comment: "")
            case .cameraInitialization(let side) where side == .front:
                return NSLocalizedString("camera.init.error.2", value: "Cannot initialize the front camera", comment: "")
            case .microphoneInitialization:
                return NSLocalizedString("camera.init.error.3", value: "Cannot initialize the microphone", comment: "")
            case .photoOutput:
                return NSLocalizedString("camera.init.error.7", value: "Cannot capture photos", comment: "")
            case .videoOutput:
                return NSLocalizedString("camera.init.error.8", value: "Cannot record video", comment: "")
            case .audioOutput:
                return NSLocalizedString("camera.init.error.9", value: "Cannot record audio", comment: "")
            default:
                break
            }

            return nil
        }
    }

    struct Options: OptionSet {
        let rawValue: Int

        static let monitorOrientation = Options(rawValue: 1 << 0)
        static let multicam = Options(rawValue: 1 << 1)
    }
}

///
class CameraModel: NSObject {

    private let options: Options
    weak var delegate: CameraModelDelegate?

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

    @Published private(set) var orientation: UIDeviceOrientation = .portrait
    @Published private(set) var activeCamera = AVCaptureDevice.Position.unspecified
    @Published var isFlashEnabled = false

    @Published private(set) var isTakingPhoto = false
    @Published private(set) var isRecordingVideo = false

    @Published private(set) var videoDuration: TimeInterval?
    private var videoRecordingStartTime: TimeInterval?

    private var cancellables: Set<AnyCancellable> = []
    private var orientationTask: Task<Void, Never>?

    init(options: Options) {
        self.options = options
        isUsingMultipleCameras = AVCaptureMultiCamSession.isMultiCamSupported && options.contains(.multicam)
        session = isUsingMultipleCameras ? AVCaptureMultiCamSession() : AVCaptureSession()

        super.init()
        formSubscriptions()
    }

    private func formSubscriptions() {
        $orientation
            .receive(on: sessionQueue)
            .sink { [weak self] orientation in
                self?.updatePhoto(orientation: orientation)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVCaptureSessionRuntimeError)
            .receive(on: sessionQueue)
            .sink { notification in
                let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
                DDLogError("CameraModel/session-runtime-error [\(String(describing: error))]")
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .AVCaptureSessionDidStartRunning)
            .receive(on: sessionQueue)
            .sink { _ in
                DDLogInfo("CameraModel/session-did-start")
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

extension CameraModel {
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

extension CameraModel {

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
            await delegate?.modelCouldNotStart(self, with: error)
        }
    }

    private func setupSession() async throws {
        if await !hasPermissions(for: .video) {
            throw CameraModelError.permissions(.video)
        }

        if await !hasPermissions(for: .audio) {
            throw CameraModelError.permissions(.audio)
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
        await delegate?.modelWillStart(self)
        await perform { [weak self] in
            self?.setFormats()
            self?.session.startRunning()
        }

        startListeningForOrientation()
        await delegate?.modelDidStart(self)
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
                throw CameraModelError.cameraInitialization(.back)
            }
        }

        if let input = backInput, session.canAddInput(input), let port = input.ports.first, let output = primaryPhotoOutput {
            session.addInputWithNoConnections(input)

            let connection = AVCaptureConnection(inputPorts: [port], output: output)
            try addConnection(connection)
            activeCamera = .back
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
        guard let format = camera.optimalMulticamPhotoFormat else {
            DDLogError("CameraModel/unable to get optimal format for camera [\(camera.position)]")
            return
        }

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
            throw CameraModelError.cameraInitialization(.back)
        }

        backCamera = device
        backInput = input
        focus(camera: device)
    }

    private func setupFrontCamera() throws {
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            throw CameraModelError.cameraInitialization(.front)
        }

        frontCamera = device
        frontInput = input
        focus(camera: device)
    }

    private func setupMicrophone() throws {
        guard
            let device = AVCaptureDevice.default(.builtInMicrophone, for: .audio, position: .unspecified),
            let input = try? AVCaptureDeviceInput(device: device),
            audioSession.canAddInput(input)
        else {
            throw CameraModelError.cameraInitialization(.front)
        }

        microphone = device
        audioInput = input
    }

    private func setupPhotoOutput() throws {
        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else {
            throw CameraModelError.photoOutput
        }

        output.maxPhotoQualityPrioritization = .speed
        session.addOutputWithNoConnections(output)
        primaryPhotoOutput = output

        if isUsingMultipleCameras {
            try setupSecondPhotoOutput()
        }

        updatePhoto(orientation: orientation)
        updateVideoMirroring(for: activeCamera)
    }

    private func setupSecondPhotoOutput() throws {
        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else {
            throw CameraModelError.photoOutput
        }

        output.maxPhotoQualityPrioritization = .speed
        output.isDepthDataDeliveryEnabled = false
        output.isHighResolutionCaptureEnabled = false
        output.isPortraitEffectsMatteDeliveryEnabled = false
        session.addOutputWithNoConnections(output)
        secondaryPhotoOutput = output
    }

    private func setupVideoOutput() throws {
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            self.videoOutput = videoOutput
        } else {
            throw CameraModelError.videoOutput
        }

        let audioOutput = AVCaptureAudioDataOutput()
        audioOutput.setSampleBufferDelegate(self, queue: videoQueue)

        if audioSession.canAddOutput(audioOutput) {
            audioSession.addOutput(audioOutput)
            self.audioOuput = audioOutput
        } else {
            throw CameraModelError.audioOutput
        }
    }

    private func stopCaptureSession(teardown: Bool = true) async {
        stopListeningForOrientation()
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

        await delegate?.modelDidStop(self)
    }
}

// MARK: - listening for device orientation

extension CameraModel {

    private func startListeningForOrientation() {
        guard options.contains(.monitorOrientation) else {
            return
        }

        orientationTask?.cancel()
        orientationTask = Task(priority: .userInitiated) { [weak self] in
            for await orientation in CMDeviceMotion.orientations {
                self?.orientation = orientation
            }
        }
    }

    private func stopListeningForOrientation() {
        orientationTask?.cancel()
    }
}

// MARK: - changing the model's state

extension CameraModel {
    func flipCamera() {
        Task {
            guard activeCamera != .unspecified else {
                return
            }

            let side: AVCaptureDevice.Position = activeCamera == .back ? .front: .back
            activeCamera = .unspecified
            await flipCamera(to: side)
            activeCamera = side
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
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if camera.isFocusPointOfInterestSupported, let point = point {
                camera.focusMode = .autoFocus
                camera.focusPointOfInterest = point
            }
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            if camera.isExposurePointOfInterestSupported, let point = point {
                camera.exposureMode = .autoExpose
                camera.exposurePointOfInterest = point
            }
        }
    }

    func zoom(_ position: AVCaptureDevice.Position, to scale: CGFloat) {
        guard
            session.isRunning,
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

extension CameraModel: AVCapturePhotoCaptureDelegate {

    private var defaultPhotoSettings: AVCapturePhotoSettings {
        let settings = AVCapturePhotoSettings.init(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        settings.flashMode = isFlashEnabled ? .on : .off
        settings.isHighResolutionPhotoEnabled = false

        return settings
    }

    func takePhoto(captureType: CaptureRequest.CaptureType, progress: @escaping ([CaptureResult], Bool) -> Void) {
        guard !isTakingPhoto, captureType.primaryPosition != .unspecified else {
            return
        }

        let request = CaptureRequest(type: captureType,
                               isMultiCam: isUsingMultipleCameras,
                                 progress: progress)
        captureRequest = request
        isTakingPhoto = true

        if isUsingMultipleCameras {
            takeMultiCamPhoto(request)
        } else {
            takeSingleCamPhoto(request)
        }
    }

    private func takeMultiCamPhoto(_ request: CaptureRequest) {
        let s1 = defaultPhotoSettings
        var s2: AVCapturePhotoSettings?

        let output1 = request.type.primaryPosition == .back ? primaryPhotoOutput : secondaryPhotoOutput
        let output2 = output1 === primaryPhotoOutput ? secondaryPhotoOutput : primaryPhotoOutput

        request.set(settings: s1, for: request.type.primaryPosition)
        output1?.capturePhoto(with: s1, delegate: self)

        if case .both(_) = request.type, let opposite = request.type.primaryPosition.opposite {
            let settings = defaultPhotoSettings
            request.set(settings: settings, for: opposite)
            s2 = settings
        }

        if let s2 = s2 {
            output2?.capturePhoto(with: s2, delegate: self)
        }
    }

    private func takeSingleCamPhoto(_ request: CaptureRequest) {
        let settings = defaultPhotoSettings
        request.set(settings: settings, for: request.type.primaryPosition)

        if case .both(_) = request.type, let opposite = request.type.primaryPosition.opposite {
            let settings = defaultPhotoSettings
            request.set(settings: settings, for: opposite)
        }

        primaryPhotoOutput?.capturePhoto(with: settings, delegate: self)
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

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            DDLogError("CameraModel/finishedProcessingPhoto/received error \(String(describing: error))")
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
}

// MARK: - recording videos

extension CameraModel: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
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
            await writer.finishWriting()
            if let error = writer.error {
                DDLogError("CameraModel/stopRecording task/asset writer finished with error: \(String(describing: error))")
            }

            let viewError = writer.error == nil ? nil : CameraModelError.videoOutput
            await delegate?.model(self, didRecordVideoTo: writer.outputURL, error: viewError)
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

    var optimalMulticamPhotoFormat: Format? {
        formats
            .filter {
                if #available(iOS 15, *), position == .front {
                    return $0.isMultiCamSupported && $0.isPortraitEffectSupported
                }

                return $0.isMultiCamSupported
            }
            .max {
                $0.highResolutionStillImageDimensions.width * $0.highResolutionStillImageDimensions.height <
                $1.highResolutionStillImageDimensions.width * $1.highResolutionStillImageDimensions.height
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
