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
    @MainActor func modelCoultNotStart(_ model: CameraModel, with error: Error)
    /// This method is called just before the session's `startRunning()` method is called.
    /// It's a good place to attach a preview layer to the session.
    @MainActor func modelWillStart(_ model: CameraModel)
    @MainActor func modelDidStart(_ model: CameraModel)

    @MainActor func model(_ model: CameraModel, didTake photo: UIImage)
    @MainActor func model(_ model: CameraModel, didRecordVideoTo url: URL, error: Error?)
}

extension CameraModel {
    /// All possible devices that we check for.
    ///
    /// - note: Order matters.
    private static var queryDevices: [AVCaptureDevice.DeviceType] {
        [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera,
            .builtInTelephotoCamera,
            .builtInUltraWideCamera,
        ]
    }

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
}

///
class CameraModel: NSObject {
    /// Used to coordinate the actual zoom value of the camera with what's being displayed to the user.
    private typealias ZoomFactor = (ui: CGFloat, actual: CGFloat)

    weak var delegate: CameraModelDelegate?

    private(set) lazy var session: AVCaptureSession = {
        let session = AVCaptureSession()
        session.automaticallyConfiguresCaptureDeviceForWideColor = true
        return session
    }()

    /// For capturing audio during video recording.
    ///
    /// We use a seperate session for audio for a couple of reasons:
    /// 1. Prevent the orange status bar dot from appearing when there is no recording taking place
    /// 2. Only pause the user's audio if they're recording video. Adding the input to the main capture
    ///    session at record time causes a stutter in the preview.
    private(set) lazy var audioSession: AVCaptureSession = {
        let session = AVCaptureSession()
        return session
    }()

    private lazy var sessionQueue = DispatchQueue(label: "camera.queue", qos: .userInteractive)

    private lazy var motionManager: CMMotionManager = {
        let manager = CMMotionManager()
        manager.deviceMotionUpdateInterval = 0.5
        return manager
    }()

    private lazy var motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    private var backCamera: AVCaptureDevice?
    private var frontCamera: AVCaptureDevice?
    private var microphone: AVCaptureDevice?

    private var backInput: AVCaptureDeviceInput?
    private var frontInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?

    private var photoOutput: AVCapturePhotoOutput?

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

    /// Maps each hardware camera to it's zoom values.
    private var zoomFactors: [AVCaptureDevice.DeviceType: ZoomFactor] = [:]
    private var hasUltraWideCamera = false
    private var maxZoomFactor: CGFloat = 1

// MARK: - published properties

    @Published private(set) var zoomFactor: CGFloat = 1
    @Published private(set) var orientation = UIDevice.current.orientation
    @Published private(set) var activeCamera = AVCaptureDevice.Position.back
    @Published var isFlashEnabled = false

    @Published private(set) var isTakingPhoto = false
    @Published private(set) var isRecordingVideo = false

    @Published private(set) var videoDuration: Int?
    private var videoDurationTimer: AnyCancellable?

    private var cancellables: Set<AnyCancellable> = []

    override init() {
        super.init()

        $orientation.receive(on: sessionQueue).sink { [weak self] orientation in
            self?.updatePhoto(orientation: orientation)
        }.store(in: &cancellables)
    }

    private func updatePhoto(orientation: UIDeviceOrientation) {
        guard
            let connection = photoOutput?.connection(with: .video),
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
        Task { await setupAndStartSession() }
    }

    func stop() {
        Task { await stopCaptureSession() }
    }

    private func setupAndStartSession() async {
        do {
            try await setupSession()
            await startSession()
        } catch {
            await delegate?.modelCoultNotStart(self, with: error)
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

            try self?.setupInputs()
            try self?.setupPhotoOutput()
            try self?.setupVideoOutput()
        }
    }

    private func startSession() async {
        await delegate?.modelWillStart(self)
        await perform { [weak self] in
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

        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        }

        if let input = backInput {
            session.addInput(input)
        }

        if let input = audioInput {
            audioSession.addInput(input)
        }
    }

    private func setupBackCamera() throws {
        /*
         I've noticed that performing a discovery session adds a noticeable amount of time to camera start up.
         Will revisit this and perform some benchmarks to get a better idea. For now we'll just use the default wide-angle.
         */
        //let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: Self.queryDevices, mediaType: .video, position: .back)
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
        //mapZoomValues(for: discovery.devices)
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

        session.addOutput(output)
        photoOutput = output
        updatePhoto(orientation: orientation)
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

    private func stopCaptureSession() async {
        stopListeningForOrientation()
        await perform { [session, audioSession] in
            session.stopRunning()
            audioSession.stopRunning()

            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }

            audioSession.inputs.forEach { audioSession.removeInput($0) }
            audioSession.outputs.forEach { audioSession.removeOutput($0) }
        }
    }

