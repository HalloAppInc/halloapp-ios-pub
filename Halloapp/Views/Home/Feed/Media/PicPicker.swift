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
    @Binding var cameraMode: String
    @Binding var pickedImage: Image
    @Binding var pickedUIImage: UIImage
    @Binding var imageUrl: String
    @Binding var pickerStatus: String
    @Binding var uploadStatus: String
    
    @Binding var imageGetUrl: String
    @Binding var imagePutUrl: String
    
    var requestUrl: () -> Void
    
    
    func makeCoordinator() -> ImagePicker.Coordinator {
        Coordinator(self)
    }
    
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<ImagePicker>) -> UIImagePickerController {
        
        self.requestUrl()
        
        let imagePicker = UIImagePickerController()
        if (cameraMode == "camera") {
            imagePicker.sourceType = .camera
        } else {
            imagePicker.sourceType = .photoLibrary
        }
        
//        imagePicker.allowsEditing = true
        
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

            if self.parent.imagePutUrl == "" || self.parent.imageGetUrl == "" {
                print("no url")
                return
            }
            
            self.parent.imageUrl = self.parent.imageGetUrl
            print("get url: \(self.parent.imageUrl)")
            
            let preUiImage = info[UIImagePickerController.InfoKey.originalImage] as! UIImage
            let uiImage = preUiImage.correctlyOrientedImage()
            
            self.parent.pickedImage = Image(uiImage: uiImage)
            self.parent.pickedUIImage = uiImage
            
            self.parent.pickerStatus = "uploading"
            self.upload(uiImage: uiImage)
        
            self.parent.showImagePicker = false
            self.parent.showPostText = true
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.showImagePicker = false
            parent.showSheet = false
        }
        
        func upload(uiImage: UIImage) {
              
            print("have url: \(self.parent.imagePutUrl)")
            
            let uploadUrl = self.parent.imagePutUrl
            
            /* note: compression below a certain point (0.2?) is the same */
            if let imgData = uiImage.jpegData(compressionQuality: 0.1) {

                let headers = [
                    "Content-Type": "image/jpeg"
                ]

                Alamofire.upload(imgData, to: uploadUrl, method: .put, headers: headers)
                    .uploadProgress(closure: { (progress) in
                        print(progress.fractionCompleted)
                    })
                    .responseData { response in

                        if (response.response != nil) {
                            print("success uploading")
              
                            self.parent.pickerStatus = ""
                            
                            self.parent.imageGetUrl = ""
                            self.parent.imagePutUrl = ""
                        }

                    }

            }
              
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
