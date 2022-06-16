//
//  NewCameraViewController.swift
//  HalloApp
//
//  Created by Tanveer on 5/28/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import AVFoundation
import CoreCommon
import Core

extension NewCameraViewController {
    struct Layout {
        static func cornerRadius(for style: Configuration = .normal) -> CGFloat {
            style == .moment ? 12 : 20
        }

        static func innerRadius(for style: Configuration = .normal) -> CGFloat {
            let difference: CGFloat = style == .moment ? 4 : 7
            return cornerRadius(for: style) - difference
        }

        static func padding(for style: Configuration = .normal) -> CGFloat {
            style == .moment ? 8 : 10
        }
    }
}

class NewCameraViewController: UIViewController {
    enum Configuration { case normal, moment }

    let configuration: Configuration

    private lazy var model = CameraModel()
    private lazy var preview: CameraPreviewView = {
        let view = CameraPreviewView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    var aspectRatio: CGFloat {
        configuration == .moment ? 1 : 4 / 3
    }

    private(set) lazy var background: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var controlStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [flashButton, shutterButton, flipCameraButton])
        stack.axis = .horizontal
        stack.distribution = .equalCentering
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 15, left: 40, bottom: 15, right: 40)
        return stack
    }()

    private(set) lazy var shutterButton: CameraShutterButton = {
        let shutter = CameraShutterButton()
        shutter.isEnabled = false
        shutter.onTap = { [weak self] in self?.handleShutterTap() }
        shutter.onLongPress = { [weak self] in self?.handleShutterLongPress($0) }
        return shutter
    }()

    private lazy var zoomButton: CameraButton = {
        let button = CameraButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = .systemFont(ofSize: 11)
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.setBackgroundColor(.tertiarySystemBackground.withAlphaComponent(0.75), for: .normal)
        button.layer.borderWidth = 0.5
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        return button
    }()

    private lazy var flipCameraButton: CameraButton = {
        let button = CameraButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(named: "CameraFlip")?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.tintColor = .white
        button.setBackgroundColor(.tertiarySystemBackground, for: .normal)
        button.addTarget(self, action: #selector(flipCameraPushed), for: .touchUpInside)
        return button
    }()

    private lazy var flashButton: CameraButton = {
        let button = CameraButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(named: "CameraFlashOff")?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.tintColor = .white
        button.setBackgroundColor(.tertiarySystemBackground, for: .normal)
        button.addTarget(self, action: #selector(flashButtonPushed), for: .touchUpInside)
        return button
    }()

    private lazy var focusIndicator: CircleView = {
        let view = CircleView(frame: CGRect(origin: .zero, size: CGSize(width: 40, height: 40)))
        view.fillColor = .clear
        view.lineWidth = 1.75
        view.strokeColor = .white
        view.alpha = 0
        return view
    }()

    private lazy var videoDurationLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.font = .systemFont(ofSize: 16)
        return label
    }()

    private lazy var durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.allowedUnits = [.second, .minute]
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 15)
        return label
    }()

    private var hideFocusIndicator: DispatchWorkItem?
    private var cancellables: Set<AnyCancellable> = []

    var onPhotoCapture: ((UIImage) -> Void)?
    var onVideoCapture: ((URL) -> Void)?
    var onDismiss: (() -> Void)?

    var subtitle: String? {
        didSet { subtitleLabel.text = subtitle }
    }

    init(style: Configuration = .normal) {
        self.configuration = style
        super.init(nibName: nil, bundle: nil)
    }

    required init(coder: NSCoder) {
        fatalError("CameraViewController coder init not implemented...")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark

        model.delegate = self
        subscribeToModelUpdates()

        installUI()

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinchedToZoom))
        preview.addGestureRecognizer(pinch)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tappedToFocus))
        preview.addGestureRecognizer(tap)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        model.stop()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.start()
    }

    private func installUI() {
        background.backgroundColor = configuration == .moment ? .momentPolaroid : .secondarySystemBackground

        view.addSubview(background)
        view.addSubview(preview)
        view.addSubview(controlStack)
        preview.addSubview(focusIndicator)
        view.addSubview(videoDurationLabel)
        view.addSubview(subtitleLabel)

        let padding = Layout.padding(for: configuration)

        NSLayoutConstraint.activate([
            background.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            background.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -2),
            background.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor),
            background.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor),

            preview.topAnchor.constraint(equalTo: background.topAnchor, constant: padding),
            preview.widthAnchor.constraint(equalTo: background.widthAnchor, constant: -padding * 2),
            preview.heightAnchor.constraint(equalTo: preview.widthAnchor, multiplier: aspectRatio),
            preview.centerXAnchor.constraint(equalTo: background.centerXAnchor),

            controlStack.topAnchor.constraint(equalTo: preview.bottomAnchor),
            controlStack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            controlStack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            controlStack.bottomAnchor.constraint(equalTo: background.bottomAnchor),

            videoDurationLabel.bottomAnchor.constraint(equalTo: background.topAnchor, constant: -10),
            videoDurationLabel.centerXAnchor.constraint(equalTo: background.centerXAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 25),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -25),
            subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: videoDurationLabel.topAnchor, constant: -30),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])

        background.layer.cornerRadius = Layout.cornerRadius(for: configuration)
        preview.previewLayer.cornerRadius = Layout.innerRadius(for: configuration)

        if case .moment = configuration {
            preview.previewLayer.videoGravity = .resizeAspectFill
        }

        installBarButtons()
    }

    private func installBarButtons() {
        let image = UIImage(systemName: "chevron.down")?.withRenderingMode(.alwaysTemplate)
        let barButton = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(dismissTapped))
        barButton.tintColor = .white
        navigationItem.leftBarButtonItem = barButton

        let appearance = UINavigationBarAppearance()
        appearance.backgroundColor = .black
        appearance.shadowColor = nil
        appearance.titleTextAttributes = [.font: UIFont.gothamFont(ofFixedSize: 16, weight: .medium)]

        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.overrideUserInterfaceStyle = .dark
    }

    @objc
    private func dismissTapped(_ sender: UIBarButtonItem) {
        onDismiss?()
        dismiss(animated: true)
    }

    private func subscribeToModelUpdates() {
        model.$orientation.receive(on: DispatchQueue.main).sink { [weak self] orientation in
            self?.refresh(orientation: orientation)
        }.store(in: &cancellables)

        model.$activeCamera.receive(on: DispatchQueue.main).sink { [weak self] active in
            self?.flipCameraButton.isEnabled = active != .unspecified
        }.store(in: &cancellables)

        model.$isFlashEnabled.receive(on: DispatchQueue.main).sink { [weak self] enabled in
            let name = enabled ? "CameraFlashOn" : "CameraFlashOff"
            let image = UIImage(named: name)?.withRenderingMode(.alwaysTemplate)
            self?.flashButton.setImage(image, for: .normal)
        }.store(in: &cancellables)

        model.$videoDuration.receive(on: DispatchQueue.main).sink { [weak self] seconds in
            self?.videoDurationLabel.isHidden = seconds == nil
            if let seconds = seconds {
                self?.videoDurationLabel.text = self?.durationFormatter.string(from: TimeInterval(seconds))
            }
        }.store(in: &cancellables)

        model.$isRecordingVideo.receive(on: DispatchQueue.main).sink { [weak self] isRecording in
            self?.flipCameraButton.isEnabled = !isRecording
            self?.flashButton.isEnabled = !isRecording
        }.store(in: &cancellables)
    }

    private func handleShutterTap() {
        model.takePhoto()
    }

    private func handleShutterLongPress(_ ended: Bool) {
        if ended {
            model.stopRecording()
        } else {
            model.startRecording()
        }
    }
    
    @objc
    private func flipCameraPushed(_ sender: UIButton) {
        model.flipCamera()
    }

    @objc
    private func flashButtonPushed(_ sender: UIButton) {
        model.isFlashEnabled = !model.isFlashEnabled
    }

    @objc
    private func pinchedToZoom(_ gesture: UIPinchGestureRecognizer) {
        model.zoom(using: gesture)
    }

    @objc
    private func tappedToFocus(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: preview)

        model.focus(on: point)
        showFocusIndicator(for: point)
    }

    private func showFocusIndicator(for point: CGPoint) {
        hideFocusIndicator?.cancel()

        focusIndicator.alpha = 0
        focusIndicator.center = point
        focusIndicator.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)

        UIView.animate(withDuration: 0.15,
                              delay: 0,
             usingSpringWithDamping: 0.7,
              initialSpringVelocity: 0.5,
                            options: [.allowUserInteraction])
        {
            self.focusIndicator.transform = .identity
            self.focusIndicator.alpha = 1
        } completion: { [weak self] _ in
            self?.scheduleFocusIndicatorHide()
        }
    }

    private func scheduleFocusIndicatorHide() {
        let item = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.15,
                                  delay: 0,
                 usingSpringWithDamping: 0.7,
                  initialSpringVelocity: 0.5,
                                options: [.allowUserInteraction])
            {
                self?.focusIndicator.alpha = 0
                self?.focusIndicator.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
            } completion: { _ in
                self?.hideFocusIndicator = nil
            }
        }

        hideFocusIndicator = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
    }

    private func refresh(orientation: UIDeviceOrientation) {
        let angle: CGFloat
        switch orientation {
        case .portraitUpsideDown:
            angle = .pi
        case .landscapeLeft:
            angle = .pi / 2
        case .landscapeRight:
            angle = .pi * 3 / 2
        default:
            angle = 0
        }

        let transform = CGAffineTransform(rotationAngle: angle)
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5) {
            self.flashButton.transform = transform
            self.flipCameraButton.transform = transform
        }
    }
}

