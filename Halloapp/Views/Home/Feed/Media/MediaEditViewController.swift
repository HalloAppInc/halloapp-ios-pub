//
//  MediaEditViewController.swift
//  HalloApp
//
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVKit
import Combine
import Core
import CoreCommon
import Dispatch
import Foundation
import SwiftUI
import UIKit

private extension Localizations {

    static var voiceOverButtonClose: String {
        NSLocalizedString("media.voiceover.button.close", value: "Close", comment: "Accessibility label for X (Close) button in media editor.")
    }

    static var voiceOverButtonRotate: String {
        NSLocalizedString("media.voiceover.button.rotate", value: "Rotate", comment: "Accessibility label for a button in media editor. Refers to media editing action.")
    }

    static var voiceOverButtonFlip: String {
        NSLocalizedString("media.voiceover.button.flip", value: "Flip", comment: "Accessibility label for a button in media editor. Refers to media editing action.")
    }

    static var voiceOverButtonDraw: String {
        NSLocalizedString("media.voiceover.button.draw", value: "Draw", comment: "Accessibility label for a button in media editor. Refers to media editing action.")
    }

    static var voiceOverButtonAnnotate: String {
        NSLocalizedString("media.voiceover.button.annotate", value: "Annotate", comment: "Accessibility label for a button in media editor. Refers to media editing action.")
    }

    static var voiceOverButtonMute: String {
        NSLocalizedString("media.voiceover.button.mute", value: "Mute", comment: "Accessibility label for a button in media editor. Refers to media editing action.")
    }

    static var discardConfirmationPrompt: String {
        NSLocalizedString("media.discard.confirmation", value: "Would you like to discard your edits?", comment: "Confirmation prompt in media composer.")
    }

    static var buttonReset: String {
        NSLocalizedString("media.button.reset", value: "Reset", comment: "Button title. Refers to resetting photo / video to original version.")
    }

    static var buttonUndo: String {
        NSLocalizedString("media.button.undo", value: "Undo", comment: "Button title. Refers to undoing an edit of a photo.")
    }
}

fileprivate struct Constants {
    static let previewSize: CGFloat = 80
}

typealias MediaEditViewControllerCallback = (MediaEditViewController, [PendingMedia], Int, Bool) -> Void

enum MediaEditCropRegion {
    case circle, square, any
}

struct MediaEditMode: OptionSet {
    let rawValue: Int

    static let crop = MediaEditMode(rawValue: 1 << 0)
    static let annotate = MediaEditMode(rawValue: 1 << 1)
    static let draw = MediaEditMode(rawValue: 1 << 2)

    static let all: MediaEditMode = [.crop, .annotate, .draw]
}

struct MediaEditConfig {
    var mode: MediaEditMode = .all
    var dark: Bool
    var showPreviews: Bool
    var cropRegion: MediaEditCropRegion
    var maxAspectRatio: CGFloat? = nil

    var canCrop: Bool {
        mode.contains(.crop)
    }

    var canAnnotate: Bool {
        mode.contains(.annotate)
    }

    var canDraw: Bool {
        mode.contains(.draw)
    }

    static var `default`: MediaEditConfig {
        MediaEditConfig(mode: .all, dark: true, showPreviews: true, cropRegion: .any)
    }

    static var groupAvatar: MediaEditConfig {
        MediaEditConfig(mode: .all, dark: true, showPreviews: true, cropRegion: .square)
    }

    static var profile: MediaEditConfig {
        MediaEditConfig(mode: .all, dark: true, showPreviews: true, cropRegion: .circle)
    }

    static var crop: MediaEditConfig {
        MediaEditConfig(mode: .crop, dark: false, showPreviews: false, cropRegion: .any)
    }

    static var annotate: MediaEditConfig {
        MediaEditConfig(mode: .annotate, dark: false, showPreviews: false, cropRegion: .any)
    }

    static var draw: MediaEditConfig {
        MediaEditConfig(mode: .draw, dark: false, showPreviews: false, cropRegion: .any)
    }
}

class MediaEditViewController: UIViewController {
    private var config: MediaEditConfig
    private var media: [MediaEdit]
    private var selected: Int
    private var editViewController: UIViewController?
    private var processing = false
    private let didFinish: MediaEditViewControllerCallback
    private var mutedCancellable: AnyCancellable?
    private var drawingColorCancellable: AnyCancellable?
    private var undoStackCancellable: AnyCancellable?
    private var draggingAnnotationCancellable: AnyCancellable?

    private lazy var undoButtonItem: UIBarButtonItem = {
        let imageConfig = UIImage.SymbolConfiguration(weight: .bold)
        let image = UIImage(named: "Undo")

        let item = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(undoAction))
        item.tintColor = .primaryBlue

