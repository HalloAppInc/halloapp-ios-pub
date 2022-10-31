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
                          value: "Audio recording will not be saved if you discard this post.",
                          comment: "Warning message shown to the user before discarding a audio post")
    }
}

enum NewPostMediaSource {
    case library
    case camera
    case noMedia
    case voiceNote
    case unified
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

final class NewPostViewController: UINavigationController {

    private let transitionDuration: CGFloat = 0.15

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    init(source: NewPostMediaSource, destination: ShareDestination, usedInTabBar: Bool = false, showDestinationPicker: Bool, didFinish: @escaping ((Bool) -> Void)) {
        self.didFinish = didFinish
        self.state = NewPostState(mediaSource: source)
        self.destination = destination
        self.usedInTabBar = usedInTabBar
        self.showDestinationPicker = showDestinationPicker
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("Use init(source:didFinish:)")
    }

    override func loadView() {
        super.loadView()
        view.backgroundColor = .feedBackground

        setViewControllers([startingViewController()], animated: false)
        navigationBar.tintColor = .primaryBlue

        if usedInTabBar {
            setupTabBarAppearance()
        }
    }

    // MARK: Private

    private let didFinish: ((Bool) -> Void)
    private var state: NewPostState
    private var destination: ShareDestination
    private let usedInTabBar: Bool
    private let showDestinationPicker: Bool

    private func setupTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.backgroundEffect = nil
        appearance.backgroundColor = nil
        appearance.backgroundImage = UIImage()
        appearance.shadowImage = UIImage()
        appearance.configureWithTransparentBackground()

