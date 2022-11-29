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
import Photos
import CocoaLumberjackSwift
import CoreCommon
import Core

protocol CameraViewControllerDelegate: AnyObject {
    func cameraViewControllerDidReleaseShutter(_ viewController: NewCameraViewController)
    func cameraViewController(_ viewController: NewCameraViewController, didRecordVideoTo url: URL)
    func cameraViewController(_ viewController: NewCameraViewController, didCapture results: [CaptureResult], with preset: CameraPreset)
    func cameraViewController(_ viewController: NewCameraViewController, didSelect media: [PendingMedia])
}

class NewCameraViewController: UIViewController, CameraPresetConfigurable {

    let viewModel: CameraViewModel
    private var cancellables: Set<AnyCancellable> = []

    private lazy var viewfinderContainerHeightConstraint: NSLayoutConstraint = .init()

    private lazy var viewfinderContainer: ViewfinderContainer = {
        let view = ViewfinderContainer()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        view.backgroundColor = .black
        view.layer.cornerRadius = 10
        view.layer.cornerCurve = .continuous
        view.delegate = self
        return view
    }()

    private(set) lazy var background: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemFill
        view.layer.cornerRadius = 14
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        return view
    }()

    private lazy var subtitleContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var shutterButton: CameraShutterButton = {
        let shutter = CameraShutterButton()
        shutter.translatesAutoresizingMaskIntoConstraints = false
        shutter.onTap = { [weak self] in self?.handleShutterTap() }
        shutter.onLongPress = { [weak self] in self?.handleShutterLongPress($0) }
        return shutter
    }()

    private lazy var presetPicker: CameraPresetPicker = {
        let picker = CameraPresetPicker(presets: viewModel.presets)
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.isHidden = viewModel.presets.count <= 1

        picker.onSelection = { [weak self] preset in
            self?.viewModel.actions.send(.selectedPreset(preset))
        }

        return picker
    }()

    private lazy var flipCameraButton: LargeHitButton = {
        let button = LargeHitButton(type: .system)
        button.targetIncrease = 12
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "camera.rotate")?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.tintColor = .white
        button.addTarget(self, action: #selector(flipCameraPushed), for: .touchUpInside)
        return button
    }()

    private lazy var flashButton: UIBarButtonItem = {
        let button = UIBarButtonItem(image: UIImage(systemName: "bolt.slash"), style: .plain, target: nil, action: nil)
        return button
    }()

    private var durationLabelConstraints: [NSLayoutConstraint] = []
    private lazy var durationLabelContainer: UIView = {
        let view = UIView()
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))

        view.translatesAutoresizingMaskIntoConstraints = false
        blur.translatesAutoresizingMaskIntoConstraints = false

        view.layoutMargins = UIEdgeInsets(top: 7, left: 9, bottom: 7, right: 9)
        blur.layer.cornerRadius = 10
        blur.layer.cornerCurve = .continuous
        blur.layer.masksToBounds = true

        view.addSubview(blur)
        view.addSubview(videoDurationLabel)

        let minimizers = [view.heightAnchor.constraint(equalToConstant: 0), view.widthAnchor.constraint(equalToConstant: 0)]
        minimizers.forEach { $0.priority = UILayoutPriority(1) }

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blur.topAnchor.constraint(equalTo: view.topAnchor),
            blur.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            videoDurationLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            videoDurationLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            videoDurationLabel.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            videoDurationLabel.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor),
        ] + minimizers)

        view.isHidden = true
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

    private(set) lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 16)
        label.adjustsFontSizeToFitWidth = true
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }()

    private lazy var galleryImageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.preferredSymbolConfiguration = .init(pointSize: 22, weight: .medium)
        view.image = UIImage(systemName: "photo.on.rectangle")
        view.backgroundColor = .darkGray
        view.contentMode = .center
        view.tintColor = .lightGray
        view.clipsToBounds = true
        view.layer.cornerRadius = 10
        return view
    }()

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    var onDismiss: (() -> Void)?
    weak var delegate: CameraViewControllerDelegate?

    init(presets: [CameraPreset], initialPresetIndex: Int) {
        viewModel = CameraViewModel(presets: presets, initial: initialPresetIndex)
        super.init(nibName: nil, bundle: nil)
    }

    required init(coder: NSCoder) {
        fatalError("CameraViewController coder init not implemented...")
    }

    deinit {
        viewfinderContainer.primaryViewfinder.previewLayer.session = nil
        viewfinderContainer.secondaryViewfinder.previewLayer.session = nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        view.addSubview(subtitleContainer)
        view.addSubview(background)
        view.addSubview(viewfinderContainer)
        view.addSubview(shutterButton)
        view.addSubview(presetPicker)
        view.addSubview(galleryImageView)
        view.addSubview(flipCameraButton)
        view.addSubview(durationLabelContainer)
        subtitleContainer.addSubview(subtitleLabel)

        let maximizeBackgroundWidth = background.widthAnchor.constraint(equalTo: view.widthAnchor)
        let minimizePicker = presetPicker.heightAnchor.constraint(equalToConstant: 0)

        minimizePicker.priority = UILayoutPriority(1)
        maximizeBackgroundWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            subtitleContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            subtitleContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 50),
            subtitleContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -50),
            subtitleContainer.bottomAnchor.constraint(equalTo: background.topAnchor, constant: -10),

            subtitleLabel.topAnchor.constraint(greaterThanOrEqualTo: subtitleContainer.topAnchor),
            subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: subtitleContainer.bottomAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: subtitleContainer.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: subtitleContainer.trailingAnchor),
            subtitleLabel.centerYAnchor.constraint(equalTo: subtitleContainer.centerYAnchor),

            background.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            background.bottomAnchor.constraint(equalTo: presetPicker.topAnchor, constant: -15),
            maximizeBackgroundWidth,

            viewfinderContainer.leadingAnchor.constraint(equalTo: background.layoutMarginsGuide.leadingAnchor),
            viewfinderContainer.topAnchor.constraint(equalTo: background.layoutMarginsGuide.topAnchor),
            viewfinderContainer.trailingAnchor.constraint(equalTo: background.layoutMarginsGuide.trailingAnchor),

            shutterButton.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            shutterButton.topAnchor.constraint(equalTo: viewfinderContainer.bottomAnchor, constant: 15),
            shutterButton.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -15),

            presetPicker.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            presetPicker.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            presetPicker.bottomAnchor.constraint(equalTo: galleryImageView.topAnchor, constant: -20),
            minimizePicker,

            galleryImageView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            galleryImageView.widthAnchor.constraint(equalToConstant: 45),
            galleryImageView.heightAnchor.constraint(equalTo: galleryImageView.widthAnchor),
            galleryImageView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            flipCameraButton.centerYAnchor.constraint(equalTo: galleryImageView.centerYAnchor),
            flipCameraButton.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])

        let galleryTap = UITapGestureRecognizer(target: self, action: #selector(galleryTapped))
        galleryImageView.addGestureRecognizer(galleryTap)

        installBarButtons()
        formSubscriptions()

        fetchLatestPhoto()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.actions.send(.willAppear)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewModel.actions.send(.onDisappear)
    }

    private func installBarButtons() {
        let configuration = UIImage.SymbolConfiguration(weight: .bold)
        let chevronImage = UIImage(systemName: "chevron.down", withConfiguration: configuration)?.withRenderingMode(.alwaysTemplate)
        let downButton = UIBarButtonItem(image: chevronImage, style: .plain, target: self, action: #selector(dismissTapped))

        navigationItem.leftBarButtonItem = downButton
        navigationItem.rightBarButtonItem = flashButton

        let appearance = UINavigationBarAppearance()
        appearance.backgroundColor = .black
        appearance.shadowColor = nil

        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.overrideUserInterfaceStyle = .dark
    }

    func set(preset: CameraPreset, animator: UIViewPropertyAnimator?) {
        let currentPreset = viewModel.activePreset
        let allowsGalleryAccess = preset.options.contains(.galleryAccess)

        title = preset.title ?? Localizations.fabAccessibilityCamera
        subtitleLabel.text = preset.subtitle

        if let background = preset.backgroundView {
            updateBackgroundView(background)
        }

        updateAspectRatio(preset.aspectRatio)

        presetPicker.set(preset: preset, animator: animator)
        viewfinderContainer.set(preset: preset, animator: animator)

        func updates() {
            currentPreset?.backgroundView?.alpha = 0
            preset.backgroundView?.alpha = 1
            galleryImageView.alpha = allowsGalleryAccess ? 1 : 0
            galleryImageView.isUserInteractionEnabled = allowsGalleryAccess
        }

        animator?.addAnimations {
            updates()
            self.view.layoutIfNeeded()
        }

        animator?.addCompletion { [weak self] _ in
            currentPreset?.backgroundView?.removeFromSuperview()
            self?.viewModel.actions.send(.changedPreset)
        }

        if animator == nil {
            updates()
            viewModel.actions.send(.changedPreset)
        }

        animator?.startAnimation()
    }

    private func updateAspectRatio(_ aspectRatio: CGFloat) {
        viewfinderContainerHeightConstraint.isActive = false
        viewfinderContainerHeightConstraint = viewfinderContainer.heightAnchor.constraint(equalTo: viewfinderContainer.widthAnchor,
                                                                                       multiplier: aspectRatio)
        viewfinderContainerHeightConstraint.isActive = true
    }

    private func updateBackgroundView(_ background: UIView) {
        background.alpha = 0
        background.translatesAutoresizingMaskIntoConstraints = false

        self.background.addSubview(background)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: self.background.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: self.background.trailingAnchor),
            background.topAnchor.constraint(equalTo: self.background.topAnchor),
            background.bottomAnchor.constraint(equalTo: self.background.bottomAnchor),
        ])

        view.layoutIfNeeded()
    }

    @objc
    private func dismissTapped(_ sender: UIBarButtonItem) {
        onDismiss?()
        dismiss(animated: true)
    }

    @objc
    private func galleryTapped(_ gesture: UITapGestureRecognizer) {
        let picker = MediaPickerViewController(config: .init(destination: .feed(.all))) { [weak self] picker, _, media, _ in
            picker.dismiss(animated: true)

            if let self, !media.isEmpty {
                self.delegate?.cameraViewController(self, didSelect: media)
            }
        }

        let nc = UINavigationController(rootViewController: picker)
        present(nc, animated: true)
    }

    private func formSubscriptions() {
        var animatePresetChange = false
        viewModel.$activePreset
            .compactMap { $0 }
            .sink { [weak self] preset in
                let animator = animatePresetChange ? UIViewPropertyAnimator(duration: 0.3, curve: .easeInOut) : nil
                self?.set(preset: preset, animator: animator)
                animatePresetChange = true
            }
            .store(in: &cancellables)

        viewModel.$cameraModel
            .compactMap { $0 }
            .sink { [weak self] model in
                self?.connectViewfinders(to: model)
            }
            .store(in: &cancellables)

        viewModel.$orientation
            .sink { [weak self] in
                self?.refresh(orientation: $0)
            }
            .store(in: &cancellables)

        viewModel.$viewfinderState
            .sink { [weak self] state in
                guard let self, let state else {
                    return
                }

                let current = self.viewModel.viewfinderState ?? state
                let shouldUpdateLayout = !self.viewModel.isCurrentlyChangingPreset

                self.viewfinderContainer.change(from: current, to: state, updateLayout: shouldUpdateLayout)
            }
            .store(in: &cancellables)

        viewModel.photos
            .sink { [weak self] photos in
                self?.process(results: photos)
            }
            .store(in: &cancellables)

        viewModel.videos
            .sink { [weak self] url in
                guard let self else {
                    return
                }

                self.delegate?.cameraViewController(self, didRecordVideoTo: url)
            }
            .store(in: &cancellables)

        viewModel.$error
            .sink { [weak self] error in
                if let error {
                    self?.presentAlert(for: error)
                }
            }
            .store(in: &cancellables)

        viewModel.$isRecordingVideo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                let state: CameraShutterButton.State = isRecording ? .recording : .normal
                self?.shutterButton.setState(state, animated: animatePresetChange)
            }
            .store(in: &cancellables)
    }

    func pause() {
        viewModel.actions.send(.pause)
    }

    func resume() {
        viewModel.actions.send(.resume)
    }

    private func handleShutterTap() {
        delegate?.cameraViewControllerDidReleaseShutter(self)
        viewModel.actions.send(.tappedShutter)
    }

    private func handleShutterLongPress(_ ended: Bool) {
        let action: CameraViewModel.Action = ended ? .endedShutterLongPress : .beganShutterLongPress
        viewModel.actions.send(action)
    }
    
    @objc
    private func flipCameraPushed(_ sender: UIButton) {
        viewModel.actions.send(.flipCamera)
    }

    @objc
    private func flashButtonPushed(_ sender: UIButton) {
        viewModel.actions.send(.toggleFlash)
    }

    private func connectViewfinders(to session: CameraSessionManager) {
        let primary = viewfinderContainer.primaryViewfinder
        let secondary = viewfinderContainer.secondaryViewfinder

        session.connect(preview: primary.previewLayer, to: .back)
        if session.isUsingMultipleCameras {
            session.connect(preview: secondary.previewLayer, to: .front)
        }
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
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.5) {
            self.flashButton.customView?.transform = transform
            self.flipCameraButton.transform = transform
        }

        durationLabelContainer.transform = CGAffineTransform(rotationAngle: angle)
        let constraints: [NSLayoutConstraint]
        let distance: CGFloat = 25

        switch orientation {
        case .portrait, .portraitUpsideDown:
            let padding: CGFloat = orientation == .portrait ? distance : -distance
            let anchor = orientation == .portrait ? viewfinderContainer.topAnchor : viewfinderContainer.bottomAnchor
            constraints = [
                durationLabelContainer.centerYAnchor.constraint(equalTo: anchor, constant: padding),
                durationLabelContainer.centerXAnchor.constraint(equalTo: viewfinderContainer.centerXAnchor),
            ]

        case .landscapeRight, .landscapeLeft:
            let padding: CGFloat = orientation == .landscapeRight ? distance : -distance
            let anchor = orientation == .landscapeRight ? viewfinderContainer.leadingAnchor : viewfinderContainer.trailingAnchor
            constraints = [
                durationLabelContainer.centerXAnchor.constraint(equalTo: anchor, constant: padding),
                durationLabelContainer.centerYAnchor.constraint(equalTo: viewfinderContainer.centerYAnchor),
            ]
        default:
            constraints = []
        }

        NSLayoutConstraint.deactivate(durationLabelConstraints)
        durationLabelConstraints = constraints
        NSLayoutConstraint.activate(durationLabelConstraints)
    }

    private func fetchLatestPhoto() {
        let options = PHFetchOptions()
        options.sortDescriptors = [.init(key: "creationDate", ascending: false)]
        options.fetchLimit = 1

        guard let asset = PHAsset.fetchAssets(with: options).firstObject else {
            return
        }

        PHImageManager.default().requestImage(for: asset,
                                       targetSize: .init(width: 100, height: 100),
                                      contentMode: .aspectFill,
                                          options: nil) { image, mapping in

            DispatchQueue.main.async { [weak self] in
                self?.galleryImageView.image = image ?? self?.galleryImageView.image
            }
        }
    }
}

