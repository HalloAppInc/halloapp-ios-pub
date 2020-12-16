//
//  CameraViewController.swift
//  HalloApp
//
//  Created by Vasil Lyutskanov on 25.08.20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import SwiftUI
import AVFoundation

fileprivate class GenericObservable<T>: ObservableObject {
    init(_ value: T) {
        self.value = value
    }

    @Published var value: T
}

fileprivate class CameraStateModel: ObservableObject {
    @Published var shouldTakePhoto = false
    @Published var shouldRecordVideo = false
    @Published var shouldUseBackCamera = true
    @Published var shouldUseFlashlight = false
    @Published var orientation = UIDevice.current.orientation
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

class CameraViewController: UIViewController {
    private var showCancelButton = false
    private let didFinish: () -> Void
    private let didPickImage: DidPickImageCallback
    private let didPickVideo: DidPickVideoCallback

    private var defaultBackButton: UIBarButtonItem?
    private var landscapeBackButton: UIBarButtonItem?

    init(showCancelButton: Bool,
         didFinish: @escaping () -> Void,
         didPickImage: @escaping DidPickImageCallback,
         didPickVideo: @escaping DidPickVideoCallback) {

        self.showCancelButton = showCancelButton
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
        setTitle(orientation: UIDevice.current.orientation)
        setBackBarButton(orientation: UIDevice.current.orientation)

        let cameraView = CameraView(
            didPickImage: didPickImage,
            didPickVideo: didPickVideo,
            goBack: { [weak self] in self?.backAction() },
            onOrientationChange: { [weak self] orientation in
                self?.setTitle(orientation: orientation)
                self?.setBackBarButton(orientation: orientation)
            }
        )

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
        if showCancelButton {
            cancelAction()
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    private func setupBarButtons() {
        let defaultBackImage = UIImage(named: "NavbarBack")
        let landscapeBackImage = defaultBackImage?.cgImage != nil ?
            UIImage(cgImage: defaultBackImage!.cgImage!, scale: 1.0, orientation: .right) : nil

        let landscapeButton = UIButton(type: .system)
        landscapeButton.setImage(landscapeBackImage, for: .normal)
        landscapeButton.addTarget(self, action: #selector(cancelAction), for: .touchUpInside)

        defaultBackButton = UIBarButtonItem(
            image: defaultBackImage, style: .plain, target: self, action: #selector(cancelAction))
        let barButton = UIBarButtonItem(customView: landscapeButton)
        barButton.customView?.translatesAutoresizingMaskIntoConstraints = false
        barButton.customView?.heightAnchor.constraint(
            equalToConstant: CameraViewLayoutConstants.barButtonSize).isActive = true
        barButton.customView?.widthAnchor.constraint(
            equalToConstant: CameraViewLayoutConstants.barButtonSize).isActive = true
        landscapeBackButton = barButton
    }

    private func setTitle(orientation: UIDeviceOrientation) {
        if orientation.isLandscape || orientation == .portraitUpsideDown {
            navigationItem.title = nil
        } else {
            navigationItem.title = NSLocalizedString("title.camera", value: "Camera", comment: "Screen title")
        }
    }

    private func setBackBarButton(orientation: UIDeviceOrientation) {
        guard let defaultBackButton = defaultBackButton,
            let landscapeBackButton = landscapeBackButton else { return }

        if showCancelButton {
            if orientation.isLandscape {
                navigationItem.leftBarButtonItem = nil
                navigationItem.rightBarButtonItem = landscapeBackButton
            } else {
                navigationItem.leftBarButtonItem = defaultBackButton
                navigationItem.rightBarButtonItem = nil
            }
        }
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

    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var cameraState = CameraStateModel()
    @ObservedObject var alertState = AlertStateModel()
    @State var captureButtonColor = Color.cameraButton
    @State var captureIsPressed = false

    private let plainButtonStyle = PlainButtonStyle()
    private let orientationPublisher = NotificationCenter.default
        .publisher(for: UIDevice.orientationDidChangeNotification)
        .map { _ in UIDevice.current.orientation }
        .eraseToAnyPublisher()

    private static func getCameraControllerHeight(_ width: CGFloat) -> CGFloat {
        return ((width - 4 * CameraViewLayoutConstants.horizontalPadding) * 4 / 3).rounded()
    }

    private static func getIconRotation(_ orientation: UIDeviceOrientation) -> Angle {
        var degrees: Double = 0
        switch orientation {
        case .portrait:
            degrees = 0
        case .landscapeLeft:
            degrees = 90
        case .portraitUpsideDown:
            degrees = 180
        case .landscapeRight:
            degrees = 270
        default:
            degrees = 0
        }
        return Angle(degrees: degrees)
    }

    var controls: some View {
        return HStack {
            Spacer()
            Button(action: self.toggleFlash) {
                if cameraState.shouldUseFlashlight {
                    Image("CameraFlashOn")
                        .foregroundColor(.cameraButton)
                        .rotationEffect(CameraView.getIconRotation(cameraState.orientation))
                } else {
                    Image("CameraFlashOff")
                        .foregroundColor(.cameraButton)
                        .rotationEffect(CameraView.getIconRotation(cameraState.orientation))
                }
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
                    .foregroundColor(.cameraButton)
                    .rotationEffect(CameraView.getIconRotation(cameraState.orientation))
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
                    .frame(maxWidth: .infinity, maxHeight: CameraView.getCameraControllerHeight(geometry.size.width))
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
            .onReceive(self.orientationPublisher) { orientation in
                self.cameraState.orientation = orientation
                self.onOrientationChange(orientation)
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
        guard captureIsPressed else { return }
        cameraState.shouldRecordVideo = true
        withAnimation {
            captureButtonColor = .lavaOrange
        }
    }

    private func captureReleased(shouldTakePhoto: Bool) {
        if captureIsPressed {
            captureIsPressed = false
            withAnimation {
                captureButtonColor = .cameraButton
            }
        }
        if cameraState.shouldRecordVideo {
            cameraState.shouldRecordVideo = false
        } else if shouldTakePhoto {
            cameraState.shouldTakePhoto = true
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
    private static let videoPendingURL =
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pending_camera_video.mov")

    let didPickImage: DidPickImageCallback
    let didPickVideo: DidPickVideoCallback
    let goBack: () -> Void

    @ObservedObject var cameraState: CameraStateModel
    var alertState: AlertStateModel
    @ObservedObject var focusPoint = GenericObservable<CGPoint?>(nil)
    var isTakingPhoto = GenericObservable(false)

    func makeUIViewController(context: Context) -> CameraController {
        let controller = CameraController(
            cameraDelegate: context.coordinator,
            orientation: context.coordinator.parent.cameraState.orientation)
        let tappedGesture =
            UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped))
        tappedGesture.numberOfTapsRequired = 1
        let doubleTappedGesture =
            UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped))
        doubleTappedGesture.numberOfTapsRequired = 2
        controller.view.addGestureRecognizer(tappedGesture)
        controller.view.addGestureRecognizer(doubleTappedGesture)
        return controller
    }

    func updateUIViewController(_ cameraController: CameraController, context: Context) {
        if context.coordinator.parent.cameraState.shouldUseBackCamera != cameraController.isUsingBackCamera {
            cameraController.switchCamera(context.coordinator.parent.cameraState.shouldUseBackCamera)
        }
        if context.coordinator.parent.cameraState.orientation != cameraController.orientation {
            cameraController.setOrientation(context.coordinator.parent.cameraState.orientation)
        }
        if !context.coordinator.parent.cameraState.shouldRecordVideo &&
            context.coordinator.parent.cameraState.shouldTakePhoto &&
            !context.coordinator.parent.isTakingPhoto.value {

            context.coordinator.parent.isTakingPhoto.value = true
            cameraController.takePhoto(useFlashlight: context.coordinator.parent.cameraState.shouldUseFlashlight)
        }
        if !context.coordinator.parent.cameraState.shouldTakePhoto &&
            cameraController.isRecordingMovie != context.coordinator.parent.cameraState.shouldRecordVideo {

            if context.coordinator.parent.cameraState.shouldRecordVideo {
                cameraController.startRecordingVideo(CameraControllerRepresentable.videoOutputURL)
            } else {
                cameraController.stopRecordingVideo()
            }
        }
        if let focusPoint = context.coordinator.parent.focusPoint.value {
            cameraController.focusOnPoint(focusPoint)
            context.coordinator.parent.focusPoint.value = nil
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

        @objc func tapped(gesture:UITapGestureRecognizer) {
            parent.focusPoint.value = gesture.location(in: gesture.view!)
        }

        @objc func doubleTapped(gesture:UITapGestureRecognizer) {
            self.parent.cameraState.shouldUseBackCamera = !self.parent.cameraState.shouldUseBackCamera
        }

        func goBack() {
            parent.goBack()
        }

        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            DDLogInfo("CameraControllerRepresentable/Coordinator/photoOutput")

            defer {
                DispatchQueue.main.async {
                    self.parent.isTakingPhoto.value = false
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

            guard let uiImage = UIImage(data: photoData) else {
                DDLogError("CameraControllerRepresentable/Coordinator/photoOutput: could not init UIImage from photoData")
                return showCameraFailureAlert(mediaType: .photo)
            }

            DispatchQueue.main.async {
                self.parent.didPickImage(uiImage)
            }
        }

        func fileOutput(_ output: AVCaptureFileOutput,
                        didFinishRecordingTo outputFileURL: URL,
                        from connections: [AVCaptureConnection], error: Error?) {
            DDLogInfo("CameraControllerRepresentable/Coordinator/fileOutput")

            defer {
                DispatchQueue.main.async {
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

            do {
                if FileManager.default.fileExists(atPath: CameraControllerRepresentable.videoPendingURL.path) {
                    try FileManager.default.removeItem(at: CameraControllerRepresentable.videoPendingURL)
                }
                try FileManager.default.moveItem(at: outputFileURL, to: CameraControllerRepresentable.videoPendingURL)
            } catch {
                DDLogError("CameraControllerRepresentable/Coordinator/fileOutput: could not copy to \(CameraControllerRepresentable.videoPendingURL)")
                return showCameraFailureAlert(mediaType: .video)
            }

            DispatchQueue.main.async {
                self.parent.didPickVideo(CameraControllerRepresentable.videoPendingURL)
            }
        }
    }
}
