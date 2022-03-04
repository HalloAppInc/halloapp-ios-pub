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

    static var voiceOverButtonMute: String {
        NSLocalizedString("media.voiceover.button.mute", value: "Mute", comment: "Accessibility label for a button in media editor. Refers to media editing action.")
    }

    static var discardConfirmationPrompt: String {
        NSLocalizedString("media.discard.confirmation", value: "Would you like to discard your edits?", comment: "Confirmation prompt in media composer.")
    }

    static var buttonReset: String {
        NSLocalizedString("media.button.reset", value: "Reset", comment: "Button title. Refers to resetting photo / video to original version.")
    }
}

typealias MediaEditViewControllerCallback = (MediaEditViewController, [PendingMedia], Int, Bool) -> Void

enum MediaEditCropRegion {
    case circle, square, any
}

class MediaEditViewController: UIViewController {
    private var media: [MediaEdit]
    private var selected: Int
    private var editViewController: UIViewController?
    private let cropRegion: MediaEditCropRegion
    private let maxAspectRatio: CGFloat?
    private var processing = false
    private let didFinish: MediaEditViewControllerCallback
    private var mutedCancellable: AnyCancellable?
    private var drawingColorCancellable: AnyCancellable?
    private var undoStackCancellable: AnyCancellable?

    private lazy var buttonsView: UIView = {
        let buttonsView = UIStackView()
        buttonsView.translatesAutoresizingMaskIntoConstraints = false
        buttonsView.axis = .horizontal
        buttonsView.distribution = .equalSpacing
        buttonsView.alignment = .center

        let resetBtn = UIButton()
        resetBtn.translatesAutoresizingMaskIntoConstraints = false
        resetBtn.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        resetBtn.setTitle(Localizations.buttonReset, for: .normal)
        resetBtn.setTitleColor(.primaryBlue, for: .normal)
        resetBtn.addTarget(self, action: #selector(resetAction), for: .touchUpInside)
        buttonsView.addArrangedSubview(resetBtn)

        let doneBtn = UIButton()
        doneBtn.translatesAutoresizingMaskIntoConstraints = false
        doneBtn.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        doneBtn.setTitle(Localizations.buttonDone, for: .normal)
        doneBtn.setTitleColor(.white, for: .normal)
        doneBtn.setBackgroundColor(.primaryBlue, for: .normal)
        doneBtn.layer.cornerRadius = 22
        doneBtn.layer.masksToBounds = true
        doneBtn.addTarget(self, action: #selector(doneAction), for: .touchUpInside)
        buttonsView.addArrangedSubview(doneBtn)

        doneBtn.heightAnchor.constraint(equalToConstant: 44).isActive = true
        doneBtn.widthAnchor.constraint(equalToConstant: 90).isActive = true

        return buttonsView
    }()

    private lazy var previewCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 20
        layout.sectionInset = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 80, height: 80)

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(PreviewCell.self, forCellWithReuseIdentifier: PreviewCell.reuseIdentifier)
        collectionView.showsHorizontalScrollIndicator = false
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
        .lightContent
    }
    
    init(cropRegion: MediaEditCropRegion = .any, mediaToEdit media: [PendingMedia], selected position: Int?, maxAspectRatio: CGFloat? = nil, didFinish: @escaping MediaEditViewControllerCallback) {
        self.cropRegion = cropRegion
        self.media = media.map { MediaEdit(cropRegion: cropRegion, maxAspectRatio: maxAspectRatio, media: $0) }
        self.maxAspectRatio = maxAspectRatio
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

        return controller
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark

        setupNavigation()

        view.backgroundColor = .black
        view.addSubview(buttonsView)
        view.addSubview(previewCollectionView)

        NSLayoutConstraint.activate([
            buttonsView.heightAnchor.constraint(equalToConstant: 44),
            buttonsView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            buttonsView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            buttonsView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            previewCollectionView.heightAnchor.constraint(equalToConstant: media.count > 1 ? 80 : 0),
            previewCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewCollectionView.bottomAnchor.constraint(equalTo: buttonsView.topAnchor, constant: -20),
        ])

        updateEditViewController()

        previewCollectionView.isHidden = media.count < 2
    }

    private func setupNavigation() {
        navigationController?.navigationBar.overrideUserInterfaceStyle = .dark

        let backImage = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(weight: .bold))
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: backImage, style: .plain, target: self, action: #selector(backAction))

