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
import CocoaLumberjackSwift
import CoreCommon
import Core

protocol CameraViewControllerDelegate: AnyObject {
    func cameraViewControllerDidReleaseShutter(_ viewController: NewCameraViewController)
    func cameraViewController(_ viewController: NewCameraViewController, didRecordVideoTo url: URL)
    func cameraViewController(_ viewController: NewCameraViewController, didCapture results: [CaptureResult], isFinished: Bool)
    func cameraViewController(_ viewController: NewCameraViewController, didSelect media: PendingMedia)
}

extension NewCameraViewController {

    struct Layout {
        static func cornerRadius(for style: Configuration = .normal) -> CGFloat {
            style == .moment ? 14 : 20
        }

        static func innerRadius(for style: Configuration = .normal) -> CGFloat {
            let difference: CGFloat = style == .moment ? 4 : 7
            return cornerRadius(for: style) - difference
        }

        static func padding(for style: Configuration = .normal) -> CGFloat {
            style == .moment ? 8 : 10
        }
    }

    private enum ViewfinderLayout {
        case primaryLeading, secondaryLeading, primaryFull, secondaryFull

        var toggled: Self {
            switch self {
            case .primaryLeading:
                return .primaryFull
            case .secondaryLeading:
                return .secondaryFull
            case .primaryFull:
                return .primaryLeading
            case .secondaryFull:
                return .secondaryLeading
            }
        }

        var flipped: Self {
            switch self {
            case .primaryLeading:
                return .secondaryLeading
            case .secondaryLeading:
                return .primaryLeading
            case .primaryFull:
                return .secondaryFull
            case .secondaryFull:
                return .primaryFull
            }
        }
    }
}

class NewCameraViewController: UIViewController {

    enum Configuration { case normal, moment }

    let configuration: Configuration
    private var layout: ViewfinderLayout = .primaryFull

    private lazy var model: CameraModel = {
        let forceSingleCamSession = MainAppContext.shared.userDefaults.bool(forKey: "moments.force.single.cam.session")
        let momentOptions: CameraModel.Options = forceSingleCamSession ? [] : [.multicam]
        let options: CameraModel.Options = configuration == .moment ? momentOptions : [.monitorOrientation]

        let model = CameraModel(options: options)
        return model
    }()

    private var cancellables: Set<AnyCancellable> = []

    private(set) lazy var primaryViewfinder: ViewfinderView = {
        let view = ViewfinderView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.delegate = self
        return view
    }()

    /// - note: Not used in non-multicam sessions.
    private lazy var secondaryViewfinder: ViewfinderView = {
        let view = ViewfinderView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.delegate = self
        return view
    }()

    private var viewfinderConstraints: [NSLayoutConstraint] = []

    var aspectRatio: CGFloat {
        configuration == .moment ? 1 : 4 / 3
    }

