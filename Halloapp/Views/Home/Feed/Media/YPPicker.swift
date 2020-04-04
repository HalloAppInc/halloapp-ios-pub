//
//  Halloapp
//
//  Created by Tony Jiang on 11/14/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//
import AVFoundation
import AVKit
import CocoaLumberjack
import Combine
import Foundation
import Photos
import SwiftUI
import UIKit
import YPImagePicker

struct PickerWrapper: UIViewControllerRepresentable {

    typealias UIViewControllerType = YPImagePicker

    @Binding var selectedMedia: [PendingMedia]
    var didFinishWithMedia: () -> Void
    var didCancel: () -> Void

    func makeCoordinator() -> PickerWrapper.Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<PickerWrapper>) -> PickerWrapper.UIViewControllerType {

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
        config.video.compression = AVAssetExportPresetMediumQuality
        config.video.fileType = .mp4
        config.video.recordingTimeLimit = 60.0
        config.video.libraryTimeLimit = 60.0
        config.video.minimumTimeLimit = 3.0
        config.video.trimmerMaxDuration = 60.0
        config.video.trimmerMinDuration = 3.0
        
        let picker = YPImagePicker(configuration: config)

        picker.didFinishPicking { [unowned picker] items, cancelled in

            if cancelled {
                picker.dismiss(animated: true, completion: nil)
                self.didCancel()
                return
            }

            for (index, item) in items.enumerated() {
                print(("item at \(index): \(item)"))
            }
            
            var orderCounter: Int = 1
            for item in items {
                switch item {
                case .photo(let photo):
                    
                    let mediaItem = PendingMedia(type: .image)
                    mediaItem.order = orderCounter
                    mediaItem.image = photo.image
                    mediaItem.size = photo.image.size

                    orderCounter += 1

                    self.selectedMedia.append(mediaItem)

                case .video(let video):
                    
                    let mediaItem = PendingMedia(type: .video)
                    mediaItem.order = orderCounter
                    mediaItem.tempUrl = video.url

                    orderCounter += 1

                    if let videoSize = VideoUtils().resolutionForLocalVideo(url: video.url) {
                        mediaItem.size = videoSize

                        DDLogInfo("Video size: [\(NSCoder.string(for: videoSize))]")
                    }
                        
                    self.selectedMedia.append(mediaItem)                    
                }
            }

            self.didFinishWithMedia()
            picker.dismiss(animated: true, completion: nil)
            return

        }

        picker.delegate = context.coordinator

        return picker

    }

    func updateUIViewController(_ uiViewController: PickerWrapper.UIViewControllerType, context: UIViewControllerRepresentableContext<PickerWrapper>) {
        return
    }

    class Coordinator: NSObject, YPImagePickerDelegate, UINavigationControllerDelegate {

        var parent: PickerWrapper

        init(_ pickerWrapper: PickerWrapper) {
            self.parent = pickerWrapper
        }

        func noPhotos() {
        }

    }

}
