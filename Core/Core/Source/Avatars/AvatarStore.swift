//
//  AvatarStore.swift
//  Core
//
//  Created by Alan Luo on 6/9/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Alamofire
import CoreCommon
import CocoaLumberjackSwift
import Combine
import Contacts
import CoreData
import UIKit

public struct AvatarData {
    public var thumbnail: Data
    public var full: Data?
}

public typealias AvatarID = String

public class AvatarStore: ServiceAvatarDelegate {
    public static let thumbnailSize = CGSize(width: 256, height: 256)
    public static let fullSize = CGSize(width: 1024, height: 1024)
    public static let avatarCDNUrl = "https://avatar-cdn.halloapp.net/"

    public struct Keys {
        public static let userDefaultsUpload = "xmpp.avatar-sent"
        public static let userDefaultsDownload = "xmpp.avatar-query"
    }

    private let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.avatars")
    
    // Please notice that when app moves to the background, `userAvatars` may be evicted.
    private let userAvatars = NSCache<NSString, UserAvatar>()
    private let groupAvatarsData = NSCache<NSString, GroupAvatarData>()
    private let addressBookAvatars = NSCache<NSString, AddressBookAvatar>()
    
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

    private var viewContext: NSManagedObjectContext
    private let fullSizeImageCache = NSCache<NSString, UIImage>()

    public init() {
        persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
        viewContext = persistentContainer.viewContext
    }

