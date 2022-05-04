//
//  CameraViewController.swift
//  HalloApp
//
//  Created by Vasil Lyutskanov on 25.08.20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import SwiftUI
import AVFoundation
import CoreMotion

fileprivate class GenericObservable<T>: ObservableObject {
    init(_ value: T) {
        self.value = value
    }

    @Published var value: T
}

fileprivate class AlertStateModel: ObservableObject {
    @Published var showAlert = false
    @Published var alertMessage = ""
}

fileprivate struct CameraViewLayoutConstants {
    static let barButtonSize: CGFloat = 24
    static let horizontalPadding = MediaCarouselViewConfiguration.default.cellSpacing * 0.5
    static let verticalPadding = MediaCarouselViewConfiguration.default.cellSpacing * 0.5
    static let backgroundRadius: CGFloat = 20
    static let imageRadius: CGFloat = 15
    static let captureButtonSize: CGFloat = 73
    static let captureButtonStroke: CGFloat = 9
    static let captureButtonPaddingTop: CGFloat = 16
    static let captureButtonPaddingBotom: CGFloat = 30

    static let buttonColorDark = Color(.sRGB, white: 0.176)
}

extension CameraViewController {
    enum Format { case normal, square }
    
    class Configuration: ObservableObject {
        let showCancelButton: Bool
        let format: Format
        
        init(showCancelButton: Bool = true, format: Format = .normal) {
            self.showCancelButton = showCancelButton
            self.format = format
        }
    }
}

class CameraViewController: UIViewController {
    let configuration: Configuration
    private let didFinish: () -> Void
    private let didPickImage: DidPickImageCallback
    private let didPickVideo: DidPickVideoCallback

    private var defaultBackButton: UIBarButtonItem?
    private var landscapeBackButton: UIBarButtonItem?