// MARK: - processing capture results

extension NewCameraViewController {

    private func process(results: [CaptureResult]) {
        guard let preset = viewModel.activePreset else {
            return
        }

        let cropToViewfinder = preset.options.contains(.cropToViewfinder)
        let mergeImages = preset.options.contains(.mergeMulticamImages)

        var results = results.map { cropToViewfinder ? crop(result: $0) : $0 }
        if mergeImages, results.count == 2 {
            results = merge(results: results)
        }

        // correct orientations
        results = results.map { result in
            guard let cgImage = result.image.cgImage else {
                return result
            }

            let correctedOrientation = correctedImageOrientation(original: result.image.imageOrientation, device: result.orientation)
            let corrected = UIImage(cgImage: cgImage, scale: result.image.scale, orientation: correctedOrientation).correctlyOrientedImage()

            return CaptureResult(identifier: result.identifier,
                                      image: corrected,
                             cameraPosition: result.cameraPosition,
                                orientation: .portrait,
                                     layout: result.layout,
                 resultsNeededForCompletion: result.resultsNeededForCompletion)
        }

        delegate?.cameraViewController(self, didCapture: results, with: preset)
    }

    private func merge(results: [CaptureResult]) -> [CaptureResult] {
        guard let layout = results.first?.layout else {
            return results
        }

        var merged: CaptureResult?

        switch layout {
        case .splitPortrait(leading: _):
            merged = mergePortrait(results: results)
        case .splitLandscape(top: _):
            merged = mergeLandscape(results: results)
        default:
            break
        }

        if let merged {
            return [merged]
        }

        return results
    }

