//
//  CameraPickerView.swift
//  Halloapp
//
//  Created by Tony Jiang on 11/13/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct CameraPickerView: UIViewControllerRepresentable {

    @Environment(\.presentationMode) var presentationMode

    @Binding var capturedMedia: [FeedMedia]
    var didFinishWithMedia: () -> Void
    var didCancel: () -> Void

    func makeCoordinator() -> CameraPickerView.Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<CameraPickerView>) -> UIImagePickerController {
        let imagePickerController = UIImagePickerController()
        imagePickerController.sourceType = .camera
        
        let mediatypes = UIImagePickerController.availableMediaTypes(for: .camera)
        
        imagePickerController.mediaTypes = mediatypes!
        
//        imagePickerController.showsCameraControls = false
        imagePickerController.allowsEditing = false
        
        // video
        imagePickerController.videoQuality = .typeMedium
        imagePickerController.videoMaximumDuration = 60
        
        imagePickerController.delegate = context.coordinator
        return imagePickerController
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: UIViewControllerRepresentableContext<CameraPickerView>) {
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: CameraPickerView
        
        init(_ cameraView: CameraPickerView) {
            self.parent = cameraView
        }
        
        func imagePickerController(_ pickerController: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let uiImage = info[.originalImage] as? UIImage {
                let normalizedImage = uiImage.correctlyOrientedImage()
                let mediaItem = FeedMedia()
                mediaItem.type = "image"
                mediaItem.image = normalizedImage
                mediaItem.width = Int(normalizedImage.size.width)
                mediaItem.height = Int(normalizedImage.size.height)
                parent.capturedMedia = [mediaItem]
                parent.didFinishWithMedia()
                
            } else if let videoURL = info[.mediaURL] as? URL {
                let mediaItem = FeedMedia()
                mediaItem.type = "video"
                mediaItem.tempUrl = videoURL
                
                if let videoSize = VideoUtils().resolutionForLocalVideo(url: videoURL) {
                
                    mediaItem.width = Int(videoSize.width)
                    mediaItem.height = Int(videoSize.height)
                    
                    print("video width: \(mediaItem.width)")
                    print("video height: \(mediaItem.height)")
                }
                
                VideoUtils().cropVideo(sourceURL: videoURL, startTime: 0.1, endTime: 5.0, completion: { url in
                    
                    DispatchQueue.main.async {
                        mediaItem.tempUrl = url
                        self.parent.capturedMedia = [mediaItem]
                        
                        self.parent.didFinishWithMedia()
                    }
                    
                })
                    
//                mediaItem.width = Int(normalizedImage.size.width)
//                mediaItem.height = Int(normalizedImage.size.height)


            }
           
        }
        
        func imagePickerControllerDidCancel(_ pickerController: UIImagePickerController) {
            parent.didCancel()
        }
    }
}

extension UIImage {
    public func correctlyOrientedImage() -> UIImage {
        if self.imageOrientation == UIImage.Orientation.up {
            return self
        }

        UIGraphicsBeginImageContextWithOptions(self.size, false, self.scale)
        self.draw(in: CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height))
        let normalizedImage:UIImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()

        return normalizedImage
    }
}
