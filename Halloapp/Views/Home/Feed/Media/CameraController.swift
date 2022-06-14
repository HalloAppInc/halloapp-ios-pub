//
//  CameraController.swift
//  HalloApp
//
//  Created by Vasil Lyutskanov on 24.08.20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVFoundation
import CocoaLumberjackSwift
import Core
import CoreCommon
import CallKit
import UIKit
import MediaPlayer
import Combine

protocol CameraDelegate {
    func goBack() -> Void
    func volumeButtonPressed() -> Void
    func cameraDidFlip(usingBackCamera: Bool) -> Void
    func finishedRecordingVideo(to outputFileURL: URL, error: Error?)
    func finishedTakingPhoto(_ photo: AVCapturePhoto, error: Error?, cropRect: CGRect?)
}

enum CameraInitError: Error, LocalizedError {
    case initFailureBackCamera
    case initFailureFrontCamera
    case initFailureMicrophone

    case cannotAddBackInput
    case cannotAddFrontInput
    case cannotAddAudioInput

    case cannotAddPhotoOutput
    case cannotAddVideoOutput
    case cannotAddAudioOutput

    var errorDescription: String? {
        switch self {
        case .initFailureBackCamera:
            return NSLocalizedString("camera.init.error.1", value: "Cannot initialize the back camera", comment: "")
        case .initFailureFrontCamera:
            return NSLocalizedString("camera.init.error.2", value: "Cannot initialize the front camera", comment: "")
        case .initFailureMicrophone:
            return NSLocalizedString("camera.init.error.3", value: "Cannot initialize the microphone", comment: "")
        case .cannotAddBackInput:
            return NSLocalizedString("camera.init.error.4", value: "Cannot access back camera", comment: "")
        case .cannotAddFrontInput:
            return NSLocalizedString("camera.init.error.5", value: "Cannot access front camera", comment: "")
        case .cannotAddAudioInput:
            return NSLocalizedString("camera.init.error.6", value: "Cannot access audio", comment: "")
        case .cannotAddPhotoOutput:
            return NSLocalizedString("camera.init.error.7", value: "Cannot capture photos", comment: "")
        case .cannotAddVideoOutput:
            return NSLocalizedString("camera.init.error.8", value: "Cannot record video", comment: "")
        case .cannotAddAudioOutput:
            return NSLocalizedString("camera.init.error.9", value: "Cannot record audio", comment: "")
        }
    }
}

class CameraController: UIViewController, AVCapturePhotoCaptureDelegate {
    private static let volumeDidChangeNotificationName: NSNotification.Name = {
        var name = "AVSystemController_SystemVolumeDidChangeNotification"
        if #available(iOS 15, *) {
           name = "SystemVolumeDidChange"
        }
        
