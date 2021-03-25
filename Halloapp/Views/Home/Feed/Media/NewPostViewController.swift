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

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    init(source: NewPostMediaSource, destination: FeedPostDestination, didFinish: @escaping (() -> Void)) {
        self.didFinish = didFinish
        self.state = NewPostState(mediaSource: source)
        self.destination = destination
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(source:didFinish:)")
    }

    override func loadView() {
        super.loadView()

        view.backgroundColor = .feedBackground
        addChild(containedNavigationController)
        containedNavigationController.view.frame = view.bounds
        view.addSubview(containedNavigationController.view)
        containedNavigationController.didMove(toParent: self)
    }

    // MARK: Private

    private let didFinish: (() -> Void)
    private var state: NewPostState
    private let destination: FeedPostDestination

    private lazy var containedNavigationController = {
        return makeNavigationController()
    }()

    private func cleanupAndFinish() {
        for media in state.pendingMedia {
            guard let encryptedFileURL = media.encryptedFileUrl else { continue }
            do {
                try FileManager.default.removeItem(at: encryptedFileURL)
                DDLogInfo("NewPostViewController/cleanup/\(encryptedFileURL.absoluteString)/deleted")
            } catch {
                DDLogInfo("NewPostViewController/cleanup/\(encryptedFileURL.absoluteString)/error [\(error)]")
            }
        }
        didFinish()
    }

    private func didFinishPickingMedia(showAddMoreMediaButton: Bool = true) {
        containedNavigationController.pushViewController(
            makeComposerViewController(showAddMoreMediaButton: showAddMoreMediaButton), animated: true)
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

    private func makeComposerViewController(showAddMoreMediaButton: Bool = true) -> UIViewController {
        var configuration: PostComposerViewConfiguration = .userPost
        configuration.showAddMoreMediaButton = showAddMoreMediaButton
        var recipientName: String? = nil
        if case .groupFeed(let groupId) = destination {
            configuration = .groupPost(id: groupId)
            if let group = MainAppContext.shared.chatData.chatGroup(groupId: groupId) {
                recipientName = group.name
            }
        }
        return PostComposerViewController(
            mediaToPost: state.pendingMedia,
            initialInput: state.pendingInput,
            recipientName: recipientName,
            configuration: configuration,
            delegate: self)
    }

    private func makeNewCameraViewController() -> UIViewController {
        return CameraViewController(
            showCancelButton: state.isPostComposerCancellable,
            didFinish: { [weak self] in self?.cleanupAndFinish() },
            didPickImage: { [weak self] uiImage in self?.onCameraImagePicked(uiImage) },
            didPickVideo: { [weak self] videoURL in self?.onCameraVideoPicked(videoURL) }
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
        let pickerController = MediaPickerViewController { [weak self] controller, media, cancel in
            guard let self = self else { return }
            
            if cancel {
                self.cleanupAndFinish()
            } else {
                self.state.pendingMedia = media
                self.didFinishPickingMedia()
            }
        }
        
        return UINavigationController(rootViewController: pickerController)
    }

    private func onCameraImagePicked(_ uiImage: UIImage) {
        var pendingMedia = [PendingMedia]()
        let normalizedImage = uiImage.correctlyOrientedImage()
        let mediaToPost = PendingMedia(type: .image)
        mediaToPost.image = normalizedImage

        pendingMedia.append(mediaToPost)
        state.pendingMedia = pendingMedia
        didFinishPickingMedia(showAddMoreMediaButton: false)
    }

    private func onCameraVideoPicked(_ videoURL: URL) {
        var pendingMedia = [PendingMedia]()
        let mediaToPost = PendingMedia(type: .video)
        mediaToPost.originalVideoURL = videoURL
        mediaToPost.fileURL = videoURL

        pendingMedia.append(mediaToPost)
        state.pendingMedia = pendingMedia
        didFinishPickingMedia(showAddMoreMediaButton: false)
    }
}

extension NewPostViewController: UIImagePickerControllerDelegate {
    func imagePickerController(_ pickerController: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        var pendingMedia = [PendingMedia]()
        if let uiImage = info[.originalImage] as? UIImage {
            let normalizedImage = uiImage.correctlyOrientedImage()
            let mediaToPost = PendingMedia(type: .image)
            mediaToPost.image = normalizedImage

            pendingMedia.append(mediaToPost)
        } else if let videoURL = info[.mediaURL] as? URL {
            let mediaToPost = PendingMedia(type: .video)
            mediaToPost.originalVideoURL = videoURL
            mediaToPost.fileURL = videoURL

            pendingMedia.append(mediaToPost)
        } else {
            DDLogError("UIImagePickerController returned unknown media type")
        }
        state.pendingMedia = pendingMedia
        didFinishPickingMedia()
    }
}

extension NewPostViewController: UINavigationControllerDelegate {}

extension NewPostViewController: PostComposerViewDelegate {
    func composerDidTapShare(controller: PostComposerViewController, mentionText: MentionText, media: [PendingMedia]) {
        MainAppContext.shared.feedData.post(text: mentionText, media: media, to: destination)
        cleanupAndFinish()
    }

    func composerDidTapBack(controller: PostComposerViewController, media: [PendingMedia]) {
        containedNavigationController.popViewController(animated: true)
        switch state.mediaSource {
        case .library:
            (containedNavigationController.topViewController as? MediaPickerViewController)?.reset(selected: media)
        case .camera:
            break
        default:
            cleanupAndFinish()
        }
    }

    func willDismissWithInput(mentionInput: MentionInput) {
        state.pendingInput = mentionInput
    }
}