    private(set) lazy var background: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = configuration == .moment ? .momentPolaroid : .secondarySystemBackground
        view.layer.cornerRadius = Layout.cornerRadius(for: configuration)
        view.layer.cornerCurve = .continuous
        return view
    }()

    private lazy var viewfinderContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        view.backgroundColor = .black
        view.layer.cornerRadius = Layout.innerRadius(for: configuration)
        view.layer.cornerCurve = .continuous
        return view
    }()

    private lazy var controlsContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var shutterButton: CameraShutterButton = {
        let shutter = CameraShutterButton()
        shutter.translatesAutoresizingMaskIntoConstraints = false
        shutter.isEnabled = isEnabled
        shutter.onTap = { [weak self] in self?.handleShutterTap() }
        shutter.onLongPress = { [weak self] in self?.handleShutterLongPress($0) }
        return shutter
    }()

    private lazy var flipCameraButton: LargeHitButton = {
        let button = LargeHitButton(type: .system)
        button.targetIncrease = 12
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(named: "CameraFlip")?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.tintColor = configuration == .moment ? .black : .white.withAlphaComponent(0.9)
        button.addTarget(self, action: #selector(flipCameraPushed), for: .touchUpInside)
        return button
    }()

    private lazy var flashButton: LargeHitButton = {
        let button = LargeHitButton(type: .system)
        button.targetIncrease = 12
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(named: "CameraFlashOff")?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.tintColor = configuration == .moment ? .black : .white.withAlphaComponent(0.9)
        button.addTarget(self, action: #selector(flashButtonPushed), for: .touchUpInside)
        return button
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

    private(set) lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 16)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }()

    private lazy var selectionGenerator = UISelectionFeedbackGenerator()

    var onDismiss: (() -> Void)?

    var subtitle: String? {
        didSet { subtitleLabel.text = subtitle }
    }

    var hideControls: Bool = false {
        didSet { controlsContainer.isHidden = hideControls }
    }

    var isEnabled: Bool = true {
        didSet {
            if oldValue != isEnabled { refreshEnabledState() }
        }
    }

    weak var delegate: CameraViewControllerDelegate?

    init(style: Configuration = .normal) {
        self.configuration = style
        super.init(nibName: nil, bundle: nil)
    }

    required init(coder: NSCoder) {
        fatalError("CameraViewController coder init not implemented...")
    }

    deinit {
        model.stop(teardown: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        overrideUserInterfaceStyle = .dark

        model.delegate = self
        subscribeToModelUpdates()

        installUI()
        shutterButton.allowsLongPress = configuration != .moment
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        model.stop(teardown: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        model.start()
    }

    private func installUI() {
        view.addSubview(background)
        view.addSubview(viewfinderContainer)
        view.addSubview(controlsContainer)

        view.addSubview(videoDurationLabel)
        view.addSubview(subtitleLabel)

        viewfinderContainer.addSubview(primaryViewfinder)
        viewfinderContainer.addSubview(secondaryViewfinder)

        let leftContainer = UIView()
        let rightContainer = UIView()
        leftContainer.translatesAutoresizingMaskIntoConstraints = false
        rightContainer.translatesAutoresizingMaskIntoConstraints = false

        controlsContainer.addSubview(shutterButton)
        controlsContainer.addSubview(leftContainer)
        controlsContainer.addSubview(rightContainer)

        leftContainer.addSubview(flashButton)
        rightContainer.addSubview(flipCameraButton)

        let minimizeControlHeight = controlsContainer.heightAnchor.constraint(equalToConstant: 0)
        let backgroundWidth = background.widthAnchor.constraint(equalTo: view.widthAnchor)
        let backgroundCenterY = background.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        minimizeControlHeight.priority = UILayoutPriority(1)
        backgroundWidth.priority = .defaultHigh
        backgroundCenterY.priority = .defaultHigh

        let padding = Layout.padding(for: configuration)

        NSLayoutConstraint.activate([
            background.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            backgroundWidth,
            backgroundCenterY,

            viewfinderContainer.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: padding),
            viewfinderContainer.topAnchor.constraint(equalTo: background.topAnchor, constant: padding),
            viewfinderContainer.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -padding),
            viewfinderContainer.heightAnchor.constraint(equalTo: viewfinderContainer.widthAnchor, multiplier: aspectRatio),

            controlsContainer.topAnchor.constraint(equalTo: viewfinderContainer.bottomAnchor, constant: 12),
            controlsContainer.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            controlsContainer.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            controlsContainer.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -12),
            minimizeControlHeight,

            leftContainer.topAnchor.constraint(equalTo: controlsContainer.topAnchor),
            leftContainer.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor),
            leftContainer.trailingAnchor.constraint(equalTo: shutterButton.leadingAnchor, constant: -10),
            leftContainer.bottomAnchor.constraint(equalTo: controlsContainer.bottomAnchor),

            rightContainer.topAnchor.constraint(equalTo: controlsContainer.topAnchor),
            rightContainer.leadingAnchor.constraint(equalTo: shutterButton.trailingAnchor, constant: 10),
            rightContainer.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor),
            rightContainer.bottomAnchor.constraint(equalTo: controlsContainer.bottomAnchor),

            shutterButton.centerXAnchor.constraint(equalTo: controlsContainer.centerXAnchor),
            shutterButton.centerYAnchor.constraint(equalTo: controlsContainer.centerYAnchor),
            shutterButton.topAnchor.constraint(greaterThanOrEqualTo: controlsContainer.topAnchor, constant: 10),
            shutterButton.bottomAnchor.constraint(lessThanOrEqualTo: controlsContainer.bottomAnchor, constant: 10),

            flashButton.centerYAnchor.constraint(equalTo: leftContainer.centerYAnchor),
            flashButton.centerXAnchor.constraint(equalTo: leftContainer.centerXAnchor),
            flipCameraButton.centerYAnchor.constraint(equalTo: rightContainer.centerYAnchor),
            flipCameraButton.centerXAnchor.constraint(equalTo: rightContainer.centerXAnchor),

            videoDurationLabel.topAnchor.constraint(greaterThanOrEqualTo: subtitleLabel.bottomAnchor, constant: 30),
            videoDurationLabel.bottomAnchor.constraint(equalTo: background.topAnchor, constant: -10),
            videoDurationLabel.centerXAnchor.constraint(equalTo: background.centerXAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            subtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])

        if case .moment = configuration, model.isUsingMultipleCameras {
            layout = .primaryLeading
        }

        updateLayout(layout)

        installBarButtons()
        // have the buttons be disabled until the session is ready
        refreshEnabledState()
    }

    private func installBarButtons() {
        let configuration = UIImage.SymbolConfiguration(weight: .bold)
        let chevronImage = UIImage(systemName: "chevron.down", withConfiguration: configuration)?.withRenderingMode(.alwaysTemplate)
        let libraryImage = UIImage(systemName: "photo")?.withRenderingMode(.alwaysTemplate)

        let downButton = UIBarButtonItem(image: chevronImage, style: .plain, target: self, action: #selector(dismissTapped))
        let libraryButton = UIBarButtonItem(image: libraryImage, style: .plain, target: self, action: #selector(libraryTapped))

        downButton.tintColor = .white
        libraryButton.tintColor = .white
        navigationItem.leftBarButtonItem = downButton
        navigationItem.rightBarButtonItem = libraryButton

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

    @objc
    private func libraryTapped(_ sender: UIBarButtonItem) {
        let picker = MediaPickerViewController(config: .moment) { [weak self] picker, _, media, _ in
            picker.dismiss(animated: true)

            if let self = self, let media = media.first {
                self.delegate?.cameraViewController(self, didSelect: media)
            }
        }

        let nc = UINavigationController(rootViewController: picker)
        present(nc, animated: true)
    }

    private func subscribeToModelUpdates() {
        model.$orientation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.refresh(orientation: $0)
            }
            .store(in: &cancellables)

        model.$activeCamera
            .receive(on: DispatchQueue.main)
            .map { [weak self] in $0 != .unspecified && (self?.isEnabled ?? false) && (self?.model.session.isRunning ?? false) }
            .assign(to: \.isEnabled, onWeak: flipCameraButton)
            .store(in: &cancellables)

        model.$isFlashEnabled
            .receive(on: DispatchQueue.main)
            .map { UIImage(named: $0 ? "CameraFlashOn" : "CameraFlashOff")?.withRenderingMode(.alwaysTemplate) }
            .sink { [weak self] in
                self?.flashButton.setImage($0, for: .normal)
            }
            .store(in: &cancellables)

        model.$videoDuration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] seconds in
                self?.videoDurationLabel.isHidden = seconds == nil
                if let seconds = seconds {
                    self?.videoDurationLabel.text = self?.durationFormatter.string(from: TimeInterval(seconds))
                }
            }
            .store(in: &cancellables)

        model.$isRecordingVideo
            .receive(on: DispatchQueue.main)
            .map { !$0 }
            .assign(to: \.isEnabled, onWeak: flipCameraButton)
            .store(in: &cancellables)

        model.$isRecordingVideo
            .receive(on: DispatchQueue.main)
            .map { !$0 }
            .assign(to: \.isEnabled, onWeak: flashButton)
            .store(in: &cancellables)
    }

    private func refreshEnabledState() {
        let enabled = isEnabled && model.session.isRunning

        shutterButton.isEnabled = enabled
        flashButton.isEnabled = enabled
        flipCameraButton.isEnabled = enabled && model.activeCamera != .unspecified
    }

    func pause() {
        if model.session.isRunning {
            model.stop(teardown: false)
        }
    }

    func resume() {
        if !model.session.isRunning {
            model.start()
        }
    }

    private func handleShutterTap() {
        guard
            !model.isTakingPhoto,
            let type = captureType
        else {
            DDLogError("CameraViewController/handleShutterTap/no capture type")
            return
        }

        model.takePhoto(captureType: type) { [weak self] results, isFinished in
            if let self = self {
                self.delegate?.cameraViewController(self, didCapture: results, isFinished: isFinished)
            }
        }

        delegate?.cameraViewControllerDidReleaseShutter(self)
    }

    private var captureType: CaptureRequest.CaptureType? {
        guard let position = layout == .primaryFull || layout == .primaryLeading ? primaryViewfinder.cameraPosition : secondaryViewfinder.cameraPosition else {
            return nil
        }

        let type: CaptureRequest.CaptureType?
        switch configuration {
        case .normal:
            type = .single(position)

        case .moment where model.isUsingMultipleCameras && (layout == .primaryFull || layout == .secondaryFull):
            // user has toggled one of the previews to full screen, so we don't take the second photo
            type = .single(position)

        case .moment:
            type = .both(primary: position)
        }

        return type
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
        if model.isUsingMultipleCameras {
            updateLayout(layout.flipped, animated: false)
        } else {
            model.flipCamera()
        }
    }

    @objc
    private func flashButtonPushed(_ sender: UIButton) {
        model.isFlashEnabled = !model.isFlashEnabled
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

    private func updateLayout(_ newLayout: ViewfinderLayout, animated: Bool = true) {
        NSLayoutConstraint.deactivate(viewfinderConstraints)
        viewfinderConstraints = constraints(for: newLayout)
        NSLayoutConstraint.activate(viewfinderConstraints)

        layout = newLayout

        let isSplitLayout = newLayout == .primaryLeading || newLayout == .secondaryLeading
        let previewState: ViewfinderView.State = isSplitLayout ? .split : .full
        primaryViewfinder.state = previewState
        secondaryViewfinder.state = previewState

        if model.isUsingMultipleCameras {
            primaryViewfinder.hideToggle = newLayout == .secondaryLeading || newLayout == .secondaryFull
            secondaryViewfinder.hideToggle = !primaryViewfinder.hideToggle
        }

        if animated {
            let animator = UIViewPropertyAnimator(duration: 0.45,
                                             controlPoint1: .init(x: 0.19, y: 1),
                                             controlPoint2: .init(x: 0.22, y: 1))
            animator.addAnimations { self.view.layoutIfNeeded() }
            return animator.startAnimation()
        }

        view.layoutIfNeeded()
    }

    private func constraints(for layout: ViewfinderLayout) -> [NSLayoutConstraint] {
        let container = viewfinderContainer
        var constraints = [NSLayoutConstraint]()

        let mainViewfinder = layout == .primaryFull || layout == .primaryLeading ? primaryViewfinder : secondaryViewfinder
        let otherViewfinder = mainViewfinder === primaryViewfinder ? secondaryViewfinder : primaryViewfinder

        switch layout {
        case .primaryLeading, .secondaryLeading:
            constraints = [
                mainViewfinder.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                mainViewfinder.trailingAnchor.constraint(equalTo: container.centerXAnchor),
                otherViewfinder.leadingAnchor.constraint(equalTo: container.centerXAnchor),
                otherViewfinder.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ]

        case .primaryFull, .secondaryFull:
            constraints = [
                mainViewfinder.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                mainViewfinder.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                otherViewfinder.leadingAnchor.constraint(equalTo: container.trailingAnchor),
                otherViewfinder.widthAnchor.constraint(equalTo: mainViewfinder.widthAnchor),
            ]
        }

        constraints.append(contentsOf: [
            mainViewfinder.topAnchor.constraint(equalTo: container.topAnchor),
            mainViewfinder.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            otherViewfinder.topAnchor.constraint(equalTo: container.topAnchor),
            otherViewfinder.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return constraints
    }
}

// MARK: - CameraModel delegate methods

extension NewCameraViewController: CameraModelDelegate {

    func modelWillStart(_ model: CameraModel) {
        model.connect(preview: primaryViewfinder.previewLayer, to: .back)
        if model.isUsingMultipleCameras {
            model.connect(preview: secondaryViewfinder.previewLayer, to: .front)
        }

        primaryViewfinder.previewLayer.videoGravity = .resizeAspectFill
        secondaryViewfinder.previewLayer.videoGravity = .resizeAspectFill
    }

    func modelDidStart(_ model: CameraModel) {
        refreshEnabledState()
    }

    func modelDidStop(_ model: CameraModel) {
        refreshEnabledState()
    }

    func modelCouldNotStart(_ model: CameraModel, with error: Error) {
        guard case let error as CameraModel.CameraModelError = error else {
            return
        }

        switch error {
        case .permissions(let type):
            showPermissionAlert(for: type)
        default:
        #if targetEnvironment(simulator)
            DDLogInfo("setupAndStartSession/Ignoring invalid session as we are running on a simulator")
        #else
            showInitializationAlert(for: error)
        #endif
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

        present(alert, animated: true)
    }

    /// Shown when there was some initialization error and the session could not start.
    private func showInitializationAlert(for error: CameraModel.CameraModelError) {
        let title = Localizations.cameraInitializationErrorTtile
        let body = error.description
        let alert = UIAlertController(title: title, message: body, preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })

        present(alert, animated: true)
    }

    func model(_ model: CameraModel, didRecordVideoTo url: URL, error: Error?) {
        if case let error as CameraModel.CameraModelError = error {
            return showInitializationAlert(for: error)
        }

        delegate?.cameraViewController(self, didRecordVideoTo: url)
    }
}

// MARK: - ViewfinderViewDelegate methods

extension NewCameraViewController: ViewfinderViewDelegate {

    func viewfinderDidToggleExpansion(_ view: ViewfinderView) {
        let newLayout = layout.toggled
        selectionGenerator.selectionChanged()

        updateLayout(newLayout)
    }

    func viewfinder(_ view: ViewfinderView, focusedOn point: CGPoint) {
        if let position = view.cameraPosition {
            model.focus(position, on: point)
        }
    }

    func viewfinder(_ view: ViewfinderView, zoomedTo scale: CGFloat) {
        if let position = view.cameraPosition {
            model.zoom(position, to: scale)
        }
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
