//
//  ImageServer.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/9/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation

import XMPPFramework
import Alamofire

import CommonCrypto

extension String {
    func sha1() -> String {
        let data = Data(self.utf8)
        var digest = [UInt8](repeating: 0, count:Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
        }
        let hexBytes = digest.map { String(format: "%02hhx", $0) }
        return hexBytes.joined()
    }
}

class ImageServer {

    func uploadMultiple(media: [FeedMedia]) {
        
        let pendingCore = PendingCore()
        
        for med in media {
            
            upload(med: med)
   
            DispatchQueue.global(qos: .background).async {
                pendingCore.create(item: med)
            }
        }
        
    }
    
    func upload(med: FeedMedia) {
            
        let uploadUrl = med.url
        
        /* note: compression below a certain point (0.2?) is the same */
        if let imgData = med.image.jpegData(compressionQuality: 0.1) {

            let headers = [
                "Content-Type": "image/jpeg"
            ]

            Alamofire.upload(imgData, to: uploadUrl, method: .put, headers: headers)
                .uploadProgress(closure: { (progress) in
//                    print(progress.fractionCompleted)
                })
                .responseData { response in

                    if (response.response != nil) {
                        print("success uploading")
          
                        DispatchQueue.global(qos: .background).async {
                            PendingCore().delete(url: uploadUrl)
                        }

                    }

                }

        }
          
    }
    
    
    func processPending() {
        var pending: [FeedMedia] = []
        
        pending = PendingCore().getAll()
        
        print("process pending: \(pending.count)")
        
        uploadMultiple(media: pending)
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
           ImageServer().deleteImageFromCloudinary(item: imageToDelete)
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
