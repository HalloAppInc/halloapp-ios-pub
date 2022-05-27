//
//  CameraViewController.swift
//  HalloApp
//
//  Created by Vasil Lyutskanov on 25.08.20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import CoreCommon
import SwiftUI
import AVFoundation
import CoreMotion

enum MediaType {
    case photo
    case video
}

extension Localizations {

    static var cameraModeVideo: String {
        NSLocalizedString("media.camera.mode.photo",
                          value: "VIDEO",
                          comment: "Label indicating that the camera is in video mode")
    }

    static var cameraModePhoto: String {
        NSLocalizedString("media.camera.mode.photo",
                          value: "PHOTO",
                          comment: "Label indicating that the camera is in photo mode")
    }

}

struct CameraViewLayoutConstants {
    static let animationDuration = 0.35
    static let barButtonSize: CGFloat = 24
    static let horizontalPadding = MediaCarouselViewConfiguration.default.cellSpacing * 0.5
    static let verticalPadding = MediaCarouselViewConfiguration.default.cellSpacing * 0.5
    static let backgroundRadius: CGFloat = 30
    static let imageRadius: CGFloat = 24

    static let cameraFrameSpacing: CGFloat = 6

    static let captureButtonSize: CGFloat = 100
    static let captureButtonCircleRadius: CGFloat = 40
    static let captureButtonCirclePressedRadius: CGFloat = 50
    static let captureButtonCircleStroke: CGFloat = 10
    static let captureButtonCircleShadowRadius: CGFloat = 30
    static let captureButtonRectCornerRadius: CGFloat = 15

    static let toggleButtonSize: CGFloat = 80

    static let captureButtonFillColorNormal = UIColor.clear.cgColor
    static let captureButtonFillColorPressed = UIColor.lavaOrange.withAlphaComponent(0.2).cgColor
    static let captureButtonStrokeColorNormal = UIColor.white.cgColor
    static let captureButtonStrokeColorPressed = UIColor.lavaOrange.cgColor

    static let controlStackVerticalPadding: CGFloat = 6
    static let controlStackHeight = 2 * controlStackVerticalPadding + captureButtonSize

    static let captureModeOptionWidth = UIScreen.main.bounds.width / 3
    static let captureModeOptionHeight: CGFloat = 50

    static let buttonColorDark = Color(.sRGB, white: 0.176)
    static let backgroundGradientStops = [
        Gradient.Stop(color: .cameraFrameGradient0, location: 0),
        Gradient.Stop(color: .cameraFrameGradient0, location: 0.02),
        Gradient.Stop(color: .cameraFrameGradient1, location: 0.7),
        Gradient.Stop(color: .cameraFrameGradient2, location: 1),
    ]

    static func getCameraControllerWidth(_ width: CGFloat) -> CGFloat {
        return width - 2 * CameraViewLayoutConstants.horizontalPadding
    }

    static func getCameraControllerHeight(_ width: CGFloat, configuration: CameraViewController.Configuration) -> CGFloat {
        let aspectRatio: CGFloat = configuration.format == .normal ? 4 / 3 : 1
        return (getCameraControllerWidth(width) * aspectRatio).rounded()
    }

    static func getCameraFrameHeight(_ width: CGFloat, configuration: CameraViewController.Configuration) -> CGFloat {
        return getCameraControllerHeight(width, configuration: configuration) + 2 * verticalPadding + cameraFrameSpacing + controlStackHeight
    }

    static func getBackgroundGradientRadius(_ width: CGFloat, configuration: CameraViewController.Configuration) -> CGFloat {
        return getCameraFrameHeight(width, configuration: configuration)
    }
}

class CameraFrameView: UIStackView {
    private lazy var backgroundLayer: CAGradientLayer = {
        let gradientLayer = CAGradientLayer()
        gradientLayer.type = .radial
        gradientLayer.colors = [
            UIColor.cameraFrameGradient0.cgColor,
            UIColor.cameraFrameGradient1.cgColor,
            UIColor.cameraFrameGradient2.cgColor,
        ]
        gradientLayer.locations = [ 0, 0.7, 1 ]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        gradientLayer.cornerRadius = CameraViewLayoutConstants.backgroundRadius
        layer.insertSublayer(gradientLayer, at: 0)
        return gradientLayer
    }()

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundLayer.frame = bounds
    }
}