    private func newBackgroundContext() -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        return context
    }

    public func performSeriallyOnBackgroundContext(_ block: @escaping (NSManagedObjectContext) -> Void) {
        backgroundProcessingQueue.async { [weak self] in
            guard let self = self else { return }

            let context = self.newBackgroundContext()
            context.performAndWait {
                block(context)
            }
        }
    }

    public func performOnBackgroundContextAndWait(_ block: (NSManagedObjectContext) -> Void) {
        backgroundProcessingQueue.sync {
            let context = self.newBackgroundContext()
            context.performAndWait {
                block(context)
            }
        }
    }

    fileprivate static func pendingThumbnailFilename(for userID: UserID) -> String {
        return "\(userID).pending.thumb"
    }

    fileprivate static func pendingFullImageFilename(for userID: UserID) -> String {
        return "\(userID).pending.full"
    }
    
    fileprivate static func fileURL(forRelativeFilePath relativePath: String) -> URL {
        return AvatarStore.avatarDirectoryURL.appendingPathComponent(relativePath)
    }
    
    private func avatar(forUserId userId: UserID) -> Avatar? {
        return avatar(forUserId: userId, using: viewContext)
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
    
    public func userAvatar(forUserId userId: UserID) -> UserAvatar {
        if let userAvatar = userAvatars.object(forKey: userId as NSString) {
            return userAvatar
        }
        
        var userAvatar: UserAvatar
        
        if let currentAvatar = avatar(forUserId: userId) {
            userAvatar = UserAvatar(currentAvatar)
        } else {
            userAvatar = UserAvatar(userId: userId)
        }
        
        userAvatars.setObject(userAvatar, forKey: userId as NSString)
        
        return userAvatar
    }
    
    @discardableResult private func save(avatarId: AvatarID, forUserId userId: UserID, using managedObjectContext: NSManagedObjectContext) -> Avatar {
        let currentAvatar = insertAvatar(avatarId: avatarId, forUserId: userId, using: managedObjectContext)
        do {
            try managedObjectContext.save()
        } catch let error as NSError {
            DDLogError("AvatarStore/save/error [\(error)]")
        }
        
        DDLogInfo("AvatarStore/save avatarId \(avatarId) for userId \(userId) has been saved")
        
        if let userAvatar = userAvatars.object(forKey: userId as NSString) {
            DDLogInfo("updating userAvatar for userId: \(userId) - avatarId: \(avatarId)")
            userAvatar.image = nil
            userAvatar.fileURL = nil
            userAvatar.avatarId = avatarId
            userAvatar.loadThumbnailImage(using: self)
        }
        
        return currentAvatar
    }

    public func removeAvatar(for userID: UserID, using service: CoreService) {
        uploadAvatarData(nil, for: userID, using: service)

        // TODO: Indicate that this is still pending instead of optimistically updating
        let observedAvatar = userAvatar(forUserId: userID)
        observedAvatar.avatarId = nil
        observedAvatar.image = nil
    }

    public func uploadAvatar(image: UIImage, for userID: UserID, using service: CoreService) {
        performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            guard let self = self else { return }
            guard let thumbnailImage = image.fastResized(to: Self.thumbnailSize),
                  let thumbnailData = thumbnailImage.jpegData(compressionQuality: CGFloat(UserData.compressionQuality)) else
            {
                DDLogError("AvatarStore/uploadAvatar/thumb/error unable to get thumbnail data")
                return
            }

            let currentAvatar = self.insertAvatar(avatarId: "", forUserId: userID, using: managedObjectContext)
            let thumbnailFilename = AvatarStore.pendingThumbnailFilename(for: userID)

            do {
                try self.writeData(thumbnailData, toRelativePath: thumbnailFilename)
                DDLogInfo("AvatarStore/uploadAvatar/write-thumb/success [userID: \(userID)] [file: \(thumbnailFilename)]")
            } catch {
                DDLogError("AvatarStore/uploadAvatar/write-thumb/error [\(error)]")
                return
            }

            var avatarData = AvatarData(thumbnail: thumbnailData)

            if let fullImage = image.fastResized(to: Self.fullSize),
               let fullData = fullImage.jpegData(compressionQuality: CGFloat(UserData.compressionQuality))
            {
                do {
                    let fullImageFilename = AvatarStore.pendingFullImageFilename(for: userID)
                    try self.writeData(fullData, toRelativePath: fullImageFilename)
                    avatarData.full = fullData
                    DDLogInfo("AvatarStore/uploadAvatar/write-full/success [userID: \(userID)] [file: \(fullImageFilename)]")
                } catch {
                    DDLogError("AvatarStore/uploadAvatar/write-full/error [\(error)]")
                }
            }

            currentAvatar.relativeFilePath = thumbnailFilename

            do {
                try managedObjectContext.save()
            } catch let error as NSError {
                DDLogError("AvatarStore/uploadAvatar/save/error [\(error)]")
            }

            // TODO: Indicate that this is still pending instead of optimistically updating
            DDLogInfo("AvatarStore/uploadAvatar/update-observed-avatar [pending]")
            self.userAvatar(forUserId: userID).image = thumbnailImage

            self.uploadAvatarData(avatarData, for: userID, using: service)
        }
    }

    public func sendPendingAvatarIfNecessary(for userID: UserID, using service: CoreService) {
        guard let pendingUserID = UserDefaults.standard.string(forKey: AvatarStore.Keys.userDefaultsUpload), pendingUserID == userID else
        {
            DDLogInfo("AvatarStore/sendPendingAvatarIfNecessary/skipping [not necessary]")
            return
        }

        loadPendingAvatar(for: userID) { [weak self] avatarData in
            self?.uploadAvatarData(avatarData, for: userID, using: service)
        }
    }

    public func loadFullSizeImage(for avatar: UserAvatar, completion: @escaping (UIImage?) -> Void) {
        guard let avatarID = avatar.avatarId, let url = URL(string: AvatarStore.avatarCDNUrl + avatarID + "-full") else
        {
            DDLogInfo("AvatarStore/loadFull/\(avatar)/error [missing-avatar-id]")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        if let cachedImage = fullSizeImageCache.object(forKey: avatarID as NSString) {
            DDLogInfo("AvatarStore/loadFull/\(avatarID)/cached")
            DispatchQueue.main.async { completion(cachedImage) }
            return
        }

        let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
            guard let data = data, let image = UIImage(data: data) else {
                DDLogError("AvatarStore/loadFull/\(avatarID)/download/error [\(error.debugDescription)]")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DDLogInfo("AvatarStore/loadFull/\(avatarID)/download/success [caching]")
            self.fullSizeImageCache.setObject(image, forKey: avatarID as NSString)
            DispatchQueue.main.async { completion(image) }
        }
        task.resume()
    }

    private func uploadAvatarData(_ avatarData: AvatarData?, for userID: UserID, using service: CoreService) {
        // NB: We currently only support uploading avatar for one user ID at a time
        UserDefaults.standard.set(userID, forKey: AvatarStore.Keys.userDefaultsUpload)
        let logAction = avatarData == nil ? "remove" : "upload"
        DDLogInfo("AvatarStore/uploadAvatarData/\(logAction)/begin")
        service.updateAvatar(avatarData, for: userID) { [weak self] result in
            switch result {
            case .success(let avatarID):
                DDLogInfo("AvatarStore/uploadAvatarData/\(logAction)/success")
                UserDefaults.standard.removeObject(forKey: AvatarStore.Keys.userDefaultsUpload)

                self?.userAvatar(forUserId: userID).avatarId = avatarID

                guard let avatarID = avatarID, let avatarData = avatarData, !avatarID.isEmpty else {
                    // Return early after removing avatar
                    return
                }

                // Save uploaded data to permanent spot
                DDLogInfo("AvatarStore/uploadAvatarData received new avatarID [\(avatarID)]")
                let relativeFilePath = "\(avatarID).jpeg"
                do {
                    try self?.writeData(avatarData.thumbnail, toRelativePath: relativeFilePath)
                } catch {
                    DDLogError("AvatarStore/uploadAvatarData/error [\(error)]")
                }

                // Update DB and remove pending files
                self?.performOnBackgroundContextAndWait { [weak self] managedObjectContext in
                    guard let currentAvatar = self?.avatar(forUserId: userID, using: managedObjectContext) else {
                        DDLogError("AvatarStore/uploadAvatarData/error avatar does not exist!")
                        return
                    }

                    currentAvatar.avatarId = avatarID
                    currentAvatar.relativeFilePath = relativeFilePath

                    do {
                        try managedObjectContext.save()
                        self?.removePendingAvatar(for: userID)
                    } catch let error as NSError {
                        DDLogError("AvatarStore/uploadAvatarData/error [\(error)]")
                    }
                }

            case .failure(let error):
                DDLogError("ProtoService/updateAvatar/\(logAction)/error: \(error)")
            }
        }
    }

    private func loadPendingAvatar(for userID: UserID, completion: @escaping (AvatarData?) -> Void) {
        let thumbPath = AvatarStore.pendingThumbnailFilename(for: userID)
        let fullImagePath = AvatarStore.pendingFullImageFilename(for: userID)

        DispatchQueue.global(qos: .userInitiated).async {
            guard let thumbnailData = self.loadData(atRelativePath: thumbPath) else {
                DDLogError("AvatarStore/loadPendingAvatar/error [no-thumbnail]")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            var avatarData = AvatarData(thumbnail: thumbnailData)
            avatarData.full = self.loadData(atRelativePath: fullImagePath)

            DispatchQueue.main.async {
                DDLogError("AvatarStore/loadPendingAvatar/success")
                completion(avatarData)
            }
        }
    }

    private func insertAvatar(avatarId: AvatarID, forUserId userId: UserID, using managedObjectContext: NSManagedObjectContext) -> Avatar {
        var currentAvatar: Avatar
        if let avatar = avatar(forUserId: userId, using: managedObjectContext) {
            currentAvatar = avatar
            if currentAvatar.avatarId != avatarId {
                removeAvatarFile(avatar: currentAvatar)
            }
        } else {
            currentAvatar = NSEntityDescription.insertNewObject(forEntityName: Avatar.entity().name!, into: managedObjectContext) as! Avatar
            currentAvatar.userId = userId
        }
        currentAvatar.avatarId = avatarId
        return currentAvatar
    }

    private func removePendingAvatar(for userID: UserID) {
        removeFile(atRelativePath: AvatarStore.pendingThumbnailFilename(for: userID))
        removeFile(atRelativePath: AvatarStore.pendingFullImageFilename(for: userID))
    }

    private func removeAvatarFile(avatar: Avatar) {
        if let relativeFilePath = avatar.relativeFilePath {
            removeFile(atRelativePath: relativeFilePath)
        }
        avatar.relativeFilePath = nil
    }

    private func removeFile(atRelativePath relativePath: String) {
        let fileURL = AvatarStore.fileURL(forRelativeFilePath: relativePath)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                DDLogError("AvatarStore/removeFile/error [\(relativePath)] [\(error)]")
            }
        }
    }

    private func loadData(atRelativePath relativePath: String) -> Data? {
        let fileURL = AvatarStore.fileURL(forRelativeFilePath: relativePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            DDLogInfo("AvatarStore/loadData/no-data [\(relativePath)]")
            return nil
        }
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            DDLogInfo("AvatarStore/loadData/error [\(relativePath)] [\(error)]")
            return nil
        }
    }

    private func writeData(_ data: Data, toRelativePath relativePath: String) throws {
        let fileURL = AvatarStore.fileURL(forRelativeFilePath: relativePath)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        try data.write(to: fileURL)
    }

    /// Updates relative file path in the database without changing files on disk.
    fileprivate func update(relativeFilePath: String, forUserId userId: UserID) {
        performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            guard let self = self else { return }

            guard let currentAvatar = self.avatar(forUserId: userId, using: managedObjectContext) else {
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
    }
    
    public func service(_ service: CoreService, didReceiveAvatarInfo avatarInfo: AvatarInfo) {
        DDLogInfo("AvatarStore/didReceiveAvatar \(avatarInfo)")

        performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            guard let self = self else { return }
            self.save(avatarId: avatarInfo.avatarID, forUserId: avatarInfo.userID, using: managedObjectContext)
        }
    }
    
    public func processContactSync(_ avatarDict: [UserID: AvatarID]) {
        performOnBackgroundContextAndWait { [weak self] (managedObjectContext) in
            for (userId, avatarId) in avatarDict {
                _ = self?.insertAvatar(avatarId: avatarId, forUserId: userId, using: managedObjectContext)
            }
            do {
                try managedObjectContext.save()
            } catch let error as NSError {
                DDLogError("AvatarStore/processContactSync/error [\(error)]")
            }
        }
    }
}

