//
//  NewPostViewController.swift
//  HalloApp
//
//  Created by Garrett on 7/22/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVFoundation
import CocoaLumberjack
import Core
import Photos
import UIKit
import SwiftUI

enum NewPostMediaSource {
    case library
    case camera
    case noMedia
}

struct NewPostState {
    var pendingMedia = [PendingMedia]()
    var mediaSource = NewPostMediaSource.noMedia
    var pendingInput = MentionInput(text: "", mentions: MentionRangeMap(), selectedRange: NSRange())

    var isPostComposerCancellable: Bool {
        // We can only return to the library picker (UIImagePickerController freezes after choosing an image 🙄).
        return mediaSource != .library
    }
}

typealias DidPickImageCallback = (UIImage) -> Void
typealias DidPickVideoCallback = (URL) -> Void

final class NewPostViewController: UIViewController {

    init(source: NewPostMediaSource, didFinish: @escaping (() -> Void)) {
        self.didFinish = didFinish
        self.state = NewPostState(mediaSource: source)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(source:didFinish:)")
    }

    override func loadView() {
        super.loadView()

        addChild(containedNavigationController)
        containedNavigationController.view.frame = view.bounds
        view.addSubview(containedNavigationController.view)
        containedNavigationController.didMove(toParent: self)
    }

    // MARK: Private

    private let didFinish: (() -> Void)
    private var state: NewPostState

    private lazy var containedNavigationController = {
        return makeNavigationController()
    }()

    private func didFinishPickingMedia() {
        containedNavigationController.pushViewController(makeComposerViewController(), animated: true)
    }

    private func makeNavigationController() -> UINavigationController {
        switch state.mediaSource {
        case .library:
            return makeMediaPickerViewControllerNew()
        case .camera:
            return UINavigationController(rootViewController: makeNewCameraViewController())
        case .noMedia:
            return UINavigationController(rootViewController: makeComposerViewController())
        }
    }

    private func makeComposerViewController() -> UIViewController {
        return PostComposerViewController(
            mediaToPost: state.pendingMedia,
            initialInput: state.pendingInput,
            showCancelButton: state.isPostComposerCancellable,
            willDismissWithInput: { [weak self] input in self?.state.pendingInput = input },
            didFinish: { [weak self] back, media in
                if back {
                    self?.containedNavigationController.popViewController(animated: true)

                    guard let picker = self?.containedNavigationController.topViewController as? MediaPickerViewController else { return }
                    picker.reset(selected: media)
                } else {
                    self?.didFinish()
                }
            })
    }

    private func makeNewCameraViewController() -> UIViewController {
        return CameraViewController(
            showCancelButton: state.isPostComposerCancellable,
            didFinish: { [weak self] in self?.didFinish() },
            didPickImage: { [weak self] uiImage in self?.onImagePicked(uiImage) },
            didPickVideo: { [weak self] videoURL in self?.onVideoPicked(videoURL) }
        )
    }

    private func makeCameraViewController() -> UINavigationController {
        let imagePickerController = UIImagePickerController()
        imagePickerController.sourceType = .camera
        if let mediatypes = UIImagePickerController.availableMediaTypes(for: .camera) {
            imagePickerController.mediaTypes = mediatypes
        }
        imagePickerController.allowsEditing = false
        imagePickerController.videoQuality = .typeHigh // gotcha: .typeMedium have empty frames in the beginning
        imagePickerController.videoMaximumDuration = Date.minutes(1)
        imagePickerController.delegate = self

        return imagePickerController
    }
    
    private func makeMediaPickerViewControllerNew() -> UINavigationController {
        let pickerController = MediaPickerViewController() { [weak self] controller, media, cancel in
            guard let self = self else { return }
            
            if cancel {
                self.didFinish()
            } else {
                self.state.pendingMedia = media
                self.didFinishPickingMedia()
            }
        }
        
        return UINavigationController(rootViewController: pickerController)
    }

    private func onImagePicked(_ uiImage: UIImage) {
        var pendingMedia = [PendingMedia]()
        let normalizedImage = uiImage.correctlyOrientedImage()
        let mediaToPost = PendingMedia(type: .image)
        mediaToPost.image = normalizedImage
        mediaToPost.size = normalizedImage.size
        pendingMedia.append(mediaToPost)
        state.pendingMedia = pendingMedia
        didFinishPickingMedia()
    }

    private func onVideoPicked(_ videoURL: URL) {
        var pendingMedia = [PendingMedia]()
        let mediaToPost = PendingMedia(type: .video)
        mediaToPost.videoURL = videoURL

        if let videoSize = VideoUtils.resolutionForLocalVideo(url: videoURL) {
            mediaToPost.size = videoSize
            DDLogInfo("Video size: [\(NSCoder.string(for: videoSize))]")
        }
        pendingMedia.append(mediaToPost)
        state.pendingMedia = pendingMedia
        didFinishPickingMedia()
    }
}

extension NewPostViewController: UIImagePickerControllerDelegate {
    func imagePickerController(_ pickerController: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        var pendingMedia = [PendingMedia]()
        if let uiImage = info[.originalImage] as? UIImage {
            let normalizedImage = uiImage.correctlyOrientedImage()
            let mediaToPost = PendingMedia(type: .image)
            mediaToPost.image = normalizedImage
            mediaToPost.size = normalizedImage.size
            pendingMedia.append(mediaToPost)
        } else if let videoURL = info[.mediaURL] as? URL {
            let mediaToPost = PendingMedia(type: .video)
            mediaToPost.videoURL = videoURL

            if let videoSize = VideoUtils.resolutionForLocalVideo(url: videoURL) {
                mediaToPost.size = videoSize
                DDLogInfo("Video size: [\(NSCoder.string(for: videoSize))]")
            }
            pendingMedia.append(mediaToPost)
        } else {
            DDLogError("UIImagePickerController returned unknown media type")
        }
        state.pendingMedia = pendingMedia
        didFinishPickingMedia()
    }
}

extension NewPostViewController: UINavigationControllerDelegate {}