    /// Maps each hardware camera to its logical and UI zoom value.
    ///
    /// - note: 1.0 is the lowest possible logical value, and is the default wide-angle camera unless there is
    ///         an ultra-wide angle camera present.
    private func mapZoomValues(for devices: [AVCaptureDevice]) {
        let switchOverPoints = backCamera?.virtualDeviceSwitchOverVideoZoomFactors ?? []
        let hasUltraWide = devices.contains { $0.deviceType == .builtInUltraWideCamera }
        let multiplier: CGFloat = hasUltraWide ? 0.5 : 1.0
        var zoomFactors = [AVCaptureDevice.DeviceType: ZoomFactor]()

        for device in devices {
            let camera = device.deviceType

            switch camera {
            case .builtInUltraWideCamera:
                zoomFactors[camera] = (0.5, 1.0)
            case .builtInWideAngleCamera:
                let hasMultipleCameras = switchOverPoints.count > 1
                let actualZoomValue = (hasMultipleCameras && hasUltraWide) ? switchOverPoints[1] : 1.0
                zoomFactors[camera] = (1.0, CGFloat(truncating: actualZoomValue))
            case .builtInTelephotoCamera:
                if let actualTelephotoZoomValue = switchOverPoints.last {
                    let converted = CGFloat(truncating: actualTelephotoZoomValue)
                    zoomFactors[camera] = (converted * multiplier, converted)
                }
            default:
                break
            }
        }

        let max = zoomFactors.values.max { $0.ui < $1.ui }
        maxZoomFactor = ((max?.ui ?? 1) * 5) / multiplier

        self.zoomFactors = zoomFactors
        hasUltraWideCamera = hasUltraWide
    }
}

// MARK: - listening for device orientation

extension CameraModel {
    private func startListeningForOrientation() {
        motionQueue.isSuspended = false
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] data, _ in
            guard
                let self = self,
                let data = data
            else {
                return
            }

            self.orientation = self.orientation(from: data)
        }
    }

    private func stopListeningForOrientation() {
        motionQueue.isSuspended = true
        motionManager.stopDeviceMotionUpdates()
    }

    private func orientation(from data: CMDeviceMotion) -> UIDeviceOrientation {
        let gravity = data.gravity
        let threshold = 0.75

        if gravity.x >= threshold {
            return .landscapeRight
        }
        if gravity.x <= -threshold {
            return .landscapeLeft
        }
        if gravity.y <= -threshold {
            return .portrait
        }
        if gravity.y >= threshold {
            return .portraitUpsideDown
        }

        // same as before
        return orientation
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
        await perform { [backInput, frontInput, session] in
            guard
                let currentCamera = side == .front ? backInput : frontInput,
                let flippedCamera = side == .front ? frontInput : backInput
            else {
                return
            }

            session.removeInput(currentCamera)
            session.addInput(flippedCamera)
        }
    }

    func focus(on point: CGPoint) {
        guard
            activeCamera != .unspecified,
            let camera = activeCamera == .back ? backCamera : frontCamera
        else {
            return
        }

        focus(camera: camera, on: point)
    }

    private func focus(camera: AVCaptureDevice, on point: CGPoint? = nil) {
        do {
            try camera.lockForConfiguration()
            defer { camera.unlockForConfiguration() }

            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if let point = point, camera.isFocusPointOfInterestSupported {
                camera.focusMode = .autoFocus
                camera.focusPointOfInterest = point
            }
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            if let point = point, camera.isExposurePointOfInterestSupported {
                camera.exposureMode = .autoExpose
                camera.exposurePointOfInterest = point
            }
        } catch {
            DDLogError("CameraModel/focus-camera-on-point/unable to focus \(String(describing: error))")
        }
    }

    func zoom(using gesture: UIPinchGestureRecognizer) {
        // TODO
    }
}

// MARK: - taking photos

extension CameraModel: AVCapturePhotoCaptureDelegate {
    ///
    func takePhoto() {
        guard let output = photoOutput else {
            return
        }

        isTakingPhoto = true

        let settings = AVCapturePhotoSettings.init(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        settings.flashMode = isFlashEnabled ? .on : .off
        settings.isHighResolutionPhotoEnabled = false

        output.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        isTakingPhoto = false
        if let error = error {
            DDLogError("CameraModel/finishedProcessingPhoto/received error \(String(describing: error))")
            return
        }

        guard
            let data = photo.fileDataRepresentation(),
            let image = UIImage(data: data)
        else {
            DDLogError("CameraModel/finishedProcessingPhoto/unable to create image from data")
            return
        }

        Task { await delegate?.model(self, didTake: image) }
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

        videoDurationTimer = Timer.publish(every: 1, on: .main, in: .default)
            .autoconnect()
            .scan(0) { seconds, _ in seconds + 1 }
            .sink { [weak self] in self?.videoDuration = $0 }
        videoDuration = 0
    }

    func stopRecording() {
        guard isRecordingVideo, let writer = assetWriter else {
            return
        }

        DDLogInfo("CameraModel/stopRecording")
        isRecordingVideo = false

        videoDurationTimer = nil
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
    /**

     */
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
}
