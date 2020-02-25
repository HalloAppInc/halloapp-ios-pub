//
//  YPPicker.swift
//  Halloapp
//
//  Created by Tony Jiang on 11/14/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Foundation
import Combine
import SwiftUI
import YPImagePicker

import UIKit
import AVFoundation
import AVKit
import Photos

private func resolutionForLocalVideo(url: URL) -> CGSize? {
    guard let track = AVURLAsset(url: url).tracks(withMediaType: AVMediaType.video).first else { return nil }
   let size = track.naturalSize.applying(track.preferredTransform)
    return CGSize(width: abs(size.width), height: abs(size.height))
}

struct PickerWrapper: UIViewControllerRepresentable {

    typealias UIViewControllerType = YPImagePicker

    @Binding var pickedImages: [FeedMedia]

    var goBack: () -> Void
    
    var goToPostMedia: () -> Void
    
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
        config.library.mediaType = YPlibraryMediaType.photo
        config.library.defaultMultipleSelection = false
        config.library.maxNumberOfItems = 10
        config.library.skipSelectionsGallery = true
        config.library.preselectedItems = nil

        // Video
        config.video.compression = AVAssetExportPresetMediumQuality
        config.video.libraryTimeLimit = 500.0
        
        let picker = YPImagePicker(configuration: config)


        picker.didFinishPicking { [unowned picker] items, cancelled in

            if cancelled {
                picker.dismiss(animated: true, completion: nil)
                self.goBack()
                return
            }

            for item in items {
                switch item {
                case .photo(let photo):
                    
                    let mediaItem = FeedMedia()
                    mediaItem.type = "image"
                    mediaItem.image = photo.image
                    
                    var imageWidth = 0
                    var imageHeight = 0

                    imageWidth = Int(photo.image.size.width)
                    imageHeight = Int(photo.image.size.height)

                    mediaItem.width = imageWidth
                    mediaItem.height = imageHeight
                    
                    self.pickedImages.append(mediaItem)

                case .video(let video):
                    
                    let mediaItem = FeedMedia()
                    mediaItem.type = "video"
  
                    
                    if let videoData = try? Data(contentsOf: video.url) {
                        mediaItem.data = videoData


                        let fileUrl = URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("video").appendingPathExtension("mp4")
                            
                        let wasFileWritten = (try? videoData.write(to: fileUrl, options: [.atomic])) != nil
                        
                        if !wasFileWritten{
                            print("File was NOT Written")
                        }
                            
                        mediaItem.tempUrl = fileUrl
                        
//                        if let tempFileUrl = try? String(contentsOf: fileUrl) {
//                            
//                            mediaItem.tempUrl = tempFileUrl
//                        }
                        
                        

                    }
                    
                    if let videoSize = resolutionForLocalVideo(url: video.url) {
                    
                        mediaItem.width = Int(videoSize.width)
                        mediaItem.height = Int(videoSize.height)
                        
                        print("video width: \(mediaItem.width)")
                        print("video height: \(mediaItem.height)")
                    }
                        


                    
                    self.pickedImages.append(mediaItem)
                    
                    print(video)
                }
            }

            self.goToPostMedia()
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