    private func mergePortrait(results: [CaptureResult]) -> CaptureResult? {
        guard
            let position = results.first?.layout.primaryCameraPosition,
            let leading = results.first(where: { $0.cameraPosition == position }),
            let trailing = results.first(where: { $0.cameraPosition != position })
        else {
            return nil
        }

        let isRightToLeft = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
        let left = isRightToLeft ? trailing : leading
        let right = isRightToLeft ? leading : trailing

        let targetHeight = floor(max(left.image.size.height, right.image.size.height))
        let leftWidth = left.image.size.width * targetHeight / left.image.size.height
        let rightWidth = right.image.size.width * targetHeight / right.image.size.height
        let targetWidth = floor(max(leftWidth, rightWidth))

        let targetSize = CGSize(width: targetWidth, height: targetHeight)
        let leftRect = drawingRect(for: left.image, targetSize: targetSize)
        var rightRect = drawingRect(for: right.image, targetSize: targetSize)

        rightRect.origin.x += targetWidth
        UIGraphicsBeginImageContext(.init(width: targetWidth * 2, height: targetHeight))

        left.image.draw(in: leftRect)
        right.image.draw(in: rightRect)

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        if let image {
            return CaptureResult(identifier: left.identifier,
                                      image: image,
                             cameraPosition: .unspecified,
                                orientation: left.orientation,
                                     layout: left.layout,
                 resultsNeededForCompletion: 1)
        }

        return nil
    }