class CaptureButton: UIButton {
    private lazy var normalCirclePath: UIBezierPath = {
        let radius = CameraViewLayoutConstants.captureButtonCircleRadius - CameraViewLayoutConstants.captureButtonCircleStroke / 2
        let rect = CGRect(x: bounds.midX - radius, y: bounds.midY - radius, width: radius * 2, height: radius * 2)
        return UIBezierPath(ovalIn: rect)
    }()

    private lazy var pressedCirclePath: UIBezierPath = {
        let radius = CameraViewLayoutConstants.captureButtonCirclePressedRadius - CameraViewLayoutConstants.captureButtonCircleStroke / 2
        let rect = CGRect(x: bounds.midX - radius, y: bounds.midY - radius, width: radius * 2, height: radius * 2)
        return UIBezierPath(ovalIn: rect)
    }()

    private lazy var circleLayer: CAShapeLayer = {
        let rect = normalCirclePath
        let circlePath = normalCirclePath
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = circlePath.cgPath
        shapeLayer.fillColor = CameraViewLayoutConstants.captureButtonFillColorNormal
        shapeLayer.strokeColor = CameraViewLayoutConstants.captureButtonStrokeColorNormal
        shapeLayer.lineWidth = CameraViewLayoutConstants.captureButtonCircleStroke
        shapeLayer.shadowColor = CameraViewLayoutConstants.captureButtonStrokeColorPressed
        shapeLayer.shadowRadius = CameraViewLayoutConstants.captureButtonCircleShadowRadius
        shapeLayer.shadowOpacity = 0
        layer.insertSublayer(shapeLayer, at: 0)
        return shapeLayer
    }()

    private lazy var cubeLayer: CAShapeLayer = {
        let radius = CameraViewLayoutConstants.captureButtonRectCornerRadius
        let rect = CGRect(x: bounds.midX - radius, y: bounds.midY - radius, width: radius * 2, height: radius * 2)
        let roundedRectPath = UIBezierPath(roundedRect: rect, cornerRadius: 8)
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = roundedRectPath.cgPath
        shapeLayer.fillColor = CameraViewLayoutConstants.captureButtonStrokeColorPressed
        shapeLayer.opacity = 0
        layer.insertSublayer(shapeLayer, at: 1)
        return shapeLayer
    }()

    private lazy var pressedFillColorAnimation: CAAnimation = {
        let animation = CABasicAnimation(keyPath: "fillColor")
        animation.duration = CameraViewLayoutConstants.animationDuration
        animation.fromValue = CameraViewLayoutConstants.captureButtonFillColorNormal
        animation.toValue = CameraViewLayoutConstants.captureButtonFillColorPressed
        return animation
    }()

    private lazy var pressedStrokeColorAnimation: CAAnimation = {
        let animation = CABasicAnimation(keyPath: "strokeColor")
        animation.duration = CameraViewLayoutConstants.animationDuration
        animation.fromValue = CameraViewLayoutConstants.captureButtonStrokeColorNormal
        animation.toValue = CameraViewLayoutConstants.captureButtonStrokeColorPressed
        return animation
    }()

    private lazy var pressedPathAnimation: CAAnimation = {
        let animation = CABasicAnimation(keyPath: "path")
        animation.duration = CameraViewLayoutConstants.animationDuration
        animation.fromValue = normalCirclePath.cgPath
        animation.toValue = pressedCirclePath.cgPath
        return animation
    }()

    private lazy var pressedShadowAnimation: CAAnimation = {
        let animation = CABasicAnimation(keyPath: "shadowOpacity")
        animation.duration = CameraViewLayoutConstants.animationDuration
        animation.fromValue = 0
        animation.toValue = 1
        return animation
    }()

    private lazy var pressedCubeAnimation: CAAnimation = {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.duration = CameraViewLayoutConstants.animationDuration
        animation.fromValue = 0
        animation.toValue = 1
        return animation
    }()

    private lazy var restoreFillColorAnimation: CAAnimation = {
        let animation = CABasicAnimation(keyPath: "fillColor")
        animation.duration = CameraViewLayoutConstants.animationDuration
        animation.fromValue = CameraViewLayoutConstants.captureButtonFillColorPressed
        animation.toValue = CameraViewLayoutConstants.captureButtonFillColorNormal
        return animation
    }()

