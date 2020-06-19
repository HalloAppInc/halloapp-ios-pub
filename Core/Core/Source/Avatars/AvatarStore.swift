//
//  AvatarStore.swift
//  Core
//
//  Created by Alan Luo on 6/9/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjack
import CoreData
import UIKit

public typealias AvatarID = String

public class AvatarStore {
    public static let avatarSize = 256
    public static let shared = AvatarStore()
    
    private class var persistentStoreURL: URL {
        get {
            return AppContext.sharedDirectoryURL.appendingPathComponent("avatars.sqlite")
        }
    }
    
    private class var avatarFileURL: URL {
        get {
            return AppContext.sharedDirectoryURL.appendingPathComponent("Avatars")
        }
    }
    
    let persistentContainer: NSPersistentContainer = {
        let storeDescription = NSPersistentStoreDescription(url: persistentStoreURL)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSMigratePersistentStoresAutomaticallyOption)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSInferMappingModelAutomaticallyOption)
        storeDescription.setValue(NSString("WAL"), forPragmaNamed: "journal_mode")
        storeDescription.setValue(NSString("1"), forPragmaNamed: "secure_delete")
        let modelURL = Bundle(for: Avatar.self).url(forResource: "Avatars", withExtension: "momd")!
        let managedObjectModel = NSManagedObjectModel(contentsOf: modelURL)
        let container = NSPersistentContainer(name: "Halloapp", managedObjectModel: managedObjectModel!)
        container.persistentStoreDescriptions = [ storeDescription ]
        container.loadPersistentStores(completionHandler: { (description, error) in
            if let error = error {
                fatalError("Unable to load persistent stores: \(error)")
            }
        })
        return container
    }()
    
    private func avatar(forUserId userId: UserID) -> Avatar? {
        let managedObjectContext = self.persistentContainer.viewContext
        
        return avatar(forUserId: userId, using: managedObjectContext)
    }
    
    private func avatar(forUserId userId: UserID, using managedObjectContext: NSManagedObjectContext) -> Avatar? {
        let fetchRequest: NSFetchRequest<Avatar> = Avatar.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userId == %@", userId)
        
        do {
            let results = try managedObjectContext.fetch(fetchRequest)
            return results.first
        } catch  {
            DDLogError("AvatarStore/fetch/error [\(error)]")
            
            return nil
        }
    }
    
    func userAvatar(forUserId userId: UserID) -> UserAvatar? {
        if let currentAvatar = avatar(forUserId: userId) {
            return UserAvatar(avatarId: currentAvatar.avatarId!, filePath: currentAvatar.relativeFilePath!)
        }
        
        return nil
    }
    
    public func save(image: UIImage, forUserId userId: UserID, avatarId: AvatarID) {
        let managedObjectContext = self.persistentContainer.viewContext
        
        var currentAvatar = avatar(forUserId: userId, using: managedObjectContext)
        
        if currentAvatar == nil {
            currentAvatar = NSEntityDescription.insertNewObject(forEntityName: Avatar.entity().name!, into: managedObjectContext) as? Avatar
            
            currentAvatar!.userId = userId
        }
        
        let data = image.jpegData(compressionQuality: CGFloat(AppContext.shared.userData.compressionQuality))!
        
        // TODO: Remove old file?
        
        let fileURL = AvatarStore.avatarFileURL.appendingPathComponent("\(avatarId).jpeg", isDirectory: false)
        
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            try data.write(to: fileURL)
        } catch {
            DDLogError("AvatarStore/save/failed [\(error)]")
            
            return
        }
        
        currentAvatar!.avatarId = avatarId
        currentAvatar!.relativeFilePath = fileURL.path
        
        DDLogInfo("AvatarStore/save avatar for user \(userId) has been saved to \(currentAvatar!.relativeFilePath!)")
        
        do {
            try managedObjectContext.save()
        } catch let error as NSError {
            DDLogError("AvatarStore/save/error [\(error)]")
        }
    }
    
    public func update(avatarId: AvatarID, forUserId userId: UserID) {
        let managedObjectContext = self.persistentContainer.viewContext
        
        guard let currentAvatar = avatar(forUserId: userId, using: managedObjectContext) else {
            DDLogError("AvatarStore/updateAvatarId/error avatar does not exist!")
            return
        }
        
        currentAvatar.avatarId = avatarId
        
        DDLogInfo("AvatarStore/updateAvatarId avatarId for user \(userId) has been changed to \(avatarId)")
        
        do {
            try managedObjectContext.save()
        } catch let error as NSError {
            DDLogError("AvatarStore/updateAvatarId/error [\(error)]")
        }
    }
}

public class UserAvatar {
    private let avatarId: AvatarID
    private let fileUrl: URL
    public var image: UIImage?
    public var data: Data?
    
    private static let avatarLoadingQueue = DispatchQueue(label: "com.halloapp.avatar-loading", qos: .userInitiated)
    
    init(avatarId: AvatarID, filePath: String) {
        self.avatarId = avatarId
        self.fileUrl = URL(fileURLWithPath: filePath)
        
        loadImage()
    }
    
    private func loadImage() {
        UserAvatar.avatarLoadingQueue.async {
            do {
                self.data = try Data(contentsOf: self.fileUrl)
            } catch {
                DDLogError("UserAvatar/reload failed to read data \(error)")
                return
            }
            
            DispatchQueue.main.async {
                if let image = UIImage(data: self.data!) {
                    self.image = image
                } else {
                    DDLogError("UserAvatar/reload failed to deserialized data into UIIamge")
                    self.data = nil
                }
            }
        }
    }
}