    private func mergeLandscape(results: [CaptureResult]) -> CaptureResult? {
        guard
            let position = results.first?.layout.primaryCameraPosition,
            let top = results.first(where: { $0.cameraPosition == position }),
            let bottom = results.first(where: { $0.cameraPosition != position })
        else {
            return nil
        }

        let targetWidth = floor(max(top.image.size.width, bottom.image.size.width))
        let topHeight = top.image.size.height * targetWidth / top.image.size.width
        let bottomHeight = bottom.image.size.height * targetWidth / bottom.image.size.width
        let targetHeight = floor(max(topHeight, bottomHeight))

        let targetSize = CGSize(width: targetWidth, height: targetHeight)
        let topRect = drawingRect(for: top.image, targetSize: targetSize)
        var bottomRect = drawingRect(for: bottom.image, targetSize: targetSize)

        bottomRect.origin.y += targetHeight
        UIGraphicsBeginImageContext(.init(width: targetWidth, height: targetHeight * 2))

        top.image.draw(in: topRect)
        bottom.image.draw(in: bottomRect)

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        if let image {
            return CaptureResult(identifier: top.identifier,
                                      image: image,
                             cameraPosition: .unspecified,
                                orientation: top.orientation,
                                     layout: top.layout,
                 resultsNeededForCompletion: 1)
        }

        return nil
    }

