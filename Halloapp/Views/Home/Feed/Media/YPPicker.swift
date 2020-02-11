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

struct PickerWrapper: UIViewControllerRepresentable {

    typealias UIViewControllerType = YPImagePicker

    @Binding var pickedImages: [UIImage]

    var goBack: () -> Void
    
    var requestUrls: () -> Void
    
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

                    self.pickedImages.append(photo.image)

                case .video(let video):
                    print(video)
                }
            }

            self.requestUrls()
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