        return NSNotification.Name(rawValue: name)
    }()
    private static let volumeNotificationParameter = "AVSystemController_AudioVolumeNotificationParameter"
    private static let reasonNotificationParameter = "AVSystemController_AudioVolumeChangeReasonNotificationParameter"
    private static let explicitVolumeChangeReason = "ExplicitVolumeChange"

    private static let maxVideoTimespan = DispatchTimeInterval.seconds(60)

    private let cameraDelegate: CameraDelegate
    let format: CameraViewController.Format

    private var captureSession: AVCaptureSession?
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    private var backCamera: AVCaptureDevice?
    private var frontCamera: AVCaptureDevice?
    private var microphone: AVCaptureDevice?

    private var backInput: AVCaptureInput?
    private var frontInput: AVCaptureInput?
    private var audioInput: AVCaptureInput?

    private var audioOutput: AVCaptureAudioDataOutput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var photoOutput: AVCapturePhotoOutput?
    
    /// - note: These asset writer instances are accessed through `bufferQueue`.
    private var videoAssetWriter: AVAssetWriterInput?
    private var audioAssetWriter: AVAssetWriterInput?
    private var assetWriter: AVAssetWriter?
    private var videoWritten = false
    /// For writing samples during video recording.
    private lazy var bufferQueue = DispatchQueue(label: "bufferQueue", qos: .userInitiated)

    private(set) var orientation: UIDeviceOrientation
    private var videoTimeout: DispatchWorkItem?
    private(set) var isRecordingVideo = false
    private(set) var isUsingBackCamera = true

    private var sessionIsStarted = false
    private var cancellables: Set<AnyCancellable> = []

    private var timer: Timer?
    private var timerSeconds = 0
    private var timerLabel: UILabel!
    private let timerTextAttributes: [NSAttributedString.Key : Any] = [
        .strokeWidth: -0.5,
        .foregroundColor: UIColor.white,
        .strokeColor: UIColor.black.withAlphaComponent(0.4),
        .font: UIFont.gothamFont(ofFixedSize: 17)
    ]
    
    private var placeholderView: UIView?
    private var focusIndicator: CircleView?
    private var hideFocusIndicator: DispatchWorkItem?

    private static func checkCapturePermissions(type: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: type)
        case .denied,
             .restricted:
            return false
        @unknown default:
            DDLogError("CameraController/checkCapturePermissions unknown AVAuthorizationStatus")
            return false
        }
    }

    init(cameraDelegate: CameraDelegate, orientation: UIDeviceOrientation, format: CameraViewController.Format = .normal) {
        self.cameraDelegate = cameraDelegate
        self.orientation = orientation
        self.format = format
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(cameraDelegate:)")
    }

    deinit {
        DDLogInfo("CameraController/deinit")
        teardownCaptureSession()
    }

    override func viewDidLoad() {
        DDLogInfo("CameraController/viewDidLoad")
        super.viewDidLoad()
        view.layer.cornerRadius = 15
        view.layer.masksToBounds = true
        let pinchToZoomRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(pinchToZoom(_:)))
        view.addGestureRecognizer(pinchToZoomRecognizer)
        
        let focusTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapToFocus(_:)))
        focusTapRecognizer.numberOfTapsRequired = 1
        view.addGestureRecognizer(focusTapRecognizer)
        
        let cameraChangeRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapToChangeCamera(_:)))
        cameraChangeRecognizer.numberOfTapsRequired = 2
        view.addGestureRecognizer(cameraChangeRecognizer)
        
        timerLabel = UILabel()
        timerLabel.textAlignment = .center
        timerLabel.isHidden = true
        timerLabel.layer.shadowColor = UIColor.black.cgColor
        timerLabel.layer.shadowOffset = CGSize(width: 0, height: 0)
        timerLabel.layer.shadowOpacity = 0.4
        timerLabel.layer.shadowRadius = 2.0
        
        // needed otherwise volume notification won't arrive
        // also hides the volume HUD when hardware buttons are pushed
        let volumeView = MPVolumeView(frame: .zero)
        volumeView.clipsToBounds = true
        view.addSubview(volumeView)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("CameraController/viewWillAppear")
        super.viewWillAppear(animated)
        if captureSession == nil {
            Task { [weak self] in
                await self?.setupSession()
            }
        } else {
            startCaptureSession()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        UIApplication.shared.beginReceivingRemoteControlEvents()
        NotificationCenter.default.addObserver(self,
                                     selector: #selector(volumeDidChange(_:)),
                                         name: CameraController.volumeDidChangeNotificationName, object: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        DDLogInfo("CameraController/viewWillDisappear")
        super.viewWillDisappear(animated)
        
        NotificationCenter.default.removeObserver(self, name: CameraController.volumeDidChangeNotificationName, object: nil)
        UIApplication.shared.endReceivingRemoteControlEvents()
        stopCaptureSession()
    }

    private func startCaptureSession() {
        guard let captureSession = captureSession else {
            return
        }
        
        if (previewLayer == nil) {
            DDLogInfo("CameraController/startCaptureSession create preview layer")
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        }
        
        DDLogInfo("CameraController/startCaptureSession attach preview layer")
        view.layer.addSublayer(previewLayer!)
        view.addSubview(timerLabel)
        previewLayer!.frame = view.layer.frame
        if case .square = format {
            previewLayer!.videoGravity = .resizeAspectFill
        }
        
        orientTimer()
        DispatchQueue.global(qos: .userInitiated).async {
            guard !captureSession.isRunning else {
                return
            }
            
            DDLogInfo("CameraController/startCaptureSession startRunning")
            captureSession.startRunning()
            
            DispatchQueue.main.async {
                self.sessionIsStarted = true
                NotificationCenter.default.addObserver(self,
                                             selector: #selector(self.sessionWasInterrupted(_:)),
                                                 name: NSNotification.Name.AVCaptureSessionWasInterrupted,
                                               object: nil)
                DDLogInfo("CameraController/startCaptureSession done")
            }
        }
    }

    private func stopCaptureSession() {
        DDLogInfo("CameraController/stopCaptureSession detach preview layer")
        previewLayer?.removeFromSuperlayer()
        timerLabel.removeFromSuperview()
        
        guard let captureSession = captureSession else { return }
        
        sessionIsStarted = false
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVCaptureSessionWasInterrupted, object: nil)
        DispatchQueue.global(qos: .userInitiated).async {
            if captureSession.isRunning {
                DDLogInfo("CameraController/stopCaptureSession stopRunning")
                captureSession.stopRunning()
                DDLogInfo("CameraController/stopCaptureSession done")
            }
        }
        
    }

    @objc func volumeDidChange(_ notification: NSNotification) {
        if let userInfo = notification.userInfo,
           let volume = userInfo[CameraController.volumeNotificationParameter] as? Float,
           let reason = userInfo[CameraController.reasonNotificationParameter] as? String,
           reason == CameraController.explicitVolumeChangeReason {
            DDLogInfo("CameraController/volumeDidChange \(volume) \(reason)")
            cameraDelegate.volumeButtonPressed()
        } else if notification.description.contains(CameraController.explicitVolumeChangeReason) {
            /*
             For iOS 15+
             
             Given that our camera implementation is rather custom, we lose out on the
             default functionality that is having the hardware volume button trigger the
             camera's shutter. To not lose out on this feature we listen for volume change
             notifications, verify that they're caused by hardware buttons, and then trigger
             the shutter.
        
             This process has become trickier since iOS 15 as the already undocumented volume
             notifications no longer contain a userInfo dictionary. Instead, the userInfo is
             embedded in the notification's description string; here we scan that string to
             verify a hardware push.
             
             Since this solution relies on undocumented behavior, it could easily break in
             future OS versions.
             */
            DispatchQueue.main.async {
                DDLogInfo("CameraController/volumeDidChange \(CameraController.explicitVolumeChangeReason)")
                self.cameraDelegate.volumeButtonPressed()
            }
        }
    }

    @objc func sessionWasInterrupted(_ notification: NSNotification) {
        guard
            let captureSession = captureSession,
            let userInfo = notification.userInfo
        else {
            return
        }
        DDLogInfo("CameraController/sessionWasInterrupted \(userInfo)")

        if let reasonRawValue = userInfo[AVCaptureSessionInterruptionReasonKey] as? Int,
           let reason = AVCaptureSession.InterruptionReason(rawValue: reasonRawValue),
           reason == .audioDeviceInUseByAnotherClient {

            DispatchQueue.main.async {
                guard let currentAudioInput = self.audioInput else { return }
                captureSession.removeInput(currentAudioInput)
                self.audioInput = nil
            }
        }
    }

    private func showPermissionDeniedAlert(title: String, message: String?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel) { [weak self] _ in
            self?.cameraDelegate.goBack()
        })
        alert.addAction(UIAlertAction(title: Localizations.settingsAppName, style: .default) { [weak self] _ in
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
            self?.cameraDelegate.goBack()
        })
        
        present(alert, animated: true)
    }

    private func showCaptureSessionSetupErrorAlert(error: Error) {
        let title = NSLocalizedString("camera.init.error.title", value: "Initialization Error", comment: "Title for a popup alerting about camera initialization error.")
        let message = (error as? CameraInitError)?.localizedDescription
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default) { [weak self] _ in
            self?.cameraDelegate.goBack()
        })
        
        present(alert, animated: true)
    }

    @MainActor
    private func checkVideoPermissions() async -> Bool {
        let videoGranted = await CameraController.checkCapturePermissions(type: .video)
        if videoGranted {
            return true
        } else {
            showPermissionDeniedAlert(title: Localizations.cameraAccessPromptTitle, message: nil)
            return false
        }
    }

    @MainActor
    private func checkAudioPermissions() async -> Bool {
        let audioGranted = await CameraController.checkCapturePermissions(type: .audio)
        if audioGranted {
            return true
        } else {
            showPermissionDeniedAlert(title: Localizations.microphoneAccessPromptTitle,
                                    message: Localizations.microphoneAccessPromptBody)
            return false
        }
    }

    @MainActor
    private func setupSession() async {
        guard
            await checkVideoPermissions(),
            await checkAudioPermissions()
        else {
            return
        }
        
        DDLogInfo("CameraController/setupAndStartCaptureSession")
        let session = AVCaptureSession()
        session.beginConfiguration()
        
        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        }
        session.usesApplicationAudioSession = false
        session.automaticallyConfiguresCaptureDeviceForWideColor = true
        
        do {
            try setupInput(session)
            try setupOutput(session)
        } catch {
            DDLogError("CameraController/setupAndStartCaptureSession: \(error)")
            showCaptureSessionSetupErrorAlert(error: error)
        }
        
        session.commitConfiguration()
        
        captureSession = session
        startCaptureSession()
    }
    
    private func teardownCaptureSession() {
        DDLogInfo("CameraController/stopAndTeardownCaptureSession")
        guard let session = captureSession else {
            return
        }
        
        session.beginConfiguration()
        if audioInput != nil {
            session.removeInput(audioInput!)
            audioInput = nil
        }
        if let cameraInput = isUsingBackCamera ? backInput : frontInput {
            session.removeInput(cameraInput)
            backInput = nil
            frontInput = nil
        }
        if photoOutput != nil {
            session.removeOutput(photoOutput!)
            photoOutput = nil
        }
        if videoOutput != nil {
            session.removeOutput(videoOutput!)
            videoOutput = nil
        }
        if audioOutput != nil {
            session.removeOutput(audioOutput!)
            audioOutput = nil
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
                break // Retain the previous orientation
            }
        }
        
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = !isUsingBackCamera
        }
    }

    private func setFocusAndExposure(camera: AVCaptureDevice, point: CGPoint? = nil) {
        do {
            try camera.lockForConfiguration()
            defer { camera.unlockForConfiguration() }
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
        } catch {
            DDLogError("CameraController/focusCameraOnPoint \(error)")
        }
    }
    
    private func showFocusIndicator(_ point: CGPoint) {
        if focusIndicator == nil {
            focusIndicator = CircleView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
            view.addSubview(focusIndicator!)
            focusIndicator?.fillColor = .clear
            focusIndicator?.lineWidth = 1.75
            focusIndicator?.strokeColor = .white
        }
        
        hideFocusIndicator?.cancel()
        
        focusIndicator?.alpha = 0
        focusIndicator?.center = point
        focusIndicator?.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
        
        UIView.animate(withDuration: 0.15,
                              delay: 0,
             usingSpringWithDamping: 0.7,
              initialSpringVelocity: 0.5,
                            options: [.allowUserInteraction])
        {
            self.focusIndicator?.transform = .identity
            self.focusIndicator?.alpha = 1
        } completion: { [weak self] _ in
            self?.scheduleFocusIndicatorHide()
        }
    }
    
    private func scheduleFocusIndicatorHide() {
        hideFocusIndicator = DispatchWorkItem {
            UIView.animate(withDuration: 0.15,
                                  delay: 0,
                 usingSpringWithDamping: 0.7,
                  initialSpringVelocity: 0.5,
                                options: [.allowUserInteraction])
            { [weak self] in
                self?.focusIndicator?.alpha = 0
                self?.focusIndicator?.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
            } completion: { [weak self] _ in
                self?.focusIndicator?.removeFromSuperview()
                self?.focusIndicator = nil
                self?.hideFocusIndicator = nil
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: self.hideFocusIndicator!)
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
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: bufferQueue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            self.videoOutput = videoOutput
        } else {
            throw CameraInitError.cannotAddVideoOutput
        }
        
        let audioOutput = AVCaptureAudioDataOutput()
        audioOutput.setSampleBufferDelegate(self, queue: bufferQueue)
        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
            self.audioOutput = audioOutput
        } else {
            throw CameraInitError.cannotAddAudioOutput
        }
    }

    private func setVideoTimeout() {
        clearVideoTimeout()
        videoTimeout = DispatchWorkItem { [weak self] in self?.stopRecordingVideo() }
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + CameraController.maxVideoTimespan, execute: videoTimeout!)
    }

    private func clearVideoTimeout() {
        videoTimeout?.cancel()
        videoTimeout = nil
    }

    private func startRecordingTimer() {
        timerSeconds = 0
        updateTimerLabel()
        timerLabel.isHidden = false
        if timer == nil {
            timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] timer in
                guard let self = self else { return }
                self.timerSeconds += 1
                self.updateTimerLabel()
            }
            RunLoop.current.add(timer!, forMode: .common)
        }
    }

    private func stopRecordingTimer() {
        timerLabel.isHidden = true
        timer?.invalidate()
        timer = nil
    }

    private func updateTimerLabel() {
        self.timerLabel.attributedText = NSAttributedString(
            string: String(format: "%02d:%02d", self.timerSeconds / 60, self.timerSeconds % 60),
            attributes: self.timerTextAttributes
        )
    }

    @objc private func pinchToZoom(_ pinchRecognizer: UIPinchGestureRecognizer) {
        guard let captureSession = captureSession,
            captureSession.isRunning,
            sessionIsStarted,
            let camera = isUsingBackCamera ? backCamera : frontCamera else { return }

        let zoom = camera.videoZoomFactor * pinchRecognizer.scale
        pinchRecognizer.scale = 1.0
        do {
            try camera.lockForConfiguration()
            defer { camera.unlockForConfiguration() }
            if camera.minAvailableVideoZoomFactor <= zoom && zoom <= camera.maxAvailableVideoZoomFactor {
                camera.videoZoomFactor = zoom
            } else {
                DDLogWarn("CameraController/pinchToZoom zoom \(zoom) out of range [\(camera.minAvailableVideoZoomFactor) \(camera.maxAvailableVideoZoomFactor)]")
            }
        } catch {
            DDLogError("CameraController/pinchToZoom \(error)")
        }
    }
    
    @objc private func tapToFocus(_ tapRecognizer: UITapGestureRecognizer) {
        let point = tapRecognizer.location(in: tapRecognizer.view)
        focusOn(point)
    }
    
    @objc private func tapToChangeCamera(_ tapRecognizer: UITapGestureRecognizer) {
        switchCamera(!isUsingBackCamera)
    }

    public func setOrientation(_ orientation: UIDeviceOrientation) {
        guard
            let captureSession = captureSession,
            captureSession.isRunning,
            sessionIsStarted,
            let photoOutput = photoOutput,
            orientation != self.orientation
        else {
            return
        }
        
        self.orientation = orientation
        DDLogInfo("CameraController/setOrientation didOrientationChange")
        orientTimer()
        
        captureSession.beginConfiguration()
        configureVideoOutput(photoOutput)
        captureSession.commitConfiguration()
    }
    
    private func orientTimer() {
        guard let previewLayer = previewLayer else {
            return
        }

        // n is the label's height when in portrait, and width when in landscape
        let n = CGFloat(30)
        timerLabel.transform = .identity
        
        switch orientation {
        case .landscapeLeft:
            timerLabel.transform = timerLabel.transform.rotated(by: .pi / 2)
            timerLabel.frame = CGRect(x: view.bounds.maxX - n,
                                      y: 0,
                                  width: n,
                                 height: previewLayer.bounds.height)
        case .landscapeRight:
            timerLabel.transform = timerLabel.transform.rotated(by: -.pi / 2)
            timerLabel.frame = CGRect(x: view.bounds.minX,
                                      y: view.bounds.minY,
                                  width: n,
                                 height: previewLayer.bounds.height)
        case .portraitUpsideDown:
            timerLabel.transform = timerLabel.transform.rotated(by: .pi)
            timerLabel.frame = CGRect(x: view.bounds.minX,
                                      y: previewLayer.frame.size.height - n,
                                  width: view.bounds.width,
                                 height: n)
        default:
            // default is portrait
            timerLabel.frame = CGRect(x: view.bounds.minX,
                                      y: view.bounds.minY,
                                  width: view.bounds.width,
                                 height: n)
        }
    }

    public func switchCamera(_ useBackCamera: Bool) {
        guard
            let captureSession = captureSession,
            captureSession.isRunning,
            sessionIsStarted,
            let backInput = backInput,
            let frontInput = frontInput,
            let photoOutput = photoOutput
        else {
            return
        }

        if useBackCamera != isUsingBackCamera {
            DDLogInfo("CameraController/switchCamera")
            captureSession.beginConfiguration()

            captureSession.removeInput(isUsingBackCamera ? backInput : frontInput)
            captureSession.addInput(isUsingBackCamera ? frontInput : backInput)
            isUsingBackCamera = !isUsingBackCamera

            configureVideoOutput(photoOutput)

            captureSession.commitConfiguration()
            cameraDelegate.cameraDidFlip(usingBackCamera: isUsingBackCamera)
        }
    }

    public func focusOn(_ point: CGPoint) {
        guard
            let captureSession = captureSession,
            captureSession.isRunning,
            sessionIsStarted,
            let backCamera = backCamera,
            let frontCamera = frontCamera,
            let previewLayer = previewLayer
        else {
            return
        }

        let convertedPoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        DDLogInfo("CameraController/focusOnPoint \(convertedPoint)")
        setFocusAndExposure(camera: isUsingBackCamera ? backCamera : frontCamera, point: convertedPoint)
        showFocusIndicator(point)
    }

    public func takePhoto(useFlashlight: Bool) -> Bool {
        guard
            let captureSession = captureSession,
            captureSession.isRunning,
            sessionIsStarted,
            let photoOutput = photoOutput
        else {
            return false
        }

        DDLogInfo("CameraController/takePhoto")
        let photoSettings = AVCapturePhotoSettings.init(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        photoSettings.flashMode = useFlashlight ? .on : .off
        photoSettings.isHighResolutionPhotoEnabled = false

        photoOutput.capturePhoto(with: photoSettings, delegate: self)
        return true
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        var cropRect: CGRect?
        if format == .square, let preview = previewLayer {
            cropRect = preview.metadataOutputRectConverted(fromLayerRect: preview.bounds)
        }
        
        cameraDelegate.finishedTakingPhoto(photo, error: error, cropRect: cropRect)
    }

    private func isCallKitSupported() -> Bool {
        guard let regionCode = NSLocale.current.regionCode else {
            return false
        }

        if regionCode.contains("CN") || regionCode.contains("CHN") {
            return false
        } else {
            return true
        }
    }

    private func isActiveCallPresent() -> Bool? {
        guard isCallKitSupported() else { return nil }
        return CXCallObserver().calls.contains { !$0.hasEnded }
    }

    private func restoreAudioInput(_ captureSession: AVCaptureSession) {
        guard let isActiveCallPresent = isActiveCallPresent() else {
            DDLogInfo("CameraController/restoreAudioInput/skipping [not supported]")
            return
        }
        if audioInput == nil && !isActiveCallPresent {
            DDLogInfo("CameraController/reinitAudioInput")
            captureSession.beginConfiguration()
            do {
                try audioInput = AVCaptureDeviceInput(device: microphone!)
                if captureSession.canAddInput(audioInput!) {
                    captureSession.addInput(audioInput!)
                } else {
                    throw CameraInitError.cannotAddAudioInput
                }
            } catch {
                DDLogError("CameraController/reinitAudioInput \(error)")
            }
            captureSession.commitConfiguration()
        }
    }

    typealias Dimensions = (height: Int32, width: Int32)
    private func scaledVideoDimensions(originalDimensions: Dimensions) -> Dimensions {
        let maxWidth: CGFloat = 1024
        let originalHeight = CGFloat(originalDimensions.height)
        let originalWidth = CGFloat(originalDimensions.width)
        
        guard originalWidth > maxWidth else {
            return (originalDimensions.height, originalDimensions.width)
        }
        
        let scaleFactor = maxWidth / originalWidth
        let newHeight = Int32(originalHeight * scaleFactor)
        let newWidth = Int32(originalWidth * scaleFactor)
        
        return (newHeight, newWidth)
    }
    
    public func startRecordingVideo(to url: URL) {
        guard
            let captureSession = captureSession,
            captureSession.isRunning,
            sessionIsStarted,
            !isRecordingVideo
        else {
            return
        }
        DDLogInfo("CameraController/startRecordingVideo")
        
        restoreAudioInput(captureSession)
        startRecordingTimer()
        setVideoTimeout()

        isRecordingVideo = true
        bufferQueue.async { [weak self, orientation] in
            self?.configureAssetWriter(url, orientation)
        }
    }
    
    private func configureAssetWriter(_ url: URL, _ orientation: UIDeviceOrientation) {
        guard let assetWriter = try? AVAssetWriter(outputURL: url, fileType: AVFileType.mp4) else {
            DDLogError("CameraController/configureAssetWriter/could not create AVAssetWriter with url \(url)")
            return
        }
        
        // make sure the dimensions
        let dimensions = CMVideoFormatDescriptionGetDimensions(backCamera!.activeFormat.formatDescription)
        let corrected = (height: dimensions.height, width: dimensions.width)
        
        let scaledDimensions = scaledVideoDimensions(originalDimensions: corrected)
        let videoOutputSettings = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoHeightKey: scaledDimensions.height,
                AVVideoWidthKey: format == .square ? scaledDimensions.height : scaledDimensions.width,
                AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
        ] as [String : Any]
        
        
        let videoWriter = AVAssetWriterInput(mediaType: .video, outputSettings: videoOutputSettings)
        videoWriter.expectsMediaDataInRealTime = true
        
        var rotation = CGAffineTransform.identity
        switch self.orientation {
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
        
        videoWriter.transform = rotation
        
        let audioOutputSettings = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 44100,
                AVEncoderBitRateKey: 64000
        ] as [String: Any]
        
        let audioWriter = AVAssetWriterInput(mediaType: .audio, outputSettings: audioOutputSettings)
        audioWriter.expectsMediaDataInRealTime = true
        
        guard
            assetWriter.canAdd(videoWriter),
            assetWriter.canAdd(audioWriter)
        else {
            return
        }
        
        assetWriter.add(videoWriter)
        assetWriter.add(audioWriter)
        self.assetWriter = assetWriter
        self.videoAssetWriter = videoWriter
        self.audioAssetWriter = audioWriter
    }

    public func stopRecordingVideo() {
        clearVideoTimeout()
        stopRecordingTimer()
        guard isRecordingVideo else {
            return
        }
        
        isRecordingVideo = false
        DDLogInfo("CameraController/stopRecordingVideo")
        
        bufferQueue.async { [weak self] in
            guard let writer = self?.assetWriter else {
                return
            }
            
            writer.finishWriting {
                var e: Error?
                if writer.status == .failed, let error = writer.error {
                    e = error
                }
                
                self?.cameraDelegate.finishedRecordingVideo(to: writer.outputURL, error: e)
                self?.assetWriter = nil
                self?.videoAssetWriter = nil
                self?.audioAssetWriter = nil
                self?.videoWritten = false
            }
        }
        
        AudioServicesPlaySystemSound(1118)
    }
}

// MARK: - writing video samples

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard
            isRecordingVideo,
            let writer = assetWriter,
            let videoWriter = videoAssetWriter,
            let audioWriter = audioAssetWriter
        else {
            return
        }

        if case .unknown = writer.status {
            writer.startWriting()
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        }
        
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }
      
        if output === self.videoOutput, videoWriter.isReadyForMoreMediaData {
            videoWriter.append(sampleBuffer)
            videoWritten = true
        }
        
        if output === self.audioOutput, videoWritten, audioWriter.isReadyForMoreMediaData {
            // make sure we append video samples first otherwise the initial frames would be black
            audioWriter.append(sampleBuffer)
        }
    }
}