extension AvatarStore {

    public func groupAvatarData(for groupID: GroupID) -> GroupAvatarData {
        if let groupAvatarData = groupAvatarsData.object(forKey: groupID as NSString) {
            return groupAvatarData
        }
        DDLogDebug("AvatarStore/group/groupAvatarData/not in cache yet \(groupID)")

        var groupAvatarData: GroupAvatarData?

        if let groupAvatar = groupAvatar(for: groupID) {
            groupAvatarData = GroupAvatarData(groupAvatar)
        } else {
            groupAvatarData = GroupAvatarData(groupID: groupID)
        }

        groupAvatarsData.setObject(groupAvatarData!, forKey: groupID as NSString)
        return groupAvatarData!
    }
 
    // MARK: GroupAvatar Core Data Inserting
  
    public func updateOrInsertGroupAvatar(for groupID: GroupID, with avatarID: AvatarID) {
        performOnBackgroundContextAndWait { [weak self] (managedObjectContext) in
            self?.updateOrInsertGroupAvatar(for: groupID, with: avatarID, using: managedObjectContext)
        }
    }
    
    private func updateOrInsertGroupAvatar(for groupID: GroupID, with avatarID: AvatarID, using managedObjectContext: NSManagedObjectContext) {
        if let groupAvatar = groupAvatar(for: groupID, using: managedObjectContext) {
            guard groupAvatar.avatarID != avatarID else {
                DDLogDebug("AvatarStore/group/save/no change to avatarID")
                return
            }
            DDLogDebug("AvatarStore/group/save/avaterID changed")

            groupAvatar.avatarID = avatarID
            
            if let relativeFilePath = groupAvatar.relativeFilePath {
                DDLogDebug("AvatarStore/group/save/delete old avatar")
                let filePath = AvatarStore.fileURL(forRelativeFilePath: relativeFilePath)
                if FileManager.default.fileExists(atPath: filePath.path) {
                    do {
                        try FileManager.default.removeItem(at: filePath)
                    } catch let error as NSError {
                        DDLogError("AvatarStore/save/failed to remove old file [\(error)]")
                    }
                }
                groupAvatar.relativeFilePath = nil
            }
            
        } else {
            DDLogDebug("AvatarStore/group/save/insert new avatar")
            let groupAvatar = NSEntityDescription.insertNewObject(forEntityName: GroupAvatar.entity().name!, into: managedObjectContext) as! GroupAvatar
            groupAvatar.groupID = groupID
            groupAvatar.avatarID = avatarID
        }

        do {
            try managedObjectContext.save()
        } catch let error as NSError {
            DDLogError("AvatarStore/save/error [\(error)]")
        }
        
        if let groupAvatarData = groupAvatarsData.object(forKey: groupID as NSString) {
            groupAvatarData.skipEmptyStateRenderingOnce = avatarID != ""
            groupAvatarData.image = nil
            groupAvatarData.data = nil
            groupAvatarData.fileUrl = nil

            groupAvatarData.avatarId = avatarID

            if avatarID != "" {
                groupAvatarData.loadImage(using: self)
            }
        }
    }
    
