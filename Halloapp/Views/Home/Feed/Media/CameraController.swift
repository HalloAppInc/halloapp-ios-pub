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

    private var videoTimeout: DispatchWorkItem?
    private(set) var isRecordingMovie =  false
    private(set) var isUsingBackCamera = true

    private static func checkCapturePermissions(type: AVMediaType, permissionHandler: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized:
            permissionHandler(true)

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: type, completionHandler: permissionHandler)

        case .denied,
             .restricted:
            permissionHandler(false)

        @unknown default:
            DDLogError("CameraController/checkCapturePermissions unknown AVAuthorizationStatus")
            permissionHandler(false)
        }
    }

    init(cameraDelegate: CameraDelegate) {
        self.cameraDelegate = cameraDelegate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(cameraDelegate:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.layer.cornerRadius = 15
        view.layer.masksToBounds = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        checkVideoPermissions()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        previewLayer?.removeFromSuperlayer()
        captureSession?.stopRunning()
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

    private func setCapturePreviewLayer(_ session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        view.layer.addSublayer(previewLayer!)
        previewLayer!.frame = view.layer.frame
    }

    private func setupAndStartCaptureSession() {
        DispatchQueue.global(qos: .userInitiated).async{
            let session = AVCaptureSession()
            session.beginConfiguration()

            if session.canSetSessionPreset(.photo) {
                session.sessionPreset = .photo
            }
            session.automaticallyConfiguresCaptureDeviceForWideColor = true

            do {
                try self.setupInput(session)

                DispatchQueue.main.async {
                    self.setCapturePreviewLayer(session)
                }

                try self.setupOutput(session)

                session.commitConfiguration()
                session.startRunning()
                self.captureSession = session
            } catch {
                DDLogError("CameraController/setupAndStartCaptureSession: \(error)")

                DispatchQueue.main.async {
                    let message = (error as? CameraInitError)?.localizedDescription
                    let alert = UIAlertController(title: "Initialization Error", message: message, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak self] _ in
                        self?.cameraDelegate.goBack()
                    }))
                    self.present(alert, animated: true)
                }
            }
        }
    }

    private func configureVideoOutput(_ output: AVCaptureOutput) {
        let connection = output.connection(with: .video)
        connection?.videoOrientation = .portrait
        connection?.isVideoMirrored = !isUsingBackCamera
    }

    private func setFocusAndExposure(camera: AVCaptureDevice, point: CGPoint = CGPoint(x: 0.5, y: 0.5)) {
        do {
            try camera.lockForConfiguration()
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if camera.isFocusPointOfInterestSupported {
                camera.focusMode = .autoFocus
                camera.focusPointOfInterest = point
            }
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            if camera.isExposurePointOfInterestSupported {
                camera.exposureMode = .autoExpose
                camera.exposurePointOfInterest = point
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

    public func switchCamera(_ useBackCamera: Bool) {
        guard let captureSession = captureSession,
            let backInput = backInput,
            let frontInput = frontInput else { return }

        if useBackCamera != isUsingBackCamera {
            DDLogInfo("CameraController/switchCamera")
            captureSession.beginConfiguration()

            captureSession.removeInput(isUsingBackCamera ? backInput : frontInput)
            captureSession.addInput(isUsingBackCamera ? frontInput : backInput)
            isUsingBackCamera = !isUsingBackCamera

            if photoOutput != nil {
                configureVideoOutput(photoOutput!)
            }
            if movieOutput != nil {
                configureVideoOutput(movieOutput!)
            }

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
            videoTimeout = DispatchWorkItem { [weak self] in self?.stopRecordingVideo() }
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + CameraController.maxVideoTimespan, execute: videoTimeout!)
        }
    }

    public func stopRecordingVideo() {
        guard let movieOutput = movieOutput else { return }

        videoTimeout?.cancel()
        videoTimeout = nil
        if isRecordingMovie {
            isRecordingMovie = false
            DDLogInfo("CameraController/stopRecordingVideo")
            movieOutput.stopRecording()
            AudioServicesPlaySystemSound(1118)
        }
    }
}