// MARK: - CameraModel delegate methods

extension NewCameraViewController: CameraModelDelegate {
    func modelWillStart(_ model: CameraModel) {
        preview.previewLayer.session = model.session
    }

    func modelDidStart(_ model: CameraModel) {
        shutterButton.isEnabled = true
    }

    func modelCoultNotStart(_ model: CameraModel, with error: Error) {
        guard case let error as CameraModel.CameraModelError = error else {
            return
        }

        switch error {
        case .permissions(let type):
            showPermissionAlert(for: type)
        default:
            showInitializationAlert(for: error)
        }
    }

    /// Shown when the the app lacks either camera or microphone permissions.
    private func showPermissionAlert(for type: AVMediaType) {
        let title = type == .video ? Localizations.cameraAccessPromptTitle : Localizations.microphoneAccessPromptTitle
        let body = type == .video ? Localizations.cameraAccessPromptBody : Localizations.microphoneAccessPromptBody
        let alert = UIAlertController(title: title, message: body, preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel) { [weak self] _ in
            self?.dismiss(animated: true)
        })

        alert.addAction(UIAlertAction(title: Localizations.settingsAppName, style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
    }

    /// Shown when there was some initialization error and the session could not start.
    private func showInitializationAlert(for error: CameraModel.CameraModelError) {
        let title = Localizations.cameraInitializationErrorTtile
        let body = error.description
        let alert = UIAlertController(title: title, message: body, preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })
    }

