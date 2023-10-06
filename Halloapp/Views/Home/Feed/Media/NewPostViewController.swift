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
    var highlightedAssetCollection: PHAssetCollection?
    var mediaDebugInfo: DebugInfoMap?

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

    init(state: NewPostState, destination: ShareDestination, usedInTabBar: Bool = false, showDestinationPicker: Bool, didFinish: @escaping ((Bool, [ShareDestination]) -> Void)) {
        self.didFinish = didFinish
        self.state = state
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        Analytics.openScreen(usedInTabBar ? .camera : .composer)
    }

    // MARK: Private

    private let didFinish: ((Bool, [ShareDestination]) -> Void)
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
        tabBarItem.scrollEdgeAppearance = appearance
    }

    private func cleanupAndFinish(didPost: Bool = false, destinations: [ShareDestination] = []) {
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

        didFinish(didPost, destinations)
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

        var postProperties = Analytics.EventProperties()
        if !text.isEmpty() {
            postProperties[.hasText] = true
        }
        result.media.forEach { media in
            switch media.type {
            case .audio:
                postProperties[.attachedAudioCount] = (postProperties[.attachedAudioCount] as? Int ?? 0) + 1
            case .image:
                postProperties[.attachedImageCount] = (postProperties[.attachedImageCount] as? Int ?? 0) + 1
            case .video:
                postProperties[.attachedVideoCount] = (postProperties[.attachedVideoCount] as? Int ?? 0) + 1
            case .document:
                postProperties[.attachedDocumentCount] = (postProperties[.attachedDocumentCount] as? Int ?? 0) + 1
            }
        }
        if result.linkPreviewData != nil {
            postProperties[.attachedLinkPreviewCount] = 1
        }
        destinations.forEach { destination in
            switch destination {
            case .feed(let privacyListType):
                switch privacyListType {
                case .all:
                    postProperties[.destinationSendToAll] = true
                case .whitelist:
                    postProperties[.destinationSendToFavorites] = true
                default:
                    break
                }
            case .user:
                postProperties[.destinationNumContacts] = (postProperties[.destinationNumContacts] as? Int ?? 0) + 1
            case .group:
                postProperties[.destinationNumGroups] = (postProperties[.destinationNumGroups] as? Int ?? 0) + 1
            }
        }
        Analytics.log(event: .sendPost, properties: postProperties)

        for destination in destinations {
            switch destination {
            case .user(let userId, _, _):
                sendChatMessage(
                    chatMessageRecipient: .oneToOneChat(toUserId: userId, fromUserId: AppContext.shared.userData.userId),
                    text: text,
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
            case .group(let groupId, let type, _):
                switch type {
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
                        text: text,
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
            case .feed(_):
                makePost(
                    text: text,
                    media: result.media,
                    linkPreviewData: result.linkPreviewData,
                    linkPreviewMedia: result.linkPreviewMedia,
                    to: destination, result: result)
            }
        }

        cleanupAndFinish(didPost: true, destinations: destinations)
    }

    private func sendChatMessage(chatMessageRecipient: ChatMessageRecipient,
                                 text: MentionText,
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
            mentionText: text,
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
        let vc = NewCameraViewController(presets: [.photo], initialPresetIndex: 0)

        vc.title = Localizations.fabAccessibilityCamera
        vc.delegate = self

        return vc
    }

    private func makeMediaPickerViewControllerNew() -> UIViewController {
        let config = MediaPickerConfig.config(with: destination)
        let pickerController = MediaPickerViewController(config: config,
                                                         selected: state.pendingMedia,
                                                         highlightedAssetCollection: state.highlightedAssetCollection,
                                                         mediaDebugInfo: state.mediaDebugInfo) { [weak self] controller, destination, media, cancel in
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
}

extension NewPostViewController: CameraViewControllerDelegate {

    func cameraViewControllerDidReleaseShutter(_ viewController: NewCameraViewController) {

    }

    func cameraViewController(_ viewController: NewCameraViewController, didCapture results: [CaptureResult], with preset: CameraPreset) {
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

    func cameraViewController(_ viewController: NewCameraViewController, didSelect media: [PendingMedia]) {
        state.pendingMedia = media
        pushComposer()
    }
}
