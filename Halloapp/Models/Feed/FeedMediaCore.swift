//
//  FeedMediaCore.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/30/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import CoreData
import SwiftUI

class FeedMediaCore {

    func getAll() -> [FeedMedia] {
        
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "CFeedImage")
        fetchRequest.sortDescriptors = [NSSortDescriptor.init(key: "order", ascending: true)]
        
        do {
            let result = try managedContext.fetch(fetchRequest)
            var arr: [FeedMedia] = []
            
            for data in result as! [NSManagedObject] {
                let item = FeedMedia(
                    feedItemId: data.value(forKey: "feedItemId") as! String,
                    order: data.value(forKey: "order") as! Int,
                    type: data.value(forKey: "type") as! String,
                    url: data.value(forKey: "url") as! String,
                    width: data.value(forKey: "width") as! Int,
                    height: data.value(forKey: "height") as! Int,
                    key: data.value(forKey: "key") as! String,
                    sha256hash: data.value(forKey: "sha256hash") as! String,
                    numTries: data.value(forKey: "numTries") as! Int
                )
                
                if let blob = data.value(forKey: "blob") as? Data {
                    let path = "tempImg.jpg"
                    let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(path)
                    do {
                        try FileManager.default.createDirectory(at: tempUrl.deletingLastPathComponent(),
                                                             withIntermediateDirectories: true,
                                                             attributes: nil)
                        try blob.write(to: tempUrl)

                        DDLogInfo("wrote to file")
                        
                     } catch {
                         DDLogError("-- Error: \(error)")
                     }
//                    if let img2 = UIImage(contentsOfFile: tempUrl.path) {
//                        item.image = img2
//
//                    }
                    if let image = UIImage(data: blob) {
                        item.image = image
                    }
                }
                arr.append(item)
            }
//            self.feedMedia.append(contentsOf: arr)
            return arr
        } catch  {
            DDLogError("failed")
            return []
        }
    }

    func getInfo(feedItemId: String) -> [FeedMedia] {
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "CFeedImage")
        let p1 = NSPredicate(format: "feedItemId = %@", feedItemId)
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [p1])
        fetchRequest.sortDescriptors = [NSSortDescriptor.init(key: "order", ascending: true)]
        
        do {
            let result = try managedContext.fetch(fetchRequest)
            var arr: [FeedMedia] = []
            for data in result as! [NSManagedObject] {
                let item = FeedMedia(
                    feedItemId: data.value(forKey: "feedItemId") as! String,
                    order: data.value(forKey: "order") as! Int,
                    type: data.value(forKey: "type") as! String,
                    url: data.value(forKey: "url") as! String,
                    width: data.value(forKey: "width") as! Int,
                    height: data.value(forKey: "height") as! Int,
                    numTries: data.value(forKey: "numTries") as! Int
                )
                arr.append(item)
            }
            return arr
        } catch  {
            DDLogError("failed")
            return []
        }
    }
    
    func get(feedItemId: String) -> [FeedMedia] {
        
        let managedContext = CoreDataManager.sharedManager.persistentContainer.viewContext
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "CFeedImage")
        
        let p1 = NSPredicate(format: "feedItemId = %@", feedItemId)
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [p1])
        
        fetchRequest.sortDescriptors = [NSSortDescriptor.init(key: "order", ascending: true)]
        
        do {
            let result = try managedContext.fetch(fetchRequest)
            var arr: [FeedMedia] = []
            for data in result as! [NSManagedObject] {
                let item = FeedMedia(
                    feedItemId: data.value(forKey: "feedItemId") as! String,
                    order: data.value(forKey: "order") as! Int,
                    type: data.value(forKey: "type") as! String,
                    url: data.value(forKey: "url") as! String,
                    width: data.value(forKey: "width") as! Int,
                    height: data.value(forKey: "height") as! Int,
                    key: data.value(forKey: "key") as! String,
                    sha256hash: data.value(forKey: "sha256hash") as! String,
                    numTries: data.value(forKey: "numTries") as! Int
                )
                
                if let blob = data.value(forKey: "blob") as? Data {
//                    let path = "\(UUID().uuidString).jpg"
//                    let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(path)
//                    do {
//                        try FileManager.default.createDirectory(at: tempUrl.deletingLastPathComponent(),
//                                                             withIntermediateDirectories: true,
//                                                             attributes: nil)
//                        try blob.write(to: tempUrl)
//                        print("wrote to file")
//                     } catch {
//                         print("-- Error: \(error)")
//                     }
//                    if let img2 = UIImage(contentsOfFile: tempUrl.path) {
//                        item.image = img2
//                    }
//                    do {
//                        try FileManager.default.removeItem(at: tempUrl)
//                    } catch let error as NSError {
//                        print("Error: \(error.domain)")
//                    }
                    
                    if item.type == "image" || item.type == "" {
                        if let image = UIImage(data: blob) {
                            item.image = image
                        }
                    } else if item.type == "video" {
                        
                        let fileName = "\(item.feedItemId)-\(item.order)"
                        let fileUrl = URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent(fileName).appendingPathExtension("mp4")
                            
                        if (!FileManager.default.fileExists(atPath: fileUrl.path))   {
                            print("file does not exists")
                            
                            let wasFileWritten = (try? blob.write(to: fileUrl, options: [.atomic])) != nil

                            if !wasFileWritten{
                                print("File was NOT Written")
                            } else {
                                print("File was written")
                            }
                            
                        } else {
                            print("file exists")
                        }
                        
                        item.tempUrl = fileUrl
        
                    }
                    
                }

                
                arr.append(item)
                

            }
            
            return arr
            
        } catch  {
            DDLogError("failed")
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
                obj.setValue(item.type, forKeyPath: "type")
                obj.setValue(item.order, forKeyPath: "order")
                obj.setValue(item.url, forKeyPath: "url")
                obj.setValue(item.width, forKeyPath: "width")
                obj.setValue(item.height, forKeyPath: "height")
                obj.setValue(item.key, forKeyPath: "key")
                obj.setValue(item.sha256hash, forKeyPath: "sha256hash")
                obj.setValue(item.numTries, forKeyPath: "numTries")
                
                do {
                    try managedContext.save()
                } catch let error as NSError {
                    DDLogError("could not save. \(error), \(error.userInfo)")
                }
                
            } catch  {
                DDLogError("failed")
            }
        }
        
    }
        
    func updateBlob(feedItemId: String, url: String, data: Data) {
                
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
    
                obj.setValue(data, forKeyPath: "blob")
                
                do {
                    try managedContext.save()
                } catch {
                    print(error)
                }
                
            } catch  {
                print("failed at updateBlob")
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
                } else {
                    DDLogWarn("Update Media Blob is nil")
                }
                
                do {
                    try managedContext.save()
                } catch {
                    DDLogError("\(error)")
                }
                
            } catch  {
                DDLogError("failed")
            }
        }
        
    }
    
    func updateNumTries(feedItemId: String, url: String, numTries: Int) {
                
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
                
                obj.setValue(numTries, forKeyPath: "numTries")
                
                do {
                    try managedContext.save()
                } catch {
                    DDLogError("\(error)")
                }
                
            } catch  {
                DDLogError("failed")
            }
        }
        
    }
    
    func delete(feedItemId: String, url: String) {
        
        let managedContext = CoreDataManager.sharedManager.bgContext

        managedContext.perform {
            
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "CFeedImage")
            
            fetchRequest.predicate = NSPredicate(format: "feedItemId == %@ AND url == %@", feedItemId, url)
            
            do {
                let result = try managedContext.fetch(fetchRequest)

                if (result.count == 0) {
                    return
                }
                
                let objectToDelete = result[0] as! NSManagedObject
                managedContext.delete(objectToDelete)
                
                do {
                    try managedContext.save()
                } catch {
                    DDLogError("\(error)")
                }
                
            } catch  {
                DDLogError("failed")
            }
        }
    }

}


