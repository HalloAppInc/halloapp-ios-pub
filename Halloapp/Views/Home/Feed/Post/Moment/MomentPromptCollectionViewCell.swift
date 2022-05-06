//
//  MomentPromptCollectionViewCell.swift
//  HalloApp
//
//  Created by Tanveer on 5/5/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import AVFoundation
import CoreCommon
import Combine

class MomentPromptCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "momentPromptCell"

    private var previewViewLeading: NSLayoutConstraint?
    private var previewViewTrailing: NSLayoutConstraint?

    private(set) lazy var promptView: MomentPromptView = {
        let view = MomentPromptView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        preservesSuperviewLayoutMargins = true
        contentView.preservesSuperviewLayoutMargins = true

        let spacing = FeedPostCollectionViewCell.LayoutConstants.interCardSpacing / 2

        contentView.addSubview(promptView)

        let leading = promptView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
        let trailing = promptView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        NSLayoutConstraint.activate([
            leading,
            trailing,
            promptView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: spacing),
            promptView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -spacing),
            promptView.heightAnchor.constraint(equalTo: promptView.widthAnchor),
        ])

        previewViewLeading = leading
        previewViewTrailing = trailing
    }

    required init?(coder: NSCoder) {
        fatalError("MomentPromptCollectionViewCell coder init not implemented")
    }

    override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()

        previewViewLeading?.constant = layoutMargins.left * FeedPostCollectionViewCell.LayoutConstants.backgroundPanelHMarginRatio * 5

        previewViewTrailing?.constant = -layoutMargins.right * FeedPostCollectionViewCell.LayoutConstants.backgroundPanelHMarginRatio * 5
    }
}

final class MomentPromptView: UIView {
    typealias Permissions = AVAuthorizationStatus
    private(set) var permissions: Permissions = .notDetermined {
        didSet {
            if oldValue != permissions { updateState() }
        }
    }

    private lazy var session = AVCaptureSession()
    private var cancellables: Set<AnyCancellable> = []

    private lazy var previewView: AVCapturePreviewView = {
        let view = AVCapturePreviewView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = FeedPostCollectionViewCell.LayoutConstants.backgroundCornerRadius
        view.layer.cornerCurve = .continuous
        view.layer.masksToBounds = true
        return view
    }()

    private lazy var blurView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = FeedPostCollectionViewCell.LayoutConstants.backgroundCornerRadius
        view.layer.masksToBounds = true
        return view
    }()

    private lazy var overlayStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [displayLabel, actionButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.distribution = .equalSpacing
        stack.alignment = .center
        stack.spacing = 15
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        return stack
    }()

    private lazy var displayLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(forTextStyle: .body, weight: .regular, maximumPointSize: 30)
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .center
        return label
    }()

    private lazy var actionButton: CapsuleButton = {
        let button = CapsuleButton()
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        button.setBackgroundColor(.systemBlue, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.layer.masksToBounds = true
        button.addTarget(self, action: #selector(actionButtonPushed), for: .touchUpInside)
        button.titleLabel?.font = .systemFont(forTextStyle: .body, weight: .medium, maximumPointSize: 30)
        return button
    }()

    var openSettings: (() -> Void)?
    var openCamera: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .feedPostBackground
        layer.cornerRadius = FeedPostCollectionViewCell.LayoutConstants.backgroundCornerRadius
        layer.masksToBounds = false
        clipsToBounds = false

        layer.shadowOpacity = 0.75
        layer.shadowColor = UIColor.feedPostShadow.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 5)
        layer.shadowRadius = 5

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification, object: nil).sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.permissions = AVCaptureDevice.authorizationStatus(for: .video)
            }
        }.store(in: &cancellables)

        permissions = AVCaptureDevice.authorizationStatus(for: .video)
        installViews()
        updateState()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    private func installViews() {
        addSubview(previewView)
        addSubview(blurView)
        addSubview(overlayStack)

        let spacing: CGFloat = 10

        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: spacing),
            previewView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -spacing),
            previewView.topAnchor.constraint(equalTo: topAnchor, constant: spacing),
            previewView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -spacing),
            blurView.leadingAnchor.constraint(equalTo: previewView.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: previewView.trailingAnchor),
            blurView.topAnchor.constraint(equalTo: previewView.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: previewView.bottomAnchor),
            overlayStack.topAnchor.constraint(greaterThanOrEqualTo: previewView.topAnchor),
            overlayStack.bottomAnchor.constraint(lessThanOrEqualTo: previewView.bottomAnchor),
            overlayStack.leadingAnchor.constraint(equalTo: previewView.leadingAnchor),
            overlayStack.trailingAnchor.constraint(equalTo: previewView.trailingAnchor),
            overlayStack.centerYAnchor.constraint(equalTo: previewView.centerYAnchor),
        ])
    }

    private func setupSession() {
        guard permissions == .authorized else {
            return
        }

        session.beginConfiguration()
        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
        }

        guard
            let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let backInput = try? AVCaptureDeviceInput(device: backCamera),
            session.canAddInput(backInput)
        else {
            return session.commitConfiguration()
        }

        session.addInput(backInput)
        session.commitConfiguration()

        previewView.previewLayer.session = session
    }

    func startSession() {
        DispatchQueue.global(qos: .default).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func stopSession() {
        DispatchQueue.global(qos: .default).async { [weak self] in
            self?.session.stopRunning()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: FeedPostCollectionViewCell.LayoutConstants.backgroundCornerRadius).cgPath
    }

    private func updateState() {
        switch permissions {
        case .authorized:
            setupSession()
            displayPermissionAllowedState()
        case .denied, .restricted:
            displayPermissionDeniedState()
        case .notDetermined:
            displayPermissionNotDeterminedState()
        @unknown default:
            break
        }

        setNeedsLayout()
    }

    private func displayPermissionDeniedState() {
        displayLabel.text = Localizations.shareMomentCameraAccess
        actionButton.setTitle(Localizations.buttonGoToSettings, for: .normal)
        previewView.backgroundColor = .black
    }

    private func displayPermissionNotDeterminedState() {
        displayLabel.text = Localizations.shareMomentCameraAccess
        actionButton.setTitle(Localizations.allowCameraAccess, for: .normal)
    }

    private func displayPermissionAllowedState() {
        displayLabel.text = Localizations.shareMoment
        actionButton.setTitle(Localizations.openCamera, for: .normal)
    }

    @objc
    private func actionButtonPushed(_ button: UIButton) {
        switch permissions {
        case .authorized:
            openCamera?()
        case .denied, .restricted:
            openSettings?()
        case .notDetermined:
            Task { permissions = await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied }
        @unknown default:
            break
        }
    }
}

// MARK: - AVCapturePreviewView implementation

fileprivate class AVCapturePreviewView: UIView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)

        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}

fileprivate class CapsuleButton: UIButton {
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2.0
    }
}

// MARK: - localization

extension Localizations {
    static var shareMoment: String {
        NSLocalizedString("share.moment.prompt",
                   value: "Share a moment",
                 comment: "Prompt for the user to share a moment.")
    }

    static var shareMomentCameraAccess: String {
        NSLocalizedString("share.moment.camera.permission",
                   value: "Allow camera access to share a moment",
                 comment: "Alert that tells the user to allow camera access to share a moment.")
    }

    static var allowCameraAccess: String {
        NSLocalizedString("camera.permission.allow.access",
                   value: "Allow access",
                 comment: "Title of the button that allows camera permissions.")
    }

    static var openCamera: String {
        NSLocalizedString("open.camera",
                   value: "Open Camera",
                 comment: "Title of the button that opens the camera.")
    }
}
