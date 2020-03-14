//
//  ImageServer.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/9/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Alamofire
import Foundation
import SwiftUI
import XMPPFramework

class ImageServer {

    func beginUploading(items mediaItems: [FeedMedia], isReady: Binding<Bool>) {
        guard !mediaItems.isEmpty else {
            isReady.wrappedValue = true
            return
        }
        // Request media URLs for all items
        var mediaURLs: [MediaURL] = []
        for _ in mediaItems {
            let request = XMPPMediaUploadURLRequest(completion: { urls, error in
                if urls != nil {
                    mediaURLs.append(contentsOf: urls!)
                }
                if mediaURLs.count == mediaItems.count {
                    startUploadingMedia()
                }
            })
            AppContext.shared.xmppController.enqueue(request: request)
        }

        func startUploadingMedia() {
            let userData = AppContext.shared.userData
            var itemsToUpload: [FeedMedia] = []
            for (index, item) in mediaItems.enumerated() {
                item.url = mediaURLs[index].get.absoluteString

                let feedMedia = FeedMedia()
                feedMedia.type = item.type
                feedMedia.url = mediaURLs[index].put.absoluteString

                if feedMedia.type == "image" {
                    userData.log("Post Image: original res - \(item.width) x \(item.height)")

                    if item.width > 1600 || item.height > 1600 {
                        item.image = item.image.getNewSize(res: 1600) ?? UIImage()
                        item.width = Int(item.image.size.width)
                        item.height = Int(item.image.size.height)

                        userData.log("Post Image: resized res - \(item.image.size.width) x \(item.image.size.height)")
                    }

                    feedMedia.image = item.image

                    /* turn on/off encryption of media */
                    if let imgData = feedMedia.image.jpegData(compressionQuality: CGFloat(userData.compressionQuality)) {
                        userData.log("Post Image: (\(userData.compressionQuality)) compressed size - \(imgData.count)")

                        (feedMedia.encryptedData, feedMedia.key, feedMedia.sha256hash) = HAC().encryptData(data: imgData, type: "image")

                        item.key = feedMedia.key
                        item.sha256hash = feedMedia.sha256hash
                    }
                }

                itemsToUpload.append(feedMedia)
            }

            self.upload(items: itemsToUpload)
            isReady.wrappedValue = true
        }
    }

    func upload(items mediaItems: [FeedMedia]) {
        guard !mediaItems.isEmpty else {
            return
        }
        let pendingCore = PendingCore()
        for item in mediaItems {
            if item.key != "" {
                uploadData(for: item)
                item.type += "-encrypted"
            } else {
                upload(item: item)
                
                /* only doing pending for unencrypted items for now */
                DispatchQueue.global(qos: .default).async {
                    pendingCore.create(item: item)
                }
            }
        }
    }
    
    func uploadData(for mediaItem: FeedMedia) {
        let uploadUrl = mediaItem.url
        let headers = [ "Content-Type": "image/jpeg" ]
        Alamofire.upload(mediaItem.encryptedData!, to: uploadUrl, method: .put, headers: headers)
            .responseData { response in
                if (response.response != nil) {
                    print("success uploading")
                    DispatchQueue.global(qos: .default).async {
                        PendingCore().delete(url: uploadUrl)
                    }
                }
        }
    }
    
    func upload(item: FeedMedia) {
        let uploadUrl = item.url
        
        /* note: compression below a certain point (0.2?) is the same */
        if let imgData = item.image.jpegData(compressionQuality: 0.1) {
            let headers = [ "Content-Type": "image/jpeg" ]
            Alamofire.upload(imgData, to: uploadUrl, method: .put, headers: headers)
                .responseData { response in
                    if (response.response != nil) {
                        print("success uploading")
                        DispatchQueue.global(qos: .default).async {
                            PendingCore().delete(url: uploadUrl)
                        }
                    }
            }
        }
    }
    
    func processPending() {
        upload(items: PendingCore().getAll())
    }
    
    func deleteImage(imageUrl: String) {

        if imageUrl == "" {
            return
        }
        
        var imageToDelete = ""
        let prefix = "https://res.cloudinary.com/halloapp/image/upload/"

        if imageUrl.hasPrefix(prefix) {

           let partial = String(imageUrl.dropFirst(prefix.count))
           
           var components = partial.components(separatedBy: "/")
           
           if components.count > 1 {
               components.removeFirst()
           }
           
           components = components[0].components(separatedBy: ".")
           
           if components.count > 1 {
               components.removeLast()
           }
           
           imageToDelete = components[0]

        }

        if imageToDelete != "" {
           print("delete: \(imageToDelete)")
           self.deleteImageFromCloudinary(item: imageToDelete)
        }
        
    }
    
    func deleteImageFromCloudinary(item: String) {

        let url = "https://api.cloudinary.com/v1_1/halloapp/image/destroy"
        
        print("url: \(url)")
    
        guard let formedUrl = URL(string: url) else {
            return
        }
        
        var urlRequest = URLRequest(url: formedUrl)

        urlRequest.httpMethod = "POST"
        
        let public_id = item
        let timestamp = Int(Date().timeIntervalSince1970)
        
        let apiKey = "288886135261181"
        let apiSecret = "6t7EcrBOJnP7eT5FsDlU6yHq-pA"
        
        let str = "invalidate=true&public_id=\(public_id)&timestamp=\(timestamp)\(apiSecret)"
        
        print("str: \(str)")
        
        let signature = str.sha1()
        
        print("signature: \(signature)")
        
        let data = "invalidate=true&public_id=\(public_id)&timestamp=\(timestamp)&api_key=\(apiKey)&signature=\(signature)"
        
        print("data: \(data)")
        
        urlRequest.httpBody = data.data(using: String.Encoding.utf8)
        
        let task = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            
            guard let data = data else { return }

            do {
                if let convertedJsonIntoDict = try JSONSerialization.jsonObject(with: data, options: []) as? NSDictionary {
                    // Print out dictionary
                    print(convertedJsonIntoDict)
               }
            } catch let error as NSError {
                print(error.localizedDescription)
            }
            

        }
        task.resume()

        
    }

}
