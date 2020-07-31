//
//  AvatarStore.swift
//  Core
//
//  Created by Alan Luo on 6/9/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Alamofire
import CocoaLumberjack
import Combine
import CoreData
import UIKit
import XMPPFramework


public typealias AvatarID = String

public class AvatarStore: XMPPControllerAvatarDelegate {
    public static let avatarSize = 256
    public static let avatarCDNUrl = "https://avatar-cdn.halloapp.net/"
    
    public struct Keys {
        public static let userDefaultsUpload = "xmpp.avatar-sent"
        public static let userDefaultsDownload = "xmpp.avatar-query"
    }
    
    // Please notice that when app moves to the background, `userAvatars` may be evicted.
    private let userAvatars = NSCache<NSString, UserAvatar>()
    
    private class var persistentStoreURL: URL {
        get {
            return AppContext.sharedDirectoryURL.appendingPathComponent("avatars.sqlite")
        }
    }
    
    fileprivate class var avatarDirectoryURL: URL {
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
    
    public init() {}
    
    private func performOnBackgroundContextAndWait(_ block: (NSManagedObjectContext) -> Void) {
        let managedObjectContext = self.persistentContainer.newBackgroundContext()
        managedObjectContext.performAndWait {
            block(managedObjectContext)
        }
    }
    
    fileprivate static func fileURL(forRelativeFilePath relativePath: String) -> URL {
        return AvatarStore.avatarDirectoryURL.appendingPathComponent(relativePath)
    }
    
    private func avatar(forUserId userId: UserID) -> Avatar? {
        let managedObjectContext = self.persistentContainer.viewContext
        
        return avatar(forUserId: userId, using: managedObjectContext)
    }
    
    private func avatar(forUserId userId: UserID, using managedObjectContext: NSManagedObjectContext) -> Avatar? {
        let fetchRequest: NSFetchRequest<Avatar> = Avatar.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userId == %@", userId)
        
        do {
            let results = try managedObjectContext.fetch(fetchRequest)
            
            if let avatar = results.first {
                // Temporary fix for the old avatar path. Please see comments below.
                changeRelativeFilePathIfNecessary(for: avatar, using: managedObjectContext)
            
                return avatar
            } else {
                return nil
            }
        } catch  {
            DDLogError("AvatarStore/fetch/error [\(error)]")
            
            return nil
        }
    }
    
    public func userAvatar(forUserId userId: UserID) -> UserAvatar {
        if let userAvatar = userAvatars.object(forKey: userId as NSString) {
            return userAvatar
        }
        
        var userAvatar: UserAvatar?
        
        if let currentAvatar = avatar(forUserId: userId) {
            userAvatar = UserAvatar(currentAvatar)
        } else {
            userAvatar = UserAvatar(userId: userId)
        }
        
        userAvatars.setObject(userAvatar!, forKey: userId as NSString)
        
        return userAvatar!
    }
    
    public func save(avatarId: AvatarID, forUserId userId: UserID) {
        let managedObjectContext = self.persistentContainer.viewContext
        
        self.save(avatarId: avatarId, forUserId: userId, using: managedObjectContext)
    }
    
    @discardableResult private func save(avatarId: AvatarID, forUserId userId: UserID, using managedObjectContext: NSManagedObjectContext, isContactSync: Bool = false) -> Avatar {
        var currentAvatar = avatar(forUserId: userId, using: managedObjectContext)
        
        if currentAvatar == nil {
            currentAvatar = NSEntityDescription.insertNewObject(forEntityName: Avatar.entity().name!, into: managedObjectContext) as? Avatar
            
            currentAvatar!.userId = userId
        } else {
            guard currentAvatar!.avatarId != avatarId else {
                // For ContactSync, most avatarIds remain the same
                if !isContactSync {
                    DDLogError("AvatarStore/save/error avatar \(avatarId) for user \(userId) is same")
                }
                return currentAvatar!
            }
            
            if let relativeFilePath = currentAvatar!.relativeFilePath {
                let filePath = AvatarStore.fileURL(forRelativeFilePath: relativeFilePath)
                
                if FileManager.default.fileExists(atPath: filePath.path) {
                    do {
                        try FileManager.default.removeItem(at: filePath)
                    } catch let error as NSError {
                        DDLogError("AvatarStore/save/failed to remove old file [\(error)]")
                    }
                }
                
                currentAvatar!.relativeFilePath = nil
            }
        }
        
        currentAvatar!.avatarId = avatarId
        
        do {
            try managedObjectContext.save()
        } catch let error as NSError {
            DDLogError("AvatarStore/save/error [\(error)]")
        }
        
        DDLogInfo("AvatarStore/save avatarId \(avatarId) for userId \(userId) has been saved")
        
        if let userAvatar = userAvatars.object(forKey: userId as NSString) {
            userAvatar.image = nil
            userAvatar.data = nil
            userAvatar.fileUrl = nil
            
            userAvatar.avatarId = avatarId
            
            if avatarId != "self" && avatarId != "" {
                userAvatar.loadImage(using: self)
            }
        }
        
        return currentAvatar!
    }
    
    public func save(image: UIImage, forUserId userId: UserID, avatarId: AvatarID) {
        let managedObjectContext = self.persistentContainer.viewContext
        
        let currentAvatar = save(avatarId: avatarId, forUserId: userId, using: managedObjectContext)
        
        let data = image.jpegData(compressionQuality: CGFloat(UserData.compressionQuality))!
        
        let fileURL = AvatarStore.fileURL(forRelativeFilePath: "\(avatarId).jpeg")
        
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            try data.write(to: fileURL)
        } catch {
            DDLogError("AvatarStore/save/failed [\(error)]")
            
            return
        }
        
        currentAvatar.relativeFilePath = "\(avatarId).jpeg"
        
        do {
            try managedObjectContext.save()
        } catch let error as NSError {
            DDLogError("AvatarStore/save/error [\(error)]")
        }
        
        DDLogInfo("AvatarStore/save avatar for user \(userId) has been saved to \(currentAvatar.relativeFilePath!)")
        
        if let userAvatar = userAvatars.object(forKey: userId as NSString) {
            userAvatar.image = image
            userAvatar.data = data
        }
    }
    
