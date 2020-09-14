//
//  CameraController.swift
//  HalloApp
//
//  Created by Vasil Lyutskanov on 24.08.20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import UIKit
import AVFoundation

protocol CameraDelegate: AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    func goBack() -> Void
}

enum CameraInitError: Error, LocalizedError {
    case initFailureBackCamera
    case initFailureFrontCamera
    case initFailureMicrophone

    case cannotAddBackInput
    case cannotAddFrontInput
    case cannotAddAudioInput

    case cannotAddPhotoOutput
    case cannotAddMovieOutput

    var errorDescription: String? {
        switch self {
        case .initFailureBackCamera:
            return NSLocalizedString("Cannot initialize the back camera", comment: "")
        case .initFailureFrontCamera:
            return NSLocalizedString("Cannot initialize the front camera", comment: "")
        case .initFailureMicrophone:
            return NSLocalizedString("Cannot initialize the microphone", comment: "")
        case .cannotAddBackInput:
            return NSLocalizedString("Cannot acess back camera input", comment: "")
        case .cannotAddFrontInput:
            return NSLocalizedString("Cannot acess front camera input", comment: "")
        case .cannotAddAudioInput:
            return NSLocalizedString("Cannot acess audio input", comment: "")
        case .cannotAddPhotoOutput:
            return NSLocalizedString("Cannot capture photos", comment: "")
        case .cannotAddMovieOutput:
            return NSLocalizedString("Cannot capture movies", comment: "")
        }
    }
}

class CameraController: UIViewController {
    private static let maxVideoTimespan = DispatchTimeInterval.seconds(60)

    private let cameraDelegate: CameraDelegate

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    private var backCamera: AVCaptureDevice?
    private var frontCamera: AVCaptureDevice?
    private var microphone: AVCaptureDevice?

    private var backInput: AVCaptureInput?
    private var frontInput: AVCaptureInput?
    private var audioInput: AVCaptureInput?

    private var photoOutput: AVCapturePhotoOutput?
    private var movieOutput: AVCaptureMovieFileOutput?

    private(set) var orientation: UIDeviceOrientation
    private var videoTimeout: DispatchWorkItem?
    private(set) var isRecordingMovie =  false
    private(set) var isUsingBackCamera = true

    private static func checkCapturePermissions(type: AVMediaType, permissionHandler: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized:
            permissionHandler(true)

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: type) { granted in
                DispatchQueue.main.async {
                    permissionHandler(granted)
                }
            }

        case .denied,
             .restricted:
            permissionHandler(false)