    private lazy var restoreColorAnimation: CAAnimation = {
        let animation = CABasicAnimation(keyPath: "strokeColor")
        animation.duration = CameraViewLayoutConstants.animationDuration
        animation.fromValue = CameraViewLayoutConstants.captureButtonStrokeColorPressed
        animation.toValue = CameraViewLayoutConstants.captureButtonStrokeColorNormal
        return animation
    }()

    private lazy var restorePathAnimation: CAAnimation = {
        let animation = CABasicAnimation(keyPath: "path")
        animation.duration = CameraViewLayoutConstants.animationDuration
        animation.fromValue = pressedCirclePath.cgPath
        animation.toValue = normalCirclePath.cgPath
        return animation
    }()

    private lazy var restoreShadowAnimation: CAAnimation = {
        let animation = CABasicAnimation(keyPath: "shadowOpacity")
        animation.duration = CameraViewLayoutConstants.animationDuration
        animation.fromValue = 1
        animation.toValue = 0
        return animation
    }()

    private lazy var restoreCubeAnimation: CAAnimation = {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.duration = CameraViewLayoutConstants.animationDuration
        animation.fromValue = 1
        animation.toValue = 0
        return animation
    }()

    override func layoutSubviews() {
        super.layoutSubviews()
        circleLayer.frame = bounds
        cubeLayer.frame = bounds
    }

    public func playPressAnimation(autoreverses: Bool, showCube: Bool) {
        let repeatCount: Float = autoreverses ? 1 : 0
        pressedFillColorAnimation.autoreverses = autoreverses
        pressedFillColorAnimation.repeatCount = repeatCount
        pressedStrokeColorAnimation.autoreverses = autoreverses
        pressedStrokeColorAnimation.repeatCount = repeatCount
        pressedPathAnimation.autoreverses = autoreverses
        pressedPathAnimation.repeatCount = repeatCount
        pressedShadowAnimation.autoreverses = autoreverses
        pressedShadowAnimation.repeatCount = repeatCount
        pressedCubeAnimation.autoreverses = autoreverses
        pressedCubeAnimation.repeatCount = repeatCount
        if !autoreverses {
            circleLayer.fillColor = CameraViewLayoutConstants.captureButtonFillColorPressed
            circleLayer.strokeColor = CameraViewLayoutConstants.captureButtonStrokeColorPressed
            circleLayer.path = pressedCirclePath.cgPath
            circleLayer.shadowOpacity = 1
            if showCube {
                cubeLayer.opacity = 1
            }
        }
        circleLayer.add(pressedFillColorAnimation, forKey: "fillColor")
        circleLayer.add(pressedStrokeColorAnimation, forKey: "strokeColor")
        circleLayer.add(pressedPathAnimation, forKey: "path")
        circleLayer.add(pressedShadowAnimation, forKey: "shadowOpacity")
        if showCube {
            cubeLayer.add(pressedCubeAnimation, forKey: "opacity")
        }
    }

    public func playRestoreAnimation() {
        circleLayer.fillColor = CameraViewLayoutConstants.captureButtonFillColorNormal
        circleLayer.strokeColor = UIColor.white.cgColor
        circleLayer.path = normalCirclePath.cgPath
        circleLayer.shadowOpacity = 0
        cubeLayer.opacity = 0
        circleLayer.add(restoreFillColorAnimation, forKey: "fillColor")
        circleLayer.add(restoreColorAnimation, forKey: "strokeColor")
        circleLayer.add(restorePathAnimation, forKey: "path")
        circleLayer.add(restoreShadowAnimation, forKey: "shadowOpacity")
        cubeLayer.add(restoreCubeAnimation, forKey: "opacity")
    }
}

class ModeScrollView: UIScrollView {
    public var currentPage: Int {
        return Int(contentOffset.x / frame.size.width)
    }

    public var currentMediaType: MediaType {
        return currentPage == 0 ? .video : .photo
    }

    private lazy var videoLabel: UILabel = {
        let label = UILabel()
        label.text = Localizations.cameraModeVideo
        label.textAlignment = .center
        addSubview(label)
        return label
    }()