    /*
     The following two `update` methods should only be used to update database.
     They will not change the actual avatar file on disk.
     Please use `save` methods above to change the actual avatar file.
     */
    
    public func update(avatarId: AvatarID, forUserId userId: UserID) {
        let managedObjectContext = self.persistentContainer.viewContext
        
        guard let currentAvatar = avatar(forUserId: userId, using: managedObjectContext) else {
            DDLogError("AvatarStore/updateAvatarId/error avatar does not exist!")
            return
        }
        
        currentAvatar.avatarId = avatarId
        
        do {
            try managedObjectContext.save()
        } catch let error as NSError {
            DDLogError("AvatarStore/updateAvatarId/error [\(error)]")
        }
        
        DDLogInfo("AvatarStore/updateAvatarId avatarId for user \(userId) has been changed to \(avatarId)")
    }
    
    fileprivate func update(relativeFilePath: String, forUserId userId: UserID) {
        let managedObjectContext = self.persistentContainer.viewContext
        
        guard let currentAvatar = avatar(forUserId: userId, using: managedObjectContext) else {
            DDLogError("AvatarStore/updateAvatarId/error avatar does not exist!")
            return
        }
        
        currentAvatar.relativeFilePath = relativeFilePath
        
        do {
            try managedObjectContext.save()
        } catch let error as NSError {
            DDLogError("AvatarStore/updateAvatarId/error [\(error)]")
        }
        
        DDLogInfo("AvatarStore/updateAvatarId relativeFilePath for user \(userId) has been changed to \(relativeFilePath)")
    }
    
    public func xmppController(_ xmppController: XMPPController, didReceiveAvatar item: XMLElement) {
        DDLogInfo("AvatarStore/didReceiveAvatar \(item)")
        
        guard let userId = item.attributeStringValue(forName: "userid"), let avatarId = item.attributeStringValue(forName: "id") else {
            DDLogError("AvatarStore/didReceiveAvatar/error userId or avatarId is nil")
            return
        }
        
        let managedObjectContext = self.persistentContainer.viewContext
        
        save(avatarId: avatarId, forUserId: userId, using: managedObjectContext)
    }
    
    public func processContactSync(_ avatarDict: [UserID: AvatarID]) {
        performOnBackgroundContextAndWait { (managedObjectContext) in
            for (userId, avatarId) in avatarDict {
                save(avatarId: avatarId, forUserId: userId, using: managedObjectContext, isContactSync: true)
            }
        }
    }
    
    /*
     Temporary fix for the old avatar path. Will remove in the future.
     I accidentally saved the absolute path instead of the relative path for the old avatar.
     This temporary fix will change the path.
     */
    private func changeRelativeFilePathIfNecessary(for avatar: Avatar, using managedObjectContext: NSManagedObjectContext) {
        if let relativeFilePath = avatar.relativeFilePath {
            guard relativeFilePath.contains("Avatars") else { return }
            
            if let realRelativeFilePath = relativeFilePath.components(separatedBy: "/").last {
                avatar.relativeFilePath = realRelativeFilePath
                
                do {
                    try managedObjectContext.save()
                    DDLogInfo("AvatarStore/changeRelativeFilePathIfNecessary changed from \(relativeFilePath) to \(realRelativeFilePath)")
                } catch let error as NSError {
                    DDLogError("AvatarStore/changeRelativeFilePathIfNecessary/error [\(error)]")
                }
            }
            
        }
    }
}

