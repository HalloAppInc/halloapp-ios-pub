//
//  picPicker.swift
//  Halloapp
//
//  Created by Tony Jiang on 11/13/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Foundation
import Combine
import SwiftUI
import Alamofire
import SwiftyJSON

struct ImagePicker: UIViewControllerRepresentable {

    @Binding var showPostText: Bool
    @Binding var showSheet: Bool
    @Binding var showImagePicker: Bool

    @Binding var pickedImages: [FeedMedia]
    var goToPostMedia: () -> Void
    
    func makeCoordinator() -> ImagePicker.Coordinator {
        Coordinator(self)
    }
    
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<ImagePicker>) -> UIImagePickerController {
        
        let imagePicker = UIImagePickerController()

        imagePicker.sourceType = .camera
        
        imagePicker.delegate = context.coordinator
        
        return imagePicker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: UIViewControllerRepresentableContext<ImagePicker>) {
        return
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        
        var parent: ImagePicker
        
        init(_ imagePicker: ImagePicker) {
            self.parent = imagePicker
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {

            let preUiImage = info[UIImagePickerController.InfoKey.originalImage] as! UIImage
            let uiImage = preUiImage.correctlyOrientedImage()

            
            let mediaItem = FeedMedia()
             mediaItem.type = "image"
             mediaItem.image = uiImage
             
             var imageWidth = 0
             var imageHeight = 0

             imageWidth = Int(uiImage.size.width)
             imageHeight = Int(uiImage.size.height)

             mediaItem.width = imageWidth
             mediaItem.height = imageHeight
             
            self.parent.pickedImages.append(mediaItem)
            
            self.parent.goToPostMedia()
            self.parent.showImagePicker = false
            self.parent.showPostText = true
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.showImagePicker = false
            parent.showSheet = false
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