    /* currently not used */
    public func updateGroupAvatarImageData(for groupID: GroupID, avatarID: AvatarID, with data: Data) {
        DDLogInfo("AvatarStore/saveGroupAvatarImageData")
 
        let fileURL = AvatarStore.fileURL(forRelativeFilePath: "\(avatarID).jpeg")
        
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            try data.write(to: fileURL)
        } catch {
            DDLogError("AvatarStore/save/failed [\(error)]")
            return
        }
        
        updateGroupAvatar(for: groupID, relativeFilePath: "\(avatarID).jpeg")
        
        // update cache
        if let groupAvatarData = groupAvatarsData.object(forKey: groupID as NSString) {
            groupAvatarData.avatarId = avatarID
            groupAvatarData.image = UIImage(data: data)
            groupAvatarData.data = data
            groupAvatarData.fileUrl = fileURL
        }
    }
    
    // MARK: GroupAvatar Core Data Fetching
    
    private func groupAvatar(for groupID: GroupID) -> GroupAvatar? {
        return groupAvatar(for: groupID, using: viewContext)
    }
    
    private func groupAvatar(for groupID: GroupID, using managedObjectContext: NSManagedObjectContext) -> GroupAvatar? {
        let fetchRequest: NSFetchRequest<GroupAvatar> = GroupAvatar.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "groupID == %@", groupID)
        
        do {
            let results = try managedObjectContext.fetch(fetchRequest)
            return results.first
        } catch  {
            DDLogError("AvatarStore/group/fetch/error [\(error)]")
            return nil
        }
    }
    
    // MARK: GroupAvatar Core Data Updating
    
    fileprivate func updateGroupAvatar(for groupID: GroupID, relativeFilePath: String) {
        performOnBackgroundContextAndWait { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            guard let currentAvatar = self.groupAvatar(for: groupID, using: managedObjectContext) else {
                DDLogError("AvatarStore/group/updateGroupAvatar/error avatar does not exist!")
                return
            }
            
            currentAvatar.relativeFilePath = relativeFilePath
            
            do {
                try managedObjectContext.save()
            } catch let error as NSError {
                DDLogError("AvatarStore/group/updateGroupAvatar/error [\(error)]")
            }
            
            DDLogInfo("AvatarStore/group/updateGroupAvatar relativeFilePath for group \(groupID) has been changed to \(relativeFilePath)")
        }
    }
    
}