        @unknown default:
            DDLogError("CameraController/checkCapturePermissions unknown AVAuthorizationStatus")
            permissionHandler(false)
        }
    }

    init(cameraDelegate: CameraDelegate, orientation: UIDeviceOrientation) {
        self.cameraDelegate = cameraDelegate
        self.orientation = orientation
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(cameraDelegate:)")
    }

    deinit {
        DDLogInfo("CameraController/deinit")
        guard let captureSession = captureSession else { return }
        teardownCaptureSession(captureSession)
    }

    override func viewDidLoad() {
        DDLogInfo("CameraController/viewDidLoad")
        super.viewDidLoad()
        view.layer.cornerRadius = 15
        view.layer.masksToBounds = true
    }

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("CameraController/viewWillAppear")
        super.viewWillAppear(animated)
        if captureSession == nil {
            checkVideoPermissions()
        } else {
            startCaptureSession()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        DDLogInfo("CameraController/viewWillDisappear")
        super.viewWillDisappear(animated)
        stopCaptureSession()
    }

    private func startCaptureSession() {
        guard let captureSession = captureSession else { return }
        DispatchQueue.global(qos: .userInitiated).async{
            if !captureSession.isRunning {
                DDLogInfo("CameraController/startCaptureSession startRunning")
                captureSession.startRunning()

                DispatchQueue.main.async {
                    guard let previewLayer = self.previewLayer else { return }
                    DDLogInfo("CameraController/startCaptureSession attach preview layer")
                    self.view.layer.addSublayer(previewLayer)
                    previewLayer.frame = self.view.layer.frame
                }
            }
        }
    }

    private func stopCaptureSession() {
        DDLogInfo("CameraController/stopCaptureSession detach preview layer")
        previewLayer?.removeFromSuperlayer()
        guard let captureSession = captureSession else { return }
        DispatchQueue.global(qos: .userInitiated).async{
            if captureSession.isRunning {
                DDLogInfo("CameraController/stopCaptureSession stopRunning")
                captureSession.stopRunning()
            }
        }
    }

    private func showPermissionDeniedAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak self] _ in
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
            self?.cameraDelegate.goBack()
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { [weak self] _ in
            self?.cameraDelegate.goBack()
        }))
        present(alert, animated: true)
    }

    private func showCaptureSessionSetupErrorAlert(error: Error) {
        let message = (error as? CameraInitError)?.localizedDescription
        let alert = UIAlertController(title: "Initialization Error", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak self] _ in
            self?.cameraDelegate.goBack()
        }))
        present(alert, animated: true)
    }

    private func checkVideoPermissions() {
        CameraController.checkCapturePermissions(type: .video) { [weak self] videoGranted in
            guard let self = self else { return }

            if videoGranted {
                self.checkAudioPermissions()
            } else {
                self.showPermissionDeniedAlert(title: "Camera Access Denied", message: "Please grant Camera access from Settings")
            }
        }
    }

    private func checkAudioPermissions() {
        CameraController.checkCapturePermissions(type: .audio) { [weak self] audioGranted in
            guard let self = self else { return }

            if audioGranted {
                self.setupAndStartCaptureSession()
            } else {
                self.showPermissionDeniedAlert(title: "Microphone Access Denied", message: "Please grant Microphone access from Settings")
            }
        }
    }

    private func setupAndStartCaptureSession() {
        DDLogInfo("CameraController/setupAndStartCaptureSession")
        let session = AVCaptureSession()
        session.beginConfiguration()

        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        }
        session.automaticallyConfiguresCaptureDeviceForWideColor = true

        do {
            try setupInput(session)
            try setupOutput(session)
        } catch {
            DDLogError("CameraController/setupAndStartCaptureSession: \(error)")
            self.showCaptureSessionSetupErrorAlert(error: error)
        }

        session.commitConfiguration()
        self.captureSession = session
        previewLayer = AVCaptureVideoPreviewLayer(session: session)

        startCaptureSession()
    }

    private func teardownCaptureSession(_ session: AVCaptureSession) {
        DDLogInfo("CameraController/stopAndTeardownCaptureSession")
        session.beginConfiguration()
        if audioInput != nil {
            session.removeInput(audioInput!)
        }
        let cameraInput = isUsingBackCamera ? backInput : frontInput
        if cameraInput != nil {
            session.removeInput(cameraInput!)
        }
        if photoOutput != nil {
            session.removeOutput(photoOutput!)
        }
        if movieOutput != nil {
            session.removeOutput(movieOutput!)
        }
        session.commitConfiguration()
    }

    private func configureVideoOutput(_ output: AVCaptureOutput) {
        let connection = output.connection(with: .video)
        // NOTE(VL): Do we need to support .landscapeLeft or .portraitUpsideDown?
        // Discuss and change if needed.
        if connection?.isVideoOrientationSupported ?? false {
            connection?.videoOrientation = orientation.isLandscape ? .landscapeRight : .portrait
        }
        if connection?.isVideoMirroringSupported ?? false {
            connection?.isVideoMirrored = !isUsingBackCamera
        }
    }

    private func setFocusAndExposure(camera: AVCaptureDevice, point: CGPoint? = nil) {
        do {
            try camera.lockForConfiguration()
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if point != nil && camera.isFocusPointOfInterestSupported {
                camera.focusMode = .autoFocus
                camera.focusPointOfInterest = point!
            }
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            if point != nil && camera.isExposurePointOfInterestSupported {
                camera.exposureMode = .autoExpose
                camera.exposurePointOfInterest = point!
            }
            camera.unlockForConfiguration()
        } catch {
            DDLogError("CameraController/focusCameraOnPoint \(error)")
        }
    }
    
    private func setupInput(_ session: AVCaptureSession) throws {
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            backCamera = device
            setFocusAndExposure(camera: backCamera!)
        } else {
            throw CameraInitError.initFailureBackCamera
        }

        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            frontCamera = device
            setFocusAndExposure(camera: frontCamera!)
        } else {
            throw CameraInitError.initFailureFrontCamera
        }

        if let device = AVCaptureDevice.default(.builtInMicrophone, for: AVMediaType.audio, position: .unspecified) {
            microphone = device
        } else {
            throw CameraInitError.initFailureMicrophone
        }

        try backInput = AVCaptureDeviceInput(device: backCamera!)
        if !session.canAddInput(backInput!) {
            throw CameraInitError.cannotAddBackInput
        }

        try frontInput = AVCaptureDeviceInput(device: frontCamera!)
        if !session.canAddInput(frontInput!) {
            throw CameraInitError.cannotAddFrontInput
        }

        try audioInput = AVCaptureDeviceInput(device: microphone!)
        if !session.canAddInput(audioInput!) {
            throw CameraInitError.cannotAddAudioInput
        }

        session.addInput(isUsingBackCamera ? backInput! : frontInput!)
        session.addInput(audioInput!)
    }

    private func setupOutput(_ session: AVCaptureSession) throws {
        let photoCaptureOutput = AVCapturePhotoOutput()
        if session.canAddOutput(photoCaptureOutput) {
            session.addOutput(photoCaptureOutput)
        } else {
            throw CameraInitError.cannotAddPhotoOutput
        }
        configureVideoOutput(photoCaptureOutput)
        photoOutput = photoCaptureOutput

        let movieCaptureOutput = AVCaptureMovieFileOutput()
        if session.canAddOutput(movieCaptureOutput) {
            session.addOutput(movieCaptureOutput)
        } else {
            throw CameraInitError.cannotAddMovieOutput
        }
        configureVideoOutput(movieCaptureOutput)
        movieOutput = movieCaptureOutput
    }

    private func setVideoTimeout() {
        clearVieoTimeout()
        videoTimeout = DispatchWorkItem { [weak self] in self?.stopRecordingVideo() }
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + CameraController.maxVideoTimespan, execute: videoTimeout!)
    }

    private func clearVieoTimeout() {
        videoTimeout?.cancel()
        videoTimeout = nil
    }

    public func setOrientation(_ orientation: UIDeviceOrientation) {
        let didOrientationChange = self.orientation.isLandscape != orientation.isLandscape
        self.orientation = orientation

        guard let captureSession = captureSession,
            let photoOutput = photoOutput,
            let movieOutput = movieOutput else { return }

        if didOrientationChange {
            DDLogInfo("CameraController/setOrientation didOrientationChange")
            captureSession.beginConfiguration()
            configureVideoOutput(photoOutput)
            configureVideoOutput(movieOutput)
            captureSession.commitConfiguration()
        }
    }

    public func switchCamera(_ useBackCamera: Bool) {
        guard let captureSession = captureSession,
            let backInput = backInput,
            let frontInput = frontInput,
            let photoOutput = photoOutput,
            let movieOutput = movieOutput else { return }

        if useBackCamera != isUsingBackCamera {
            DDLogInfo("CameraController/switchCamera")
            captureSession.beginConfiguration()

            captureSession.removeInput(isUsingBackCamera ? backInput : frontInput)
            captureSession.addInput(isUsingBackCamera ? frontInput : backInput)
            isUsingBackCamera = !isUsingBackCamera

            configureVideoOutput(photoOutput)
            configureVideoOutput(movieOutput)

            captureSession.commitConfiguration()
        }
    }

    public func focusOnPoint(_ point: CGPoint) {
        guard let backCamera = backCamera,
            let frontCamera = frontCamera,
            let previewLayer = previewLayer else { return }

        let convertedPoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        DDLogInfo("CameraController/focusOnPoint \(convertedPoint)")
        setFocusAndExposure(camera: isUsingBackCamera ? backCamera : frontCamera, point: convertedPoint)
    }

    public func takePhoto(_ useFlashlight: Bool) {
        guard let photoOutput = photoOutput else { return }

        DDLogInfo("CameraController/takePhoto")
        let photoSettings = AVCapturePhotoSettings()
        photoSettings.flashMode = useFlashlight ? .auto : .off
        photoOutput.capturePhoto(with: photoSettings, delegate: cameraDelegate)
    }

    public func startRecordingVideo(_ to: URL) {
        guard let movieOutput = movieOutput else { return }

        if !isRecordingMovie {
            isRecordingMovie = true
            DDLogInfo("CameraController/startRecordingVideo")
            AudioServicesPlaySystemSound(1117)
            movieOutput.startRecording(to: to, recordingDelegate: cameraDelegate)
            setVideoTimeout()
        }
    }

    public func stopRecordingVideo() {
        guard let movieOutput = movieOutput else { return }

        clearVieoTimeout()
        if isRecordingMovie {
            isRecordingMovie = false
            DDLogInfo("CameraController/stopRecordingVideo")
            movieOutput.stopRecording()
            AudioServicesPlaySystemSound(1118)
        }
    }
}
