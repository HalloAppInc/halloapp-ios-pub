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

    enum Error: Swift.Error {
        case permissions(AVMediaType)
        case cameraInitialization(AVCaptureDevice.Position)
        case outputInitialization

        var description: String? {
            switch self {
            case .permissions(let format) where format == .video:
                break
            case .permissions(let format) where format == .audio:
                break
            case .cameraInitialization(let side) where side == .back:
                return NSLocalizedString("camera.init.error.1", value: "Cannot initialize the back camera", comment: "")
            case .cameraInitialization(let side) where side == .front:
                return NSLocalizedString("camera.init.error.5", value: "Cannot access front camera", comment: "")
            case .outputInitialization:
                break
            default:
                break
            }

            return nil
        }
    }
}

///
class CameraModel {
    /// Used to coordinate the actual zoom value of the camera with what's being displayed to the user.
    private typealias ZoomFactor = (ui: CGFloat, actual: CGFloat)

    weak var delegate: CameraModelDelegate?

    private(set) lazy var session: AVCaptureSession = {
        let session = AVCaptureSession()
        session.automaticallyConfiguresCaptureDeviceForWideColor = true
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

    private var photoOutput: AVCapturePhotoOutput?

    /// Maps each hardware camera to it's zoom values.
    private var zoomFactors: [AVCaptureDevice.DeviceType: ZoomFactor] = [:]
    private var hasUltraWideCamera = false
    private var maxZoomFactor: CGFloat = 1

// MARK: - published properties

    @Published private(set) var zoomFactor: CGFloat = 1
    @Published private(set) var orientation = UIDevice.current.orientation
    @Published private(set) var activeCamera = AVCaptureDevice.Position.back
    @Published private(set) var isFlashEnabled = false

    private var cancellables: Set<AnyCancellable> = []

    init() {
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
        let hasVideoPermissions = await hasPermissions(for: .video)
        let hasAudioPermissions = await hasPermissions(for: .audio)
        guard hasVideoPermissions, hasAudioPermissions else {
            throw Error.permissions(hasVideoPermissions ? .audio : .video)
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
            throw Error.cameraInitialization(.back)
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
            throw Error.cameraInitialization(.front)
        }

        frontCamera = device
        frontInput = input
        focus(camera: device)
    }

    private func setupMicrophone() throws {
        // TODO:
    }

    private func setupPhotoOutput() throws {
        let output = AVCapturePhotoOutput()
        guard session.canAddOutput(output) else {
            throw Error.outputInitialization
        }

        session.addOutput(output)
        photoOutput = output
        updatePhoto(orientation: orientation)
    }

    private func setupVideoOutput() throws {
        // TODO:
    }

    private func stopCaptureSession() async {
        stopListeningForOrientation()
        await perform { [session] in
            session.stopRunning()
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }
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

    func toggleFlash() {
        isFlashEnabled = !isFlashEnabled
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