public class UserAvatar {
    public var data: Data?
    public var image: UIImage? {
        didSet {
            DispatchQueue.main.async {
                self.imageDidChange.send(self.image)
            }
        }
    }
    public var isEmpty = true
    
    fileprivate var avatarId: AvatarID? {
        didSet {
            if avatarId != nil && !avatarId!.isEmpty {
                isEmpty = false
            } else {
                isEmpty = true
            }
        }
    }
    fileprivate var fileUrl: URL?
    
    private let userId: UserID
    private var imageIsLoading = false
    
    public let imageDidChange = PassthroughSubject<UIImage?, Never>()
    
    private static let avatarLoadingQueue = DispatchQueue(label: "com.halloapp.avatar-loading", qos: .userInitiated)
    
    init(_ avatar: Avatar) {
        avatarId = avatar.avatarId
        userId = avatar.userId
        
        if avatarId != nil && !avatarId!.isEmpty {
            isEmpty = false
        } else {
            isEmpty = true
        }
        
        if let relativeFilePath = avatar.relativeFilePath {
            fileUrl = AvatarStore.fileURL(forRelativeFilePath: relativeFilePath)
        } else {
            fileUrl = nil
        }
        
        DDLogInfo("UserAvatar/init for user=\(userId)")
    }
    
    // Create a dummy object for a user that's not in the database
    init(userId: UserID) {
        self.userId = userId
        
        DDLogInfo("UserAvatar/init a dummy object for user=\(userId) has been created")
    }
    
    public func loadImage(using avatarStore: AvatarStore) {
        guard image == nil && !imageIsLoading && !isEmpty else {
            return
        }
        
        imageIsLoading = true
        
        DDLogInfo("UserAvatar/loadImage for user=\(userId), avatar=\(avatarId ?? ""), fileUrl=\(String(describing: fileUrl))")
        if let fileUrl = self.fileUrl { // avatar has been downloaded
            UserAvatar.avatarLoadingQueue.async {
                do {
                    self.data = try Data(contentsOf: fileUrl)
                } catch {
                    DDLogError("UserAvatar/reload failed to read data \(error)")
                    return
                }
                
                if let image = UIImage(data: self.data!) {
                    DispatchQueue.main.async {
                        self.image = image
                        DDLogInfo("UserAvatar/loadImage avatar for user \(self.userId) has been loaded from disk")
                    }
                } else {
                    DDLogError("UserAvatar/reload failed to deserialized data into UIImage")
                    self.data = nil
                }
                
                self.imageIsLoading = false
            }
        } else { // avatar has not been downloaded yet
            guard let url = URL(string: AvatarStore.avatarCDNUrl + avatarId!) else {
                DDLogError("UserAvatar/loadImage/error \(AvatarStore.avatarCDNUrl + avatarId!) cannot be formed as a URL")
                self.imageIsLoading = false
                return
            }
            
            let fileName = "\(avatarId!).jpeg"
            let fileUrl = AvatarStore.fileURL(forRelativeFilePath: fileName)
            let destination: DownloadRequest.Destination = { _, _ in
                return (fileUrl, [.removePreviousFile, .createIntermediateDirectories])
            }
            
            AF.download(url, to: destination).responseData(queue: UserAvatar.avatarLoadingQueue) { (response) in
                if let error = response.error {
                    DDLogError("UserAvatar/loadImage/AFDownload/error \(error)")
                    self.imageIsLoading = false
                    return
                }
                
                guard let httpURLResponse = response.response else {
                    DDLogError("UserAvatar/loadImage/AFDownload/error can't get response")
                    self.imageIsLoading = false
                    return
                }
                
                guard httpURLResponse.statusCode == 200 else {
                    DDLogError("UserAvatar/loadImage/AFDownload/error unexpected response code \(httpURLResponse.statusCode)")
                    self.imageIsLoading = false
                    return
                }
                
                guard let image = UIImage(data: response.value!) else {
                    DDLogError("UserAvatar/loadImage/AFDownload/error failed to deserialized data into UIIamge")
                    self.imageIsLoading = false
                    return
                }
                
                avatarStore.update(relativeFilePath: fileName, forUserId: self.userId)
                
                DispatchQueue.main.async {
                    self.image = image
                    self.data = response.value!
                    DDLogInfo("UserAvatar/loadImage avatar for user \(self.userId) has been loaded from network")
                }
                
                self.imageIsLoading = false
            }
        }
    }
}