        return item
    }()

    private lazy var rotateButtonItem: UIBarButtonItem = {
        let rotateBtn = UIBarButtonItem(image: UIImage(named: "Rotate"), style: .plain, target: self, action: #selector(rotateAction))
        rotateBtn.tintColor = .primaryBlue
        rotateBtn.accessibilityLabel = Localizations.voiceOverButtonRotate

        return rotateBtn
    }()

    private lazy var flipButtonItem: UIBarButtonItem = {
        let flipBtn = UIBarButtonItem(image: UIImage(named: "Flip"), style: .plain, target: self, action: #selector(flipAction))
        flipBtn.tintColor = .primaryBlue
        flipBtn.accessibilityLabel = Localizations.voiceOverButtonFlip

        return flipBtn
    }()

    private lazy var drawButtonItem: UIBarButtonItem = {
        let drawIcon = UIImage(named: "Draw")?.withTintColor(.primaryBlue, renderingMode: .alwaysOriginal)
        let drawBtn = UIButton(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        drawBtn.setImage(drawIcon, for: .normal)
        drawBtn.layer.cornerRadius = 22
        drawBtn.clipsToBounds = true
        drawBtn.addTarget(self, action: #selector(drawAction), for: .touchUpInside)

        let item = UIBarButtonItem(customView: drawBtn)
        item.accessibilityLabel = Localizations.voiceOverButtonDraw

        return item
    }()

    private lazy var annotateButtonItem: UIBarButtonItem = {
        let annotateIcon = UIImage(named: "Annotate")?.withTintColor(.primaryBlue, renderingMode: .alwaysOriginal)
        let annotateBtn = UIButton(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        annotateBtn.setImage(annotateIcon, for: .normal)
        annotateBtn.layer.cornerRadius = 22
        annotateBtn.clipsToBounds = true
        annotateBtn.addTarget(self, action: #selector(annotateAction), for: .touchUpInside)

        let item = UIBarButtonItem(customView: annotateBtn)
        item.accessibilityLabel = Localizations.voiceOverButtonAnnotate

        return item
    }()

    private lazy var muteButtonItem: UIBarButtonItem = {
        let muteButtonItem = UIBarButtonItem(image: muteIcon(media[selected].muted), style: .plain, target: self, action: #selector(toggleMuteAction))
        muteButtonItem.accessibilityLabel = Localizations.voiceOverButtonMute
        muteButtonItem.tintColor = .primaryBlue

        return muteButtonItem
    }()

    private lazy var doneButton: UIButton = {
        let doneButton = UIButton()
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        doneButton.setTitle(Localizations.buttonDone, for: .normal)
        doneButton.setTitleColor(.white, for: .normal)
        doneButton.setTitleColor(.white.withAlphaComponent(0.6), for: .highlighted)
        doneButton.setBackgroundColor(.primaryBlue, for: .normal)
        doneButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 40, bottom: 1, right: 40)
        doneButton.layer.cornerRadius = 22
        doneButton.layer.masksToBounds = true
        doneButton.addTarget(self, action: #selector(doneAction), for: .touchUpInside)

        doneButton.heightAnchor.constraint(equalToConstant: 44).isActive = true

        return doneButton
    }()

    private lazy var previewCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 10
        layout.sectionInset = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: Constants.previewSize, height: Constants.previewSize)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(PreviewCell.self, forCellWithReuseIdentifier: PreviewCell.reuseIdentifier)
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.dataSource = self

        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressPreviewCollection(gesture:)))
        collectionView.addGestureRecognizer(recognizer)

        return collectionView
    }()

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        config.dark ? .lightContent : super.preferredStatusBarStyle
    }

    init(config: MediaEditConfig, mediaToEdit media: [PendingMedia], selected position: Int?, didFinish: @escaping MediaEditViewControllerCallback) {
        self.config = config
        self.media = media.map { MediaEdit(config: config, media: $0) }
        self.didFinish = didFinish

        if let position = position, 0 <= position && position < media.count {
            self.selected = position
        } else {
            self.selected = 0
        }
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("Use init(mediaEdit:)")
    }

    func withNavigationController() -> UIViewController {
        let controller = UINavigationController(rootViewController: self)
        controller.modalPresentationStyle = .fullScreen
        controller.delegate = self

        if config.dark {
            controller.navigationBar.overrideUserInterfaceStyle = .dark
        }

        controller.navigationBar.isTranslucent = true
        controller.navigationBar.backgroundColor = .clear

        return controller
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        if config.dark {
            overrideUserInterfaceStyle = .dark
        }

        setupNavigation()

        view.backgroundColor = config.dark ? .black : .feedBackground
        view.addSubview(doneButton)
        view.addSubview(previewCollectionView)

        let previewHeight = media.count > 1 && config.showPreviews ? Constants.previewSize : 0

        NSLayoutConstraint.activate([
            doneButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            doneButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            previewCollectionView.heightAnchor.constraint(equalToConstant: previewHeight),
            previewCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewCollectionView.bottomAnchor.constraint(equalTo: doneButton.topAnchor, constant: -20),
        ])

        updateEditViewController()

        previewCollectionView.isHidden = media.count < 2
    }

    private func setupNavigation() {
        navigationItem.standardAppearance = .transparentAppearance
        navigationItem.compactAppearance = .transparentAppearance
        navigationItem.scrollEdgeAppearance = .transparentAppearance

        let backImage = UIImage(systemName: "chevron.left", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: backImage, style: .plain, target: self, action: #selector(backAction))
        navigationItem.leftBarButtonItem?.tintColor = .primaryBlue

        updateNavigation()
    }

    private func updateNavigation() {
        #if DEBUG
        let isDrawingEnabled = true
        #else
        let isDrawingEnabled = ServerProperties.isInternalUser || ServerProperties.isMediaDrawingEnabled
        #endif

        mutedCancellable?.cancel()
        drawingColorCancellable?.cancel()
        undoStackCancellable?.cancel()
        draggingAnnotationCancellable?.cancel()

        draggingAnnotationCancellable = media[selected].$isDraggingAnnotation.sink { [weak self] isDragging in
            guard let self = self else { return }

            UIView.animate(withDuration: 0.3) {
                self.navigationController?.navigationBar.alpha = isDragging ? 0 : 1
            }
        }

        undoButtonItem.isEnabled = media[selected].undoStack.count > 0
        undoStackCancellable = media[selected].$undoStack.sink { [weak self] stack in
            self?.undoButtonItem.isEnabled = stack.count > 0
        }

        switch media[selected].type {
        case .image:
            navigationItem.rightBarButtonItems = []

            if isDrawingEnabled, config.canDraw, let button = drawButtonItem.customView as? UIButton {
                if media[selected].isDrawing {
                    button.setBackgroundColor(media[selected].drawingColor, for: .normal)

                    drawingColorCancellable = media[selected].$drawingColor.sink {
                        button.setBackgroundColor($0, for: .normal)
                    }
                } else {
                    drawingColorCancellable = nil
                    button.setBackgroundColor(.clear, for: .normal)
                }

                navigationItem.rightBarButtonItems?.append(drawButtonItem)
            }

            if isDrawingEnabled, config.canAnnotate, let button = annotateButtonItem.customView as? UIButton {
                if media[selected].isAnnotating {
                    button.setBackgroundColor(media[selected].drawingColor, for: .normal)

                    drawingColorCancellable = media[selected].$drawingColor.sink {
                        button.setBackgroundColor($0, for: .normal)
                    }
                } else {
                    drawingColorCancellable = nil
                    button.setBackgroundColor(.clear, for: .normal)
                }

                navigationItem.rightBarButtonItems?.append(annotateButtonItem)
            }

            if config.canCrop {
                navigationItem.rightBarButtonItems?.append(rotateButtonItem)
                navigationItem.rightBarButtonItems?.append(flipButtonItem)
            }
        case .video:
            navigationItem.rightBarButtonItems = [muteButtonItem]

            mutedCancellable = media[selected].$muted.sink { [weak self] in
                guard let self = self else { return }
                self.navigationItem.rightBarButtonItem?.image = self.muteIcon($0)
            }
        case .audio:
            break // audio edit is not currently suported
        }

        navigationItem.rightBarButtonItems?.append(undoButtonItem)
    }

    private func muteIcon(_ muted: Bool) -> UIImage {
        return UIImage(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))!
    }

    private func updateEditViewController() {
        if let controller = editViewController {
            controller.view.removeFromSuperview()
            controller.removeFromParent()
        }

        let controller: UIViewController
        switch media[selected].type {
        case .image:
            controller = ImageEditViewController(media[selected], config: config)
        case .video:
            controller = VideoEditViewController(media[selected], config: config)
        case .audio:
            return // audio edit is not currently suported
        }

        controller.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(controller)
        view.addSubview(controller.view)

        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: previewCollectionView.topAnchor, constant: -14),
        ])

        controller.didMove(toParent: self)
        editViewController = controller
    }

    @objc private func longPressPreviewCollection(gesture: UILongPressGestureRecognizer) {
        guard !processing else { return }
        guard let collectionView = gesture.view as? UICollectionView else { return }

        switch(gesture.state) {
        case .began:
            guard let indexPath = collectionView.indexPathForItem(at: gesture.location(in: collectionView)) else { return }
            collectionView.beginInteractiveMovementForItem(at: indexPath)
        case .changed:
            let location = gesture.location(in: collectionView)
            collectionView.updateInteractiveMovementTargetPosition(CGPoint(x: location.x, y: collectionView.bounds.midY))
        case .ended:
            collectionView.endInteractiveMovement()
        default:
            collectionView.cancelInteractiveMovement()
        }
    }

    @objc private func toggleMuteAction() {
        guard !processing else { return }
        guard media[selected].type == .video else { return }
        media[selected].muted = !media[selected].muted
    }

    @objc private func rotateAction() {
        guard !processing else { return }
        guard media[selected].type == .image else { return }
        media[selected].isDrawing = false
        media[selected].isAnnotating = false
        media[selected].rotate()
        updateNavigation()
    }

    @objc private func flipAction() {
        guard !processing else { return }
        guard media[selected].type == .image else { return }
        media[selected].isDrawing = false
        media[selected].isAnnotating = false
        media[selected].flip()
        updateNavigation()
    }

    @objc private func drawAction() {
        guard !processing else { return }
        guard media[selected].type == .image else { return }
        media[selected].isAnnotating = false
        media[selected].isDrawing = !media[selected].isDrawing
        updateNavigation()
    }

    @objc private func annotateAction() {
        guard !processing else { return }
        guard media[selected].type == .image else { return }
        media[selected].isDrawing = false
        media[selected].isAnnotating = !media[selected].isAnnotating
        updateNavigation()
    }

    @objc private func undoAction() {
        guard !processing else { return }
        guard media[selected].type == .image else { return }
        media[selected].isDrawing = false
        media[selected].isAnnotating = false
        media[selected].undo()
        updateNavigation()
    }

    @objc private func backAction() {
        guard !processing else { return }

        if media.filter({ $0.hasChanges() }).count > 0 {
            let alert = UIAlertController(title: Localizations.discardConfirmationPrompt, message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Localizations.buttonDiscard, style: .destructive) { [weak self] _ in
                guard let self = self else { return }
                self.didFinish(self, self.media.map { $0.media }, self.selected, true)
            })
            alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
            present(alert, animated: true)
        } else {
            didFinish(self, media.map { $0.media }, selected, true)
        }
    }

    @objc private func doneAction() {
        guard !processing else { return }
        processing = true

        let media = media
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let results = media.map { $0.process() }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.didFinish(self, results, self.selected, false)
            }
        }
    }
}