        updateNavigation()
    }

    private func updateNavigation() {
        mutedCancellable?.cancel()
        drawingColorCancellable?.cancel()
        undoStackCancellable?.cancel()

        switch media[selected].type {
        case .image:
            navigationItem.rightBarButtonItems = []

            if ServerProperties.isInternalUser {
                let drawIcon = UIImage(named: "Draw")?.withTintColor(.white, renderingMode: .alwaysOriginal)
                let drawBtn = UIButton(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
                drawBtn.setImage(drawIcon, for: .normal)
                drawBtn.layer.cornerRadius = 22
                drawBtn.clipsToBounds = true
                drawBtn.addTarget(self, action: #selector(drawAction), for: .touchUpInside)

                if media[selected].isDrawing {
                    drawBtn.setBackgroundColor(media[selected].drawingColor, for: .normal)

                    drawingColorCancellable = media[selected].$drawingColor.sink {
                        drawBtn.setBackgroundColor($0, for: .normal)
                    }
                }

                let drawBarBtn = UIBarButtonItem(customView: drawBtn)
                drawBarBtn.accessibilityLabel = Localizations.voiceOverButtonDraw

                navigationItem.rightBarButtonItems?.append(drawBarBtn)
            }

            let rotateIcon = UIImage(named: "Rotate")?.withTintColor(.white, renderingMode: .alwaysOriginal)
            let rotateBtn = UIBarButtonItem(image: rotateIcon, style: .plain, target: self, action: #selector(rotateAction))
            rotateBtn.accessibilityLabel = Localizations.voiceOverButtonFlip
            navigationItem.rightBarButtonItems?.append(rotateBtn)

            let flipIcon = UIImage(named: "Flip")?.withTintColor(.white, renderingMode: .alwaysOriginal)
            let flipBtn = UIBarButtonItem(image: flipIcon, style: .plain, target: self, action: #selector(flipAction))
            flipBtn.accessibilityLabel = Localizations.voiceOverButtonRotate
            navigationItem.rightBarButtonItems?.append(flipBtn)

            if ServerProperties.isInternalUser {
                let undoIcon = UIImage(systemName: "arrow.uturn.backward")?.withTintColor(.white, renderingMode: .alwaysOriginal)
                let undoBtn = UIBarButtonItem(image: undoIcon, style: .plain, target: self, action: #selector(undoAction))
                undoBtn.accessibilityLabel = Localizations.voiceOverButtonRotate

                if media[selected].undoStack.count > 0 {
                    navigationItem.rightBarButtonItems?.append(undoBtn)
                }

                undoStackCancellable = media[selected].$undoStack.sink { [weak self] stack in
                    guard let self = self else { return }
                    let idx = self.navigationItem.rightBarButtonItems?.firstIndex(of: undoBtn)

                    if stack.count > 0 && idx == nil {
                        self.navigationItem.rightBarButtonItems?.append(undoBtn)
                    } else if stack.count == 0, let idx = idx {
                        self.navigationItem.rightBarButtonItems?.remove(at: idx)
                    }
                }
            }
        case .video:
            let muteBtn = UIBarButtonItem(image: muteIcon(media[selected].muted), style: .plain, target: self, action: #selector(toggleMuteAction))
            muteBtn.accessibilityLabel = Localizations.voiceOverButtonMute
            navigationItem.rightBarButtonItems = [muteBtn]

            mutedCancellable = media[selected].$muted.sink { [weak self] in
                guard let self = self else { return }
                self.navigationItem.rightBarButtonItem?.image = self.muteIcon($0)
            }
        case .audio:
            break // audio edit is not currently suported
        }
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
            controller = ImageEditViewController(media[selected], cropRegion: cropRegion, maxAspectRatio: maxAspectRatio)
        case .video:
            controller = VideoEditViewController(media[selected])
        case .audio:
            return // audio edit is not currently suported
        }

        controller.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(controller)
        view.addSubview(controller.view)

        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: previewCollectionView.topAnchor),
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
        media[selected].rotate()
        updateNavigation()
    }

    @objc private func flipAction() {
        guard !processing else { return }
        guard media[selected].type == .image else { return }
        media[selected].isDrawing = false
        media[selected].flip()
        updateNavigation()
    }

    @objc private func drawAction() {
        guard !processing else { return }
        guard media[selected].type == .image else { return }
        media[selected].isDrawing = !media[selected].isDrawing
        updateNavigation()
    }

    @objc private func undoAction() {
        guard !processing else { return }
        guard media[selected].type == .image else { return }
        media[selected].isDrawing = false
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

    @objc private func resetAction() {
        guard !processing else { return }
        media[selected].isDrawing = false

        for item in media {
            item.reset()
        }

        updateNavigation()
    }

    @objc private func doneAction() {
        guard !processing else { return }
        processing = true

        didFinish(self, media.map { $0.process() }, selected, false)
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
        imageView.layer.borderColor = UIColor.primaryBlue.cgColor
        imageView.layer.cornerRadius = 10
        imageView.layer.masksToBounds = true

        return imageView
    }()
    private lazy var overlayView: UIView = {
        let overlayView = UIView()
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.4)

        return overlayView
    }()
    private lazy var videoIconView: UIImageView = {
        let videoIcon = UIImage(systemName: "play.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal)
        let videoIconView = UIImageView(image: videoIcon)
        videoIconView.translatesAutoresizingMaskIntoConstraints = false
        videoIconView.contentMode = .scaleAspectFit
        videoIconView.alpha = 0.6

        return videoIconView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.layer.cornerRadius = 3
        contentView.layer.masksToBounds = true

        contentView.addSubview(imageView)
        contentView.addSubview(overlayView)
        contentView.addSubview(videoIconView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: contentView.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            overlayView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            videoIconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            videoIconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            videoIconView.widthAnchor.constraint(equalToConstant: 24),
            videoIconView.heightAnchor.constraint(equalToConstant: 24),
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

        imageView.layer.borderWidth = selected ? 5 : 0
        overlayView.isHidden = selected
        videoIconView.isHidden = media.type != .video
    }
}