    private lazy var photoLabel: UILabel = {
        let label = UILabel()
        label.text = Localizations.cameraModePhoto
        label.textAlignment = .center
        addSubview(label)
        return label
    }()

    init(initialMode: MediaType) {
        super.init(frame: .zero)
        let initialPage: Int = {
            switch initialMode {
            case .video:
                return 0
            case .photo:
                return 1
            }
        }()
        isPagingEnabled = true
        contentSize = CGSize(width: 2 * CameraViewLayoutConstants.captureModeOptionWidth, height: CameraViewLayoutConstants.captureModeOptionHeight)
        contentOffset = CGPoint(x: CGFloat(initialPage) * CameraViewLayoutConstants.captureModeOptionWidth, y: 0)
        clipsToBounds = false
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        updateLabelColor(selectedMediaType: initialMode)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let elementWidth = CameraViewLayoutConstants.captureModeOptionWidth
        videoLabel.frame = CGRect(x: 0, y: 0, width: elementWidth, height: bounds.height)
        photoLabel.frame = CGRect(x: elementWidth, y: 0, width: elementWidth, height: bounds.height)
    }

    public func updateLabelColor(selectedMediaType: MediaType) {
        switch selectedMediaType {
        case .photo:
            photoLabel.textColor = .cameraSelectedLabel
            videoLabel.textColor = .white
        case .video:
            photoLabel.textColor = .white
            videoLabel.textColor = .cameraSelectedLabel
        }
    }

    public func handleTap(point: CGPoint) -> MediaType? {
        if videoLabel.frame.contains(point) {
            scrollRectToVisible(videoLabel.frame, animated: true)
            updateLabelColor(selectedMediaType: .video)
            return .video
        } else if photoLabel.frame.contains(point) {
            scrollRectToVisible(photoLabel.frame, animated: true)
            updateLabelColor(selectedMediaType: .photo)
            return .photo
        }
        return nil
    }
}

extension CameraViewController {
    enum Format { case normal, square }
    
    class Configuration: ObservableObject {
        let showCancelButton: Bool
        let format: Format
        let subtitle: String?
        
        init(showCancelButton: Bool = true, format: Format = .normal, subtitle: String? = nil) {
            self.showCancelButton = showCancelButton
            self.format = format
            self.subtitle = subtitle
        }
    }
}

class CameraViewController: UIViewController {
    private static let videoOutputURL =
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("temp_camera_video.mov")

    let configuration: Configuration
    private let didFinish: () -> Void
    private let didPickImage: DidPickImageCallback
    private let didPickVideo: DidPickVideoCallback

    private var cameraController: CameraController?

    private let toggleFlashButton = UIButton(type: .system)
    private let flipCameraButton = UIButton(type: .system)
    private let captureButton = CaptureButton(type: .system)

    private let modeScrollView = ModeScrollView(initialMode: .photo)

    private let flashOnImage = UIImage(named: "CameraFlashOn")
    private let flashOffImage = UIImage(named: "CameraFlashOff")
    private let cameraFlipImage = UIImage(named: "CameraFlip")

    private var orientation = UIDevice.current.orientation

    private let manager: CMMotionManager
    private let queue: OperationQueue

    private var shouldUseFlashlight = false
    private var shouldUseBackCamera = false

    private var isTakingPhoto = false
    private var captureMediaType: MediaType = .photo

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.font = .systemFont(forTextStyle: .subheadline, weight: .regular, maximumPointSize: 24)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()

    init(configuration: Configuration,
         didFinish: @escaping () -> Void,
         didPickImage: @escaping DidPickImageCallback,
         didPickVideo: @escaping DidPickVideoCallback) {

        self.configuration = configuration
        self.didFinish = didFinish
        self.didPickImage = didPickImage
        self.didPickVideo = didPickVideo

        manager = CMMotionManager()
        queue = OperationQueue()
        queue.qualityOfService = .utility

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(showCancelButton:didFinish:didPickImage:didPickVideo:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black
        setupBarButtons()
        orientation = UIDevice.current.orientation.isValidInterfaceOrientation ? UIDevice.current.orientation : .portrait
        setTitle()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: false)
        navigationController?.navigationBar.overrideUserInterfaceStyle = .dark
        navigationController?.navigationBar.isTranslucent = true
        navigationController?.navigationBar.backgroundColor = .clear
        startListeningForOrientation()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopListeningForOrientation()
    }