    init(configuration: Configuration,
         didFinish: @escaping () -> Void,
         didPickImage: @escaping DidPickImageCallback,
         didPickVideo: @escaping DidPickVideoCallback) {

        self.configuration = configuration
        self.didFinish = didFinish
        self.didPickImage = didPickImage
        self.didPickVideo = didPickVideo
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(showCancelButton:didFinish:didPickImage:didPickVideo:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupBarButtons()
        let initialOrientation = UIDevice.current.orientation.isValidInterfaceOrientation ? UIDevice.current.orientation : .portrait
        setTitle(orientation: initialOrientation)
        setBackBarButton(orientation: initialOrientation)

        let cameraView = CameraView(
            didPickImage: didPickImage,
            didPickVideo: didPickVideo,
            goBack: { [weak self] in self?.backAction() },
            onOrientationChange: { [weak self] orientation in
                self?.setTitle(orientation: orientation)
                self?.setBackBarButton(orientation: orientation)
            }
        ).environmentObject(configuration)

        let cameraViewController = UIHostingController(rootView: cameraView)
        addChild(cameraViewController)
        view.addSubview(cameraViewController.view)
        cameraViewController.view.translatesAutoresizingMaskIntoConstraints = false
        cameraViewController.view.constrain(to: view)
        cameraViewController.didMove(toParent: self)
    }

    @objc private func cancelAction() {
        didFinish()
    }

    private func backAction() {
        if configuration.showCancelButton {
            cancelAction()
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    private func setupBarButtons() {
        let backImage = UIImage(named: "NavbarBack")
        let backButton = UIButton(type: .system)
        backButton.setImage(backImage, for: .normal)
        backButton.addTarget(self, action: #selector(cancelAction), for: .touchUpInside)
        
        let backBarItem = UIBarButtonItem(customView: backButton)
        backBarItem.customView?.translatesAutoresizingMaskIntoConstraints = false
        backBarItem.customView?.heightAnchor.constraint(
            equalToConstant: CameraViewLayoutConstants.barButtonSize).isActive = true
        backBarItem.customView?.widthAnchor.constraint(
            equalToConstant: CameraViewLayoutConstants.barButtonSize).isActive = true
        
        let rotated = UIButton(type: .system)
        rotated.setImage(backImage, for: .normal)
        rotated.addTarget(self, action: #selector(cancelAction), for: .touchUpInside)
        
        let landscapeBarItem = UIBarButtonItem(customView: rotated)
        landscapeBarItem.customView?.translatesAutoresizingMaskIntoConstraints = false
        landscapeBarItem.customView?.heightAnchor.constraint(
            equalToConstant: CameraViewLayoutConstants.barButtonSize).isActive = true
        landscapeBarItem.customView?.widthAnchor.constraint(
            equalToConstant: CameraViewLayoutConstants.barButtonSize).isActive = true
        landscapeBarItem.customView?.transform = landscapeBarItem.customView!.transform.rotated(by: .pi / 2)
        
        defaultBackButton = backBarItem
        landscapeBackButton = landscapeBarItem
    }

    private func setTitle(orientation: UIDeviceOrientation) {
        if orientation.isLandscape || orientation == .portraitUpsideDown {
            navigationItem.title = nil
        } else if orientation == .portrait {
            navigationItem.title = NSLocalizedString("title.camera", value: "Camera", comment: "Screen title")
        }
    }

    private func setBackBarButton(orientation: UIDeviceOrientation) {
        guard let defaultBackButton = defaultBackButton,
            let landscapeBackButton = landscapeBackButton else { return }

        if configuration.showCancelButton {
            if orientation.isLandscape {
                navigationItem.leftBarButtonItem = landscapeBackButton
            } else if orientation.isPortrait {
                navigationItem.leftBarButtonItem = defaultBackButton
            }
        }
    }
}

fileprivate class CameraModel: ObservableObject {
    @Published var shouldTakePhoto = false
    @Published var shouldRecordVideo = false {
        didSet {
            if shouldRecordVideo {
                // once we start recording, orientation is locked
                stopListeningForOrientation()
            } else {
                startListeningForOrientation()
            }
        }
    }
    @Published var shouldUseBackCamera = true
    @Published var shouldUseFlashlight = false
    @Published var orientation = UIDevice.current.orientation
    private let manager: CMMotionManager
    private let queue: OperationQueue
    
    init() {
        manager = CMMotionManager()
        queue = OperationQueue()
        queue.qualityOfService = .utility
        
        startListeningForOrientation()
    }
    
    private func startListeningForOrientation() {
        queue.isSuspended = false
        manager.deviceMotionUpdateInterval = 0.5
        manager.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
            guard
                let self = self,
                let data = data
            else {
                return
            }
            
            let orientation = self.orientation(from: data)
            DispatchQueue.main.async {
                if orientation != self.orientation {
                    self.orientation = orientation
                }
            }
        }
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
        return self.orientation
    }
    
    private func stopListeningForOrientation() {
        manager.stopDeviceMotionUpdates()
        queue.isSuspended = true
    }
}


fileprivate struct CameraView: View {
    let didPickImage: DidPickImageCallback
    let didPickVideo: DidPickVideoCallback
    let goBack: () -> Void
    let onOrientationChange: (UIDeviceOrientation) -> Void
    let captureButtonExtendedFrame = CGRect(x: -0.5 * CameraViewLayoutConstants.captureButtonSize,
                                            y: -0.5 * CameraViewLayoutConstants.captureButtonSize,
                                        width: 2 * CameraViewLayoutConstants.captureButtonSize,
                                       height: 2 * CameraViewLayoutConstants.captureButtonSize)

    @EnvironmentObject var configuration: CameraViewController.Configuration
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var cameraState = CameraModel()
    @ObservedObject var alertState = AlertStateModel()
    @State var captureButtonColor = Color.cameraButton
    @State var captureIsPressed = false
    @State var rotationAngle = Angle(degrees: 0)

    private let plainButtonStyle = PlainButtonStyle()
    private func getCameraControllerHeight(_ width: CGFloat) -> CGFloat {
        let aspectRatio: CGFloat = configuration.format == .normal ? 4 / 3 : 1
        return ((width - 4 * CameraViewLayoutConstants.horizontalPadding) * aspectRatio).rounded()
    }

    private func updateRotationAngle(orientation: UIDeviceOrientation) {
        switch orientation {
        case .portrait:
            rotationAngle = Angle(degrees: 0)
        case .landscapeLeft:
            rotationAngle = Angle(degrees: 90)
        case .portraitUpsideDown:
            rotationAngle = Angle(degrees: 180)
        case .landscapeRight:
            rotationAngle = Angle(degrees: 270)
        default:
            break // Retain the previous rotation angle
        }
    }

    var controls: some View {
        return HStack {
            Spacer()
            Button(action: self.toggleFlash) {
                let flashIconString = cameraState.shouldUseFlashlight ? "CameraFlashOn" : "CameraFlashOff"
                Image(flashIconString)
                    .renderingMode(.template)
                    .foregroundColor(.cameraButton)
                    .rotationEffect(rotationAngle)
            }
            Spacer()

            Circle()
                .strokeBorder(self.captureButtonColor, lineWidth: CameraViewLayoutConstants.captureButtonStroke)
                .frame(width: CameraViewLayoutConstants.captureButtonSize, height: CameraViewLayoutConstants.captureButtonSize)
                .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local).onChanged { _ in
                self.capturePressed()
            }.onEnded { value in
                self.captureReleased(shouldTakePhoto: captureButtonExtendedFrame.contains(value.location))
            })
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                self.captureLongPressed()
            })

            Spacer()
            Button(action: self.flipCamera) {
                Image("CameraFlip")
                    .renderingMode(.template)
                    .foregroundColor(.cameraButton)
                    .rotationEffect(rotationAngle)
            }
            Spacer()
        }
        .padding(.top, CameraViewLayoutConstants.captureButtonPaddingTop)
        .padding(.bottom, CameraViewLayoutConstants.captureButtonPaddingBotom)
    }