// MARK: UICollectionViewDelegate
extension MediaEditViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard !processing else { return }
        media[selected].isDrawing = false

        let previous = selected
        selected = indexPath.row

        collectionView.reloadItems(at: [indexPath, IndexPath(row: previous, section: 0)])

        updateNavigation()
        updateEditViewController()
    }
}

// MARK: UICollectionViewDataSource
extension MediaEditViewController : UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return media.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PreviewCell.reuseIdentifier, for: indexPath) as! PreviewCell
        cell.configure(media: media[indexPath.row], selected: indexPath.row == selected)

        return cell
    }

    func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        if sourceIndexPath.row == selected {
            selected = destinationIndexPath.row
        } else if destinationIndexPath.row == selected {
            selected = sourceIndexPath.row
        }

        media.insert(media.remove(at: sourceIndexPath.row), at: destinationIndexPath.row)

        // Order for media items should start at zero.
        for (i, item) in media.enumerated() {
            item.media.order = i
        }
    }
}

// MARK: UINavigationControllerDelegate
extension MediaEditViewController: UINavigationControllerDelegate {
    func navigationControllerSupportedInterfaceOrientations(_ navigationController: UINavigationController) -> UIInterfaceOrientationMask {
        return .portrait
    }
}


fileprivate class PreviewCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: PreviewCell.self)
    }

    private var cancellable: AnyCancellable?

    private lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 10
        imageView.layer.masksToBounds = true

        return imageView
    }()
    private lazy var videoIconView: UIImageView = {
        let videoIcon = UIImage(systemName: "play.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal)
        let videoIconView = UIImageView(image: videoIcon)
        videoIconView.translatesAutoresizingMaskIntoConstraints = false
        videoIconView.contentMode = .scaleAspectFit

        return videoIconView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.layer.cornerRadius = 16
        contentView.layer.masksToBounds = true

        contentView.addSubview(imageView)
        contentView.addSubview(videoIconView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            videoIconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            videoIconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            videoIconView.widthAnchor.constraint(equalToConstant: 32),
            videoIconView.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        cancellable?.cancel()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancellable?.cancel()
    }

    func configure(media: MediaEdit, selected: Bool) {
        cancellable = media.$image.sink { [weak self] in
            self?.imageView.image = $0
        }

        contentView.backgroundColor = selected ? .primaryBlue : .clear
        videoIconView.isHidden = media.type != .video
    }
}