public class UserAvatar {
    public var image: UIImage? {
        didSet {
            DispatchQueue.main.async {
                self.imageDidChange.send(self.image)
            }
        }
    }
    public var isEmpty: Bool {
        avatarId?.isEmpty ?? true
    }

    fileprivate var avatarId: AvatarID?
    fileprivate var fileURL: URL?
    
    private let userId: UserID
    private var imageIsLoading = false
    
    public let imageDidChange = PassthroughSubject<UIImage?, Never>()
    
    private static let avatarLoadingQueue = DispatchQueue(label: "com.halloapp.avatar-loading", qos: .userInitiated)
    
    init(_ avatar: Avatar) {
        avatarId = avatar.avatarId
        userId = avatar.userId

        if let relativeFilePath = avatar.relativeFilePath {
            fileURL = AvatarStore.fileURL(forRelativeFilePath: relativeFilePath)
        } else {
            fileURL = nil
        }
        
        DDLogInfo("UserAvatar/init for user=\(userId)")
    }
    
    // Create a dummy object for a user that's not in the database
    public init(userId: UserID, avatarID: String? = nil) {
        self.userId = userId
        self.avatarId = avatarID
        
        DDLogInfo("UserAvatar/init a dummy object for user=\(userId) has been created")
    }
    
    public func loadThumbnailImage(using avatarStore: AvatarStore) {
        guard let avatarId = avatarId, image == nil && !imageIsLoading && !isEmpty else {
            return
        }
        
        imageIsLoading = true
        
        DDLogInfo("UserAvatar/loadImage for user=\(userId), avatar=\(avatarId), fileUrl=\(String(describing: fileURL))")
        if let fileURL = self.fileURL { // avatar has been downloaded
            UserAvatar.avatarLoadingQueue.async {
                let data: Data
                do {
                    data = try Data(contentsOf: fileURL)
                } catch {
                    DDLogError("UserAvatar/reload failed to read data \(error)")
                    return
                }
                
                if let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self.image = image
                        DDLogInfo("UserAvatar/loadImage avatar for user \(self.userId) has been loaded from disk")
                    }
                } else {
                    DDLogError("UserAvatar/reload failed to deserialized data into UIImage")
                }
                
                self.imageIsLoading = false
            }
        } else { // avatar has not been downloaded yet
            guard let url = URL(string: AvatarStore.avatarCDNUrl + avatarId) else {
                DDLogError("UserAvatar/loadImage/error \(AvatarStore.avatarCDNUrl + avatarId) cannot be formed as a URL")
                self.imageIsLoading = false
                return
            }

            let fileName = "\(avatarId).jpeg"
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
                
                guard let data = response.value, let image = UIImage(data: data) else {
                    DDLogError("UserAvatar/loadImage/AFDownload/error failed to deserialized data into UIIamge")
                    self.imageIsLoading = false
                    return
                }
                
                avatarStore.update(relativeFilePath: fileName, forUserId: self.userId)
                
                DispatchQueue.main.async {
                    self.image = image
                    DDLogInfo("UserAvatar/loadImage avatar for user \(self.userId) has been loaded from network")
                }
                
                self.imageIsLoading = false
            }
        }
    }
}