        tabBarItem.standardAppearance = appearance
        if #available(iOS 15, *) {
            tabBarItem.scrollEdgeAppearance = appearance
        }
    }

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

        if usedInTabBar, let first = viewControllers.first {
            setViewControllers([first], animated: true)
        }

        didFinish(didPost)
    }

    private func pushComposer() {
        UIView.transition(with: view, duration: transitionDuration, options: [.transitionCrossDissolve]) {
            self.pushViewController(self.makeComposerViewController(), animated: false)
        }
    }

    private func startingViewController() -> UIViewController {
        switch state.mediaSource {
        case .library:
            return makeMediaPickerViewControllerNew()
        case .camera:
            return makeNewCameraViewController()
        case .noMedia, .voiceNote, .unified:
            return makeComposerViewController()
        }
    }

    private func makeComposerViewController() -> UIViewController {
        return ComposerViewController(config: .config(with: destination),
                                      type: state.mediaSource,
                                      showDestinationPicker: showDestinationPicker,
                                      input: state.pendingInput,
                                      media: state.pendingMedia,
                                      voiceNote: state.pendingVoiceNote) { [weak self] controller, result , success in
            guard let self = self else { return }

            self.state.pendingInput = result.input
            self.state.pendingMedia = result.media
            self.state.pendingVoiceNote = result.voiceNote

            if success {
                if result.destinations.isEmpty || (!controller.isCompactShareFlow && self.showDestinationPicker) {
                    UIView.transition(with: self.view, duration: self.transitionDuration, options: [.transitionCrossDissolve]) {
                        self.pushViewController(self.makeDestinationPickerViewController(with: result), animated: false)
                    }
                } else {
                    self.share(to: result.destinations, result: result)
                }
            } else {
                UIView.transition(with: self.view, duration: self.transitionDuration, options: [.transitionCrossDissolve]) {
                    self.popViewController(animated: false)
                }

                switch self.state.mediaSource {
                case .library:
                    let controller = self.topViewController as? MediaPickerViewController
                    controller?.reset(destination: self.destination, selected: self.state.pendingMedia)
                case .camera:
                    break
                default:
                    self.cleanupAndFinish()
                }
            }
        }
    }

    private func makeDestinationPickerViewController(with result: ComposerResult) -> UIViewController {
        return DestinationPickerViewController(config: .composer, destinations: result.destinations) { controller, destinations in
            if destinations.count > 0 {
                self.share(to: destinations, result: result)
            } else {
                UIView.transition(with: self.view, duration: self.transitionDuration, options: [.transitionCrossDissolve]) {
                    self.popViewController(animated: false)
                }
            }
        }
    }

    private func share(to destinations: [ShareDestination], result: ComposerResult) {
        guard let text = result.text else { return }

        for destination in destinations {
            switch destination {
            case .contact(let userId, _, _):
                sendChatMessage(
                    chatMessageRecipient: .oneToOneChat(toUserId: userId, fromUserId: AppContext.shared.userData.userId),
                    text: text.trimmed().collapsedText,
                    media: result.media,
                    files: [],
                    linkPreviewData: result.linkPreviewData,
                    linkPreviewMedia: result.linkPreviewMedia,
                    feedPostId: nil,
                    feedPostMediaIndex: 0,
                    chatReplyMessageID: nil,
                    chatReplyMessageSenderID: nil,
                    chatReplyMessageMediaIndex: 0,
                    result: result)
            case .group(let groupId, _):
                if let group = MainAppContext.shared.chatData.chatGroup(groupId: groupId, in: MainAppContext.shared.feedData.viewContext) {
                    switch group.type {
                    case .groupFeed:
                        makePost(
                            text: text,
                            media: result.media,
                            linkPreviewData: result.linkPreviewData,
                            linkPreviewMedia: result.linkPreviewMedia,
                            to: destination, result: result)
                    case .groupChat:
                        sendChatMessage(
                            chatMessageRecipient: .groupChat(toGroupId: groupId, fromUserId: AppContext.shared.userData.userId),
                            text: text.trimmed().collapsedText,
                            media: result.media,
                            files: [],
                            linkPreviewData: result.linkPreviewData,
                            linkPreviewMedia: result.linkPreviewMedia,
                            feedPostId: nil,
                            feedPostMediaIndex: 0,
                            chatReplyMessageID: nil,
                            chatReplyMessageSenderID: nil,
                            chatReplyMessageMediaIndex: 0,
                            result: result)
                    case .oneToOne:
                        break
                    }
                }
            case .feed(_):
                makePost(
                    text: text,
                    media: result.media,
                    linkPreviewData: result.linkPreviewData,
                    linkPreviewMedia: result.linkPreviewMedia,
                    to: destination, result: result)
            }
        }

        cleanupAndFinish(didPost: true)
    }

    private func sendChatMessage(chatMessageRecipient: ChatMessageRecipient,
                                 text: String,
                                 media: [PendingMedia],
                                 files: [FileSharingData],
                                 linkPreviewData: LinkPreviewData? = nil,
                                 linkPreviewMedia : PendingMedia? = nil,
                                 location: ChatLocationProtocol? = nil,
                                 feedPostId: String?,
                                 feedPostMediaIndex: Int32,
                                 chatReplyMessageID: String? = nil,
                                 chatReplyMessageSenderID: UserID? = nil,
                                 chatReplyMessageMediaIndex: Int32,
                                 result: ComposerResult) {
        MainAppContext.shared.chatData.sendMessage(
            chatMessageRecipient: chatMessageRecipient,
            text: text,
            media: result.media,
            files: [],
            linkPreviewData: result.linkPreviewData,
            linkPreviewMedia: result.linkPreviewMedia,
            feedPostId: nil,
            feedPostMediaIndex: 0,
            chatReplyMessageID: nil,
            chatReplyMessageSenderID: nil,
            chatReplyMessageMediaIndex: 0)
        
    }

    private func makePost(text: MentionText, media: [PendingMedia], linkPreviewData: LinkPreviewData?, linkPreviewMedia : PendingMedia?, to destination: ShareDestination, momentInfo: PendingMomentInfo? = nil, result: ComposerResult) {
        MainAppContext.shared.feedData.post(
            text: text,
            media: result.media,
            linkPreviewData: result.linkPreviewData,
            linkPreviewMedia: result.linkPreviewMedia,
            to: destination)
    }

    private func makeNewCameraViewController() -> UIViewController {
        let options: NewCameraViewController.Options = usedInTabBar ? [.showLibraryButton] : [.showDismissButton, .showLibraryButton]
        let vc = NewCameraViewController(options: options)

        vc.title = Localizations.fabAccessibilityCamera
        vc.delegate = self

        return vc
    }
    
    private func makeMediaPickerViewControllerNew() -> UIViewController {
        let config = MediaPickerConfig.config(with: destination)
        let pickerController = MediaPickerViewController(config: config) { [weak self] controller, destination, media, cancel in
            guard let self = self else { return }
            
            if cancel {
                self.cleanupAndFinish()
            } else {
                if let destination = destination {
                    self.destination = destination
                }

                self.state.pendingMedia = media
                self.pushComposer()
            }
        }
        pickerController.title = Localizations.newPost
        
        return pickerController
    }

    private func onCameraImagePicked(_ uiImage: UIImage) {
        var pendingMedia = [PendingMedia]()
        let normalizedImage = uiImage.correctlyOrientedImage()
        let mediaToPost = PendingMedia(type: .image)
        mediaToPost.image = normalizedImage

        pendingMedia.append(mediaToPost)
        state.pendingMedia = pendingMedia
        pushComposer()
    }

    private func onCameraVideoPicked(_ videoURL: URL) {
        var pendingMedia = [PendingMedia]()
        let mediaToPost = PendingMedia(type: .video)
        mediaToPost.originalVideoURL = videoURL
        mediaToPost.fileURL = videoURL

        pendingMedia.append(mediaToPost)
        state.pendingMedia = pendingMedia
        pushComposer()
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
        pushComposer()
    }
}

