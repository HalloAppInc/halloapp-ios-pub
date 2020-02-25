//
//  FeedMediaCore.swift
//  Halloapp
//
//  Created by Tony Jiang on 1/30/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI
import CoreData

extension UIImage {

    func save(at directory: FileManager.SearchPathDirectory,
              pathAndImageName: String,
              createSubdirectoriesIfNeed: Bool = true,
              compressionQuality: CGFloat = 1.0)  -> URL? {
        do {
        let documentsDirectory = try FileManager.default.url(for: directory, in: .userDomainMask,
                                                             appropriateFor: nil,
                                                             create: false)
        return save(at: documentsDirectory.appendingPathComponent(pathAndImageName),
                    createSubdirectoriesIfNeed: createSubdirectoriesIfNeed,
                    compressionQuality: compressionQuality)
        } catch {
            print("-- Error: \(error)")
            return nil
        }
    }

    func save(at url: URL,
              createSubdirectoriesIfNeed: Bool = true,
              compressionQuality: CGFloat = 1.0)  -> URL? {
        do {
            if createSubdirectoriesIfNeed {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true,
                                                        attributes: nil)
            }
            guard let data = jpegData(compressionQuality: compressionQuality) else { return nil }
            try data.write(to: url)
            return url
        } catch {
            print("-- Error: \(error)")
            return nil
        }
    }
}

// load from path

extension UIImage {
    convenience init?(fileURLWithPath url: URL, scale: CGFloat = 1.0) {
        do {
            let data = try Data(contentsOf: url)
            self.init(data: data, scale: scale)
        } catch {
            print("-- Error: \(error)")
            return nil
        }
    }
}
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

                    type: "image",
                    url: data.value(forKey: "url") as! String,
                    width: data.value(forKey: "width") as! Int,
                    height: data.value(forKey: "height") as! Int,
                    numTries: data.value(forKey: "numTries") as! Int
                )
                
                if let blob = data.value(forKey: "smallBlob") as? Data {
                    
                    let path = "tempImg.jpg"
                    let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(path)
                    
                    do {
                        
                        try FileManager.default.createDirectory(at: tempUrl.deletingLastPathComponent(),
                                                             withIntermediateDirectories: true,
                                                             attributes: nil)


                        try blob.write(to: tempUrl)
                        print("wrote to file")
                        
                     } catch {
                         print("-- Error: \(error)")
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
            print("failed")
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

                    type: "image",
                    url: data.value(forKey: "url") as! String,
                    width: data.value(forKey: "width") as! Int,
                    height: data.value(forKey: "height") as! Int,
                    numTries: data.value(forKey: "numTries") as! Int
                    
                )
                                

                arr.append(item)
                
            }
            
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
        
        fetchRequest.sortDescriptors = [NSSortDescriptor.init(key: "order", ascending: true)]
        
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
                    height: data.value(forKey: "height") as! Int,
                    numTries: data.value(forKey: "numTries") as! Int
                    
                )

                
                if let blob = data.value(forKey: "smallBlob") as? Data {
    
//
//                    let path = "\(UUID().uuidString).jpg"
//                    let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(path)
//
//                    do {
//
//                        try FileManager.default.createDirectory(at: tempUrl.deletingLastPathComponent(),
//                                                             withIntermediateDirectories: true,
//                                                             attributes: nil)
//
//
//                        try blob.write(to: tempUrl)
//                        print("wrote to file")
//
//                     } catch {
//                         print("-- Error: \(error)")
//                     }
//
//                    if let img2 = UIImage(contentsOfFile: tempUrl.path) {
//                        item.image = img2
//                    }
//
//                    do {
//                        try FileManager.default.removeItem(at: tempUrl)
//                    } catch let error as NSError {
//                        print("Error: \(error.domain)")
//                    }
                    
                    
                    if let image = UIImage(data: blob) {
                        item.image = image
                    }
                    
                }

                
                arr.append(item)
                

            }
            
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
                obj.setValue(item.numTries, forKeyPath: "numTries")
                
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
                } else {
                    print("Update Media Blob is nil")
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
                    print(error)
                }
                
            } catch  {
                print("failed")
            }
        }
        
    }
    
}


