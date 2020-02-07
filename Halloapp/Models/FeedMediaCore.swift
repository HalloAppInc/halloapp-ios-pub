//
//  FeedMediaCore.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/30/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import SwiftUI
import Combine
import CoreData

extension UIImage {

  func getThumbnail() -> UIImage? {

    guard let imageData = self.pngData() else { return nil }
    
    var resolution: Int = 1080
    
    if UIScreen.main.bounds.width <= 375 {
        resolution = 800
    }
    
//    print("orig: \(imageData.count/1000)")

    let options = [
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: resolution] as CFDictionary

    guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
    guard let imageReference = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }

//    let temp = UIImage(cgImage: imageReference)
//    let temp2 = temp.pngData()
//    print("thumb: \(temp2!.count/1000)")
//    print("percent: \(Float(temp2!.count) / Float(imageData.count))")
    
    return UIImage(cgImage: imageReference)

  }
}

class FeedMediaCore {

    func getAll() -> [FeedMedia] {
        
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "CFeedImage")
        
        fetchRequest.sortDescriptors = [NSSortDescriptor.init(key: "order", ascending: false)]
        
        do {
            let result = try managedContext.fetch(fetchRequest)
            
            var arr: [FeedMedia] = []
            
            for data in result as! [NSManagedObject] {
                let item = FeedMedia(
                    
                    feedItemId: data.value(forKey: "feedItemId") as! String,
                    order: data.value(forKey: "order") as! Int,

                    type: "image",
                    url: data.value(forKey: "url") as! String,
                    width: data.value(forKey: "width") as! Int,
                    height: data.value(forKey: "height") as! Int
                )
                
                if let blob = data.value(forKey: "smallBlob") as? Data {
                    if let image = UIImage(data: blob) {
                        item.image = image
                    }
                }
                
                arr.append(item)

            }
            
//            self.feedMedia.append(contentsOf: arr)
            return arr
            
        } catch  {
            print("failed")
            return []
        }
    }

    func get(feedItemId: String) -> [FeedMedia] {
        
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "CFeedImage")
        
        let p1 = NSPredicate(format: "feedItemId = %@", feedItemId)
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [p1])
        
        fetchRequest.sortDescriptors = [NSSortDescriptor.init(key: "order", ascending: false)]
        
        do {
            let result = try managedContext.fetch(fetchRequest)
            
            var arr: [FeedMedia] = []
            
            for data in result as! [NSManagedObject] {
                let item = FeedMedia(
                    
                    feedItemId: data.value(forKey: "feedItemId") as! String,
                    order: data.value(forKey: "order") as! Int,

                    type: "image",
                    url: data.value(forKey: "url") as! String,
                    width: data.value(forKey: "width") as! Int,
                    height: data.value(forKey: "height") as! Int
                )
                
//                if let blob = data.value(forKey: "smallBlob") as? Data {
//                    if let image = UIImage(data: blob) {
//
//                        if let thumb = image.getThumbnail() {
//                            item.image = thumb
//                        } else {
//                            item.image = image
//                        }
//
//                    }
//                }
                
                if let blob = data.value(forKey: "smallBlob") as? Data {
                    if let image = UIImage(data: blob) {
                        item.image = image
                    }
                }

                arr.append(item)

            }
            
//            self.feedMedia.append(contentsOf: arr)
            return arr
            
        } catch  {
            print("failed")
            return []
        }
    }
    
    func create(item: FeedMedia) {
        
        let managedContext = CoreDataManager.sharedManager.bgContext
        
        managedContext.perform {
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "CFeedImage")

            fetchRequest.predicate = NSPredicate(format: "feedItemId == %@ AND url == %@", item.feedItemId, item.url)
            
            do {
                
                let result = try managedContext.fetch(fetchRequest)
                
                if result.count > 0 {
                    return
                }
            
                let userEntity = NSEntityDescription.entity(forEntityName: "CFeedImage", in: managedContext)!
                
                let obj = NSManagedObject(entity: userEntity, insertInto: managedContext)
                obj.setValue(item.feedItemId, forKeyPath: "feedItemId")
                obj.setValue(item.order, forKeyPath: "order")
                obj.setValue(item.url, forKeyPath: "url")
                obj.setValue(item.width, forKeyPath: "width")
                obj.setValue(item.height, forKeyPath: "height")
                
                do {
                    try managedContext.save()
                } catch let error as NSError {
                    print("could not save. \(error), \(error.userInfo)")
                }
                
            } catch  {
                print("failed")
            }
        }
        
    }
        
    func updateImage(feedItemId: String, url: String, thumb: UIImage, orig: UIImage) {
        
        let managedContext = CoreDataManager.sharedManager.bgContext
        
        managedContext.perform {
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "CFeedImage")

            fetchRequest.predicate = NSPredicate(format: "feedItemId == %@ AND url == %@", feedItemId, url)
            
            do {
                let result = try managedContext.fetch(fetchRequest)
                
                if result.count == 0 {
                    return
                }
                
                let obj = result[0] as! NSManagedObject
                
                let thumbData = thumb.jpegData(compressionQuality: 1.0)
                let origData = orig.jpegData(compressionQuality: 1.0)
                
                if thumbData != nil {
                    obj.setValue(thumbData, forKeyPath: "smallBlob")
                   
                }
                
                if origData != nil {
                    obj.setValue(origData, forKeyPath: "blob")
                }
                
                do {
                    try managedContext.save()
                } catch {
                    print(error)
                }
                
            } catch  {
                print("failed")
            }
        }
        
    }
    
}