extension NewPostViewController: CameraViewControllerDelegate {

    func cameraViewControllerDidReleaseShutter(_ viewController: NewCameraViewController) {

    }

    func cameraViewController(_ viewController: NewCameraViewController, didCapture results: [CaptureResult], isFinished: Bool) {
        guard isFinished else {
            return
        }

        let media = results.map { result -> PendingMedia in
            let media = PendingMedia(type: .image)
            media.image = result.image
            return media
        }

        state.pendingMedia = media
        pushComposer()
    }

    func cameraViewController(_ viewController: NewCameraViewController, didRecordVideoTo url: URL) {
        let media = PendingMedia(type: .video)
        media.originalVideoURL = url
        media.fileURL = url

        state.pendingMedia = [media]
        pushComposer()
    }

    func cameraViewController(_ viewController: NewCameraViewController, didSelect media: PendingMedia) {
        state.pendingMedia = [media]
        pushComposer()
    }
}

extension NewPostViewController: PostComposerViewDelegate {
    func composerDidTapShare(controller: PostComposerViewController,
                            destination: ShareDestination,
                            mentionText: MentionText,
                                  media: [PendingMedia],
                        linkPreviewData: LinkPreviewData? = nil,
                       linkPreviewMedia: PendingMedia? = nil) {
        self.destination = destination

        MainAppContext.shared.feedData.post(text: mentionText,
                                           media: media,
                                 linkPreviewData: linkPreviewData,
                                linkPreviewMedia: linkPreviewMedia,
                                              to: destination)
        cleanupAndFinish(didPost: true)
    }

    func composerDidTapBack(controller: PostComposerViewController, destination: ShareDestination, media: [PendingMedia], voiceNote: PendingMedia?) {
        self.destination = destination

        state.pendingVoiceNote = voiceNote
        UIView.transition(with: self.view, duration: transitionDuration, options: [.transitionCrossDissolve]) {
            self.popViewController(animated: false)
        }

        switch state.mediaSource {
        case .library:
            let picker = topViewController as? MediaPickerViewController
            picker?.reset(destination: destination, selected: media)
        case .camera:
            break
        default:
            cleanupAndFinish()
        }
    }

    func willDismissWithInput(mentionInput: MentionInput) {
        state.pendingInput = mentionInput
    }

    func composerDidTapLinkPreview(controller: PostComposerViewController, url: URL) {
        URLRouter.shared.handleOrOpen(url: url)
    }
}
