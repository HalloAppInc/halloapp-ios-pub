//
//  FeedViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 4/20/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVFoundation
import CocoaLumberjack
import Combine
import Core
import CoreData
import Photos
import SwiftUI
import UIKit
import YPImagePicker

class FeedViewController: FeedTableViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate, YPImagePickerDelegate {

    private var cancellables: Set<AnyCancellable> = []

    // MARK: UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        let notificationButton = BadgedButton(type: .system)
        notificationButton.setImage(UIImage(named: "FeedNavbarNotifications"), for: .normal)
        notificationButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        notificationButton.addTarget(self, action: #selector(presentNotificationsView), for: .touchUpInside)
        if let feedNotifications = MainAppContext.shared.feedData.feedNotifications {
            notificationButton.isBadgeHidden = feedNotifications.unreadCount == 0
            self.cancellables.insert(feedNotifications.unreadCountDidChange.sink { (unreadCount) in
                notificationButton.isBadgeHidden = unreadCount == 0
            })
        }

        let composeButton = UIButton(type: .system)
        composeButton.setImage(UIImage(named: "FeedCompose"), for: .normal)
        composeButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        composeButton.tintColor = .lavaOrange
        composeButton.addTarget(self, action: #selector(composePost), for: .touchUpInside)

        self.navigationItem.rightBarButtonItems = [
            UIBarButtonItem(customView: composeButton),
            UIBarButtonItem(customView: notificationButton) ]

        let privacySettings = MainAppContext.shared.xmppController.privacySettings!
        cancellables.insert(privacySettings.mutedContactsChanged.sink { [weak self] in
            guard let self = self else { return }
            self.reloadTableView()
            })

        cancellables.insert(
            MainAppContext.shared.didTapNotification.sink { [weak self] (metadata) in
                guard metadata.contentType == .comment else { return }
                guard let self = self else { return }
                self.processNotification(metadata: metadata)
            }
        )

        // When the user was not on this view, and HomeView sends user to here
        if let metadata = NotificationUtility.Metadata.fromUserDefaults(), metadata.contentType == .comment {
            self.processNotification(metadata: metadata)
        }
    }

    deinit {
        self.cancellables.forEach { $0.cancel() }
    }

    // MARK: FeedTableViewController

    override var fetchRequest: NSFetchRequest<FeedPost> {
        get {
            let mutedUserIds = MainAppContext.shared.xmppController.privacySettings.mutedContactIds
            let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
            if !mutedUserIds.isEmpty {
                fetchRequest.predicate = NSPredicate(format: "NOT (userId IN %@)", mutedUserIds)
            }
            fetchRequest.sortDescriptors = [ NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false) ]
            return fetchRequest
        }
    }

    // MARK: UI Actions

