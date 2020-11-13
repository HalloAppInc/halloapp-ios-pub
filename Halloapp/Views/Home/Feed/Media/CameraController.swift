//
//  CameraController.swift
//  HalloApp
//
//  Created by Vasil Lyutskanov on 24.08.20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Core
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
            return NSLocalizedString("camera.init.error.1", value: "Cannot initialize the back camera", comment: "")
        case .initFailureFrontCamera:
            return NSLocalizedString("camera.init.error.2", value: "Cannot initialize the front camera", comment: "")
        case .initFailureMicrophone:
            return NSLocalizedString("camera.init.error.3", value: "Cannot initialize the microphone", comment: "")
        case .cannotAddBackInput:
            return NSLocalizedString("camera.init.error.4", value: "Cannot access back camera input", comment: "")
        case .cannotAddFrontInput:
            return NSLocalizedString("camera.init.error.5", value: "Cannot access front camera input", comment: "")
        case .cannotAddAudioInput:
            return NSLocalizedString("camera.init.error.6", value: "Cannot access audio input", comment: "")
        case .cannotAddPhotoOutput:
            return NSLocalizedString("camera.init.error.7", value: "Cannot capture photos", comment: "")
        case .cannotAddMovieOutput:
            return NSLocalizedString("camera.init.error.8", value: "Cannot capture movies", comment: "")
        }
    }
}

private extension Localizations {

    static var cameraAccessPrompt: String {
        NSLocalizedString("media.camera.access.request",
                          value: "HalloApp does not have access to your camera. To enable access, tap Settings and turn on Camera",
                          comment: "Alert asking to enable Camera permission after attempting to use in-app camera.")
    }

    static var microphoneAccessPromptTitle: String {
        NSLocalizedString("media.mic.access.request.title",
                          value: "Want Videos with Sound?",
                          comment: "Alert asking to enable Microphone permission after attempting to use in-app camera.")
    }

    static var microphoneAccessPromptBody: String {
        NSLocalizedString("media.mic.access.request.body",
                          value: "To record videos with sound, HalloApp needs microphone access. To enable access, tap Settings and turn on Microphone.",
                          comment: "Alert asking to enable Camera permission after attempting to use in-app camera.")

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
                    if (self.previewLayer == nil) {
                        DDLogInfo("CameraController/startCaptureSession create preview layer")
                        self.previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
                    }
                    DDLogInfo("CameraController/startCaptureSession attach preview layer")
                    self.view.layer.addSublayer(self.previewLayer!)
                    self.previewLayer!.frame = self.view.layer.frame
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

    private func showPermissionDeniedAlert(title: String, message: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel, handler: { [weak self] _ in
            self?.cameraDelegate.goBack()
        }))
        alert.addAction(UIAlertAction(title: Localizations.settingsAppName, style: .default, handler: { [weak self] _ in
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
            self?.cameraDelegate.goBack()
        }))
        present(alert, animated: true)
    }

    private func showCaptureSessionSetupErrorAlert(error: Error) {
        let title = NSLocalizedString("camera.init.error.title", value: "Initialization Error", comment: "Title for a popup alerting about camera initialization error.")
        let message = (error as? CameraInitError)?.localizedDescription
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: { [weak self] _ in
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
                self.showPermissionDeniedAlert(title: Localizations.cameraAccessPrompt, message: nil)
            }
        }
    }

    private func checkAudioPermissions() {
        CameraController.checkCapturePermissions(type: .audio) { [weak self] audioGranted in
            guard let self = self else { return }

            if audioGranted {
                self.setupAndStartCaptureSession()
            } else {
                self.showPermissionDeniedAlert(title: Localizations.microphoneAccessPromptTitle,
                                               message: Localizations.microphoneAccessPromptBody)
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
        guard let connection = output.connection(with: .video) else { return }

        if connection.isVideoOrientationSupported {
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
                connection.videoOrientation = .portrait
            }
        }
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = !isUsingBackCamera
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
        guard let captureSession = captureSession,
            let photoOutput = photoOutput,
            let movieOutput = movieOutput else { return }

        if self.orientation != orientation {
            self.orientation = orientation
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

    public func takePhoto(useFlashlight: Bool) {
        guard let photoOutput = photoOutput else { return }

        DDLogInfo("CameraController/takePhoto")
        let photoSettings = AVCapturePhotoSettings.init(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        photoSettings.flashMode = useFlashlight ? .on : .off
        photoSettings.isHighResolutionPhotoEnabled = false

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
