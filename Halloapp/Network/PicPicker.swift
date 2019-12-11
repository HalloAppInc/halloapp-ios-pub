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
    
    var callback: () -> Void
    
    
    
    func makeCoordinator() -> ImagePicker.Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<ImagePicker>) -> UIImagePickerController {
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
            let preUiImage = info[UIImagePickerController.InfoKey.originalImage] as! UIImage
            
            let uiImage = preUiImage.correctlyOrientedImage()
            
            parent.pickedImage = Image(uiImage: uiImage)
            parent.pickedUIImage = uiImage
            
            parent.pickerStatus = "uploading"
            self.upload(uiImage: uiImage)
            
//
//            if let imgData = uiImage.jpegData(compressionQuality: 0.2) {
//                let parameters = ["user":"Sol", "password":"secret1234"]
//                upload(params: parameters, imageData: imgData)
//            }
            
            
            parent.showImagePicker = false
            parent.showPostText = true
//            parent.showSheet = false
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.showImagePicker = false
            parent.showSheet = false
        }
        

        func upload(uiImage: UIImage) {
            
            /* note: compression below a certain point (0.2?) is the same */
            if let imgData = uiImage.jpegData(compressionQuality: 0.1) {

                print("img: \(imgData.count)")
                
                let parameters = ["user":"Sol", "password":"secret1234"]
                
                let apiSecret = "OTAuZPlIJIM8rFOoJUNpYayd7Iubi/0B2HC+PU8WnRo="
                let apiKey = "Heis4jPh62Tuzh9hGP+K4w=="
                let base64 = "\(apiKey):\(apiSecret)".data(using: .utf8)?.base64EncodedString()
                let headers = [
                    "Content-Type": "application/json",
                    "Authorization": "Basic \(base64!)"
                ]
                
                Alamofire.upload(
                    multipartFormData: { multipartFormData in
                        multipartFormData.append(imgData, withName: "fileset",fileName: "file.jpg", mimeType: "image/jpg")
                        for (key, value) in parameters {
                                multipartFormData.append(value.data(using: String.Encoding.utf8)!, withName: key)
                            } //Optional for extra parameters
                    },
                    to: "https://api.image4.io/v0.1/upload",
                    headers: headers
                    
                )
                { (result) in
                    switch result {
                    case .success(let upload, _, _):

                        upload.uploadProgress(closure: { (progress) in
                            print("Upload Progress: \(progress.fractionCompleted)")
                        })

                        upload.responseJSON { response in
                      
                            if let json = response.data {
                                do {
                                    let data = try JSON(data: json)
                                    let str = data["uploadedFiles"][0]["name"].stringValue
                                    
                                    print("DATA PARSED: \(str)")
                                    self.parent.imageUrl = str
                                    self.parent.pickerStatus = ""
                                    
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0) {
                                        self.parent.callback()
                                    }
                                    
                                    
                                    
                                }
                                catch{
                                print("JSON Error")
                                }

                            }
                            
                        }

                    case .failure(let encodingError):
                        print(encodingError)
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
        let normalizedImage:UIImage = UIGraphicsGetImageFromCurrentImageContext()!;
        UIGraphicsEndImageContext();

        return normalizedImage;
    }
}