    func model(_ model: CameraModel, didTake photo: UIImage) {
        if case .moment = configuration {
            let cropped = cropImageForMoment(photo)
            onPhotoCapture?(cropped)
        } else {
            onPhotoCapture?(photo)
        }
    }

    private func cropImageForMoment(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else {
            return image
        }

        let rect = preview.previewLayer.metadataOutputRectConverted(fromLayerRect: preview.previewLayer.bounds)
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let crop = CGRect(x: rect.origin.x * width,
                          y: rect.origin.y * height,
                      width: rect.width * width,
                     height: rect.height * height)

        if let cropped = cgImage.cropping(to: crop) {
            return UIImage(cgImage: cropped, scale: 1.0, orientation: image.imageOrientation)
        }

        return image
    }

    func model(_ model: CameraModel, didRecordVideoTo url: URL, error: Error?) {
        if case let error as CameraModel.CameraModelError = error {
            return showInitializationAlert(for: error)
        }

        onVideoCapture?(url)
    }
}

// MARK: - CameraPreviewView implementation

/// A wrapper view for `AVCaptureVideoPreviewLayer`, so that it can be used with autolayout.
fileprivate class CameraPreviewView: UIView {
    private(set) lazy var previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)

        layer.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("CameraPreviewView coder init not implemented...")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}

// MARK: - CameraButton implementation

fileprivate class CameraButton: UIButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true

        contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalTo: widthAnchor).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("Circle button coder init not implemented...")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

// MARK: - localization

extension Localizations {
    static var cameraAccessPromptTitle: String {
        NSLocalizedString("camera.permissions.title",
                   value: "Camera Access",
                 comment: "Title of alert for when the app does not have permissions to access the camera.")
    }

    static var cameraAccessPromptBody: String {
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

    static var cameraInitializationErrorTtile: String {
        NSLocalizedString("camera.init.error.title",
                   value: "Initialization Error",
                 comment: "Title for a popup alerting about camera initialization error.")
    }
}