    var body: some View {
        return GeometryReader { geometry in
            VStack {
                VStack (spacing: 0) {
                    CameraControllerRepresentable(
                        didPickImage: self.didPickImage,
                        didPickVideo: self.didPickVideo,
                        goBack: self.goBack,
                        cameraState: self.cameraState,
                        alertState: self.alertState)
                    .frame(maxWidth: .infinity, maxHeight: getCameraControllerHeight(geometry.size.width))
                    .padding(.horizontal, CameraViewLayoutConstants.horizontalPadding)
                    .padding(.vertical, CameraViewLayoutConstants.verticalPadding)
                    

                    self.controls
                }
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: CameraViewLayoutConstants.backgroundRadius)
                        .fill(Color(.tertiarySystemBackground))
                        .shadow(color: Color.black.opacity(self.colorScheme == .dark ? 0 : 0.08), radius: 8, y: 8))
                .padding(.horizontal, CameraViewLayoutConstants.horizontalPadding)
                .padding(.vertical, CameraViewLayoutConstants.verticalPadding)
                .alert(isPresented: self.$alertState.showAlert) {
                    Alert(title: Text(self.alertState.alertMessage))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.feedBackground)
            .edgesIgnoringSafeArea(.bottom)
            .edgesIgnoringSafeArea(.top)
            .onReceive(cameraState.$orientation) { orientation in
                self.onOrientationChange(orientation)
                self.updateRotationAngle(orientation: orientation)
            }
        }
    }

    private func capturePressed() {
        guard !captureIsPressed else { return }
        captureIsPressed = true
        withAnimation {
            captureButtonColor = Color.cameraButton.opacity(0.7)
        }
    }

    private func captureLongPressed() {
        defer {
            withAnimation {
                captureButtonColor = .lavaOrange
            }
        }
        guard captureIsPressed else { return }
        if !cameraState.shouldTakePhoto && !cameraState.shouldRecordVideo {
            cameraState.shouldRecordVideo = true
        }
    }

    private func captureReleased(shouldTakePhoto: Bool) {
        defer {
            withAnimation {
                captureButtonColor = .cameraButton
            }
        }
        guard captureIsPressed else { return }
        captureIsPressed = false
        if !cameraState.shouldTakePhoto {
            if cameraState.shouldRecordVideo {
                cameraState.shouldRecordVideo = false
            } else if shouldTakePhoto {
                cameraState.shouldTakePhoto = true
            }
        }
    }

    private func toggleFlash() {
        cameraState.shouldUseFlashlight = !cameraState.shouldUseFlashlight
    }

    private func flipCamera() {
        cameraState.shouldUseBackCamera = !cameraState.shouldUseBackCamera
    }
}

