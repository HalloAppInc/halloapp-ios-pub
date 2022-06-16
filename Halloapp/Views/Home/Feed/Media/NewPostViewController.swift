//
//  NewPostViewController.swift
//  HalloApp
//
//  Created by Garrett on 7/22/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVFoundation
import CocoaLumberjackSwift
import Core
import CoreCommon
import Photos
import UIKit
import SwiftUI

extension Localizations {
    static var newPost: String {
        NSLocalizedString("post.controller.picker.title", value: "New Post", comment: "Title for the picker screen.")
    }

    static var voiceNoteDeleteWarningTitle: String {
        NSLocalizedString("composer.deletevoicenote.title",
                          value: "Discard Post?",
                          comment: "Title for alert when closing the post composer with a voice note")
    }

    static var voiceNoteDeleteWarningMessage: String {
        NSLocalizedString("composer.deletevoicenote.message",
                          value: "Voice recording will not be saved if you discard this post.",
                          comment: "Warning message shown to the user before discarding a voice post")
    }
}

enum NewPostMediaSource {
    case library
    case camera
    case noMedia
    case voiceNote
}

enum NewMomentContext {
    case normal
    case unlock(UserID)
}

struct NewPostState {
    var pendingMedia = [PendingMedia]()
    var mediaSource = NewPostMediaSource.noMedia
    var pendingInput = MentionInput(text: "", mentions: MentionRangeMap(), selectedRange: NSRange())
    var pendingVoiceNote: PendingMedia?

    var isPostComposerCancellable: Bool {
        // We can only return to the library picker (UIImagePickerController freezes after choosing an image 🙄).
        switch mediaSource {
        case .library:
            return false
        default:
            return true
        }
    }
}

typealias DidPickImageCallback = (UIImage) -> Void
typealias DidPickVideoCallback = (URL) -> Void