    /// - Returns: A capture result where `image` is cropped to what is visible in the viewfinder.
    private func crop(result: CaptureResult) -> CaptureResult {
        guard let cgImage = result.image.cgImage else {
            DDLogError("CameraViewController/crop-result/cgImage is nil")
            return result
        }

        let previewLayer: AVCaptureVideoPreviewLayer
        switch result.cameraPosition {
        case .back, .unspecified:
            previewLayer = viewfinderContainer.primaryViewfinder.previewLayer
        case .front:
            previewLayer = viewfinderContainer.secondaryViewfinder.previewLayer
        @unknown default:
            previewLayer = viewfinderContainer.primaryViewfinder.previewLayer
        }

        let viewfinderRect = previewLayer.metadataOutputRectConverted(fromLayerRect: previewLayer.bounds)
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        let cropRect = CGRect(x: viewfinderRect.origin.x * imageWidth,
                              y: viewfinderRect.origin.y * imageHeight,
                          width: viewfinderRect.size.width * imageWidth,
                         height: viewfinderRect.size.height * imageHeight)

        if let cropped = cgImage.cropping(to: cropRect) {
            let image = UIImage(cgImage: cropped, scale: result.image.scale, orientation: result.image.imageOrientation)
            return CaptureResult(identifier: result.identifier,
                                      image: image,
                             cameraPosition: result.cameraPosition,
                                orientation: result.orientation,
                                     layout: result.layout,
                 resultsNeededForCompletion: result.resultsNeededForCompletion)
        }

        return result
    }