fileprivate struct CameraControllerRepresentable: UIViewControllerRepresentable{
    private static let videoOutputURL =
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("temp_camera_video.mov")

    let didPickImage: DidPickImageCallback
    let didPickVideo: DidPickVideoCallback
    let goBack: () -> Void

    @EnvironmentObject var configuration: CameraViewController.Configuration
    @ObservedObject var cameraState: CameraModel
    var alertState: AlertStateModel

    func makeUIViewController(context: Context) -> CameraController {
        let controller = CameraController(cameraDelegate: context.coordinator,
                                             orientation: cameraState.orientation,
                                                  format: configuration.format)
        
        return controller
    }

    func updateUIViewController(_ cameraController: CameraController, context: Context) {
        if cameraState.shouldUseBackCamera != cameraController.isUsingBackCamera {
            cameraController.switchCamera(cameraState.shouldUseBackCamera)
        }
        if cameraState.orientation != cameraController.orientation {
            cameraController.setOrientation(cameraState.orientation)
        }
        
        if cameraState.shouldTakePhoto &&
            !context.coordinator.isTakingPhoto &&
            !cameraState.shouldRecordVideo &&
            !context.coordinator.isRecordingVideo {

            if cameraController.takePhoto(useFlashlight: cameraState.shouldUseFlashlight) {
                context.coordinator.isTakingPhoto = true
            } else {
                cameraState.shouldTakePhoto = false
            }
        }
        if !cameraState.shouldTakePhoto &&
            !context.coordinator.isTakingPhoto &&
            cameraState.shouldRecordVideo != context.coordinator.isRecordingVideo {

            if cameraState.shouldRecordVideo {
                cameraController.startRecordingVideo(to: CameraControllerRepresentable.videoOutputURL)
                if cameraController.isRecordingVideo {
                    context.coordinator.isRecordingVideo = true
                } else {
                    cameraState.shouldRecordVideo = false
                }
            } else {
                cameraController.stopRecordingVideo()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, CameraDelegate {
        enum MediaType {
            case photo
            case video
        }

        var parent: CameraControllerRepresentable
        var isTakingPhoto = false
        var isRecordingVideo = false

        init(_ controller: CameraControllerRepresentable) {
            parent = controller
        }

        private func showCameraFailureAlert(mediaType: MediaType) {
            DispatchQueue.main.async {
                self.parent.alertState.showAlert = true
                self.parent.alertState.alertMessage =
                    mediaType == .photo ? "Could not take a photo" : "Could not record a video"
            }
        }
        
        func cameraDidFlip(usingBackCamera: Bool) {
            parent.cameraState.shouldUseBackCamera = usingBackCamera
        }

        func goBack() {
            parent.goBack()
        }
        
        func volumeButtonPressed() {
            if !parent.cameraState.shouldTakePhoto &&
                !isTakingPhoto &&
                !parent.cameraState.shouldRecordVideo &&
                !isRecordingVideo {

                parent.cameraState.shouldTakePhoto = true
            }
        }
        
        func finishedTakingPhoto(_ photo: AVCapturePhoto, error: Error?, cropRect: CGRect?) {
            DDLogInfo("CameraControllerRepresentable/Coordinator/photoOutput")

            defer {
                DispatchQueue.main.async {
                    self.isTakingPhoto = false
                    self.parent.cameraState.shouldTakePhoto = false
                }
            }
            
            guard error == nil else {
                DDLogError("CameraControllerRepresentable/Coordinator/photoOutput: \(error!)")
                return showCameraFailureAlert(mediaType: .photo)
            }

            guard let photoData = photo.fileDataRepresentation() else {
                DDLogError("CameraControllerRepresentable/Coordinator/photoOutput: fileDataRepresentation returned nil")
                return showCameraFailureAlert(mediaType: .photo)
            }
            
            guard var uiImage = UIImage(data: photoData) else {
                DDLogError("CameraControllerRepresentable/Coordinator/photoOutput: could not init UIImage from photoData")
                return showCameraFailureAlert(mediaType: .photo)
            }
            
            if let cropRect = cropRect, let cgImage = uiImage.cgImage {
                // crop to square
                let width = CGFloat(cgImage.width)
                let height = CGFloat(cgImage.height)
                let finalCropRect = CGRect(x: cropRect.origin.x * width,
                                           y: cropRect.origin.y * height,
                                       width: cropRect.size.width * width,
                                      height: cropRect.size.height * height)
                
                if let croppedCGImage = cgImage.cropping(to: finalCropRect) {
                    uiImage = UIImage(cgImage: croppedCGImage, scale: 1.0, orientation: uiImage.imageOrientation)
                }
            }
            
            DispatchQueue.main.async {
                self.parent.didPickImage(uiImage)
            }
        }
        
        func finishedRecordingVideo(to outputFileURL: URL, error: Error?) {
            DDLogInfo("CameraControllerRepresentable/Coordinator/fileOutput")

            defer {
                DispatchQueue.main.async {
                    self.isRecordingVideo = false
                    self.parent.cameraState.shouldRecordVideo = false
                }
            }
            
            if error != nil {
                DDLogError("CameraControllerRepresentable/Coordinator/fileOutput: \(error!)")
            }

            guard FileManager.default.fileExists(atPath: outputFileURL.path) else {
                DDLogError("CameraControllerRepresentable/Coordinator/fileOutput: \(outputFileURL) does not exist")
                return showCameraFailureAlert(mediaType: .video)
            }

            let pendingVideoURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString, isDirectory: false)
                .appendingPathExtension("mp4")
            do {
                if FileManager.default.fileExists(atPath: pendingVideoURL.path) {
                    try FileManager.default.removeItem(at: pendingVideoURL)
                }
                try FileManager.default.moveItem(at: outputFileURL, to: pendingVideoURL)
            } catch {
                DDLogError("CameraControllerRepresentable/Coordinator/fileOutput: could not copy to \(pendingVideoURL)")
                return showCameraFailureAlert(mediaType: .video)
            }

            DispatchQueue.main.async {
                self.parent.didPickVideo(pendingVideoURL)
            }
        }
    }
}