    private func setupBarButtons() {
        let backImage = UIImage(named: "NavbarClose")
        let backButton = UIButton(type: .system)
        backButton.setImage(backImage, for: .normal)
        backButton.addTarget(self, action: #selector(cancelAction), for: .touchUpInside)

        let backBarItem = UIBarButtonItem(customView: backButton)
        backBarItem.customView?.translatesAutoresizingMaskIntoConstraints = false
        backBarItem.customView?.heightAnchor.constraint(
            equalToConstant: CameraViewLayoutConstants.barButtonSize).isActive = true
        backBarItem.customView?.widthAnchor.constraint(
            equalToConstant: CameraViewLayoutConstants.barButtonSize).isActive = true

        navigationItem.leftBarButtonItem = backBarItem
    }

    private func setTitle() {
        switch configuration.format {
        case .normal:
            navigationItem.title = ""
        case .square:
            navigationItem.title = NSLocalizedString("title.camera.moment", value: "New Moment", comment: "Camera screen title for a new moment")
        }
    }

    private func setupUI() {
        var constraints: [NSLayoutConstraint] = []

        let contentView = UIStackView(frame: .zero)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.axis = .vertical
        contentView.alignment = .center
        view.addSubview(contentView)

        constraints.append(contentsOf: [
            contentView.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        contentView.addArrangedSubview(subtitleLabel)
        subtitleLabel.text = configuration.subtitle

        constraints.append(contentsOf: [
            subtitleLabel.topAnchor.constraint(equalTo: contentView.topAnchor),
            subtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 65),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -65),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])

        let frameView = CameraFrameView()
        frameView.axis = .vertical
        frameView.alignment = .center
        frameView.distribution = .equalSpacing
        frameView.layoutMargins = UIEdgeInsets(top: CameraViewLayoutConstants.verticalPadding, left: CameraViewLayoutConstants.horizontalPadding, bottom: CameraViewLayoutConstants.verticalPadding, right: CameraViewLayoutConstants.horizontalPadding)
        frameView.isLayoutMarginsRelativeArrangement = true
        contentView.addArrangedSubview(frameView)
        view.addSubview(contentView)

        constraints.append(contentsOf: [
            frameView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            frameView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            frameView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor),
            frameView.heightAnchor.constraint(equalToConstant: CameraViewLayoutConstants.getCameraFrameHeight(UIScreen.main.bounds.width, configuration: configuration)),
        ])

        let cameraController = CameraController(cameraDelegate: self, orientation: orientation, format: configuration.format)
        frameView.addArrangedSubview(cameraController.view)
        addChild(cameraController)
        cameraController.didMove(toParent: self)
        self.cameraController = cameraController

        constraints.append(contentsOf: [
            cameraController.view.widthAnchor.constraint(equalToConstant: CameraViewLayoutConstants.getCameraControllerWidth(UIScreen.main.bounds.width)),
            cameraController.view.heightAnchor.constraint(equalToConstant: CameraViewLayoutConstants.getCameraControllerHeight(UIScreen.main.bounds.width, configuration: configuration)),
        ])

        let controlStackView = UIStackView()
        controlStackView.translatesAutoresizingMaskIntoConstraints = false
        controlStackView.axis = .horizontal
        controlStackView.alignment = .center
        controlStackView.distribution = .fillEqually
        frameView.addArrangedSubview(controlStackView)

        constraints.append(contentsOf: [
            controlStackView.widthAnchor.constraint(equalToConstant: CameraViewLayoutConstants.getCameraControllerWidth(UIScreen.main.bounds.width)),
            controlStackView.heightAnchor.constraint(equalToConstant: CameraViewLayoutConstants.controlStackHeight),
        ])

        updateToggleFlashButton()
        toggleFlashButton.tintColor = .black
        toggleFlashButton.addTarget(self, action: #selector(toggleFlash), for: .touchUpInside)
        controlStackView.addArrangedSubview(toggleFlashButton)

        captureButton.addTarget(self, action: #selector(capture), for: .touchDown)
        controlStackView.addArrangedSubview(captureButton)

        flipCameraButton.setImage(cameraFlipImage, for: .normal)
        flipCameraButton.tintColor = .black
        flipCameraButton.addTarget(self, action: #selector(flipCamera), for: .touchUpInside)
        controlStackView.addArrangedSubview(flipCameraButton)

        updateButtonRotation()

        constraints.append(contentsOf: [
            toggleFlashButton.widthAnchor.constraint(equalToConstant: CameraViewLayoutConstants.toggleButtonSize),
            toggleFlashButton.heightAnchor.constraint(equalToConstant: CameraViewLayoutConstants.toggleButtonSize),
            flipCameraButton.widthAnchor.constraint(equalToConstant: CameraViewLayoutConstants.toggleButtonSize),
            flipCameraButton.heightAnchor.constraint(equalToConstant: CameraViewLayoutConstants.toggleButtonSize),
            captureButton.widthAnchor.constraint(equalToConstant: CameraViewLayoutConstants.captureButtonSize),
            captureButton.heightAnchor.constraint(equalToConstant: CameraViewLayoutConstants.captureButtonSize),
        ])

        let modeContainerView = UIStackView()
        modeContainerView.axis = .horizontal
        modeContainerView.layoutMargins = UIEdgeInsets(top: 0, left: CameraViewLayoutConstants.captureModeOptionWidth, bottom: 0, right: CameraViewLayoutConstants.captureModeOptionWidth)
        modeContainerView.isLayoutMarginsRelativeArrangement = true
        contentView.addArrangedSubview(modeContainerView)

        constraints.append(contentsOf: [
            modeContainerView.heightAnchor.constraint(equalToConstant: CameraViewLayoutConstants.captureModeOptionHeight),
            modeContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            modeContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

        modeScrollView.delegate = self
        modeContainerView.addGestureRecognizer(modeScrollView.panGestureRecognizer)
        modeContainerView.addArrangedSubview(modeScrollView)

        constraints.append(contentsOf: [
            modeScrollView.widthAnchor.constraint(equalToConstant: CameraViewLayoutConstants.captureModeOptionWidth),
            modeScrollView.heightAnchor.constraint(equalToConstant: CameraViewLayoutConstants.captureModeOptionHeight),
            modeScrollView.centerXAnchor.constraint(equalTo: modeContainerView.centerXAnchor),
        ])

        let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleModeTap))
        modeContainerView.addGestureRecognizer(gestureRecognizer)

        NSLayoutConstraint.activate(constraints)
    }

    @objc func handleModeTap(sender: UITapGestureRecognizer) {
        if sender.state == .ended {
            let point = sender.location(in: modeScrollView)
            if let mediaType = modeScrollView.handleTap(point: point) {
                captureMediaType = mediaType
            }
        }
    }

    @objc func toggleFlash() {
        guard let cameraController = cameraController, !cameraController.isRecordingVideo, !isTakingPhoto else { return }
        shouldUseFlashlight = !shouldUseFlashlight
        updateToggleFlashButton()
    }

    @objc func flipCamera() {
        guard let cameraController = cameraController, !cameraController.isRecordingVideo, !isTakingPhoto else { return }
        shouldUseBackCamera = !shouldUseBackCamera
        cameraController.switchCamera(shouldUseBackCamera)
    }

    @objc func capture(sender: CaptureButton) {
        guard let cameraController = cameraController else { return }
        if cameraController.isRecordingVideo {
            sender.playRestoreAnimation()
            cameraController.stopRecordingVideo()
            startListeningForOrientation()
        } else if !isTakingPhoto {
            switch captureMediaType {
            case .photo:
                sender.playPressAnimation(autoreverses: true, showCube: false)
                isTakingPhoto = cameraController.takePhoto(useFlashlight: shouldUseFlashlight)
            case .video:
                sender.playPressAnimation(autoreverses: false, showCube: true)
                videoRecordingToStart()
                cameraController.startRecordingVideo(to: CameraViewController.videoOutputURL)
            }
        }
    }

    private func updateToggleFlashButton() {
        toggleFlashButton.setImage(shouldUseFlashlight ? flashOnImage : flashOffImage, for: .normal)
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

    private func getRotationTransform() -> CGAffineTransform {
        let radians: CGFloat = {
            switch orientation {
            case .portraitUpsideDown:
                return CGFloat.pi
            case .landscapeLeft:
                return CGFloat.pi / 2
            case .landscapeRight:
                return CGFloat.pi * 3 / 2
            default:
                return 0
            }
        }()
        return CGAffineTransform.init(rotationAngle: radians)
    }

    private func updateButtonRotation() {
        let rotationTransform = getRotationTransform()
        flipCameraButton.transform = rotationTransform
        toggleFlashButton.transform = rotationTransform
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

            let orientation = self.computeOrientation(from: data)
            DispatchQueue.main.async {
                if orientation != self.orientation {
                    self.orientation = orientation
                    self.updateButtonRotation()
                    self.cameraController?.setOrientation(orientation)
                }
            }
        }
    }

    private func computeOrientation(from data: CMDeviceMotion) -> UIDeviceOrientation {
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

    private func showCameraFailureAlert(mediaType: MediaType) {
        DispatchQueue.main.async {
            let message = mediaType == .photo ? "Could not take a photo" : "Could not record a video"
            let alert = UIAlertController(title: message, message: nil, preferredStyle: UIAlertController.Style.alert)
            alert.addAction(UIAlertAction(title: "Click", style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
    }

    private func videoRecordingToStart() {
        flipCameraButton.alpha = 0
        toggleFlashButton.alpha = 0
        stopListeningForOrientation()
    }

    private func videoRecordingStopped() {
        startListeningForOrientation()
        flipCameraButton.alpha = 1
        toggleFlashButton.alpha = 1
    }
}

extension CameraViewController: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        scrollView.isUserInteractionEnabled = false
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        if let modeView = scrollView as? ModeScrollView {
            captureMediaType = modeView.currentMediaType
            modeView.updateLabelColor(selectedMediaType: captureMediaType)
        }
        scrollView.isUserInteractionEnabled = true
    }
}

extension CameraViewController: CameraDelegate {
    func cameraDidFlip(usingBackCamera: Bool) {
        shouldUseBackCamera = usingBackCamera
    }

    func goBack() {
        backAction()
    }

    func volumeButtonPressed() {
        guard let cameraController = cameraController else { return }
        if !cameraController.isRecordingVideo && !isTakingPhoto {
            isTakingPhoto = cameraController.takePhoto(useFlashlight: shouldUseFlashlight)
        }
    }

    func updateVideoTimer(timerSeconds: Int) {
        navigationItem.title = String(format: "%02d:%02d", timerSeconds / 60, timerSeconds % 60)
    }

    func resetVideoTimer() -> Void {
        setTitle()
    }

    func finishedTakingPhoto(_ photo: AVCapturePhoto, error: Error?, cropRect: CGRect?) {
        DDLogInfo("CameraViewController/photoOutput")

        defer {
            DispatchQueue.main.async {
                self.isTakingPhoto = false
            }
        }

        guard error == nil else {
            DDLogError("CameraViewController/photoOutput: \(error!)")
            return showCameraFailureAlert(mediaType: .photo)
        }

        guard let photoData = photo.fileDataRepresentation() else {
            DDLogError("CameraViewController/photoOutput: fileDataRepresentation returned nil")
            return showCameraFailureAlert(mediaType: .photo)
        }

        guard var uiImage = UIImage(data: photoData) else {
            DDLogError("CameraViewController/photoOutput: could not init UIImage from photoData")
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
            self.didPickImage(uiImage)
        }
    }

    func finishedRecordingVideo(to outputFileURL: URL, error: Error?) {
        DDLogInfo("CameraViewController/fileOutput")

        defer {
            DispatchQueue.main.async {
                self.videoRecordingStopped()
            }
        }

        if error != nil {
            DDLogError("CameraViewController/fileOutput: \(error!)")
        }

        guard FileManager.default.fileExists(atPath: outputFileURL.path) else {
            DDLogError("CameraViewController/fileOutput: \(outputFileURL) does not exist")
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
            DDLogError("CameraViewController/fileOutput: could not copy to \(pendingVideoURL)")
            return showCameraFailureAlert(mediaType: .video)
        }

        DispatchQueue.main.async {
            self.didPickVideo(pendingVideoURL)
        }
    }
}