    @objc(composePost)
    private func composePost() {
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: "Photo Library", style: .default) { _ in
            self.presentPhotoLibraryPicker()
        })
        actionSheet.addAction(UIAlertAction(title: "Camera", style: .default) { _ in
            self.presentCameraView()
        })
        actionSheet.addAction(UIAlertAction(title: "Text", style: .default) { _ in
            self.presentPostComposer(with: [])
        })
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        self.present(actionSheet, animated: true, completion: nil)
    }

    @objc(showNotifications)
    private func presentNotificationsView() {
        self.present(UINavigationController(rootViewController: NotificationsViewController()), animated: true)
    }

    // MARK: Camera View

    private func presentCameraView() {
        let imagePickerController = UIImagePickerController()
        imagePickerController.sourceType = .camera
        if let mediatypes = UIImagePickerController.availableMediaTypes(for: .camera) {
            imagePickerController.mediaTypes = mediatypes
        }
        imagePickerController.allowsEditing = false
        imagePickerController.videoQuality = .typeHigh // gotcha: .typeMedium have empty frames in the beginning
        imagePickerController.videoMaximumDuration = Date.minutes(1)
        imagePickerController.delegate = self
        self.present(imagePickerController, animated: true)
    }

    func imagePickerController(_ pickerController: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        var mediaToPost: PendingMedia?
        if let uiImage = info[.originalImage] as? UIImage {
            let normalizedImage = uiImage.correctlyOrientedImage()
            mediaToPost = PendingMedia(type: .image)
            mediaToPost!.image = normalizedImage
            mediaToPost!.size = normalizedImage.size
        } else if let videoURL = info[.mediaURL] as? URL {
            mediaToPost = PendingMedia(type: .video)
            mediaToPost!.videoURL = videoURL

            if let videoSize = VideoUtils.resolutionForLocalVideo(url: videoURL) {
                mediaToPost!.size = videoSize
                DDLogInfo("Video size: [\(NSCoder.string(for: videoSize))]")
            }
        }
        self.dismiss(animated: mediaToPost == nil) {
            if mediaToPost != nil {
                self.presentPostComposer(with: [ mediaToPost! ])
            }
        }
    }

    // MARK: Photo Library Picker

    private func presentPhotoLibraryPicker() {
        var config = YPImagePickerConfiguration()

        // General
        config.library.mediaType = .photoAndVideo
        config.shouldSaveNewPicturesToAlbum = false
        config.showsCrop = .none
        config.wordings.libraryTitle = "Gallery"
        config.showsPhotoFilters = false
        config.showsVideoTrimmer = false
        config.startOnScreen = YPPickerScreen.library
        config.screens = [.library]
        config.hidesStatusBar = true
        config.hidesBottomBar = true

        // Library
        config.library.onlySquare = false
        config.library.isSquareByDefault = false
        config.library.mediaType = YPlibraryMediaType.photoAndVideo
        config.library.defaultMultipleSelection = false
        config.library.maxNumberOfItems = 10
        config.library.skipSelectionsGallery = true
        config.library.preselectedItems = nil

        // Video
        config.video.compression = AVAssetExportPresetPassthrough
        config.video.fileType = .mp4
        config.video.recordingTimeLimit = 60.0
        config.video.libraryTimeLimit = 60.0
        config.video.minimumTimeLimit = 3.0
        config.video.trimmerMaxDuration = 60.0
        config.video.trimmerMinDuration = 3.0

        let picker = YPImagePicker(configuration: config)
        picker.delegate = self
        picker.didFinishPicking { [unowned picker] items, cancelled in

            guard !cancelled else {
                picker.dismiss(animated: true)
                return
            }

            var mediaToPost: [PendingMedia] = []
            let mediaGroup = DispatchGroup()
            var orderCounter: Int = 1
            for item in items {
                switch item {
                case .photo(let photo):
                    let mediaItem = PendingMedia(type: .image)
                    mediaItem.order = orderCounter
                    mediaItem.image = photo.image
                    mediaItem.size = photo.image.size
                    orderCounter += 1
                    mediaToPost.append(mediaItem)
                case .video(let video):
                    let mediaItem = PendingMedia(type: .video)
                    mediaItem.order = orderCounter
                    orderCounter += 1

                    if let videoSize = VideoUtils.resolutionForLocalVideo(url: video.url) {
                        mediaItem.size = videoSize
                        DDLogInfo("Video size: [\(NSCoder.string(for: videoSize))]")
                    }

                    if let asset = video.asset {
                        mediaGroup.enter()
                        PHCachingImageManager().requestAVAsset(forVideo: asset, options: nil) { (avAsset, _, _) in
                            let asset = avAsset as! AVURLAsset
                            mediaItem.videoURL = asset.url
                            mediaToPost.append(mediaItem)
                            mediaGroup.leave()
                        }
                    }
                }
            }

            mediaGroup.notify(queue: .main) {
                mediaToPost.sort { $0.order < $1.order }
                let postComposerViewController = PostComposerViewController(mediaToPost: mediaToPost, showCancelButton: false) {
                    self.dismiss(animated: true)
                }
                picker.pushViewController(postComposerViewController, animated: true)
            }
        }
        self.present(picker, animated: true)
    }

    func noPhotos() { }

    // MARK: Post Composer

    private func presentPostComposer(with media: [PendingMedia]) {
        let postComposerViewController = PostComposerViewController(mediaToPost: media, showCancelButton: true) {
            self.dismiss(animated: true)
        }
        self.present(UINavigationController(rootViewController: postComposerViewController), animated: true)
    }

    // MARK: Notification Handling

    private func processNotification(metadata: NotificationUtility.Metadata) {
        metadata.removeFromUserDefaults()

        DDLogInfo("FeedViewController/notification/process contentId=\(metadata.contentId)")

        guard let protoContainer = metadata.protoContainer, protoContainer.hasComment else {
            DDLogError("FeedViewController/notification/process/error Invalid protobuf")
            return
        }

        guard let feedPost = MainAppContext.shared.feedData.feedPost(with: protoContainer.comment.feedPostID) else {
            DDLogError("FeedViewController/notification/process/error Missing post with id=[\(protoContainer.comment.feedPostID)]")
            return
        }

        self.navigationController?.popToRootViewController(animated: false)
        self.showCommentsView(for: feedPost.id)
    }


}