final class NewPostViewController: UIViewController {

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    init(source: NewPostMediaSource, destination: FeedPostDestination, privacyListType: PrivacyListType? = nil, momentContext: NewMomentContext? = nil, didFinish: @escaping ((Bool) -> Void)) {
        self.didFinish = didFinish
        self.state = NewPostState(mediaSource: source)
        self.destination = destination
        self.privacyListType = privacyListType
        self.momentContext = momentContext
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

    private let didFinish: ((Bool) -> Void)
    private var state: NewPostState
    private let momentContext: NewMomentContext?
    private var destination: FeedPostDestination
    private var privacyListType: PrivacyListType?

    private(set) lazy var containedNavigationController = {
        return makeNavigationController()
    }()

    private func cleanupAndFinish(didPost: Bool = false) {
        // Display warning about deleting voice note
        if !didPost, state.pendingVoiceNote != nil {
            let alert = UIAlertController(title: Localizations.voiceNoteDeleteWarningTitle,
                                          message: Localizations.voiceNoteDeleteWarningMessage,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
            alert.addAction(UIAlertAction(title: Localizations.buttonDiscard, style: .destructive, handler: { [weak self] _ in
                guard let self = self else {
                    return
                }
                self.state.pendingVoiceNote = nil
                self.cleanupAndFinish()
            }))
            present(alert, animated: true)
            return
        }

        var allMedia = state.pendingMedia
        if let voiceNote = state.pendingVoiceNote {
            allMedia.append(voiceNote)
        }
        for media in allMedia {
            guard let encryptedFileURL = media.encryptedFileUrl else { continue }
            do {
                try FileManager.default.removeItem(at: encryptedFileURL)
                DDLogInfo("NewPostViewController/cleanup/\(encryptedFileURL.absoluteString)/deleted")
            } catch {
                DDLogInfo("NewPostViewController/cleanup/\(encryptedFileURL.absoluteString)/error [\(error)]")
            }
        }
        didFinish(didPost)
    }

    private func didFinishPickingMedia() {
        containedNavigationController.pushViewController(makeComposerViewController(), animated: true)
    }

    private func makeNavigationController() -> UINavigationController {
        switch state.mediaSource {
        case .library:
            return makeMediaPickerViewControllerNew()
        case .camera:
            return UINavigationController(rootViewController: makeNewCameraViewController())
        case .noMedia, .voiceNote:
            return UINavigationController(rootViewController: makeComposerViewController())
        }
    }

    private func makeComposerViewController() -> UIViewController {
        var configuration: PostComposerViewConfiguration = .userPost
        if let privacyListType = privacyListType {
            configuration.privacyListType = privacyListType
        }
        if case .groupFeed(let groupId) = destination {
            configuration = .groupPost(id: groupId)
        }
        
        if let _ = momentContext {
            configuration = .moment
        }

        return PostComposerViewController(
            mediaToPost: state.pendingMedia,
            initialInput: state.pendingInput,
            configuration: configuration,
            initialPostType: state.mediaSource,
            voiceNote: state.pendingVoiceNote,
            delegate: self)
    }

    private func makeNewCameraViewController() -> UIViewController {
        let cameraSubtitle: String?
        switch momentContext {
        case .normal:
            cameraSubtitle = Localizations.newMomentCameraSubtitle
        case .unlock(let userID):
            let name = MainAppContext.shared.contactStore.firstName(for: userID, in: MainAppContext.shared.contactStore.viewContext)
            cameraSubtitle = String(format: Localizations.newMomentCameraUnlockSubtitle, name)
        case .none:
            cameraSubtitle = nil
        }

        return CameraViewController(
            configuration: .init(showCancelButton: state.isPostComposerCancellable, format: momentContext != nil ? .square : .normal, subtitle: cameraSubtitle),
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
        let config: MediaPickerConfig

        switch destination {
        case .userFeed:
            config = .feed
        case .groupFeed(let groupID):
            config = .group(id: groupID)
        }

        let pickerController = MediaPickerViewController(config: config) { [weak self] controller, destination, privacyListType, media, cancel in
            guard let self = self else { return }
            
            if cancel {
                self.cleanupAndFinish()
            } else {
                switch destination {
                case .userFeed:
                    self.privacyListType = privacyListType
                    self.destination = .userFeed
                case .groupFeed(let groupID):
                    self.destination = .groupFeed(groupID)
                default:
                    break
                }

                self.state.pendingMedia = media
                self.didFinishPickingMedia()
            }
        }
        pickerController.title = Localizations.newPost
        
        return UINavigationController(rootViewController: pickerController)
    }

    private func onCameraImagePicked(_ uiImage: UIImage) {
        var pendingMedia = [PendingMedia]()
        let normalizedImage = uiImage.correctlyOrientedImage()
        let mediaToPost = PendingMedia(type: .image)
        mediaToPost.image = normalizedImage

        pendingMedia.append(mediaToPost)
        state.pendingMedia = pendingMedia
        didFinishPickingMedia()
    }

    private func onCameraVideoPicked(_ videoURL: URL) {
        var pendingMedia = [PendingMedia]()
        let mediaToPost = PendingMedia(type: .video)
        mediaToPost.originalVideoURL = videoURL
        mediaToPost.fileURL = videoURL

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
    func composerDidTapShare(controller: PostComposerViewController,
                            destination: PostComposerDestination,
                             feedAudience: FeedAudience,
                               isMoment: Bool = false,
                            mentionText: MentionText,
                                  media: [PendingMedia],
                        linkPreviewData: LinkPreviewData? = nil,
                       linkPreviewMedia: PendingMedia? = nil) {

        switch destination {
        case .userFeed:
            self.destination = .userFeed
        case .groupFeed(let groupId):
            self.destination = .groupFeed(groupId)
        case .chat:
            break
        }

        MainAppContext.shared.feedData.post(text: mentionText,
                                           media: media,
                                 linkPreviewData: linkPreviewData,
                                linkPreviewMedia: linkPreviewMedia,
                                              to: self.destination,
                                            feedAudience: feedAudience,
                                        isMoment: isMoment)
        cleanupAndFinish(didPost: true)
    }

    func composerDidTapBack(controller: PostComposerViewController, destination: PostComposerDestination, privacyListType: PrivacyListType, media: [PendingMedia], voiceNote: PendingMedia?) {
        state.pendingVoiceNote = voiceNote
        containedNavigationController.popViewController(animated: true)
        switch state.mediaSource {
        case .library:
            (containedNavigationController.topViewController as? MediaPickerViewController)?.reset(destination: destination, privacyListType: privacyListType, selected: media)
        case .camera:
            break
        default:
            cleanupAndFinish()
        }

        switch destination {
        case .userFeed:
            self.destination = .userFeed
        case .groupFeed(let groupID):
            self.destination = .groupFeed(groupID)
        case .chat:
            break
        }
    }

    func willDismissWithInput(mentionInput: MentionInput) {
        state.pendingInput = mentionInput
    }

    func composerDidTapLinkPreview(controller: PostComposerViewController, url: URL) {
        URLRouter.shared.handleOrOpen(url: url)
    }
}