public class GroupAvatarData {
    
    public let imageDidChange = PassthroughSubject<UIImage?, Never>()
    public var isEmpty = true
    
    public var data: Data?
    public var skipEmptyStateRenderingOnce: Bool = false
    public var image: UIImage? {
        didSet {
            if !skipEmptyStateRenderingOnce {
                DispatchQueue.main.async {
                    self.imageDidChange.send(self.image)
                }
            } else {
                skipEmptyStateRenderingOnce = false
            }
        }
    }
    
    
    private static let avatarLoadingQueue = DispatchQueue(label: "com.halloapp.group-avatar-loading", qos: .userInitiated)
    fileprivate var fileUrl: URL?
    private let groupID: GroupID
    fileprivate var avatarId: AvatarID? {
        didSet {
            if avatarId != nil && !avatarId!.isEmpty {
                isEmpty = false
            } else {
                isEmpty = true
            }
        }
    }
    
    private var imageIsLoading = false
    
    init(_ groupAvatar: GroupAvatar) {
        avatarId = groupAvatar.avatarID
        groupID = groupAvatar.groupID
        
        if avatarId != nil && !avatarId!.isEmpty {
            isEmpty = false
        } else {
            isEmpty = true
        }
        
        if let relativeFilePath = groupAvatar.relativeFilePath {
            fileUrl = AvatarStore.fileURL(forRelativeFilePath: relativeFilePath)
        } else {
            fileUrl = nil
        }
        
        DDLogInfo("GroupAvatarData/init \(groupID)")
        DDLogInfo("GroupAvatarData/init avatarID: \(avatarId ?? "<none>")")
    }
    
    init(groupID: GroupID) {
        self.groupID = groupID
        
        DDLogInfo("GroupAvatarData/init dummy object \(groupID)")
    }
    