    /// - note: Cropped images can have a very slight difference in their aspect ratios, causing the merged
    ///         image to sometimes have a white border along an edge. To fix this we make sure the image is
    ///         scaled so that it fills its portion of the output.
    private func drawingRect(for image: UIImage, targetSize: CGSize) -> CGRect {
        let targetWidth = targetSize.width
        let targetHeight = targetSize.height
        let aspect = image.size.width / image.size.height
        let drawingRect: CGRect

        if targetWidth / aspect > targetHeight {
            let height = targetWidth / aspect
            drawingRect = .init(x: 0,
                                y: (targetHeight - height) / 2,
                            width: targetWidth,
                           height: height)
        } else {
            let width = targetHeight * aspect
            drawingRect = .init(x: (targetWidth - width) / 2,
                                y: 0,
                            width: width,
                           height: targetHeight)
        }

        return drawingRect
    }

    private func correctedImageOrientation(original: UIImage.Orientation, device: UIDeviceOrientation) -> UIImage.Orientation {
        let final: UIImage.Orientation

        switch (original, device) {
        // merged image
        case (.up, .portrait):
            final = .up
        case (.up, .landscapeLeft):
            final = .left
        case (.up, .landscapeRight):
            final = .right
        case (.up, .portraitUpsideDown):
            final = .down
        // back camera
        case (.right, .portrait):
            final = .right
        case (.right, .landscapeLeft):
            final = .up
        case (.right, .landscapeRight):
            final = .down
        case (.right, .portraitUpsideDown):
            final = .left
        // front camera
        case (.leftMirrored, .portrait):
            final = .leftMirrored
        case (.leftMirrored, .landscapeLeft):
            final = .downMirrored
        case (.leftMirrored, .landscapeRight):
            final = .upMirrored
        case (.leftMirrored, .portraitUpsideDown):
            final = .rightMirrored

        default:
            final = original
        }

        return final
    }
}

// MARK: - presenting errors

extension NewCameraViewController {

    private func presentAlert(for error: CameraSessionError) {
#if targetEnvironment(simulator)
            DDLogInfo("setupAndStartSession/Ignoring invalid session as we are running on a simulator")
            return
#endif

        let title = error.title
        let description = error.description
        let alert = UIAlertController(title: title, message: description, preferredStyle: .alert)

        switch error {
        case .permissions(_):
            alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel) { [weak self] _ in
                self?.dismiss(animated: true)
            })

            alert.addAction(UIAlertAction(title: Localizations.settingsAppName, style: .default) { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            })

        default:
            alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default) { [weak self] _ in
                self?.dismiss(animated: true)
            })
        }

        present(alert, animated: true)
    }
}

// MARK: - ViewfinderContainerDelegate methods

extension NewCameraViewController: ViewfinderContainerDelegate {

    func viewfinderContainerDidSelectLayoutChange(_ container: ViewfinderContainer) {
        viewModel.actions.send(.pushedNextLayout)
    }

    func viewfinderContainerDidToggleExpansion(_ container: ViewfinderContainer) {
        viewModel.actions.send(.pushedToggleLayout)
    }

    func viewfinderContainerDidCompleteLayoutChange(_ container: ViewfinderContainer) {
        viewModel.actions.send(.completedNextLayout)
    }

    func viewfinder(_ view: ViewfinderView, focusedOn point: CGPoint) {
        if let position = view.cameraPosition {
            viewModel.actions.send(.tappedFocus(position, point))
        }
    }

    func viewfinder(_ view: ViewfinderView, zoomedTo scale: CGFloat) {
        if let position = view.cameraPosition {
            viewModel.actions.send(.pinchedZoom(position, scale))
        }
    }
}
