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

class NewCameraViewController: UIViewController {

    private lazy var model = CameraModel()
    private lazy var preview: CameraPreviewView = {
        let view = CameraPreviewView()
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

    private lazy var shutterButton: CameraShutterButton = {
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
        return button
    }()

    private var cancellables: Set<AnyCancellable> = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark

        model.delegate = self
        subscribeToModelUpdates()
        model.start()

        installUI()

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinchedToZoom))
        preview.addGestureRecognizer(pinch)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        model.stop()
    }

    private func installUI() {
        let background = UIView()
        background.translatesAutoresizingMaskIntoConstraints = false
        background.backgroundColor = .secondarySystemBackground

        view.addSubview(background)
        view.addSubview(preview)
        view.addSubview(controlStack)

        NSLayoutConstraint.activate([
            background.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            background.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            background.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -2),
            background.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor),
            background.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),

            preview.topAnchor.constraint(equalTo: background.topAnchor, constant: 10),
            preview.widthAnchor.constraint(equalTo: background.widthAnchor, constant: -20),
            preview.heightAnchor.constraint(equalTo: preview.widthAnchor, multiplier: 4 / 3),
            preview.centerXAnchor.constraint(equalTo: background.centerXAnchor),

            controlStack.topAnchor.constraint(equalTo: preview.bottomAnchor),
            controlStack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            controlStack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            controlStack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])

        background.layer.cornerRadius = 20
        preview.previewLayer.cornerRadius = 15
    }

    private func subscribeToModelUpdates() {
        // TODO: subscribe to rotation, flash state, camera state changes
        model.$orientation.receive(on: DispatchQueue.main).sink { [weak self] orientation in
            self?.refresh(orientation: orientation)
        }.store(in: &cancellables)
    }

    private func handleShutterTap() {
        // TODO:
    }

    private func handleShutterLongPress(_ ended: Bool) {
        // TODO:
    }
    
    @objc
    private func flipCameraPushed(_ sender: UIButton) {
        // TODO:
    }

    @objc
    private func pinchedToZoom(_ gesture: UIPinchGestureRecognizer) {
        model.zoom(using: gesture)
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
        guard case let error as CameraModel.Error = error else {
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
    private func showInitializationAlert(for error: CameraModel.Error) {
        let title = Localizations.cameraInitializationErrorTtile
        let body = error.description
        let alert = UIAlertController(title: title, message: body, preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })
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