    public func loadImage(using avatarStore: AvatarStore) {
        guard let avatarId = avatarId, image == nil && !imageIsLoading && !isEmpty else {
            return
        }
        
        imageIsLoading = true
        
        DDLogInfo("GroupAvatarData/loadImage for group=\(groupID), avatar=\(avatarId), fileUrl=\(String(describing: fileUrl))")
        if let fileUrl = self.fileUrl { // avatar has been downloaded
            GroupAvatarData.avatarLoadingQueue.async {
                do {
                    self.data = try Data(contentsOf: fileUrl)
                } catch {
                    DDLogError("UserAvatar/reload failed to read data \(error)")
                    self.imageIsLoading = false
                    return
                }
                
                if let image = UIImage(data: self.data!) {
                    DispatchQueue.main.async {
                        self.image = image
                        DDLogInfo("GroupAvatarData/loadImage avatar for group \(self.groupID) has been loaded from disk")
                    }
                } else {
                    DDLogError("GroupAvatarData/reload failed to deserialized data into UIImage")
                    self.data = nil
                }
                
                self.imageIsLoading = false
            }
        } else { // avatar has not been downloaded yet
            guard let url = URL(string: AvatarStore.avatarCDNUrl + avatarId) else {
                DDLogError("GroupAvatarData/loadImage/error \(AvatarStore.avatarCDNUrl + avatarId) cannot be formed as a URL")
                self.imageIsLoading = false
                return
            }

            let fileName = "\(avatarId).jpeg"
            let fileUrl = AvatarStore.fileURL(forRelativeFilePath: fileName)
            let destination: DownloadRequest.Destination = { _, _ in
                return (fileUrl, [.removePreviousFile, .createIntermediateDirectories])
            }
            
            AF.download(url, to: destination).responseData(queue: GroupAvatarData.avatarLoadingQueue) { (response) in
                if let error = response.error {
                    DDLogError("GroupAvatarData/loadImage/AFDownload/error \(error)")
                    self.imageIsLoading = false
                    return
                }
                
                guard let httpURLResponse = response.response else {
                    DDLogError("GroupAvatarData/loadImage/AFDownload/error can't get response")
                    self.imageIsLoading = false
                    return
                }
                
                guard httpURLResponse.statusCode == 200 else {
                    DDLogError("GroupAvatarData/loadImage/AFDownload/error unexpected response code \(httpURLResponse.statusCode)")
                    self.imageIsLoading = false
                    return
                }
                
                guard let image = UIImage(data: response.value!) else {
                    DDLogError("GroupAvatarData/loadImage/AFDownload/error failed to deserialized data into UIIamge")
                    self.imageIsLoading = false
                    return
                }
                
                avatarStore.updateGroupAvatar(for: self.groupID, relativeFilePath: fileName)
                
                DispatchQueue.main.async {
                    self.image = image
                    self.data = response.value!
                    DDLogInfo("GroupAvatarData/loadImage avatar for group \(self.groupID) has been loaded from network")
                }
                
                self.imageIsLoading = false
            }
        }
    }
}

// MARK: Contact Avatars

extension AvatarStore {

    public func addressBookAvatar(for identifier: String) -> AddressBookAvatar {
        if let addressBookAvatar = addressBookAvatars.object(forKey: identifier as NSString) {
            return addressBookAvatar
        }

        let addressBookAvatar = AddressBookAvatar(identifer: identifier)
        addressBookAvatars.setObject(addressBookAvatar, forKey: identifier as NSString)
        return addressBookAvatar
    }
}

public class AddressBookAvatar {

    public let identifier: String
    public let imageDidChange = PassthroughSubject<UIImage?, Never>()
    public var image: UIImage? {
        didSet {
            DispatchQueue.main.async {
                self.imageDidChange.send(self.image)
            }
        }
    }
    private var imageIsLoading = false
    private var hasEmptyImage = false

    fileprivate init(identifer: String) {
        self.identifier = identifer
    }

    public func loadImage(using avatarStore: AvatarStore) {
        guard !imageIsLoading, !hasEmptyImage, CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            return
        }

        DispatchQueue.global(qos: .default).async { [weak self, identifier] in
            defer {
                self?.imageIsLoading = false
            }

            do {
                let contact = try CNContactStore().unifiedContact(withIdentifier: identifier,
                                                                  keysToFetch: [CNContactImageDataKey as CNKeyDescriptor])
                guard let imageData = contact.imageData else {
                    self?.hasEmptyImage = true
                    return
                }

                guard let image = UIImage(data: imageData) else {
                    DDLogError("AddressBookAvatar/loadImage/failed to deserialize data into UIImage")
                    return
                }

                self?.image = image
            } catch {
                DDLogError("AddressBookAvatar/loadImage/Error fetching contact image \(error)")
            }
        }
    }
}
