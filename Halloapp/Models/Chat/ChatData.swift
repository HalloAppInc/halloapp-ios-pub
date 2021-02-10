//
//  HalloApp
//
//  Created by Tony Jiang on 4/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import CoreData
import UIKit

typealias ChatAck = (id: String, timestamp: Date?)

typealias ChatPresenceInfo = (userID: UserID, presence: PresenceType?, lastSeen: Date?)

typealias ChatStateInfo = (from: UserID, threadType: ChatType, threadID: String, type: ChatState, timestamp: Date?)
typealias ChatRetractInfo = (from: UserID, threadType: ChatType, threadID: String, messageID: String)

typealias ChatMessageID = String
typealias ChatGroupMessageID = String

public enum UserPresenceType: Int16 {
    case none = 0
    case available = 1
    case away = 2
}


class ChatData: ObservableObject {

    public var currentPage: Int = 0
    
    let didChangeUnreadThreadCount = PassthroughSubject<Int, Never>()
    let didChangeUnreadThreadGroupsCount = PassthroughSubject<Int, Never>()
    let didChangeUnreadCount = PassthroughSubject<Int, Never>()
    let didGetCurrentChatPresence = PassthroughSubject<(UserPresenceType, Date?), Never>()
    let didGetChatStateInfo = PassthroughSubject<Void, Never>()
    
    let didGetMediaDownloadProgress = PassthroughSubject<(String, Int, Double), Never>()
    
    let didGetAGroupFeed = PassthroughSubject<GroupID, Never>()
    let didGetAChatMsg = PassthroughSubject<UserID, Never>()
    let didGetAGroupChatMsg = PassthroughSubject<GroupID, Never>()
    
    private let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.chat")
    
    private let userData: UserData
    private let contactStore: ContactStoreMain
    private var service: HalloService
    private let mediaUploader: MediaUploader
    
    private var currentlyChattingWithUserId: String? = nil
    private var isSubscribedToCurrentUser: Bool = false
    
    private var currentlyChattingInGroup: GroupID? = nil
    
    private var chatStateInfoList: [ChatStateInfo] = []
    private var chatStateDebounceTimer: Timer? = nil
    
    private var unreadThreadCount: Int = 0 {
        didSet {
            didChangeUnreadThreadCount.send(unreadThreadCount)
//            DispatchQueue.main.async {
//                UIApplication.shared.applicationIconBadgeNumber = self.unreadThreadCount
//            }
        }
    }
    
    private var unreadThreadGroupsCount: Int = 0 {
        didSet {
            didChangeUnreadThreadGroupsCount.send(unreadThreadGroupsCount)
        }
    }
    
    private var unreadMessageCount: Int = 0 {
        didSet {
            didChangeUnreadCount.send(unreadMessageCount)
        }
    }

    private let downloadQueue = DispatchQueue(label: "com.halloapp.chat.download", qos: .userInitiated)
    private let maxNumDownloads: Int = 3
    private var currentlyDownloading: [URL] = []
    private let maxTries: Int = 10
    
    
    
    private let persistentContainer: NSPersistentContainer = {
        let storeDescription = NSPersistentStoreDescription(url: MainAppContext.chatStoreURL)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSMigratePersistentStoresAutomaticallyOption)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSInferMappingModelAutomaticallyOption)
        storeDescription.setValue(NSString("WAL"), forPragmaNamed: "journal_mode")
        storeDescription.setValue(NSString("1"), forPragmaNamed: "secure_delete")
        let container = NSPersistentContainer(name: "Chat")
        container.persistentStoreDescriptions = [ storeDescription ]
        container.loadPersistentStores(completionHandler: { (description, error) in
            if let error = error {
                DDLogError("Failed to load persistent store: \(error)")
                fatalError("Unable to load persistent store: \(error)")
            } else {
                DDLogInfo("ChatData/load-store/completed [\(description)]")
            }
        })
        return container
    }()
    
    var viewContext: NSManagedObjectContext
    private var bgContext: NSManagedObjectContext
    
    private struct UserDefaultsKey {
        static let persistentStoreUserID = "chat.store.userID"
    }
    
    private var cancellableSet: Set<AnyCancellable> = []
    
    init(service: HalloService, contactStore: ContactStoreMain, userData: UserData) {
        self.service = service
        self.contactStore = contactStore
        self.userData = userData
        
        self.mediaUploader = MediaUploader(service: service)
        
        self.persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
        self.viewContext = persistentContainer.viewContext
        self.bgContext = persistentContainer.newBackgroundContext()
        
        self.service.chatDelegate = self
        
        mediaUploader.resolveMediaPath = { relativePath in
            return MainAppContext.chatMediaDirectoryURL.appendingPathComponent(relativePath, isDirectory: false)
        }
        
        var shouldGetGroupsList = false
        
        cancellableSet.insert(
            service.didGetChatAck.sink { [weak self] chatAck in
                guard let self = self else { return }
                DDLogInfo("ChatData/didGetChatAck \(chatAck.id)")
                self.processInboundChatAck(chatAck)
            }
        )
        
        cancellableSet.insert(
            service.didGetNewChatMessage.sink { [weak self] xmppMessage in
                guard let self = self else { return }
                DDLogInfo("ChatData/didGetNewChatMessage \(xmppMessage.id)")
                self.processInboundXMPPChatMessage(xmppMessage)
                
                self.didGetAChatMsg.send(xmppMessage.fromUserId)
            }
        )
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.cancellableSet.insert(
                MainAppContext.shared.feedData.didReceiveFeedPost.sink { [weak self] (feedPost) in
                    guard let self = self else { return }
                    guard let groupID = feedPost.groupId else { return }
                    let postID = feedPost.id
                    DDLogInfo("ChatData/didReceiveFeedPost/group/\(groupID)")
                    
                    self.didGetAGroupFeed.send(groupID)
                    
                    self.performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
                        guard let self = self else { return }
                        self.updateThreadWithGroupFeed(postID, isInbound: true, using: managedObjectContext)
                    }
                }
            )
            
            self.cancellableSet.insert(
                MainAppContext.shared.feedData.didMergeFeedPost.sink { [weak self] (postID) in
                    guard let self = self else { return }
                    guard let feedPost = MainAppContext.shared.feedData.feedPost(with: postID) else { return }
                    guard let groupID = feedPost.groupId else { return }
                    DDLogInfo("ChatData/didMergeFeedPost")
                    
                    self.didGetAGroupFeed.send(groupID)
                    
                    self.performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
                        guard let self = self else { return }
                        self.updateThreadWithGroupFeed(postID, isInbound: true, using: managedObjectContext)
                    }
                }
            )
            
            self.cancellableSet.insert(
                MainAppContext.shared.feedData.didSendGroupFeedPost.sink { [weak self] (feedPost) in
                    guard let self = self else { return }
                    guard let groupID = feedPost.groupId else { return }
                    let postID = feedPost.id
                    DDLogInfo("ChatData/didSendGroupFeedPost/group/\(groupID)")
                    self.performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
                        guard let self = self else { return }
                        self.updateThreadWithGroupFeed(postID, isInbound: false, using: managedObjectContext)
                    }
                }
            )
            
            self.cancellableSet.insert(
                MainAppContext.shared.feedData.didProcessGroupFeedPostRetract.sink { [weak self] (feedPostID) in
                    guard let self = self else { return }
                    DDLogInfo("ChatData/didProcessGroupFeedPostRetract")
                    self.performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
                        guard let self = self else { return }

                        self.updateThreadWithGroupFeedRetract(feedPostID, using: managedObjectContext)
                    }
                }
            )
            
            self.cancellableSet.insert(
                MainAppContext.shared.feedData.groupFeedStates.sink{ [weak self] (statesList) in
                    guard let self = self else { return }
                    statesList.forEach({ (keyGroupId, state) in
                        switch state {
                        case .noPosts: break
                        case .newPosts(let numNew, _):
                            self.setThreadUnreadFeedCount(type: .group, for: keyGroupId, num: Int32(numNew))
                        case .seenPosts(_):
                            self.updateChatThread(type: .group, for: keyGroupId, block: { thread in
                                guard thread.unreadFeedCount > 0 else { return }
                                thread.unreadFeedCount = 0
                                self.updateUnreadThreadGroupsCount()
                            })
                        }
                    })
                }
            )
            
        }
                
        cancellableSet.insert(
            service.didConnect.sink { [weak self] in
                guard let self = self else { return }
                DDLogInfo("ChatData/didConnect")
                
                // include inactive as app is still in foreground (one case found is when app is freshly installed and the scene is in transition)
                if ([.active, .inactive].contains(UIApplication.shared.applicationState)) {
                    DDLogInfo("ChatData/didConnect/sendPresence \(UIApplication.shared.applicationState.rawValue)")
                    self.sendPresence(type: .available)
                    
                    if let currentUser = self.currentlyChattingWithUserId {
                        if !self.isSubscribedToCurrentUser {
                            self.subscribeToPresence(to: currentUser)
                        }
                    }
                } else {
                    DDLogDebug("ChatData/didConnect/app is in background \(UIApplication.shared.applicationState.rawValue)")
                }
                
                self.processPendingChatMsgs()
                self.processRetractingChatMsgs()
                self.processPendingSeenReceipts()
                
                self.processPendingGroupChatMsgs()
                self.processRetractingGroupChatMsgs()
                self.processPendingGroupChatSeenReceipts()
                
                if (UIApplication.shared.applicationState == .active) {
                    self.currentlyDownloading.removeAll()
                    self.processInboundPendingChatMsgMedia()
                    self.processInboundPendingGroupChatMsgMedia()
                }
                
                // temporary setting for builds older than 87 since they don't have the key set yet
                if MainAppContext.shared.userDefaults?.string(forKey: UserDefaultsKey.persistentStoreUserID) == nil {
                    DDLogInfo("ChatData/no persistent userID found")
                    MainAppContext.shared.userDefaults?.setValue(userData.userId, forKey: UserDefaultsKey.persistentStoreUserID)
                    self.getGroupsList()
                }
                
                if shouldGetGroupsList {
                    self.getGroupsList()
                    shouldGetGroupsList = false
                }
                
            }
        )
                
        cancellableSet.insert(
            service.didGetPresence.sink { [weak self] xmppPresence in
                guard let self = self else { return }
                DDLogInfo("ChatData/didGetPresence \(xmppPresence.userID)")
                self.processIncomingPresence(xmppPresence)
            }
        )
        
        cancellableSet.insert(
            service.didGetChatState.sink { [weak self] chatStateInfo in
                guard let self = self else { return }
                DDLogInfo("ChatData/didGetChatState \(chatStateInfo.from)")
                self.processInboundChatStateInBg(chatStateInfo)
            }
        )
        
        cancellableSet.insert(
            service.didGetChatRetract.sink { [weak self] chatRetractInfo in
                guard let self = self else { return }
                DDLogInfo("ChatData/didGetChatRetract \(chatRetractInfo.from)")
                self.processInboundChatRetractInBg(chatRetractInfo)
            }
        )
        
        /** gotcha: use Combine sink instead of notificationCenter.addObserver because for some reason if the user flicks the app to the background and back
            really quickly, the observer doesn't fire
         */
        cancellableSet.insert(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification).sink { [weak self] notification in
                guard let self = self else { return }
                self.sendPresence(type: .available)
                if let currentlyChattingWithUserId = self.currentlyChattingWithUserId {
                    self.performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
                        guard let self = self else { return }
                        self.markSeenMessages(type: .oneToOne, for: currentlyChattingWithUserId, in: managedObjectContext)
                    }
                }
                //TODO: if at group screen
            }
        )
        
        cancellableSet.insert(
            NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification).sink { [weak self] notification in
                guard let self = self else { return }
                self.sendPresence(type: .away)
            }
        )

        cancellableSet.insert(
            contactStore.didDiscoverNewUsers.sink { [weak self] (userIDs) in
                DDLogInfo("ChatData/didDiscoverNewUsers/count: \(userIDs.count)")
                var contactsDict = [UserID:String]()
                userIDs.forEach {
                    contactsDict[$0] = contactStore.fullName(for: $0)
                }
                self?.updateThreads(for: contactsDict, areNewUsers: true)
            })

        cancellableSet.insert(
            userData.didLogIn.sink { [weak self] in
                guard let self = self else { return }
                DDLogInfo("ChatData/didLogIn")
                
                if let previousID = MainAppContext.shared.userDefaults?.string(forKey: UserDefaultsKey.persistentStoreUserID) {
                    
                    if previousID != self.userData.userId {
                        DDLogInfo("ChatData/didLogIn/userID mismatch previous: [\(previousID)] current [\(self.userData.userId)], clear previous chats and media")
                        self.clearAllChatsAndMedia()
                    } else {
                        DDLogInfo("ChatData/didLogin/userID matches")
                    }
                    
                } else {
                    DDLogInfo("ChatData/didLogin/fresh app install")
                }
                
                MainAppContext.shared.userDefaults?.setValue(self.userData.userId, forKey: UserDefaultsKey.persistentStoreUserID)
                shouldGetGroupsList = true
            }
        )
        
    }

    func clearAllChatsAndMedia() {

        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            
            let model = self.persistentContainer.managedObjectModel
            let entities = model.entities
           
            /* nb: batchdelete will not auto delete entities with a cascade delete rule for core data relationships but
               can result in not deleting an entity if there's a deny delete rule in place */
            for entity in entities {
                guard let entityName = entity.name else { continue }
                DDLogDebug("ChatData/clearAllChatsAndMedia/clear/\(entityName)")
                
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                batchDeleteRequest.resultType = .resultTypeObjectIDs
                do {
                    let result = try managedObjectContext.execute(batchDeleteRequest) as? NSBatchDeleteResult
                    guard let objectIDs = result?.result as? [NSManagedObjectID] else { continue }
                    let changes = [NSDeletedObjectsKey: objectIDs]
                    DDLogDebug("ChatData/clearAllChatsAndMedia/clear/\(entityName)/num: \(objectIDs.count)")

                    // update main context manually as batchdelete does not notify other contexts
                    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self.viewContext])
                    
                } catch {
                    DDLogError("ChatData/clearAllChatsAndMedia/clear/\(entityName)/error \(error)")
                }
            }
            
            // clear media
            do {
                try FileManager.default.removeItem(at: MainAppContext.chatMediaDirectoryURL)
                DDLogError("ChatData/clearAllChatsAndMedia/clear/media finished")
            }
            catch {
                DDLogError("ChatData/clearAllChatsAndMedia/clear/media/error [\(error)]")
            }
        }
        
    }
    

    func populateThreadsWithSymmetricContacts() {
        let contactStore = MainAppContext.shared.contactStore
        let contacts = contactStore.allInNetworkContacts(sorted: true)
        DDLogInfo("ChatData/populateThreadsWithSymmetricContacts/allInNetworkContacts: \(contacts.count)")
        var contactsDict = [UserID:String]()
        contacts.forEach {
            guard let userID = $0.userId else { return }
            contactsDict[userID] = $0.fullName
        }
        updateThreads(for: contactsDict, areNewUsers: false)
    }

    func updateThreads(for userIDs: [UserID:String], areNewUsers: Bool) {
        guard !userIDs.isEmpty else { return }
        let timestampForNewThreads = Date()
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }

            for (userId, fullName) in userIDs {
                if let chatThread = self.chatThread(type: ChatType.oneToOne, id: userId, in: managedObjectContext) {
                    guard chatThread.lastMsgId == nil else { continue }
                    if chatThread.title != fullName {
                        DDLogDebug("ChatData/populateThreads/contact/rename \(userId)")
                        self.updateChatThread(type: .oneToOne, for: userId) { (chatThread) in
                            chatThread.title = fullName
                        }
                    }
                } else {
                    DDLogInfo("ChatData/populateThreads/contact/new \(userId)")
                    let chatThread = ChatThread(context: managedObjectContext)
                    chatThread.title = fullName
                    chatThread.chatWithUserId = userId
                    chatThread.lastMsgUserId = userId
                    chatThread.lastMsgText = nil
                    chatThread.lastMsgTimestamp = timestampForNewThreads
                    chatThread.unreadCount = 0
                    chatThread.isNew = areNewUsers
                }
            }
            // TODO: take care of deletes, ie. user removes contact from address book

            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    func processInboundPendingChatMsgMedia() {
        guard currentlyDownloading.count <= maxNumDownloads else { return }
        
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            
            let pendingMessagesWithMedia = self.pendingIncomingChatMessagesMedia(in: managedObjectContext)
            
            for chatMessage in pendingMessagesWithMedia {
                
                guard let media = chatMessage.media else { continue }
                
                let sortedMedia = media.sorted(by: { $0.order < $1.order })
                guard let med = sortedMedia.first(where: {
                    guard let url = $0.url else { return false }
                    guard $0.incomingStatus == .pending else { return false }
                    guard !self.currentlyDownloading.contains(url) else { return false }
                    if $0.numTries > self.maxTries {
                        // just logging for now and not stopping the attempt
                        DDLogDebug("ChatData/processInboundPendingChatMsgMedia/\(chatMessage.id)/media/order/\($0.order)/numTries: \($0.numTries)")
                    }
                    return true
                } ) else { continue }
                
                DDLogDebug("ChatData/processInboundPendingChatMsgMedia/\(chatMessage.id)/media/order/\(med.order)")
                
                guard let url = med.url else { continue }
                
                self.currentlyDownloading.append(url)

                let threadId = chatMessage.fromUserId
                let messageId = chatMessage.id
                let order = med.order
                let key = med.key
                let sha = med.sha256
                let type: FeedMediaType = med.type == ChatMessageMediaType.image ? FeedMediaType.image : FeedMediaType.video
            
                // save attempts
                self.updateChatMessage(with: messageId) { (chatMessage) in
                    if let index = chatMessage.media?.firstIndex(where: { $0.order == order } ), (chatMessage.media?[index].numTries ?? 0) < 9999 {
                        chatMessage.media?[index].numTries += 1
                    }
                }
                                
                _ = ChatMediaDownloader(url: url, progressHandler: { [weak self] progress in
                    guard let self = self else { return }
                    self.didGetMediaDownloadProgress.send((messageId, Int(order), progress))
                }, completion: { [weak self] (outputUrl) in
                    guard let self = self else { return }
                    if let index = self.currentlyDownloading.firstIndex(of: url) {
                        self.currentlyDownloading.remove(at: index)
                    }
                    
                    var encryptedData: Data
                    do {
                        encryptedData = try Data(contentsOf: outputUrl)
                    } catch {
                        return
                    }

                    // Decrypt data
                    guard let mediaKey = Data(base64Encoded: key), let sha256Hash = Data(base64Encoded: sha) else {
                        return
                    }

                    var decryptedData: Data
                    do {
                        decryptedData = try MediaCrypter.decrypt(data: encryptedData, mediaKey: mediaKey, sha256hash: sha256Hash, mediaType: type)
                    } catch {
                        return
                    }

                    let fileExtension = type == .image ? "jpg" : "mp4"
                    let filename = "\(messageId)-\(order).\(fileExtension)"
                    
                    let fileURL = MainAppContext.chatMediaDirectoryURL
                        .appendingPathComponent(threadId, isDirectory: true)
                        .appendingPathComponent(filename, isDirectory: false)
                    
                    // create intermediate directories
                    if !FileManager.default.fileExists(atPath: fileURL.path) {
                        do {
                            try FileManager.default.createDirectory(atPath: fileURL.path, withIntermediateDirectories: true, attributes: nil)
                        } catch {
                            DDLogError(error.localizedDescription)
                        }
                    }
                    
                    // delete the file if it already exists, ie. previous attempts
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        try! FileManager.default.removeItem(atPath: fileURL.path)
                    } else {
                        DDLogError("File does not exist")
                    }
                    
                    do {
                        try decryptedData.write(to: fileURL, options: [])
                    }
                    catch {
                        DDLogError("can't write error: \(error)")
                        return
                    }
                    
                    self.updateChatMessage(with: messageId, block: { [weak self] (chatMessage) in
                        guard let self = self else { return }
                        if let index = chatMessage.media?.firstIndex(where: { $0.order == order } ) {
                            let relativePath = self.relativePath(from: fileURL)
                            chatMessage.media?[index].relativeFilePath = relativePath
                            chatMessage.media?[index].incomingStatus = .downloaded
                            
                            // hack: force a change so frc can pick up the change
                            let fromUserId = chatMessage.fromUserId
                            chatMessage.fromUserId = fromUserId
                        }
                    }) { [weak self] in
                        guard let self = self else { return }
                        self.processInboundPendingChatMsgMedia()
                        self.processInboundPendingGroupChatMsgMedia()
                    }
                })

            }
        }
    }
    
    // TODO: need to refactor, have chat and group share this component
    func processInboundPendingGroupChatMsgMedia() {
        guard currentlyDownloading.count < maxNumDownloads else { return }
        
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            
            let pendingMessagesWithMedia = self.inboundPendingGroupChatMsgMedia(in: managedObjectContext)
            
            for chatGroupMessage in pendingMessagesWithMedia {
                guard let media = chatGroupMessage.media else { continue }
                
                let sortedMedia = media.sorted(by: { $0.order < $1.order })
                guard let med = sortedMedia.first(where: {
                    guard let url = $0.url else { return false }
                    guard $0.incomingStatus == .pending else { return false }
                    guard !self.currentlyDownloading.contains(url) else { return false }
                    if $0.numTries > self.maxTries {
                        // just logging for now and not stopping the attempt
                        DDLogDebug("ChatData/processInboundPendingGroupChatMsgMedia/\(chatGroupMessage.id)/media/order/\($0.order)/numTries: \($0.numTries)")
                    }
                    return true
                } ) else { continue }
                
                DDLogDebug("ChatData/processInboundPendingGroupChatMsgMedia/\(chatGroupMessage.id)/media/order/\(med.order)")
                
                guard let url = med.url else { continue }

                self.currentlyDownloading.append(url)
                
                let threadId = chatGroupMessage.groupId
                let messageId = chatGroupMessage.id
                let order = med.order
                let key = med.key
                let sha = med.sha256
                let type: FeedMediaType = med.type == ChatMessageMediaType.image ? FeedMediaType.image : FeedMediaType.video
            
                // save attempts
                self.updateChatGroupMessage(with: messageId) { (chatGroupMessage) in
                    if let index = chatGroupMessage.media?.firstIndex(where: { $0.order == order } ), (chatGroupMessage.media?[index].numTries ?? 0) < 9999 {
                        chatGroupMessage.media?[index].numTries += 1
                    }
                }
                
                _ = ChatMediaDownloader(url: url, progressHandler: { [weak self] progress in
                    guard let self = self else { return }
                    self.didGetMediaDownloadProgress.send((messageId, Int(order), progress))
                }, completion: { [weak self] (outputUrl) in
                    guard let self = self else { return }
                    if let index = self.currentlyDownloading.firstIndex(of: url) {
                        self.currentlyDownloading.remove(at: index)
                    }
                    
                    var encryptedData: Data
                    do {
                        encryptedData = try Data(contentsOf: outputUrl)
                    } catch {
                        return
                    }

                    // Decrypt data
                    guard let mediaKey = Data(base64Encoded: key), let sha256Hash = Data(base64Encoded: sha) else {
                        return
                    }

                    var decryptedData: Data
                    do {
                        decryptedData = try MediaCrypter.decrypt(data: encryptedData, mediaKey: mediaKey, sha256hash: sha256Hash, mediaType: type)
                    } catch {
                        return
                    }

                    let fileExtension = type == .image ? "jpg" : "mp4"
                    let filename = "\(messageId)-\(order).\(fileExtension)"
                    
                    let fileURL = MainAppContext.chatMediaDirectoryURL
                        .appendingPathComponent(threadId, isDirectory: true)
                        .appendingPathComponent(filename, isDirectory: false)
                    
                    // create intermediate directories
                    if !FileManager.default.fileExists(atPath: fileURL.path) {
                        do {
                            try FileManager.default.createDirectory(atPath: fileURL.path, withIntermediateDirectories: true, attributes: nil)
                        } catch {
                            DDLogError(error.localizedDescription)
                        }
                    }
                    
                    // delete the file it already exists, ie. previous attempts
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        try! FileManager.default.removeItem(atPath: fileURL.path)
                    } else {
                        DDLogError("File does not exist")
                    }
                    
                    do {
                        try decryptedData.write(to: fileURL, options: [])
                    }
                    catch {
                        DDLogError("can't write error: \(error)")
                        return
                    }
                    
                    self.updateChatGroupMessage(with: messageId, block: { [weak self] (chatGroupMessage) in
                        guard let self = self else { return }
                        if let index = chatGroupMessage.media?.firstIndex(where: { $0.order == order } ) {
                            let relativePath = self.relativePath(from: fileURL)
                            chatGroupMessage.media?[index].relativeFilePath = relativePath
                            chatGroupMessage.media?[index].incomingStatus = .downloaded
                            
                            // hack: force a change so frc can pick up the change
                            let groupId = chatGroupMessage.groupId
                            chatGroupMessage.groupId = groupId
                        }
                    }) { [weak self] in
                        guard let self = self else { return }
                        self.processInboundPendingGroupChatMsgMedia()
                        self.processInboundPendingChatMsgMedia()
                    }
                    
                })

            }
        }
    }
    
    // MARK: Core Data Setup
    
    private func performSeriallyOnBackgroundContext(_ block: @escaping (NSManagedObjectContext) -> Void) {
        backgroundProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            self.bgContext.performAndWait { block(self.bgContext) }
        }
    }
    
    private func save(_ managedObjectContext: NSManagedObjectContext) {
        do {
            try managedObjectContext.save()
            DDLogVerbose("ChatData/save")
        } catch {
            DDLogError("ChatData/save/error [\(error)]")
        }
    }
    
    // MARK: Process Inbound Acks
    
    private func processInboundChatAck(_ chatAck: ChatAck) {
        DDLogDebug("ChatData/processInboundChatAck/ [\(chatAck.id)]")
        let messageID = chatAck.id
        
        // search for pending 1-1 message
        updateChatMessageByStatus(for: messageID, status: .pending) { [weak self] (chatMessage) in
            guard let self = self else { return }
            DDLogDebug("ChatData/processInboundChatAck/updatePendingChatMessage/ [\(messageID)]")

            chatMessage.outgoingStatus = .sentOut
        
            self.updateChatThreadStatus(type: .oneToOne, for: chatMessage.toUserId, messageId: chatMessage.id) { (chatThread) in
                chatThread.lastMsgStatus = .sentOut
            }

            // only change timestamp the first time message is ack'ed,
            // rerequests should not, with the assumption resendAttempts are only used for rerequests
            guard chatMessage.resendAttempts == 0 else { return }
            guard let serverTimestamp = chatAck.timestamp else { return }
            chatMessage.timestamp = serverTimestamp

        }

        // search for pending group message
        updateChatGroupMessageByStatus(for: messageID, status: .pending) { (chatGroupMessage) in
            DDLogDebug("ChatData/processInboundChatAck/updatePendingChatGroupMessage [\(messageID)]")
    
            chatGroupMessage.outboundStatus = .sentOut
                
            self.updateChatThreadStatus(type: .group, for: chatGroupMessage.groupId, messageId: chatGroupMessage.id) { (chatThread) in
                chatThread.lastMsgStatus = .sentOut
            }
                    
            if let serverTimestamp = chatAck.timestamp {
                chatGroupMessage.timestamp = serverTimestamp
            }
            
        }
        
        // search for retracting 1-1 message
        updateRetractingChatMessage(for: messageID) { (chatMessage) in
            DDLogDebug("ChatData/processInboundChatAck/updateRetractingChatMessage/ [\(messageID)]")
            chatMessage.outgoingStatus = .retracted
            
            self.updateChatThreadStatus(type: .oneToOne, for: chatMessage.toUserId, messageId: messageID) { (chatThread) in
                chatThread.lastMsgStatus = .retracted
            }
        }
        
        // search for retracting group message
        updateRetractingGroupChatMessage(for: messageID) { (groupChatMessage) in
            DDLogDebug("ChatData/processInboundChatAck/updateRetractingGroupChatMessage [\(messageID)]")

            groupChatMessage.outboundStatus = .retracted

            self.updateChatThreadStatus(type: .group, for: groupChatMessage.groupId, messageId: groupChatMessage.id) { (chatThread) in
                chatThread.lastMsgStatus = .retracted
            }

            return
        }
        

    }
    
    func copyFiles(toChatMedia chatMedia: ChatMedia, fileUrl: URL, encryptedFileUrl: URL?) throws {
        
        var threadId = ""
        var messageId = ""
        
        if let chatMessage = chatMedia.message {
            threadId = chatMessage.toUserId
            messageId = chatMessage.id
        } else if let chatGroupMessage = chatMedia.groupMessage {
            threadId = chatGroupMessage.groupId
            messageId = chatGroupMessage.id
        }
        
        let order = chatMedia.order
        
        let fileExtension = chatMedia.type == .image ? "jpg" : "mp4"
        let filename = "\(messageId)-\(order).\(fileExtension)"
        
        let toUrl = MainAppContext.chatMediaDirectoryURL
            .appendingPathComponent(threadId, isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
        
        // create intermediate directories
        if !FileManager.default.fileExists(atPath: toUrl.path) {
            do {
                try FileManager.default.createDirectory(at: toUrl.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            } catch {
                DDLogError(error.localizedDescription)
            }
        }

        try FileManager.default.copyItem(at: fileUrl, to: toUrl)

        if let encryptedFileUrl = encryptedFileUrl {
            let encryptedDestinationUrl = toUrl.appendingPathExtension("enc")
            try FileManager.default.copyItem(at: encryptedFileUrl, to: encryptedDestinationUrl)
        }
        
        let relativePath = self.relativePath(from: toUrl)
        chatMedia.relativeFilePath = relativePath
    }
    
    private func relativePath(from fileURL: URL) -> String? {
        let fullPath = fileURL.path
        let mediaDirectoryPath = MainAppContext.chatMediaDirectoryURL.path
        if let range = fullPath.range(of: mediaDirectoryPath, options: [.anchored]) {
            return String(fullPath.suffix(from: range.upperBound))
        }
        return nil
    }
    
    func copyMediaToQuotedMedia(fromDir: URL, fromPath: String?, to quotedMedia: ChatQuotedMedia) throws {
        guard let fromRelativePath = fromPath else {
            return
        }

        let fromURL = fromDir.appendingPathComponent(fromRelativePath, isDirectory: false)
        
        // append unique id to allow multiple quoted messages of the same feedpost so each message can be deleted independently in the future
        
        var pathComponents = fromRelativePath.components(separatedBy: ".")
        
        guard pathComponents.count > 1 else {
            return
        }
        
        pathComponents[0] += "-\(UUID().uuidString)"
        
        let newPath = "\(pathComponents[0]).\(pathComponents[1])"

        // todo: the directory for quoted media should follow a similar structure as chat media, should do mini migration also
        
        let toURL = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(newPath, isDirectory: false)

        try FileManager.default.createDirectory(at: toURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)

        try FileManager.default.copyItem(at: fromURL, to: toURL)
        quotedMedia.relativeFilePath = newPath
    }
    
    func sendSeenReceipt(for chatMessage: ChatMessage) {
        DDLogInfo("ChatData/sendSeenReceipt \(chatMessage.id)")
        service.sendReceipt(
            itemID: chatMessage.id,
            thread: .none,
            type: .read,
            fromUserID: userData.userId,
            toUserID: chatMessage.fromUserId)
    }
    
    func sendSeenGroupReceipt(for chatGroupMessage: ChatGroupMessage) {
        DDLogInfo("ChatData/sendSeenGroupReceipt \(chatGroupMessage.id)")
        guard let userId = chatGroupMessage.userId else {
            DDLogInfo("ChatData/sendSeenGroupReceipt/no userId \(chatGroupMessage.id)")
            return
        }
        service.sendReceipt(
            itemID: chatGroupMessage.id,
            thread: .group(chatGroupMessage.groupId),
            type: .read,
            fromUserID: userData.userId,
            toUserID: userId)
    }
    
    // MARK: Share Extension Merge Data
    
    func mergeData(from sharedDataStore: SharedDataStore, completion: @escaping (() -> ())) {
        let messages = sharedDataStore.messages()
        guard !messages.isEmpty else {
            DDLogDebug("ChatData/merge-data/ Nothing to merge")
            completion()
            return
        }

        performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            guard let self = self else { return }
            self.merge(messages: messages, from: sharedDataStore, using: managedObjectContext, completion: completion)
        }
    }

    private func merge(messages: [SharedChatMessage], from sharedDataStore: SharedDataStore, using managedObjectContext: NSManagedObjectContext, completion: @escaping (() -> ())) {
        for message in messages {
            let messageId: ChatMessageID = message.id

            guard chatMessage(with: messageId, in: managedObjectContext) == nil else {
                DDLogError("ChatData/mergeSharedData/already-exists [\(messageId)]")
                continue
            }

            DDLogDebug("ChatData/mergeSharedData/message/\(messageId)")
            
            let chatMessage = NSEntityDescription.insertNewObject(forEntityName: ChatMessage.entity().name!, into: managedObjectContext) as! ChatMessage
            chatMessage.id = messageId
            chatMessage.toUserId = message.toUserId
            chatMessage.fromUserId = message.fromUserId
            chatMessage.text = message.text
            chatMessage.feedPostId = nil
            chatMessage.feedPostMediaIndex = 0
            switch message.status {
            case .none:
                chatMessage.incomingStatus = .none
                chatMessage.outgoingStatus = .error
            case .sent:
                chatMessage.incomingStatus = .none
                chatMessage.outgoingStatus = .sentOut
            case .received:
                chatMessage.incomingStatus = .none
                chatMessage.outgoingStatus = .none
            case .sendError:
                chatMessage.incomingStatus = .none
                chatMessage.outgoingStatus = .error
            }
            chatMessage.timestamp = message.timestamp
            
            var lastMsgMediaType: ChatThread.LastMediaType = .none
            
            message.media?.forEach { media in
                DDLogDebug("ChatData/mergeSharedData/message/\(messageId)/add-media [\(media)]")

                let chatMedia = NSEntityDescription.insertNewObject(forEntityName: ChatMedia.entity().name!, into: managedObjectContext) as! ChatMedia
                switch media.type {
                case .image:
                    chatMedia.type = .image
                    if lastMsgMediaType == .none {
                        lastMsgMediaType = .image
                    }
                case .video:
                    chatMedia.type = .video
                    if lastMsgMediaType == .none {
                        lastMsgMediaType = .video
                    }
                }
                chatMedia.incomingStatus = media.status == .downloaded ? .downloaded : .none
                chatMedia.outgoingStatus = {
                    switch media.status {
                    case .none, .downloaded: return .none
                    case .uploaded: return .uploaded
                    case .uploading, .error: return .error
                    }
                }()
                chatMedia.url = media.url
                chatMedia.uploadUrl = media.uploadUrl
                chatMedia.size = media.size
                chatMedia.key = media.key
                chatMedia.order = media.order - 1 // adjusts for share extension starting at 1
                chatMedia.sha256 = media.sha256
                chatMedia.message = chatMessage

                if let relativeFilePath = media.relativeFilePath {
                    do {
                        let sourceUrl = sharedDataStore.fileURL(forRelativeFilePath: relativeFilePath)
                        let encryptedFileUrl = chatMedia.outgoingStatus == .error ? sourceUrl.appendingPathExtension("enc") : nil
                        try copyFiles(toChatMedia: chatMedia, fileUrl: sourceUrl, encryptedFileUrl: encryptedFileUrl)
                    } catch {
                        DDLogError("ChatData/mergeSharedData/media/copy-media/error [\(error)]")
                    }
                }
            }
            
            // Update Chat Thread
            if let chatThread = chatThread(type: ChatType.oneToOne, id: chatMessage.toUserId, in: managedObjectContext) {
                chatThread.lastMsgId = chatMessage.id
                chatThread.lastMsgUserId = chatMessage.fromUserId
                chatThread.lastMsgText = chatMessage.text
                chatThread.lastMsgMediaType = lastMsgMediaType
                chatThread.lastMsgStatus = .none
                chatThread.lastMsgTimestamp = chatMessage.timestamp
            } else {
                let chatThread = NSEntityDescription.insertNewObject(forEntityName: ChatThread.entity().name!, into: managedObjectContext) as! ChatThread
                chatThread.chatWithUserId = chatMessage.toUserId
                chatThread.lastMsgId = chatMessage.id
                chatThread.lastMsgUserId = chatMessage.fromUserId
                chatThread.lastMsgText = chatMessage.text
                chatThread.lastMsgMediaType = lastMsgMediaType
                chatThread.lastMsgStatus = .none
                chatThread.lastMsgTimestamp = chatMessage.timestamp
            }
        }
        
        save(managedObjectContext)

        DDLogInfo("ChatData/mergeSharedData/finished")
        
        sharedDataStore.delete(messages: messages) {
            completion()
        }
    }
    
    private func incrementApplicationIconBadgeNumber() {
        let badgeNum = MainAppContext.shared.applicationIconBadgeNumber
        MainAppContext.shared.applicationIconBadgeNumber = badgeNum == -1 ? 1 : badgeNum + 1
    }
    
    // MARK: Helpers
    
    private func isAtChatListViewTop() -> Bool {
        guard let keyWindow = UIApplication.shared.windows.filter({$0.isKeyWindow}).first else { return false }
        guard let topController = keyWindow.rootViewController else { return false }
        guard let homeView = topController as? UITabBarController else { return false }
        
        guard homeView.selectedIndex == (ServerProperties.isGroupFeedEnabled ? 2 : 1) else { return false }
        guard let navigationController = homeView.selectedViewController as? UINavigationController else { return false }
        guard let chatListViewController = navigationController.topViewController as? ChatListViewController else { return false }

        return chatListViewController.isScrolledFromTop(by: 100)
    }
}

extension ChatData {

    // MARK: Thread
    
    func markSeenMessages(type: ChatType, for id: String, in managedObjectContext: NSManagedObjectContext) {
        if type == .oneToOne {
            let unseenChatMsgs = unseenChatMessages(with: id, in: managedObjectContext)
            
            unseenChatMsgs.forEach {
                sendSeenReceipt(for: $0)
                $0.incomingStatus = ChatMessage.IncomingStatus.haveSeen
            }
        } else if type == .group {
            let unseenGroupChatMsgs = unseenChatGroupMessages(with: id, in: managedObjectContext)
            unseenGroupChatMsgs.forEach {
                sendSeenGroupReceipt(for: $0)
                $0.inboundStatus = ChatGroupMessage.InboundStatus.haveSeen
            }
        }
        
        if managedObjectContext.hasChanges {
            save(managedObjectContext)
        }
    }
    
    func setThreadUnreadFeedCount(type: ChatType, for id: String, num: Int32) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            
            if let chatThread = self.chatThread(type: type, id: id, in: managedObjectContext) {
                if chatThread.unreadFeedCount != num {
                    chatThread.unreadFeedCount = num
                }
            }

            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    func markThreadAsRead(type: ChatType, for id: String) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            
            if let chatThread = self.chatThread(type: type, id: id, in: managedObjectContext) {
                if chatThread.unreadCount != 0 {
                    chatThread.unreadCount = 0
                }

                if chatThread.isNew {
                    chatThread.isNew = false
                }
            }
            
            self.markSeenMessages(type: type, for: id, in: managedObjectContext)
            
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    func updateUnreadThreadGroupsCount() {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            let threads = self.chatThreads(predicate: NSPredicate(format: "unreadFeedCount > 0"), in: managedObjectContext)
            self.unreadThreadGroupsCount = Int(threads.count)
        }
    }

    func updateUnreadThreadCount() {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            let threads = self.chatThreads(predicate: NSPredicate(format: "unreadCount > 0"), in: managedObjectContext)
            self.unreadThreadCount = Int(threads.count)
        }
    }
    
    func updateUnreadMessageCount() {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            let threads = self.chatThreads(predicate: NSPredicate(format: "unreadCount > 0"), in: managedObjectContext)
            self.unreadMessageCount = Int(threads.reduce(0) { $0 + $1.unreadCount })
        }
    }
    
    func saveDraft(type: ChatType, for id: String, with draft: String?) {
        updateChatThread(type: type, for: id) { chatThread in
            guard chatThread.draft != draft else { return }
            chatThread.draft = draft
        }
    }

    //MARK: Thread Core Data Fetching
    
    private func chatThreads(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatThread] {
        let managedObjectContext = managedObjectContext ?? viewContext
        let fetchRequest: NSFetchRequest<ChatThread> = ChatThread.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false
        
        do {
            let chatThreads = try managedObjectContext.fetch(fetchRequest)
            return chatThreads
        }
        catch {
            DDLogError("ChatThread/fetch/error  [\(error)]")
            fatalError("Failed to fetch chat threads")
        }
    }
    
    func chatThread(type: ChatType, id: String, in managedObjectContext: NSManagedObjectContext? = nil) -> ChatThread? {
        if type == .group {
            return chatThreads(predicate: NSPredicate(format: "groupId == %@", id), in: managedObjectContext).first
        } else {
            return chatThreads(predicate: NSPredicate(format: "chatWithUserId == %@", id), in: managedObjectContext).first
        }
    }
    
    func chatThreadStatus(type: ChatType, id: String, messageId: String, in managedObjectContext: NSManagedObjectContext? = nil) -> ChatThread? {
        if type == .group {
            return chatThreads(predicate: NSPredicate(format: "groupId == %@ AND lastMsgId == %@", id, messageId), in: managedObjectContext).first
        } else {
            return chatThreads(predicate: NSPredicate(format: "chatWithUserId == %@ AND lastMsgId == %@", id, messageId), in: managedObjectContext).first
        }
    }
    
    // MARK: Thread Core Data Updating
    
    private func updateChatThread(type: ChatType, for id: String, block: @escaping (ChatThread) -> Void, performAfterSave: (() -> ())? = nil) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            defer {
                if let performAfterSave = performAfterSave {
                    performAfterSave()
                }
            }
            guard let self = self else { return }
            guard let chatThread = self.chatThread(type: type, id: id, in: managedObjectContext) else {
                DDLogError("ChatData/update-chatThread/missing-thread [\(id)]")
                return
            }
            block(chatThread)
            if managedObjectContext.hasChanges {
                DDLogVerbose("ChatData/update-chatThread [\(id)]")
                self.save(managedObjectContext)
            }
        }
    }
    
    private func updateChatThreadStatus(type: ChatType, for id: String, messageId: String, block: @escaping (ChatThread) -> Void) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            guard let chatThread = self.chatThreadStatus(type: type, id: id, messageId: messageId, in: managedObjectContext) else { return }
            DDLogVerbose("ChatData/updateChatThreadStatus found lastMsgID: [\(messageId)] in threadID: [\(id)]")
            block(chatThread)
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }

}

// MARK: Chat State
extension ChatData {
    
    public func sendChatState(type: ChatType, id: String, state: ChatState) {
        DDLogInfo("ChatData/sendChatState \(state) in \(id)")
        backgroundProcessingQueue.async {
            self.service.sendChatStateIfPossible(type: type, id: id, state: state)
        }
    }

    public func getTypingIndicatorString(type: ChatType, id: String?) -> String? {
        guard let id = id else { return nil }
        
        var typingStr = ""
        var chatStateList: [ChatStateInfo] = []
        
        switch type {
        case .oneToOne:
            chatStateList = chatStateInfoList.filter { $0.threadType == .oneToOne && $0.threadID == id }
            typingStr = Localizations.chatTyping
        case .group:
            chatStateList = chatStateInfoList.filter { $0.threadType == .group && $0.threadID == id }
        }
        
        guard chatStateList.count > 0 else { return nil }
        
        if type == .group {
            let numUser = chatStateList.count

            var firstNameList: [String] = []
            for typingUser in chatStateList {
                firstNameList.append(contactStore.firstName(for: typingUser.from))
            }
            
            let localizedFirstNameList = ListFormatter.localizedString(byJoining: firstNameList)

            let formatString = NSLocalizedString("chat.n.users.typing", comment: "Text showing all the users who are typing")
            return String.localizedStringWithFormat(formatString, localizedFirstNameList, numUser)
            
        }
        return typingStr
    }
    
    // used for inbound messages/presence, in case the other client is not resetting/sending their available status properly
    private func removeFromChatStateList(from: UserID, threadType: ChatType, threadID: String, type: ChatState) {
        let chatStateInfo = ChatStateInfo(from: from, threadType: threadType, threadID: threadID, type: type, timestamp: Date())
        processInboundChatStateInBg(chatStateInfo)
    }
    
    private func processInboundChatStateInBg(_ chatStateInfo: ChatStateInfo?) {
        backgroundProcessingQueue.async {
            self.processInboundChatState(chatStateInfo)
        }
    }
    
    private func processInboundChatState(_ chatStateInfo: ChatStateInfo?) {
        
        let timeToRecheck: TimeInterval = 25
        
        // remove old indicators
        chatStateInfoList.removeAll(where: {
            guard let timestamp = $0.timestamp else { return false }
            return abs(timestamp.timeIntervalSinceNow) >= Date.seconds(Int(timeToRecheck))
        })
        
        if let chatStateInfo = chatStateInfo {
            // remove indicators from the same user
            chatStateInfoList.removeAll(where: {
                $0.threadType == chatStateInfo.threadType && $0.threadID == chatStateInfo.threadID && $0.from == chatStateInfo.from
            })
            
            // add new typing indicator
            if chatStateInfo.type == .typing {
                chatStateInfoList.append(chatStateInfo)
            }
        }
        
        didGetChatStateInfo.send()
        
        chatStateDebounceTimer?.invalidate()
        
        guard chatStateInfoList.count > 0 else { return }
        
        chatStateDebounceTimer = Timer.scheduledTimer(withTimeInterval: timeToRecheck, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.processInboundChatState(nil)
        }
        
    }
        
    private func processInboundChatRetractInBg(_ chatRetractInfo: ChatRetractInfo) {

        backgroundProcessingQueue.asyncAfter(deadline: .now() + 1) {
            self.retractMsgIfFound(chatRetractInfo: chatRetractInfo, attemptsLeft: 3)
        }
                
    }
    
    
    private func retractMsgIfFound(chatRetractInfo: ChatRetractInfo, attemptsLeft: Int) {
        guard attemptsLeft > 0 else { return }
        DDLogInfo("ChatData/retractMsgIfFound/attemptsLeft: \(attemptsLeft)")
 
        switch chatRetractInfo.threadType {
        case .oneToOne:
            if chatMessage(with: chatRetractInfo.messageID, in: bgContext) != nil {
                processInboundChatMessageRetract(from: chatRetractInfo.from, messageID: chatRetractInfo.messageID)
                return
            }
        case .group:
            if chatGroupMessage(with: chatRetractInfo.messageID, in: bgContext) != nil {
                processInboundGroupChatMessageRetract(groupID: chatRetractInfo.threadID, messageID: chatRetractInfo.messageID)
                return
            }
        }
        
        backgroundProcessingQueue.asyncAfter(deadline: .now() + 3) {
            self.retractMsgIfFound(chatRetractInfo: chatRetractInfo, attemptsLeft: attemptsLeft - 1)
        }
        
    }
    
}

// MARK: 1-1
extension ChatData {
    
    func setCurrentlyChattingWithUserId(for chatWithUserId: String?) {
        currentlyChattingWithUserId = chatWithUserId
        isSubscribedToCurrentUser = false
    }
            
    // MARK: 1-1 Sending Messages
    
    func sendMessage(toUserId: String,
                     text: String,
                     media: [PendingMedia],
                     feedPostId: String?,
                     feedPostMediaIndex: Int32,
                     chatReplyMessageID: String? = nil,
                     chatReplyMessageSenderID: UserID? = nil,
                     chatReplyMessageMediaIndex: Int32) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            self.createChatMsg(toUserId: toUserId,
                                                       text: text,
                                                       media: media,
                                                       feedPostId: feedPostId,
                                                       feedPostMediaIndex: feedPostMediaIndex,
                                                       chatReplyMessageID: chatReplyMessageID,
                                                       chatReplyMessageSenderID: chatReplyMessageSenderID,
                                                       chatReplyMessageMediaIndex: chatReplyMessageMediaIndex)
        }
    }
    
    func createChatMsg(toUserId: String,
                     text: String,
                     media: [PendingMedia],
                     feedPostId: String?,
                     feedPostMediaIndex: Int32,
                     chatReplyMessageID: String? = nil,
                     chatReplyMessageSenderID: UserID? = nil,
                     chatReplyMessageMediaIndex: Int32) {
        
        let messageId = UUID().uuidString
        let isMsgToYourself: Bool = toUserId == userData.userId
        
        // Create and save new ChatMessage object.
        DDLogDebug("ChatData/createChatMsg/\(messageId)")
        let chatMessage = ChatMessage(context: bgContext)
        chatMessage.id = messageId
        chatMessage.toUserId = toUserId
        chatMessage.fromUserId = userData.userId
        chatMessage.text = text
        chatMessage.feedPostId = feedPostId
        chatMessage.feedPostMediaIndex = feedPostMediaIndex
        chatMessage.chatReplyMessageID = chatReplyMessageID
        chatMessage.chatReplyMessageSenderID = chatReplyMessageSenderID
        chatMessage.chatReplyMessageMediaIndex = chatReplyMessageMediaIndex
        chatMessage.incomingStatus = .none
        chatMessage.outgoingStatus = isMsgToYourself ? .seen : .pending
        chatMessage.timestamp = Date()

        var lastMsgMediaType: ChatThread.LastMediaType = .none // going with the first media
        
        for (index, mediaItem) in media.enumerated() {
            DDLogDebug("ChatData/createChatMsg/\(messageId)/add-media [\(mediaItem)]")
            guard let mediaItemSize = mediaItem.size,
                  let mediaItemKey = mediaItem.key,
                  let mediaItemSha256 = mediaItem.sha256,
                  let mediaItemfileURL = mediaItem.fileURL else {
                DDLogDebug("ChatData/createChatMsg/\(messageId)/add-media/skip/missing info")
                continue
            }
                  
            let chatMedia = ChatMedia(context: bgContext)
            switch mediaItem.type {
            case .image:
                chatMedia.type = .image
                if lastMsgMediaType == .none {
                    lastMsgMediaType = .image
                }
            case .video:
                chatMedia.type = .video
                if lastMsgMediaType == .none {
                    lastMsgMediaType = .video
                }
            }
            chatMedia.outgoingStatus = isMsgToYourself ? .uploaded : .pending
            chatMedia.url = mediaItem.url
            chatMedia.uploadUrl = mediaItem.uploadUrl
            chatMedia.size = mediaItemSize
            chatMedia.key = mediaItemKey
            chatMedia.sha256 = mediaItemSha256
            chatMedia.order = Int16(index)
            chatMedia.message = chatMessage

            do {
                try copyFiles(toChatMedia: chatMedia, fileUrl: mediaItemfileURL, encryptedFileUrl: mediaItem.encryptedFileUrl)
            }
            catch {
                DDLogError("ChatData/createChatMsg/\(messageId)/copy-media/error [\(error)]")
            }
        }
        
        // Create and save Quoted FeedPost
        if let feedPostId = feedPostId, let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId) {
            let quoted = ChatQuoted(context: bgContext)
            quoted.type = .feedpost
            quoted.userId = feedPost.userId
            quoted.text = feedPost.text
            quoted.message = chatMessage

            quoted.mentions = {
                guard let feedMentions = feedPost.mentions, !feedMentions.isEmpty else { return nil }
                var chatMentions = Set<ChatMention>()
                for feedMention in feedMentions {
                    let chatMention = ChatMention(context: bgContext)
                    chatMention.index = feedMention.index
                    chatMention.userID = feedMention.userID
                    chatMention.name = feedMention.name
                    chatMentions.insert(chatMention)
                }
                return chatMentions
            }()

            if let feedPostMedia = feedPost.media?.first(where: { $0.order == feedPostMediaIndex }) {
                let quotedMedia = ChatQuotedMedia(context: bgContext)
                if feedPostMedia.type == .image {
                    quotedMedia.type = .image
                } else {
                    quotedMedia.type = .video
                }
                quotedMedia.order = feedPostMedia.order
                quotedMedia.width = Float(feedPostMedia.size.width)
                quotedMedia.height = Float(feedPostMedia.size.height)
                quotedMedia.quoted = quoted

                do {
                    try copyMediaToQuotedMedia(fromDir: MainAppContext.mediaDirectoryURL, fromPath: feedPostMedia.relativeFilePath, to: quotedMedia)
                }
                catch {
                    DDLogError("ChatData/createChatMsg/\(messageId)/quoted/copy-media/error [\(error)]")
                }
            }
        }
        
        if let chatReplyMessageID = chatReplyMessageID,
           let chatReplyMessageSenderID = chatReplyMessageSenderID,
           let quotedChatMessage = self.chatMessage(with: chatReplyMessageID, in: bgContext) {
            
            let quoted = ChatQuoted(context: bgContext)
            quoted.type = .message
            quoted.userId = chatReplyMessageSenderID
            quoted.text = quotedChatMessage.text
            quoted.message = chatMessage

            if let quotedChatMessageMedia = quotedChatMessage.media?.first(where: { $0.order == chatReplyMessageMediaIndex }) {
                let quotedMedia = ChatQuotedMedia(context: bgContext)
                if quotedChatMessageMedia.type == .image {
                    quotedMedia.type = .image
                } else {
                    quotedMedia.type = .video
                }
                quotedMedia.order = quotedChatMessageMedia.order
                quotedMedia.width = Float(quotedChatMessageMedia.size.width)
                quotedMedia.height = Float(quotedChatMessageMedia.size.height)
                quotedMedia.quoted = quoted

                do {
                    try copyMediaToQuotedMedia(fromDir: MainAppContext.chatMediaDirectoryURL, fromPath: quotedChatMessageMedia.relativeFilePath, to: quotedMedia)
                }
                catch {
                    DDLogError("ChatData/createChatMsg/\(messageId)/quoted/copy-media/error [\(error)]")
                }
            }
        }
        
        // Update Chat Thread
        if let chatThread = self.chatThread(type: ChatType.oneToOne, id: chatMessage.toUserId, in: bgContext) {
            DDLogDebug("ChatData/createChatMsg/ update-thread")
            chatThread.lastMsgId = chatMessage.id
            chatThread.lastMsgUserId = chatMessage.fromUserId
            chatThread.lastMsgText = chatMessage.text
            chatThread.lastMsgMediaType = lastMsgMediaType
            chatThread.lastMsgStatus = isMsgToYourself ? .seen : .pending
            chatThread.lastMsgTimestamp = chatMessage.timestamp
        } else {
            DDLogDebug("ChatData/createChatMsg/\(messageId)/new-thread")
            let chatThread = ChatThread(context: bgContext)
            chatThread.chatWithUserId = chatMessage.toUserId
            chatThread.lastMsgId = chatMessage.id
            chatThread.lastMsgUserId = chatMessage.fromUserId
            chatThread.lastMsgText = chatMessage.text
            chatThread.lastMsgMediaType = lastMsgMediaType
            chatThread.lastMsgStatus = isMsgToYourself ? .seen : .pending
            chatThread.lastMsgTimestamp = chatMessage.timestamp
            chatThread.unreadCount = 0
        }
        
        save(bgContext)

        if !isMsgToYourself {
            let xmppChatMsg = XMPPChatMessage(chatMessage: chatMessage)
            uploadChatMsgMediaAndSend(xmppChatMsg)
        }
    }

    private func uploadChatMsgMediaAndSend(_ xmppChatMsg: XMPPChatMessage) {
        let msgID = xmppChatMsg.id
        
        guard let chatMsg = chatMessage(with: msgID, in: bgContext) else { return }
        
        // Either all media has already been uploaded or post does not contain media.
        guard let mediaItemsToUpload = chatMsg.media?.filter({ $0.outgoingStatus == .none || $0.outgoingStatus == .pending || $0.outgoingStatus == .error }), !mediaItemsToUpload.isEmpty else {
            send(message: XMPPChatMessage(chatMessage: chatMsg))
            return
        }
        
        var numberOfFailedUploads = 0
        let totalUploads = mediaItemsToUpload.count
        DDLogInfo("ChatData/upload-media/\(msgID)/starting [\(totalUploads)]")

        let uploadGroup = DispatchGroup()
        for mediaItem in mediaItemsToUpload {
            let mediaIndex = mediaItem.order
            uploadGroup.enter()
            mediaUploader.upload(media: mediaItem, groupId: msgID, didGetURLs: { (mediaURLs) in
                DDLogInfo("ChatData/upload-media/\(msgID)/\(mediaIndex)/acquired-urls [\(mediaURLs)]")

                // Save URLs acquired during upload to the database.
                self.updateChatMessage(with: msgID) { msg in
                    guard let media = msg.media?.first(where: { $0.order == mediaIndex }) else { return }
                    
                    switch mediaURLs {
                    case .getPut(let getURL, let putURL):
                        media.url = getURL
                        media.uploadUrl = putURL
                    case .patch(let patchURL):
                        media.uploadUrl = patchURL
                    }
                    
                }
            }) { (uploadResult) in
                DDLogInfo("ChatData/upload-media/\(msgID)/\(mediaIndex)/finished result=[\(uploadResult)]")

                // Save URLs acquired during upload to the database.
                self.updateChatMessage(with: msgID, block: { msg in
                    guard let media = msg.media?.first(where: { $0.order == mediaIndex }) else { return }
                    
                    switch uploadResult {
                    case .success(let url):
                        media.url = url
                        media.outgoingStatus = .uploaded
                    case .failure(_):
                        numberOfFailedUploads += 1
                        media.outgoingStatus = .error
                    }
                    
                }, performAfterSave: {
                    uploadGroup.leave()
                })
            }
        }

        uploadGroup.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            DDLogInfo("ChatData/upload-media/\(msgID)/all/finished [\(totalUploads-numberOfFailedUploads)/\(totalUploads)]")
            if numberOfFailedUploads > 0 {
                self.updateChatMessage(with: msgID) { msg in
                    msg.outgoingStatus = .error
                }
            } else {
                self.send(message: XMPPChatMessage(chatMessage: chatMsg))
            }
        }
    }

    private func send(message: ChatMessageProtocol) {
        service.sendChatMessage(message, encryption: AppContext.shared.encryptOperation(for: message.toUserId)) { _ in }
    }

    private func handleRerequest(for messageID: String, from userID: UserID) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            guard let chatMessage = self.chatMessage(with: messageID, in: managedObjectContext) else {
                DDLogError("ChatData/handleRerequest/\(messageID)/error could not find message")
                return
            }
            guard userID == chatMessage.toUserId else {
                DDLogError("ChatData/handleRerequest/\(messageID)/error user mismatch [original: \(chatMessage.toUserId)] [rerequest: \(userID)]")
                return
            }
            guard chatMessage.resendAttempts < 5 else {
                DDLogInfo("ChatData/handleRerequest/\(messageID)/skipping (\(chatMessage.resendAttempts) resend attempts)")
                return
            }
            chatMessage.resendAttempts += 1

            let xmppChatMessage = XMPPChatMessage(chatMessage: chatMessage)
            self.backgroundProcessingQueue.async {
                self.send(message: xmppChatMessage)
            }

            self.save(managedObjectContext)
        }
    }

    func retractChatMessage(toUserID: UserID, messageToRetractID: String) {
        let messageID = UUID().uuidString
                
        updateChatMessage(with: messageToRetractID) { [weak self] (chatMessage) in
            guard let self = self else { return }
            guard [.sentOut, .delivered, .seen].contains(chatMessage.outgoingStatus) else { return }
            
            chatMessage.retractID = messageID
            chatMessage.outgoingStatus = .retracting
            
            self.deleteChatMessageContent(in: chatMessage)
            
            self.updateChatThreadStatus(type: .oneToOne, for: chatMessage.toUserId, messageId: chatMessage.id) { (chatThread) in
                chatThread.lastMsgStatus = .retracting
                chatThread.lastMsgText = nil
                chatThread.lastMsgMediaType = .none
            }
            
        }
                
        self.service.retractChatMessage(messageID: messageID, toUserID: toUserID, messageToRetractID: messageToRetractID)
        
    }
    
    // MARK: 1-1 Core Data Fetching
    
    private func chatMessages(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatMessage] {
        let managedObjectContext = managedObjectContext ?? self.viewContext
        let fetchRequest: NSFetchRequest<ChatMessage> = ChatMessage.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false
        
        do {
            let chatMessages = try managedObjectContext.fetch(fetchRequest)
            return chatMessages
        }
        catch {
            DDLogError("ChatData/fetch-messages/error  [\(error)]")
            fatalError("Failed to fetch chat messages")
        }
    }
    
    func chatMessage(with id: String, in managedObjectContext: NSManagedObjectContext? = nil) -> ChatMessage? {
        return self.chatMessages(predicate: NSPredicate(format: "id == %@", id), in: managedObjectContext).first
    }
    
    // includes seen but not sent messages
    func unseenChatMessages(with fromUserId: String, in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true)
        ]
        return self.chatMessages(predicate: NSPredicate(format: "fromUserId = %@ && toUserId = %@ && (incomingStatusValue = %d OR incomingStatusValue = %d)", fromUserId, userData.userId, ChatMessage.IncomingStatus.none.rawValue, ChatMessage.IncomingStatus.haveSeen.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }
    
    func pendingOutgoingChatMessages(in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true)
        ]
        return chatMessages(predicate: NSPredicate(format: "fromUserId = %@ && outgoingStatusValue = %d", userData.userId, ChatMessage.OutgoingStatus.pending.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }
    
    func retractingOutboundChatMsgs(in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatGroupMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatGroupMessage.timestamp, ascending: true)
        ]
        return chatGroupMessages(predicate: NSPredicate(format: "outboundStatusValue = %d", ChatMessage.OutgoingStatus.retracting.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }
    
    func pendingOutgoingSeenReceipts(in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true)
        ]
        return chatMessages(predicate: NSPredicate(format: "fromUserId = %@ && incomingStatusValue = %d", userData.userId, ChatMessage.IncomingStatus.haveSeen.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }
    
    func pendingIncomingChatMessagesMedia(in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true)
        ]
        return chatMessages(predicate: NSPredicate(format: "ANY media.incomingStatusValue == %d", ChatMedia.IncomingStatus.pending.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }
    
    // MARK: 1-1 Core Data Updating
    
    private func updateChatMessage(with chatMessageId: String, block: @escaping (ChatMessage) -> (), performAfterSave: (() -> ())? = nil) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            defer {
                if let performAfterSave = performAfterSave {
                    performAfterSave()
                }
            }
            guard let self = self else { return }
            guard let chatMessage = self.chatMessage(with: chatMessageId, in: managedObjectContext) else {
                DDLogError("ChatData/update-message/missing [\(chatMessageId)]")
                return
            }
            DDLogVerbose("ChatData/update-message [\(chatMessageId)]")
            block(chatMessage)
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    private func updateChatMessageByStatus(for id: String, status: ChatMessage.OutgoingStatus, block: @escaping (ChatMessage) -> ()) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            let sortDescriptors = [
                NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true)
            ]
            guard let chatMessage = self.chatMessages(predicate: NSPredicate(format: "outgoingStatusValue = %d && id == %@", status.rawValue, id), sortDescriptors: sortDescriptors, in: managedObjectContext).first else {
                return
            }
            
            DDLogVerbose("ChatData/updateChatMessageByStatus [\(id)]")
            block(chatMessage)
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    private func updateRetractingChatMessage(for id: String, block: @escaping (ChatMessage) -> ()) {

        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            let sortDescriptors = [
                NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true)
            ]
            guard let chatMessage = self.chatMessages(predicate: NSPredicate(format: "outgoingStatusValue = %d && retractID == %@", ChatMessage.OutgoingStatus.retracting.rawValue, id), sortDescriptors: sortDescriptors, in: managedObjectContext).first else {
                return
            }
            
            DDLogVerbose("ChatData/updateRetractingChatMessage [\(id)]")
            block(chatMessage)
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    public func updateChatMessageCellHeight(for chatMessageId: String, with cellHeight: Int) {
        updateChatMessage(with: chatMessageId) { (chatMessage) in
            chatMessage.cellHeight = Int16(cellHeight)
        }
    }
        
    // MARK: 1-1 Core Data Deleting

    func deleteChat(chatThreadId: String) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            // delete thread
            if let chatThread = self.chatThread(type: ChatType.oneToOne, id: chatThreadId, in: managedObjectContext) {
                managedObjectContext.delete(chatThread)
            }
            
            let fetchRequest = NSFetchRequest<ChatMessage>(entityName: ChatMessage.entity().name!)
            // TODO: eventually use a chatId instead of a confusing match
            fetchRequest.predicate = NSPredicate(format: "(fromUserId = %@ AND toUserId = %@) || (toUserId = %@ && fromUserId = %@)", chatThreadId, MainAppContext.shared.userData.userId, chatThreadId, AppContext.shared.userData.userId)
            
            do {
                let chatMessages = try managedObjectContext.fetch(fetchRequest)
                DDLogInfo("ChatData/delete-messages/begin count=[\(chatMessages.count)]")
                chatMessages.forEach {
                    self.deleteMedia(in: $0)
                    managedObjectContext.delete($0)
                }
                DDLogInfo("ChatData/delete-messages/finished")
            }
            catch {
                DDLogError("ChatData/delete-messages/error  [\(error)]")
                return
            }
            self.save(managedObjectContext)
            
            DispatchQueue.main.async { [weak self] in
                self?.populateThreadsWithSymmetricContacts()
            }
        }
    }
    
    private func deleteChatMessageContent(in chatMessage: ChatMessage) {
        DDLogDebug("ChatData/deleteChatMessageContent/message \(chatMessage.id) ")
        
        chatMessage.text = nil
        
        chatMessage.feedPostId = nil
        chatMessage.feedPostMediaIndex = 0
        
        chatMessage.chatReplyMessageID = nil
        chatMessage.chatReplyMessageSenderID = nil
        chatMessage.chatReplyMessageMediaIndex = 0
        
        self.deleteMedia(in: chatMessage)
        chatMessage.media = nil
        chatMessage.quoted = nil
    }
    
    private func deleteMedia(in chatMessage: ChatMessage) {
        DDLogDebug("ChatData/deleteMedia/message \(chatMessage.id) ")
        chatMessage.media?.forEach { (media) in
            if media.relativeFilePath != nil {
                let fileURL = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(media.relativeFilePath!, isDirectory: false)
                do {
                    DDLogDebug("ChatData/deleteMedia ")
                    try FileManager.default.removeItem(at: fileURL)
                }
                catch {
                    DDLogError("ChatData/deleteMedia/error [\(error)]")
                }
            }
            chatMessage.managedObjectContext?.delete(media)
        }
        
        if let quoted = chatMessage.quoted {
            DDLogDebug("ChatData/deleteMedia/quoted ")
            if let quotedMedia = quoted.media {
                quotedMedia.forEach { (media) in
                    if media.relativeFilePath != nil {
                        let fileURL = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(media.relativeFilePath!, isDirectory: false)
                        do {
                            DDLogDebug("ChatData/deleteMedia/quoted/media ")
                            try FileManager.default.removeItem(at: fileURL)
                        }
                        catch {
                            DDLogError("ChatData/deleteMedia/quoted/media/error [\(error)]")
                        }
                    }
                    quoted.managedObjectContext?.delete(media)
                }
            }
            chatMessage.managedObjectContext?.delete(quoted)
        }
    }
    
}

extension ChatData {

    // MARK: 1-1 Process Inbound Messages
    
    private func processInboundXMPPChatMessage(_ chatMessage: ChatMessageProtocol) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let isAppActive = UIApplication.shared.applicationState == .active
            
            self.performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
                guard let self = self else { return }
                self.processInboundChatMessage(xmppChatMessage: chatMessage, using: managedObjectContext, isAppActive: isAppActive)
            }
        }
    }
    
    private func processInboundChatMessage(xmppChatMessage: ChatMessageProtocol, using managedObjectContext: NSManagedObjectContext, isAppActive: Bool) {
        guard self.chatMessage(with: xmppChatMessage.id, in: managedObjectContext) == nil else {
            // This is expected if we rerequest a message where decryption failed but a plaintext version was included
            DDLogInfo("ChatData/process/already-exists [\(xmppChatMessage.id)]")
            return
        }
        
        var isCurrentlyChattingWithUser = false
        
        if let currentlyChattingWithUserId = self.currentlyChattingWithUserId {
            if xmppChatMessage.fromUserId == currentlyChattingWithUserId {
                isCurrentlyChattingWithUser = true
            }
        }
        
        // Add new ChatMessage to database.
        DDLogDebug("ChatData/process/new [\(xmppChatMessage.id)]")
        let chatMessage = NSEntityDescription.insertNewObject(forEntityName: ChatMessage.entity().name!, into: managedObjectContext) as! ChatMessage
        chatMessage.id = xmppChatMessage.id
        chatMessage.toUserId = xmppChatMessage.toUserId
        chatMessage.fromUserId = xmppChatMessage.fromUserId
        chatMessage.text = xmppChatMessage.text
        chatMessage.feedPostId = xmppChatMessage.feedPostId
        chatMessage.feedPostMediaIndex = xmppChatMessage.feedPostMediaIndex
        
        chatMessage.chatReplyMessageID = xmppChatMessage.chatReplyMessageID
        chatMessage.chatReplyMessageSenderID = xmppChatMessage.chatReplyMessageSenderID
        chatMessage.chatReplyMessageMediaIndex = xmppChatMessage.chatReplyMessageMediaIndex
        
        chatMessage.incomingStatus = .none
        chatMessage.outgoingStatus = .none
        
        if let ts = xmppChatMessage.timeIntervalSince1970 {
            chatMessage.timestamp = Date(timeIntervalSince1970: ts)
        } else {
            chatMessage.timestamp = Date()
        }
        
        var lastMsgMediaType: ChatThread.LastMediaType = .none // going with the first media found
        
        // Process chat media
        for (index, xmppMedia) in xmppChatMessage.orderedMedia.enumerated() {
            guard let downloadUrl = xmppMedia.url else { continue }
            
            DDLogDebug("ChatData/process/new/add-media [\(downloadUrl)]")
            let chatMedia = NSEntityDescription.insertNewObject(forEntityName: ChatMedia.entity().name!, into: managedObjectContext) as! ChatMedia

            switch xmppMedia.mediaType {
            case .image:
                chatMedia.type = .image
                if lastMsgMediaType == .none {
                    lastMsgMediaType = .image
                }
            case .video:
                chatMedia.type = .video
                if lastMsgMediaType == .none {
                    lastMsgMediaType = .video
                }
            }
            chatMedia.incomingStatus = .pending
            chatMedia.outgoingStatus = .none
            chatMedia.url = xmppMedia.url
            chatMedia.size = xmppMedia.size
            chatMedia.key = xmppMedia.key
            chatMedia.order = Int16(index)
            chatMedia.sha256 = xmppMedia.sha256
            chatMedia.message = chatMessage
        }
        
        // Process Quoted Feedpost
        if xmppChatMessage.feedPostId != nil {
            if let feedPost = MainAppContext.shared.feedData.feedPost(with: xmppChatMessage.feedPostId!) {
                let quoted = NSEntityDescription.insertNewObject(forEntityName: ChatQuoted.entity().name!, into: managedObjectContext) as! ChatQuoted
                quoted.type = .feedpost
                quoted.userId = feedPost.userId
                quoted.text = feedPost.text
                quoted.message = chatMessage

                quoted.mentions = {
                    guard let feedMentions = feedPost.mentions, !feedMentions.isEmpty else { return nil }
                    var chatMentions = Set<ChatMention>()
                    for feedMention in feedMentions {
                        let chatMention = NSEntityDescription.insertNewObject(forEntityName: ChatMention.entity().name!, into: managedObjectContext) as! ChatMention
                        chatMention.index = feedMention.index
                        chatMention.userID = feedMention.userID
                        chatMention.name = feedMention.name
                        chatMentions.insert(chatMention)
                    }
                    return chatMentions
                }()
                
                if feedPost.media != nil {
                    if let feedPostMedia = feedPost.media!.first(where: { $0.order == xmppChatMessage.feedPostMediaIndex}) {
                        let quotedMedia = NSEntityDescription.insertNewObject(forEntityName: ChatQuotedMedia.entity().name!, into: managedObjectContext) as! ChatQuotedMedia
                        if feedPostMedia.type == .image {
                            quotedMedia.type = .image
                        } else {
                            quotedMedia.type = .video
                        }
                        quotedMedia.order = feedPostMedia.order
                        quotedMedia.width = Float(feedPostMedia.size.width)
                        quotedMedia.height = Float(feedPostMedia.size.height)
                        quotedMedia.quoted = quoted
                        do {
                            try copyMediaToQuotedMedia(fromDir: MainAppContext.mediaDirectoryURL, fromPath: feedPostMedia.relativeFilePath, to: quotedMedia)
                        }
                        catch {
                            DDLogError("ChatData/new-msg/quoted/copy-media/error [\(error)]")
                        }
                    }
                }
            }
        }
        
        // Process Quoted Message
        if xmppChatMessage.chatReplyMessageID != nil {
            
            if let quotedChatMessage = MainAppContext.shared.chatData.chatMessage(with: xmppChatMessage.chatReplyMessageID!) {
                let quoted = NSEntityDescription.insertNewObject(forEntityName: ChatQuoted.entity().name!, into: managedObjectContext) as! ChatQuoted
                quoted.type = .message
                quoted.userId = quotedChatMessage.fromUserId
                quoted.text = quotedChatMessage.text
                quoted.message = chatMessage

                if quotedChatMessage.media != nil {
                    if let quotedChatMessageMedia = quotedChatMessage.media!.first(where: { $0.order == xmppChatMessage.chatReplyMessageMediaIndex}) {
                        let quotedMedia = NSEntityDescription.insertNewObject(forEntityName: ChatQuotedMedia.entity().name!, into: managedObjectContext) as! ChatQuotedMedia
                        if quotedChatMessageMedia.type == .image {
                            quotedMedia.type = .image
                        } else {
                            quotedMedia.type = .video
                        }
                        quotedMedia.order = quotedChatMessageMedia.order
                        quotedMedia.width = Float(quotedChatMessageMedia.size.width)
                        quotedMedia.height = Float(quotedChatMessageMedia.size.height)
                        quotedMedia.quoted = quoted
                        do {
                            try copyMediaToQuotedMedia(fromDir: MainAppContext.chatMediaDirectoryURL, fromPath: quotedChatMessageMedia.relativeFilePath, to: quotedMedia)
                        }
                        catch {
                            DDLogError("ChatData/new-msg/quoted/copy-media/error [\(error)]")
                        }
                    }
                }
            }
        }
        
        // Update Chat Thread
        if let chatThread = self.chatThread(type: ChatType.oneToOne, id: chatMessage.fromUserId, in: managedObjectContext) {
            chatThread.lastMsgId = chatMessage.id
            chatThread.lastMsgUserId = chatMessage.fromUserId
            chatThread.lastMsgText = chatMessage.text
            chatThread.lastMsgMediaType = lastMsgMediaType
            chatThread.lastMsgStatus = .none
            chatThread.lastMsgTimestamp = chatMessage.timestamp
            chatThread.unreadCount = isCurrentlyChattingWithUser ? 0 : chatThread.unreadCount + 1
        } else {
            let chatThread = NSEntityDescription.insertNewObject(forEntityName: ChatThread.entity().name!, into: managedObjectContext) as! ChatThread
            chatThread.chatWithUserId = chatMessage.fromUserId
            chatThread.lastMsgId = chatMessage.id
            chatThread.lastMsgUserId = chatMessage.fromUserId
            chatThread.lastMsgText = chatMessage.text
            chatThread.lastMsgMediaType = lastMsgMediaType
            chatThread.lastMsgStatus = .none
            chatThread.lastMsgTimestamp = chatMessage.timestamp
            chatThread.unreadCount = 1
        }
        
        self.save(managedObjectContext)
        
        if isCurrentlyChattingWithUser && isAppActive {
            self.sendSeenReceipt(for: chatMessage)
            self.updateChatMessage(with: chatMessage.id) { (chatMessage) in
                chatMessage.incomingStatus = .haveSeen
            }
        } else {
            self.unreadMessageCount += 1
            self.updateUnreadThreadCount()
        }
        
        // 1 and higher means it's an offline message and that server has sent out a push notification already
        if xmppChatMessage.retryCount == nil || xmppChatMessage.retryCount == 0 {
            showOneToOneNotification(for: xmppChatMessage)
        }
        
        // download chat message media
        processInboundPendingChatMsgMedia()
        
        // remove user from typing state
        removeFromChatStateList(from: xmppChatMessage.fromUserId, threadType: .oneToOne, threadID: xmppChatMessage.fromUserId, type: .available)
    }
    
    // MARK: 1-1 Process Inbound Receipts
    
    private func processInboundOneToOneMessageReceipt(with receipt: XMPPReceipt) {
        DDLogInfo("ChatData/processInboundOneToOneMessageReceipt")
        let messageId = receipt.itemId
        let receiptType = receipt.type
        
        updateChatMessage(with: messageId) { [weak self] (chatMessage) in
            guard let self = self else { return }
            guard ![.seen, .retracting, .retracted].contains(chatMessage.outgoingStatus) else { return }
            
            if receiptType == .delivery {
                chatMessage.outgoingStatus = .delivered
                
                self.updateChatThreadStatus(type: .oneToOne, for: chatMessage.toUserId, messageId: chatMessage.id) { (chatThread) in
                    chatThread.lastMsgStatus = .delivered
                }
                
            } else if receiptType == .read {
                chatMessage.outgoingStatus = .seen
                
                self.updateChatThreadStatus(type: .oneToOne, for: chatMessage.toUserId, messageId: chatMessage.id) { (chatThread) in
                    chatThread.lastMsgStatus = .seen
                }
            }
            
        }
    }
    
    // MARK: 1-1 Process Inbound Retract Message
    
    private func processInboundChatMessageRetract(from: UserID, messageID: String) {
        DDLogInfo("ChatData/processInboundChatMessageRetract")

        updateChatMessage(with: messageID) { [weak self] (chatMessage) in
            guard let self = self else { return }
            
            chatMessage.incomingStatus = .retracted
            
            self.deleteChatMessageContent(in: chatMessage)

            self.updateChatThreadStatus(type: .oneToOne, for: from, messageId: messageID) { (chatThread) in
                chatThread.lastMsgStatus = .retracted

                chatThread.lastMsgText = nil
                chatThread.lastMsgMediaType = .none
            }

        }
    }
}
    
extension ChatData {

    // MARK: 1-1 Presence
    
    func subscribeToPresence(to chatWithUserId: String) {
        guard !self.isSubscribedToCurrentUser else { return }
        self.isSubscribedToCurrentUser = service.subscribeToPresenceIfPossible(to: chatWithUserId)
    }
    
    private func sendPresence(type: PresenceType) {
        MainAppContext.shared.service.sendPresenceIfPossible(type)
    }
    
    // MARK: 1-1 Process Inbound Presence
    
    private func processIncomingPresence(_ presenceInfo: ChatPresenceInfo) {

        var presenceStatus = UserPresenceType.none
        var presenceLastSeen: Date?
        
        if let status = presenceInfo.presence {
            if status == .away {
                presenceStatus = UserPresenceType.away
                presenceLastSeen = presenceInfo.lastSeen
            } else if status == .available {
                presenceStatus = UserPresenceType.available
                presenceLastSeen = presenceInfo.lastSeen
            }
        }
                
        // notify chatViewController
        guard let currentlyChattingWithUserId = self.currentlyChattingWithUserId else { return }
        guard currentlyChattingWithUserId == presenceInfo.userID else { return }
        didGetCurrentChatPresence.send((presenceStatus, presenceLastSeen))
        
        // remove user from typing state
        if presenceInfo.presence == .away {
            removeFromChatStateList(from: currentlyChattingWithUserId, threadType: .oneToOne, threadID: currentlyChattingWithUserId, type: .available)
        }
    }
}

// MARK: OneToOne - Process Pending Tasks
extension ChatData {
    
    private func processPendingChatMsgs() {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            let pendingOutgoingChatMessages = self.pendingOutgoingChatMessages(in: managedObjectContext)
            DDLogInfo("ChatData/processPendingChatMsgs/num: \(pendingOutgoingChatMessages.count)")

            // inject delay between batch sends so that they won't be timestamped the same time,
            // which causes display of messages to be in mixed order
            var timeDelay = 0.0
            pendingOutgoingChatMessages.forEach {
                DDLogInfo("ChatData/processPendingChatMsgs/msg \($0.id)")
                let xmppChatMsg = XMPPChatMessage(chatMessage: $0)
                self.backgroundProcessingQueue.asyncAfter(deadline: .now() + timeDelay) { [weak self] in
                    guard let self = self else { return }
                    self.uploadChatMsgMediaAndSend(xmppChatMsg)
                }
                timeDelay += 1.0
            }
        }
    }
    
    private func processRetractingChatMsgs() {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            let retractingOutboundChatMsgs = self.retractingOutboundChatMsgs(in: managedObjectContext)
            DDLogInfo("ChatData/processRetractingChatMsgs/num: \(retractingOutboundChatMsgs.count)")

            retractingOutboundChatMsgs.forEach {
                guard let chatMsg = self.chatMessage(with: $0.id) else { return }
                guard let messageID = chatMsg.retractID else { return }
                DDLogInfo("ChatData/processRetractingChatMsgs \($0.id)")
                let toUserID = chatMsg.toUserId
                let msgToRetractID = chatMsg.id

                self.service.retractChatMessage(messageID: messageID, toUserID: toUserID, messageToRetractID: msgToRetractID)
            }
        }
    }
    
    private func processPendingSeenReceipts() {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            let pendingOutgoingSeenReceipts = self.pendingOutgoingSeenReceipts(in: managedObjectContext)
            DDLogInfo("ChatData/processPendingSeenReceipts/num: \(pendingOutgoingSeenReceipts.count)")
            
            pendingOutgoingSeenReceipts.forEach {
                DDLogInfo("ChatData/processPendingSeenReceipts/seenReceipts \($0.id)")
                self.sendSeenReceipt(for: $0)
            }
        }
    }
}

// MARK: 1-1 Local Notifications
extension ChatData {
    
    private func showOneToOneNotification(for xmppChatMessage: ChatMessageProtocol) {
        DDLogVerbose("ChatData/showOneToOneNotification")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch UIApplication.shared.applicationState {
            case .background, .inactive:
                self.presentLocalOneToOneNotifications(for: xmppChatMessage)
            case .active:
                guard !self.isAtChatListViewTop() else {
                    DDLogVerbose("ChatData/showOneToOneNotification/isAtChatListViewTop/skip")
                    return
                }
                guard self.currentlyChattingWithUserId != xmppChatMessage.fromUserId else {
                    DDLogVerbose("ChatData/showOneToOneNotification/currentlyChattingWithUserId/skip")
                    return
                }
                self.presentOneToOneBanner(for: xmppChatMessage)
            @unknown default:
                self.presentLocalOneToOneNotifications(for: xmppChatMessage)
            }
        }
    }
    
    private func presentOneToOneBanner(for xmppChatMessage: ChatMessageProtocol) {
        DDLogDebug("ChatData/presentOneToOneBanner")
        let userID = xmppChatMessage.fromUserId
        
        let name = contactStore.fullName(for: userID)
        
        let title = "\(name)"
        
        var body = ""
        
        body += xmppChatMessage.text ?? ""
        
        if !xmppChatMessage.orderedMedia.isEmpty {
            var mediaStr = "📷"
            if let firstMedia = xmppChatMessage.orderedMedia.first {
                if firstMedia.mediaType == .video {
                    mediaStr = "📹"
                }
            }
            
            if body.isEmpty {
                body = mediaStr
            } else {
                body = "\(mediaStr) \(body)"
            }
        }
        
        Banner.show(title: title, body: body, userID: userID, using: MainAppContext.shared.avatarStore)
    }
    
    private func presentLocalOneToOneNotifications(for xmppChatMessage: ChatMessageProtocol) {
        DDLogDebug("ChatData/presentLocalOneToOneNotifications")
        let userID = xmppChatMessage.fromUserId
        
        guard let ts = xmppChatMessage.timeIntervalSince1970 else { return }
        
        let timestamp = Date(timeIntervalSinceReferenceDate: ts)
        
        var notifications: [UNMutableNotificationContent] = []
        
        let protoContainer = xmppChatMessage.protoContainer
        let protobufData = try? protoContainer.serializedData()
        
        let metadata = NotificationMetadata(contentId: xmppChatMessage.id,
                                            contentType: .chatMessage,
                                            fromId: userID,
                                            data: protobufData,
                                            timestamp: timestamp)
        
        let notification = UNMutableNotificationContent()
        notification.title = contactStore.fullName(for: userID)
        notification.populate(withDataFrom: protoContainer, notificationMetadata: metadata, mentionNameProvider: { userID in
            contactStore.mentionName(for: userID, pushName: protoContainer.mentionPushName(for: userID))
        })
        
        notification.userInfo[NotificationMetadata.userInfoKey] = metadata.rawData
        notifications.append(notification)
        
        let notificationCenter = UNUserNotificationCenter.current()
        notifications.forEach { (notificationContent) in
            notificationCenter.add(UNNotificationRequest(identifier: UUID().uuidString, content: notificationContent, trigger: nil))
            incrementApplicationIconBadgeNumber()
        }
    }
}

extension ChatData {
    
    public typealias GroupActionCompletion = (Error?) -> Void
    
    // MARK: Group
    
    func setCurrentlyChattingInGroup(for groupId: GroupID?) {
        currentlyChattingInGroup = groupId
    }
    
    // MARK: Group Actions
    
    public func createGroup(name: String, members: [UserID], data: Data?, completion: @escaping ServiceRequestCompletion<String>) {
        
        MainAppContext.shared.service.createGroup(name: name, members: members) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let groupID):
                if let data = data {
                    self.changeGroupAvatar(groupID: groupID, data: data) { result in
                        completion(.success(groupID)) // the group can be created regardless if avatar update succeeds or not
                    }
                } else {
                    completion(.success(groupID))
                }
            case .failure(let error):
                DDLogError("ChatData/groups/createGroup/error \(error)")
                completion(.failure(error))
            }
        }
    
    }
    
    private func updateGroupName(for groupID: GroupID, with name: String, completion: @escaping () -> ()) {
        let group = DispatchGroup()
            
        group.enter()
        updateChatGroup(with: groupID, block: { (chatGroup) in
            guard chatGroup.name != name else { return }
            chatGroup.name = name
        }, performAfterSave: {
            group.leave()
        })

        group.enter()
        updateChatThread(type: .group, for: groupID, block: { (chatThread) in
            guard chatThread.title != name else { return }
            chatThread.title = name
        }, performAfterSave: {
            group.leave()
        })
        
        group.notify(queue: backgroundProcessingQueue) {
            completion()
        }
    }
    
    public func changeGroupName(groupID: GroupID, name: String, completion: @escaping ServiceRequestCompletion<Void>) {
        MainAppContext.shared.service.changeGroupName(groupID: groupID, name: name) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.updateGroupName(for: groupID, with: name) {
                    completion(.success(()))
                }
            case .failure(let error):
                DDLogError("CreateGroupViewController/createAction/error \(error)")
                completion(.failure(error))
            }
        }
    }
    
    public func changeGroupAvatar(groupID: GroupID, data: Data, completion: @escaping ServiceRequestCompletion<Void>) {
        DDLogInfo("ChatData/changeGroupAvatar")
        MainAppContext.shared.service.changeGroupAvatar(groupID: groupID, data: data) { [weak self] result in
            guard let self = self else { return }
     
            switch result {
            case .success(let avatarID):
                self.updateChatGroup(with: groupID, block: { (chatGroup) in
                    chatGroup.avatar = avatarID
                }, performAfterSave: {
                    MainAppContext.shared.avatarStore.updateOrInsertGroupAvatar(for: groupID, with: avatarID)
//                    MainAppContext.shared.avatarStore.updateGroupAvatarImageData(for: groupID, avatarID: avatarID, with: data)
                    completion(.success(()))
                })
            case .failure(let error):
                DDLogError("CreateGroupViewController/createAction/error \(error)")
            }
        }
    }
    
    public func getGroupsList() {
        DDLogDebug("ChatData/group/getGroupsList")
        service.getGroupsList() { [weak self] result in
            switch result {
            case .success(let groups):
                self?.processGroupsList(groups)
            case .failure(let error):
                DDLogError("ChatData/group/getGroupsList/error \(error)")
            }
        }
    }
    
    public func getAndSyncGroup(groupId: GroupID) {
        DDLogDebug("ChatData/group/getAndSyncGroupInfo/group \(groupId)")
        service.getGroupInfo(groupID: groupId) { [weak self] result in
            switch result {
            case .success(let group):
                self?.syncGroup(group)
            case .failure(let error):
                DDLogError("ChatData/group/getGroupInfo/error \(error)")
            }
        }
    }
    
    func syncGroupIfNeeded(for groupId: GroupID) {
        guard MainAppContext.shared.chatData.chatGroupMember(groupId: groupId, memberUserId: MainAppContext.shared.userData.userId) != nil else { return }
        guard let chatGroup = chatGroup(groupId: groupId) else { return }
        var shouldSync = false
    
        if let lastSync = chatGroup.lastSync {
            if let diff = Calendar.current.dateComponents([.hour], from: lastSync, to: Date()).hour, diff > 24 {
                shouldSync = true
            }
        } else {
            shouldSync = true
        }
        if shouldSync {
            MainAppContext.shared.chatData.getAndSyncGroup(groupId: groupId)
        }
    }
    
    func syncGroup(_ xmppGroup: XMPPGroup) {
        DDLogInfo("ChatData/group/syncGroupInfo")
    
        updateChatGroup(with: xmppGroup.groupId) { [weak self] (chatGroup) in
            guard let self = self else { return }
            chatGroup.lastSync = Date()
            
            if chatGroup.name != xmppGroup.name {
                chatGroup.name = xmppGroup.name
                self.updateChatThread(type: .group, for: xmppGroup.groupId) { (chatThread) in
                    chatThread.title = xmppGroup.name
                }
            }
            if chatGroup.avatar != xmppGroup.avatarID {
                chatGroup.avatar = xmppGroup.avatarID
                if let avatarID = xmppGroup.avatarID {
                    MainAppContext.shared.avatarStore.updateOrInsertGroupAvatar(for: chatGroup.groupId, with: avatarID)
                }
            }
            
            // look for users that are not members anymore
            chatGroup.orderedMembers.forEach { currentMember in
                let foundMember = xmppGroup.members?.first(where: { $0.userId == currentMember.userId })
                
                if foundMember == nil {
                    chatGroup.managedObjectContext!.delete(currentMember)
                }
            }
            
            var contactNames = [UserID:String]()
            
            // see if there are new members added or needs to be updated
            xmppGroup.members?.forEach { inboundMember in
                let foundMember = chatGroup.members?.first(where: { $0.userId == inboundMember.userId })
                
                // member already exists
                if let member = foundMember {
                    if let inboundType = inboundMember.type {
                        if member.type != inboundType {
                            member.type = inboundType
                        }
                    }
                } else {
                    DDLogDebug("ChatData/group/syncGroupInfo/new/add-member [\(inboundMember.userId)]")
                    self.processGroupAddMemberAction(chatGroup: chatGroup, xmppGroupMember: inboundMember, in: chatGroup.managedObjectContext!)
                }
                
                // add to pushnames
                if let name = inboundMember.name, !name.isEmpty {
                    contactNames[inboundMember.userId] = name
                }
            }
            
            if !contactNames.isEmpty {
                self.contactStore.addPushNames(contactNames)
            }
        }
    }
    
    // MARK: Group Sending Messages
    
    func sendGroupMessage(toGroupId: GroupID,
                          mentionText: MentionText,
                          media: [PendingMedia],
                          chatReplyMessageID: String? = nil,
                          chatReplyMessageSenderID: UserID? = nil,
                          chatReplyMessageMediaIndex: Int32) {
        
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            self.createGroupChatMsg(toGroupId: toGroupId,
                                  mentionText: mentionText,
                                  media: media,
                                  chatReplyMessageID: chatReplyMessageID,
                                  chatReplyMessageSenderID: chatReplyMessageSenderID,
                                  chatReplyMessageMediaIndex: chatReplyMessageMediaIndex)
        }
        
    }
    
    func createGroupChatMsg(toGroupId: GroupID,
                          mentionText: MentionText,
                          media: [PendingMedia],
                          chatReplyMessageID: String? = nil,
                          chatReplyMessageSenderID: UserID? = nil,
                          chatReplyMessageMediaIndex: Int32) {
        let groupMessageId = UUID().uuidString

        // Create and save new ChatGroupMessage object
        DDLogDebug("ChatData/group/new-msg/\(groupMessageId)")
        let chatGroupMessage = ChatGroupMessage(context: bgContext)
        chatGroupMessage.id = groupMessageId
        chatGroupMessage.groupId = toGroupId
        chatGroupMessage.userId = AppContext.shared.userData.userId
        chatGroupMessage.text = mentionText.trimmed().collapsedText
        chatGroupMessage.chatReplyMessageID = chatReplyMessageID
        chatGroupMessage.chatReplyMessageSenderID = chatReplyMessageSenderID
        chatGroupMessage.chatReplyMessageMediaIndex = chatReplyMessageMediaIndex
        chatGroupMessage.inboundStatus = .none
        chatGroupMessage.outboundStatus = .pending
        chatGroupMessage.timestamp = Date()

        // Add mentions
        var mentionSet = Set<ChatMention>()
        for (index, userID) in mentionText.mentions {
            let chatMention = ChatMention(context: bgContext)
            chatMention.index = index
            chatMention.userID = userID
            chatMention.name = contactStore.pushNames[userID] ?? ""
            if chatMention.name == "" {
                DDLogError("ChatData/createGroupChatMsg/mention/\(userID) missing push name")
            }
            mentionSet.insert(chatMention)
        }
        chatGroupMessage.mentions = mentionSet
        
        // insert all the group members who should get this message
        if let chatGroup = self.chatGroup(groupId: toGroupId, in: bgContext) {
            if let members = chatGroup.members {
                for member in members {
                    guard member.userId != MainAppContext.shared.userData.userId else { continue }
                    let messageInfo = ChatGroupMessageInfo(context: bgContext)
                    messageInfo.chatGroupMessageId = chatGroupMessage.id
                    messageInfo.userId = member.userId
                    messageInfo.outboundStatus = .none
                    messageInfo.groupMessage = chatGroupMessage
                    messageInfo.timestamp = Date()
                }
            }
        }
        
        var lastMsgMediaType: ChatThread.LastMediaType = .none // going with the first media
        
        for (index, mediaItem) in media.enumerated() {
            DDLogDebug("ChatData/group/new-msg/\(groupMessageId)/add-media [\(mediaItem)]")
            guard let mediaItemSize = mediaItem.size,
                  let mediaItemKey = mediaItem.key,
                  let mediaItemSha256 = mediaItem.sha256,
                  let mediaItemFileURL = mediaItem.fileURL else {
                DDLogDebug("ChatData/createChatMsg/\(groupMessageId)/add-media/skip/missing info")
                continue
            }
            
            let chatMedia = ChatMedia(context: bgContext)
            switch mediaItem.type {
            case .image:
                chatMedia.type = .image
                if lastMsgMediaType == .none {
                    lastMsgMediaType = .image
                }
            case .video:
                chatMedia.type = .video
                if lastMsgMediaType == .none {
                    lastMsgMediaType = .video
                }
            }
            chatMedia.outgoingStatus = .pending
            chatMedia.url = mediaItem.url
            chatMedia.uploadUrl = mediaItem.uploadUrl
            chatMedia.size = mediaItemSize
            chatMedia.key = mediaItemKey
            chatMedia.sha256 = mediaItemSha256
            chatMedia.order = Int16(index)
            chatMedia.message = nil
            chatMedia.groupMessage = chatGroupMessage

            do {
                try copyFiles(toChatMedia: chatMedia, fileUrl: mediaItemFileURL, encryptedFileUrl: mediaItem.encryptedFileUrl)
            }
            catch {
                DDLogError("ChatData/group/new-msg/\(groupMessageId)/copy-media/error [\(error)]")
            }
        }
        
        if let chatReplyMessageID = chatReplyMessageID,
           let chatReplyMessageSenderID = chatReplyMessageSenderID,
           let quotedChatGroupMessage = MainAppContext.shared.chatData.chatGroupMessage(with: chatReplyMessageID) {
            
            let quoted = ChatQuoted(context: bgContext)
            quoted.type = .message
            quoted.userId = chatReplyMessageSenderID
            quoted.text = quotedChatGroupMessage.text
            quoted.groupMessage = chatGroupMessage

            var quotedMentions = Set<ChatMention>()
            for quotedChatGroupMessageMention in quotedChatGroupMessage.orderedMentions {
                let quotedMention = ChatMention(context: bgContext)
                quotedMention.index = quotedChatGroupMessageMention.index
                quotedMention.userID = quotedChatGroupMessageMention.userID
                quotedMention.name = quotedChatGroupMessageMention.name
                quotedMentions.insert(quotedMention)
            }
            quoted.mentions = quotedMentions
            
            if let quotedChatGroupMessageMedia = quotedChatGroupMessage.media?.first(where: { $0.order == chatReplyMessageMediaIndex }) {
                let quotedMedia = ChatQuotedMedia(context: bgContext)
                if quotedChatGroupMessageMedia.type == .image {
                    quotedMedia.type = .image
                } else {
                    quotedMedia.type = .video
                }
                quotedMedia.order = quotedChatGroupMessageMedia.order
                quotedMedia.width = Float(quotedChatGroupMessageMedia.size.width)
                quotedMedia.height = Float(quotedChatGroupMessageMedia.size.height)
                quotedMedia.quoted = quoted

                do {
                    try copyMediaToQuotedMedia(fromDir: MainAppContext.chatMediaDirectoryURL, fromPath: quotedChatGroupMessageMedia.relativeFilePath, to: quotedMedia)
                }
                catch {
                    DDLogError("ChatData/new-msg/\(groupMessageId)/quoted/copy-media/error [\(error)]")
                }
            }
        }
        
        // Update Chat Thread
        let attrMentionText = contactStore.textWithMentions(chatGroupMessage.text, orderedMentions: chatGroupMessage.orderedMentions)
        if let chatThread = self.chatThread(type: .group, id: chatGroupMessage.groupId, in: bgContext) {
            DDLogDebug("ChatData/group/new-msg/ update-thread")
            chatThread.type = .group
            chatThread.lastMsgId = chatGroupMessage.id
            chatThread.lastMsgUserId = chatGroupMessage.userId
            chatThread.lastMsgText = attrMentionText?.string ?? ""
            chatThread.lastMsgMediaType = lastMsgMediaType
            chatThread.lastMsgStatus = .pending
            chatThread.lastMsgTimestamp = chatGroupMessage.timestamp
            chatThread.draft = nil
        } else {
            DDLogDebug("ChatData/group/new-msg/\(groupMessageId)/new-thread")
            let chatThread = ChatThread(context: bgContext)
            chatThread.type = .group
            chatThread.groupId = chatGroupMessage.groupId
            chatThread.lastMsgId = chatGroupMessage.id
            chatThread.lastMsgUserId = chatGroupMessage.userId
            chatThread.lastMsgText = attrMentionText?.string ?? ""
            chatThread.lastMsgMediaType = lastMsgMediaType
            chatThread.lastMsgStatus = .pending
            chatThread.lastMsgTimestamp = chatGroupMessage.timestamp
            chatThread.unreadCount = 0
        }
        save(bgContext)
        
        let xmppGroupChatMsg = XMPPChatGroupMessage(chatGroupMessage: chatGroupMessage)
        uploadGroupChatMsgMediaAndSend(xmppGroupChatMsg: xmppGroupChatMsg)
    }
    
    // TODO: consolidate this with ChatMessage
    private func uploadGroupChatMsgMediaAndSend(xmppGroupChatMsg: XMPPChatGroupMessage) {
        let groupChatMsgID = xmppGroupChatMsg.id
        guard let groupChatMsg = chatGroupMessage(with: groupChatMsgID, in: bgContext) else { return }
        
        // Either all media has already been uploaded or post does not contain media.
        guard let mediaItemsToUpload = groupChatMsg.media?.filter({ $0.outgoingStatus == .none || $0.outgoingStatus == .pending || $0.outgoingStatus == .error }), !mediaItemsToUpload.isEmpty else {
            service.sendGroupChatMessage(xmppGroupChatMsg)
            return
        }
        
        var numberOfFailedUploads = 0
        let totalUploads = mediaItemsToUpload.count
        DDLogInfo("ChatData/group/upload-media/\(groupChatMsgID)/starting [\(totalUploads)]")

        let uploadGroup = DispatchGroup()
        
        for mediaItem in mediaItemsToUpload {
            let mediaIndex = mediaItem.order
            uploadGroup.enter()
            
            mediaUploader.upload(media: mediaItem, groupId: groupChatMsgID, didGetURLs: { (mediaURLs) in
                DDLogInfo("ChatData/group/upload-media/\(groupChatMsgID)/\(mediaIndex)/acquired-urls [\(mediaURLs)]")

                // Save URLs acquired during upload to the database.
                self.updateChatGroupMessage(with: groupChatMsgID) { msg in
                    guard let media = msg.media?.first(where: { $0.order == mediaIndex }) else { return }
                    switch mediaURLs {
                    case .getPut(let getURL, let putURL):
                        media.url = getURL
                        media.uploadUrl = putURL
                    case .patch(let patchURL):
                        media.uploadUrl = patchURL
                    }
                }
                
            }) { (uploadResult) in
                DDLogInfo("ChatData/group/upload-media/\(groupChatMsgID)/\(mediaIndex)/finished result=[\(uploadResult)]")

                self.updateChatGroupMessage(with: groupChatMsgID, block: { msg in
                    guard let media = msg.media?.first(where: { $0.order == mediaIndex }) else { return }
                    switch uploadResult {
                    case .success(let url):
                        media.url = url
                        media.outgoingStatus = .uploaded

                    case .failure(_):
                        numberOfFailedUploads += 1
                        media.outgoingStatus = .error
                    }
                },
                performAfterSave: {
                    uploadGroup.leave()
                })
            }
        }

        uploadGroup.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            DDLogInfo("ChatData/group/upload-media/\(groupChatMsgID)/all/finished [\(totalUploads-numberOfFailedUploads)/\(totalUploads)]")
            if numberOfFailedUploads > 0 {
                self.updateChatGroupMessage(with: groupChatMsgID) { msg in
                    msg.outboundStatus = .error
                }
            } else {
                self.service.sendGroupChatMessage(XMPPChatGroupMessage(chatGroupMessage: groupChatMsg))
            }
        }
    }

    func retractGroupChatMessage(groupID: GroupID, messageToRetractID: String) {
        let messageID = UUID().uuidString
                
        updateChatGroupMessage(with: messageToRetractID) { [weak self] (groupChatMessage) in
            guard let self = self else { return }
            guard [.sentOut, .delivered, .seen].contains(groupChatMessage.outboundStatus) else { return }

            groupChatMessage.retractID = messageID
            groupChatMessage.outboundStatus = .retracting

            self.deleteGroupChatMessageContent(in: groupChatMessage)

            self.updateChatThreadStatus(type: .group, for: groupChatMessage.groupId, messageId: groupChatMessage.id) { (chatThread) in
                chatThread.lastMsgStatus = .retracting
                chatThread.lastMsgText = nil
                chatThread.lastMsgMediaType = .none
            }

        }

        self.service.retractGroupChatMessage(messageID: messageID, groupID: groupID, messageToRetractID: messageToRetractID)
        
    }
    
    // MARK: Group Core Data Fetching
    
    private func chatGroups(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatGroup] {
        let managedObjectContext = managedObjectContext ?? viewContext
        let fetchRequest: NSFetchRequest<ChatGroup> = ChatGroup.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false
        
        do {
            let chatGroups = try managedObjectContext.fetch(fetchRequest)
            return chatGroups
        }
        catch {
            DDLogError("ChatData/group/fetch/error  [\(error)]")
            fatalError("Failed to fetch chat groups")
        }
    }
    
    func chatGroup(groupId id: String, in managedObjectContext: NSManagedObjectContext? = nil) -> ChatGroup? {
        return chatGroups(predicate: NSPredicate(format: "groupId == %@", id), in: managedObjectContext).first
    }
    
    private func chatGroupMembers(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatGroupMember] {
        let managedObjectContext = managedObjectContext ?? self.viewContext
        let fetchRequest: NSFetchRequest<ChatGroupMember> = ChatGroupMember.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false
        
        do {
            let chatGroupMembers = try managedObjectContext.fetch(fetchRequest)
            return chatGroupMembers
        }
        catch {
            DDLogError("ChatData/group/fetchGroupMembers/error  [\(error)]")
            fatalError("Failed to fetch chat group members")
        }
    }
    
    func chatGroupMember(groupId id: GroupID, memberUserId: UserID, in managedObjectContext: NSManagedObjectContext? = nil) -> ChatGroupMember? {
        return chatGroupMembers(predicate: NSPredicate(format: "groupId == %@ && userId == %@", id, memberUserId), in: managedObjectContext).first
    }
    
    private func chatGroupMessages(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatGroupMessage] {
        let managedObjectContext = managedObjectContext ?? viewContext
        let fetchRequest: NSFetchRequest<ChatGroupMessage> = ChatGroupMessage.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false
        
        do {
            let chatGroupMessages = try managedObjectContext.fetch(fetchRequest)
            return chatGroupMessages
        }
        catch {
            DDLogError("ChatData/group/fetch-messages/error  [\(error)]")
            fatalError("Failed to fetch chat group messages")
        }
    }
    
    func chatGroupMessage(with id: String, in managedObjectContext: NSManagedObjectContext? = nil) -> ChatGroupMessage? {
        return chatGroupMessages(predicate: NSPredicate(format: "id == %@", id), in: managedObjectContext).first
    }
    
    // includes seen but not sent messages
    func unseenChatGroupMessages(with groupId: String, in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatGroupMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatGroupMessage.timestamp, ascending: true)
        ]
        return chatGroupMessages(predicate: NSPredicate(format: "(groupId = %@) && (event.@count == 0) && (inboundStatusValue = %d OR inboundStatusValue = %d)", groupId, ChatGroupMessage.InboundStatus.none.rawValue, ChatGroupMessage.InboundStatus.haveSeen.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }
    
    func pendingOutboundGroupChatMsgs(in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatGroupMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatGroupMessage.timestamp, ascending: true)
        ]
        return chatGroupMessages(predicate: NSPredicate(format: "outboundStatusValue = %d", ChatGroupMessage.OutboundStatus.pending.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }
    
    func retractingOutboundGroupChatMsgs(in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatGroupMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatGroupMessage.timestamp, ascending: true)
        ]
        return chatGroupMessages(predicate: NSPredicate(format: "outboundStatusValue = %d", ChatGroupMessage.OutboundStatus.retracting.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }
    
    func pendingGroupChatSeenReceipts(in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatGroupMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatGroupMessage.timestamp, ascending: true)
        ]
        return chatGroupMessages(predicate: NSPredicate(format: "inboundStatusValue = %d", ChatGroupMessage.InboundStatus.haveSeen.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }
    
    func inboundPendingGroupChatMsgMedia(in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatGroupMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatGroupMessage.timestamp, ascending: true)
        ]
        return chatGroupMessages(predicate: NSPredicate(format: "ANY media.incomingStatusValue == %d", ChatMedia.IncomingStatus.pending.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }
    
    private func chatGroupMessageAllInfo(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatGroupMessageInfo] {
        let managedObjectContext = managedObjectContext ?? self.viewContext
        let fetchRequest: NSFetchRequest<ChatGroupMessageInfo> = ChatGroupMessageInfo.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false
        
        do {
            let chatGroupMessageInfo = try managedObjectContext.fetch(fetchRequest)
            return chatGroupMessageInfo
        }
        catch {
            DDLogError("ChatData/group/fetch-messageInfo/error  [\(error)]")
            fatalError("Failed to fetch chat group message info")
        }
    }
    
    func chatGroupMessageInfo(messageId: String, in managedObjectContext: NSManagedObjectContext? = nil) -> ChatGroupMessageInfo? {
        return chatGroupMessageAllInfo(predicate: NSPredicate(format: "chatGroupMessageId == %@", messageId), in: managedObjectContext).first
    }
    
    func chatGroupMessageInfoForUser(messageId: String, userId: UserID, in managedObjectContext: NSManagedObjectContext? = nil) -> ChatGroupMessageInfo? {
        return chatGroupMessageAllInfo(predicate: NSPredicate(format: "chatGroupMessageId == %@ && userId == %@", messageId, userId), in: managedObjectContext).first
    }
    
    // MARK: Group Core Data Updating
    
    public func updateChatGroupMessageCellHeight(for chatGroupMessageId: String, with cellHeight: Int) {
        updateChatGroupMessage(with: chatGroupMessageId) { (chatGroupMessage) in
            chatGroupMessage.cellHeight = Int16(cellHeight)
        }
    }
    
    func updateChatGroup(with groupId: GroupID, block: @escaping (ChatGroup) -> (), performAfterSave: (() -> ())? = nil) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            defer {
                if let performAfterSave = performAfterSave {
                    performAfterSave()
                }
            }
            guard let self = self else { return }
            guard let chatGroup = self.chatGroup(groupId: groupId, in: managedObjectContext) else {
                DDLogError("ChatData/group/updateChatGroup/missing [\(groupId)]")
                return
            }
            DDLogVerbose("ChatData/group/updateChatGroup [\(groupId)]")
            block(chatGroup)
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    func updateChatGroupMessage(with chatGroupMessageId: String, block: @escaping (ChatGroupMessage) -> (), performAfterSave: (() -> ())? = nil) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            defer {
                if let performAfterSave = performAfterSave {
                    performAfterSave()
                }
            }
            guard let self = self else { return }
            guard let chatGroupMessage = self.chatGroupMessage(with: chatGroupMessageId, in: managedObjectContext) else {
                DDLogError("ChatData/group/update-message/missing [\(chatGroupMessageId)]")
                return
            }
            DDLogVerbose("ChatData/group/update-message [\(chatGroupMessageId)]")
            block(chatGroupMessage)
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    func updateChatGroupMessageByStatus(for id: String, status: ChatGroupMessage.OutboundStatus, block: @escaping (ChatGroupMessage) -> ()) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            let sortDescriptors = [
                NSSortDescriptor(keyPath: \ChatGroupMessage.timestamp, ascending: true)
            ]
            guard let chatGroupMessage = self.chatGroupMessages(predicate: NSPredicate(format: "outboundStatusValue = %d && id == %@", status.rawValue, id), sortDescriptors: sortDescriptors, in: managedObjectContext).first else {
                return
            }

            DDLogVerbose("ChatData/group/updateChatGroupMessageByStatus [\(id)]")
            block(chatGroupMessage)
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    private func updateRetractingGroupChatMessage(for id: String, block: @escaping (ChatGroupMessage) -> ()) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            let sortDescriptors = [
                NSSortDescriptor(keyPath: \ChatGroupMessage.timestamp, ascending: true)
            ]
            guard let groupChatMessage = self.chatGroupMessages(predicate: NSPredicate(format: "outboundStatusValue = %d && retractID == %@", ChatGroupMessage.OutboundStatus.retracting.rawValue, id), sortDescriptors: sortDescriptors, in: managedObjectContext).first else {
                return
            }
            
            DDLogVerbose("ChatData/updateRetractingGroupChatMessage [\(id)]")
            block(groupChatMessage)
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    func updateChatGroupMessageInfo(with chatGroupMessageId: String, userId: UserID, block: @escaping (ChatGroupMessageInfo) -> (), performAfterSave: (() -> ())? = nil) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            defer {
                if let performAfterSave = performAfterSave {
                    performAfterSave()
                }
            }
            guard let self = self else { return }
            guard let chatGroupMessageInfo = self.chatGroupMessageInfoForUser(messageId: chatGroupMessageId, userId: userId, in: managedObjectContext) else {
                DDLogError("ChatData/group/update-message/missing [\(chatGroupMessageId)]")
                return
            }
            DDLogVerbose("ChatData/group/update-messageInfo")
            block(chatGroupMessageInfo)
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    // MARK: Group Core Data Deleting
    
    func deleteChatGroup(groupId: GroupID) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            // delete group
            if let chatGroup = self.chatGroup(groupId: groupId, in: managedObjectContext) {
                if let members = chatGroup.members {
                    members.forEach {
                        managedObjectContext.delete($0)
                    }
                }
                managedObjectContext.delete(chatGroup)
            }
            
            // delete thread
            if let chatThread = self.chatThread(type: .group, id: groupId, in: managedObjectContext) {
                managedObjectContext.delete(chatThread)
            }
            
            let fetchRequest = NSFetchRequest<ChatGroupMessage>(entityName: ChatGroupMessage.entity().name!)
            
            fetchRequest.predicate = NSPredicate(format: "groupId = %@", groupId)
            
            do {
                let chatGroupMessages = try managedObjectContext.fetch(fetchRequest)
                DDLogInfo("ChatData/group/delete-messages/begin count=[\(chatGroupMessages.count)]")
                chatGroupMessages.forEach {
                    self.deleteGroupMedia(in: $0)
                    
                    // delete message receipts
                    $0.info?.forEach { info in
                        managedObjectContext.delete(info)
                    }
                    
                    managedObjectContext.delete($0)
                }
            }
            catch {
                DDLogError("ChatData/group/delete-messages/error  [\(error)]")
                return
            }
            self.save(managedObjectContext)
        }
    }
    
    func deleteChatGroupMember(groupId: GroupID, memberUserId: UserID) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            let fetchRequest = NSFetchRequest<ChatGroupMember>(entityName: ChatGroupMember.entity().name!)
            fetchRequest.predicate = NSPredicate(format: "groupId = %@ && userId = %@", groupId, memberUserId)
            
            do {
                let chatGroupMembers = try managedObjectContext.fetch(fetchRequest)
                DDLogInfo("ChatData/group/deleteChatGroupMember/begin count=[\(chatGroupMembers.count)]")
                chatGroupMembers.forEach {
                    managedObjectContext.delete($0)
                }
            }
            catch {
                DDLogError("ChatData/group/deleteChatGroupMember/error  [\(error)]")
                return
            }
            self.save(managedObjectContext)
        }
    }
    
    private func deleteGroupChatMessageContent(in groupChatMessage: ChatGroupMessage) {
        DDLogVerbose("ChatData/deleteChatGroupMessageContent/message \(groupChatMessage.id) ")
        
        groupChatMessage.text = nil
        
        groupChatMessage.chatReplyMessageID = nil
        groupChatMessage.chatReplyMessageSenderID = nil
        groupChatMessage.chatReplyMessageMediaIndex = 0
        
        deleteGroupMedia(in: groupChatMessage)
        groupChatMessage.media = nil
        groupChatMessage.quoted = nil
    }
    
    private func deleteGroupMedia(in chatGroupMessage: ChatGroupMessage) {
        DDLogDebug("ChatData/group/delete/message/media \(chatGroupMessage.id) ")
        chatGroupMessage.media?.forEach { (media) in
            if media.relativeFilePath != nil {
                let fileURL = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(media.relativeFilePath!, isDirectory: false)
                do {
                    DDLogDebug("ChatData/group/delete/message/media ")
                    try FileManager.default.removeItem(at: fileURL)
                }
                catch {
                    DDLogError("ChatData/group/delete/message/media/error [\(error)]")
                }
            }
            chatGroupMessage.managedObjectContext?.delete(media)
        }

    }
    
}

// MARK: Group Process Inbound/Outbound Group Feed
extension ChatData {

    private func updateThreadWithGroupFeed(_ id: FeedPostID, isInbound: Bool, using managedObjectContext: NSManagedObjectContext) {

        guard let groupFeedPost = MainAppContext.shared.feedData.feedPost(with: id) else { return }
        guard let groupID = groupFeedPost.groupId else { return }
        
        var groupExist = true
        
        if isInbound {
            // if group doesn't exist yet, create
            if chatGroup(groupId: groupID, in: managedObjectContext) == nil {
                DDLogDebug("ChatData/group/updateThreadWithGroupFeed/group not exist yet [\(groupID)]")
                groupExist = false
                let chatGroup = ChatGroup(context: managedObjectContext)
                chatGroup.groupId = groupID
            }
        }
        
        var lastFeedMediaType: ChatThread.LastMediaType = .none // going with the first media found
        
        // Process chat media
        if groupFeedPost.orderedMedia.count > 0 {
            if let firstMedia = groupFeedPost.orderedMedia.first {
                switch firstMedia.type {
                case .image:
                    lastFeedMediaType = .image
                case .video:
                    lastFeedMediaType = .video
                }
            }
        }
        
        // Update Chat Thread
        let mentionText = contactStore.textWithMentions(groupFeedPost.text, orderedMentions: groupFeedPost.orderedMentions)
        if let chatThread = chatThread(type: .group, id: groupID, in: managedObjectContext) {
            chatThread.lastFeedId = groupFeedPost.id
            chatThread.lastFeedUserID = groupFeedPost.userId
            chatThread.lastFeedText = mentionText?.string ?? ""
            chatThread.lastFeedMediaType = lastFeedMediaType
            chatThread.lastFeedStatus = .none
            chatThread.lastFeedTimestamp = groupFeedPost.timestamp
            if isInbound {
                chatThread.unreadFeedCount = chatThread.unreadFeedCount + 1
            }
        } else {
            let chatThread = ChatThread(context: managedObjectContext)
            chatThread.type = ChatType.group
            chatThread.groupId = groupID
            chatThread.lastFeedId = groupFeedPost.id
            chatThread.lastFeedUserID = groupFeedPost.userId
            chatThread.lastFeedText = mentionText?.string ?? ""
            chatThread.lastFeedMediaType = lastFeedMediaType
            chatThread.lastFeedStatus = .none
            chatThread.lastFeedTimestamp = groupFeedPost.timestamp
            if isInbound {
                chatThread.unreadFeedCount = 1
            }
        }
        
        save(managedObjectContext)
        
        if isInbound {
            if !groupExist {
                getAndSyncGroup(groupId: groupID)
            }
            
            updateUnreadThreadGroupsCount()
        }
        
    }
    
    private func updateThreadWithGroupFeedRetract(_ id: FeedPostID, using managedObjectContext: NSManagedObjectContext) {
        
        guard let groupFeedPost = MainAppContext.shared.feedData.feedPost(with: id) else { return }
        guard let groupID = groupFeedPost.groupId else { return }
        
        guard let thread = chatThread(type: .group, id: groupID, in: managedObjectContext) else { return }
        
        guard thread.lastFeedId == id else { return }
        
        thread.lastFeedStatus = .retracted
        
        save(managedObjectContext)
        
    }
    
}

extension ChatData {
    
    // MARK: Group Process Inbound Messages
    
    private func processInboundChatGroupMessage(xmppChatGroupMessage: XMPPChatGroupMessage, using managedObjectContext: NSManagedObjectContext, isAppActive: Bool) {
        guard chatGroupMessage(with: xmppChatGroupMessage.id, in: managedObjectContext) == nil else {
            DDLogError("ChatData/group/processInboundChatGroupMessage/already-exists [\(xmppChatGroupMessage.id)]")
            return
        }
        
        var isCurrentlyChattingInGroup = false
        var groupExist = true
        
        if let currentlyChattingInGroup = currentlyChattingInGroup {
            if xmppChatGroupMessage.groupId == currentlyChattingInGroup {
                isCurrentlyChattingInGroup = true
            }
        }
        
        // if group doesn't exist yet, add
        if chatGroup(groupId: xmppChatGroupMessage.groupId, in: managedObjectContext) == nil {
            DDLogDebug("ChatData/group/processInboundChatGroupMessage/group not exist yet [\(xmppChatGroupMessage.groupId)]")
            groupExist = false
            let chatGroup = ChatGroup(context: managedObjectContext)
            chatGroup.groupId = xmppChatGroupMessage.groupId
            if let groupName = xmppChatGroupMessage.groupName {
                chatGroup.name = groupName
            }
        }
        
        // Add new ChatGroupMessage to database.
        DDLogDebug("ChatData/group/process/newMsg [\(xmppChatGroupMessage.id)]")
        let chatGroupMessage = NSEntityDescription.insertNewObject(forEntityName: ChatGroupMessage.entity().name!, into: managedObjectContext) as! ChatGroupMessage
        chatGroupMessage.id = xmppChatGroupMessage.id
        chatGroupMessage.groupId = xmppChatGroupMessage.groupId
        chatGroupMessage.userId = xmppChatGroupMessage.userId
        chatGroupMessage.text = xmppChatGroupMessage.text
        chatGroupMessage.chatReplyMessageID = xmppChatGroupMessage.chatReplyMessageID
        chatGroupMessage.chatReplyMessageSenderID = xmppChatGroupMessage.chatReplyMessageSenderID
        chatGroupMessage.chatReplyMessageMediaIndex = xmppChatGroupMessage.chatReplyMessageMediaIndex
        
        chatGroupMessage.inboundStatus = .none
        chatGroupMessage.outboundStatus = .none
        chatGroupMessage.timestamp = xmppChatGroupMessage.timestamp
        
        // Mentions
        var mentions = Set<ChatMention>()
        for mention in xmppChatGroupMessage.orderedMentions {
            let chatMention = ChatMention(context: bgContext)
            chatMention.index = mention.index
            chatMention.userID = mention.userID
            chatMention.name = mention.name
            mentions.insert(chatMention)
        }
        chatGroupMessage.mentions = mentions
        
        var lastMsgMediaType: ChatThread.LastMediaType = .none // going with the first media found
        
        // Process chat media
        for (index, xmppMedia) in xmppChatGroupMessage.media.enumerated() {
            guard let downloadUrl = xmppMedia.url else { continue }

            DDLogDebug("ChatData/group/process/newMsg/add-media [\(downloadUrl)]")
            let chatMedia = NSEntityDescription.insertNewObject(forEntityName: ChatMedia.entity().name!, into: managedObjectContext) as! ChatMedia
            
            switch xmppMedia.type {
            case .image:
                chatMedia.type = .image
                if lastMsgMediaType == .none {
                    lastMsgMediaType = .image
                }
            case .video:
                chatMedia.type = .video
                if lastMsgMediaType == .none {
                    lastMsgMediaType = .video
                }
            }
            chatMedia.incomingStatus = .pending
            chatMedia.outgoingStatus = .none
            chatMedia.url = xmppMedia.url
            chatMedia.size = xmppMedia.size
            chatMedia.key = xmppMedia.key
            chatMedia.order = Int16(index)
            chatMedia.sha256 = xmppMedia.sha256
            chatMedia.groupMessage = chatGroupMessage
        }
                
        // Process Quoted Message
        
        if xmppChatGroupMessage.chatReplyMessageID != nil {
            
            if let quotedChatGroupMessage = MainAppContext.shared.chatData.chatGroupMessage(with: xmppChatGroupMessage.chatReplyMessageID!) {
                let quoted = NSEntityDescription.insertNewObject(forEntityName: ChatQuoted.entity().name!, into: managedObjectContext) as! ChatQuoted
                quoted.type = .message
                quoted.userId = quotedChatGroupMessage.userId
                quoted.text = quotedChatGroupMessage.text
                quoted.groupMessage = chatGroupMessage
                
                var quotedMentions = Set<ChatMention>()
                for quotedChatGroupMessageMention in quotedChatGroupMessage.orderedMentions {
                    let quotedMention = ChatMention(context: bgContext)
                    quotedMention.index = quotedChatGroupMessageMention.index
                    quotedMention.userID = quotedChatGroupMessageMention.userID
                    quotedMention.name = quotedChatGroupMessageMention.name
                    quotedMentions.insert(quotedMention)
                }
                quoted.mentions = quotedMentions
                
                if quotedChatGroupMessage.media != nil {
                    
                    if let quotedChatMessageMedia = quotedChatGroupMessage.media!.first(where: { $0.order == xmppChatGroupMessage.chatReplyMessageMediaIndex}) {
                        
                        let quotedMedia = NSEntityDescription.insertNewObject(forEntityName: ChatQuotedMedia.entity().name!, into: managedObjectContext) as! ChatQuotedMedia
                        if quotedChatMessageMedia.type == .image {
                            quotedMedia.type = .image
                        } else {
                            quotedMedia.type = .video
                        }
                        quotedMedia.order = quotedChatMessageMedia.order
                        quotedMedia.width = Float(quotedChatMessageMedia.size.width)
                        quotedMedia.height = Float(quotedChatMessageMedia.size.height)
                        quotedMedia.quoted = quoted
                        do {
                            try copyMediaToQuotedMedia(fromDir: MainAppContext.chatMediaDirectoryURL, fromPath: quotedChatMessageMedia.relativeFilePath, to: quotedMedia)
                        }
                        catch {
                            DDLogError("ChatData/new-msg/quoted/copy-media/error [\(error)]")
                        }
                    }
                }
            }
        }
        
        // Update Chat Thread
        let mentionText = contactStore.textWithMentions(xmppChatGroupMessage.text, orderedMentions: xmppChatGroupMessage.orderedMentions)
        if let chatThread = chatThread(type: .group, id: chatGroupMessage.groupId, in: managedObjectContext) {
            chatThread.lastMsgId = chatGroupMessage.id
            chatThread.lastMsgUserId = chatGroupMessage.userId
            chatThread.lastMsgText = mentionText?.string ?? ""
            chatThread.lastMsgMediaType = lastMsgMediaType
            chatThread.lastMsgStatus = .none
            chatThread.lastMsgTimestamp = chatGroupMessage.timestamp
            chatThread.unreadCount = isCurrentlyChattingInGroup ? 0 : chatThread.unreadCount + 1
        } else {
            let chatThread = NSEntityDescription.insertNewObject(forEntityName: ChatThread.entity().name!, into: managedObjectContext) as! ChatThread
            chatThread.type = ChatType.group
            chatThread.groupId = xmppChatGroupMessage.groupId
            if let groupName = xmppChatGroupMessage.groupName {
                chatThread.title = groupName
            }
            chatThread.lastMsgId = chatGroupMessage.id
            chatThread.lastMsgUserId = chatGroupMessage.userId
            chatThread.lastMsgText = mentionText?.string ?? ""
            chatThread.lastMsgMediaType = lastMsgMediaType
            chatThread.lastMsgStatus = .none
            chatThread.lastMsgTimestamp = chatGroupMessage.timestamp
            chatThread.unreadCount = 1
        }
        
        save(managedObjectContext)
                
        if !groupExist {
            getAndSyncGroup(groupId: xmppChatGroupMessage.groupId)
        }
        
        if isCurrentlyChattingInGroup && isAppActive {
            sendSeenGroupReceipt(for: chatGroupMessage)
            updateChatGroupMessage(with: chatGroupMessage.id) { (chatGroupMessage) in
                chatGroupMessage.inboundStatus = .haveSeen
            }
        } else {
            updateUnreadThreadCount()
        }
        
        // add to pushnames
        if let userId = xmppChatGroupMessage.userId, let name = xmppChatGroupMessage.userName, !name.isEmpty {
            contactStore.addPushNames([userId: name])
        }
        
        if xmppChatGroupMessage.retryCount == nil || xmppChatGroupMessage.retryCount == 0 {
            showGroupNotification(for: xmppChatGroupMessage)
        }
        
        // download chat group message media
        processInboundPendingGroupChatMsgMedia()
        
        // remove user from typing state
        guard let fromUserID = xmppChatGroupMessage.userId else { return }
        removeFromChatStateList(from: fromUserID, threadType: .group, threadID: xmppChatGroupMessage.groupId, type: .available)
    }
    
    // MARK: Group Process Inbound Receipts

    private func processInboundGroupMessageReceipt(with receipt: XMPPReceipt, for groupId: GroupID) {
        let messageId = receipt.itemId
        guard let receiptTimestamp = receipt.timestamp else { return }
        
        if receipt.type == .delivery {
            updateChatGroupMessageInfo(with: messageId, userId: receipt.userId) { [weak self] (chatGroupMessageInfo) in
                guard let self = self else { return }
                DDLogDebug("ChatData/processInboundGroupMessageReceipt/updateChatGroupMessageInfo/delivered receipt")
                if chatGroupMessageInfo.outboundStatus == .none {
                    chatGroupMessageInfo.outboundStatus = .delivered
                    
                    chatGroupMessageInfo.timestamp = receiptTimestamp
                }
                
                let msg = chatGroupMessageInfo.groupMessage
                
                guard ![.delivered, .seen, .retracting, .retracted].contains(msg.outboundStatus) else { return }
                
                let delivered = msg.orderedInfo.filter {
                    $0.outboundStatus == .delivered || $0.outboundStatus == .seen
                }
                
                if delivered.count == msg.orderedInfo.count {
                    msg.outboundStatus = .delivered
                    
                    self.updateChatThreadStatus(type: .group, for: msg.groupId, messageId: msg.id) { (chatThread) in
                        chatThread.lastMsgStatus = .delivered
                    }
                }
                
            }
            
        } else if receipt.type == .read {
            
            updateChatGroupMessageInfo(with: messageId, userId: receipt.userId) { [weak self] (chatGroupMessageInfo) in
                guard let self = self else { return }
                DDLogDebug("ChatData/processInboundGroupMessageReceipt/updateChatGroupMessageInfo/seen receipt")
                if (chatGroupMessageInfo.outboundStatus == .none || chatGroupMessageInfo.outboundStatus == .delivered) {
                    chatGroupMessageInfo.outboundStatus = .seen
                    chatGroupMessageInfo.timestamp = receiptTimestamp
                }
                
                let msg = chatGroupMessageInfo.groupMessage
                
                guard ![.seen, .retracting, .retracted].contains(msg.outboundStatus) else { return }
                
                let seen = msg.orderedInfo.filter {
                    $0.outboundStatus == .seen
                }
                
                if seen.count == msg.orderedInfo.count {
                    msg.outboundStatus = .seen
                    
                    self.updateChatThreadStatus(type: .group, for: msg.groupId, messageId: msg.id) { (chatThread) in
                        chatThread.lastMsgStatus = .seen
                    }
                }
                
            }
            
        }
            
    }
    
    // MARK: Group - Process Inbound Retract Message
    
    private func processInboundGroupChatMessageRetract(groupID: GroupID, messageID: String) {
        DDLogInfo("ChatData/processInboundGroupChatMessageRetract")

        updateChatGroupMessage(with: messageID) { [weak self] (groupChatMessage) in
            guard let self = self else { return }
            
            groupChatMessage.inboundStatus = .retracted
            
            self.deleteGroupChatMessageContent(in: groupChatMessage)

            self.updateChatThreadStatus(type: .group, for: groupChatMessage.groupId, messageId: messageID) { (chatThread) in
                chatThread.lastMsgStatus = .retracted

                chatThread.lastMsgText = nil
                chatThread.lastMsgMediaType = .none
            }

        }
    }
    
    
    // MARK: Group Process Inbound Actions/Events

    private func processGroupsList(_ groups: XMPPGroups) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            
            groups.groups?.forEach({
                if self.chatGroup(groupId: $0.groupId, in: managedObjectContext) == nil {
                    _ = self.addGroup(xmppGroup: $0, in: managedObjectContext)
                    self.getAndSyncGroup(groupId: $0.groupId)
                }
            })
            
        }
    }
    
    private func processIncomingXMPPGroup(_ group: XMPPGroup) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            self.processIncomingGroup(xmppGroup: group, using: managedObjectContext)
        }
    }
    
    private func processIncomingGroup(xmppGroup: XMPPGroup, using managedObjectContext: NSManagedObjectContext) {
        switch xmppGroup.action {
        case .create:
            processGroupCreateAction(xmppGroup: xmppGroup, in: managedObjectContext)
        case .leave:
            processGroupLeaveAction(xmppGroup: xmppGroup, in: managedObjectContext)
        case .modifyMembers, .modifyAdmins:
            processGroupModifyMembersAction(xmppGroup: xmppGroup, in: managedObjectContext)
        case .changeName:
            processGroupChangeNameAction(xmppGroup: xmppGroup, in: managedObjectContext)
        case .changeAvatar:
            processGroupChangeAvatarAction(xmppGroup: xmppGroup, in: managedObjectContext)
        default: break
        }
        
        self.save(managedObjectContext)
    }
    
    
    private func processGroupCreateAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) {

        let chatGroup = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)
        
        var contactNames = [UserID:String]()
        
        // Add Group Creator
        if let existingCreator = chatGroupMember(groupId: xmppGroup.groupId, memberUserId: xmppGroup.sender ?? "", in: managedObjectContext) {
            existingCreator.type = .admin
        } else {
            guard let sender = xmppGroup.sender else { return }
            let groupCreator =  ChatGroupMember(context: managedObjectContext)
            groupCreator.groupId = xmppGroup.groupId
            groupCreator.userId = sender
            groupCreator.type = .admin
            groupCreator.group = chatGroup
            
            if let name = xmppGroup.senderName {
                contactNames[sender] = name
            }
        }

        // Add new Group members to database
        for xmppGroupMember in xmppGroup.members ?? [] {
            DDLogDebug("ChatData/group/process/new/add-member [\(xmppGroupMember.userId)]")
            processGroupAddMemberAction(chatGroup: chatGroup, xmppGroupMember: xmppGroupMember, in: managedObjectContext)
            
            // add to pushnames
            if let name = xmppGroupMember.name, !name.isEmpty {
                contactNames[xmppGroupMember.userId] = name
            }
        }
        
        if !contactNames.isEmpty {
            contactStore.addPushNames(contactNames)
        }
        
        recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: nil, in: managedObjectContext)
    }

    private func processGroupLeaveAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) {
        
        _ = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)
        
        for xmppGroupMember in xmppGroup.members ?? [] {
            DDLogDebug("ChatData/group/process/new/add-member [\(xmppGroupMember.userId)]")
            guard xmppGroupMember.action == .leave else { continue }
            deleteChatGroupMember(groupId: xmppGroup.groupId, memberUserId: xmppGroupMember.userId)
            
            recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: xmppGroupMember, in: managedObjectContext)
            
            if xmppGroupMember.userId != MainAppContext.shared.userData.userId {
                getAndSyncGroup(groupId: xmppGroup.groupId)
            }
        }
    
    }

    private func processGroupModifyMembersAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) {
        DDLogDebug("ChatData/group/processGroupModifyMembersAction")
        _ = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)
        
        var syncGroup = false
        for xmppGroupMember in xmppGroup.members ?? [] {
            DDLogDebug("ChatData/group/process/modifyMembers [\(xmppGroupMember.userId)]")
            
            // add pushname first before recording message since user could be new
            var contactNames = [UserID:String]()
            if let name = xmppGroupMember.name, !name.isEmpty {
                contactNames[xmppGroupMember.userId] = name
            }
            if !contactNames.isEmpty {
                contactStore.addPushNames(contactNames)
            }
            
            if xmppGroupMember.action == .remove {
                deleteChatGroupMember(groupId: xmppGroup.groupId, memberUserId: xmppGroupMember.userId)

                // if user is removed, there's no need to sync up group
                if xmppGroupMember.userId != MainAppContext.shared.userData.userId {
                    syncGroup = true
                }
                
            } else {
                syncGroup = true
            }
            
//            if xmppGroupMember.action == .add {
//                processGroupAddMemberAction(chatGroup: chatGroup, xmppGroupMember: xmppGroupMember, in: managedObjectContext)
//            } else if xmppGroupMember.action == .remove {
//                deleteChatGroupMember(groupId: xmppGroup.groupId, memberUserId: xmppGroupMember.userId)
//            }
            
            recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: xmppGroupMember, in: managedObjectContext)
        }
        
        if syncGroup {
            getAndSyncGroup(groupId: xmppGroup.groupId)
        }
    }
    
    private func processGroupChangeNameAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) {
        DDLogDebug("ChatData/group/processGroupChangeNameAction")
        _ = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)
        
        recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: nil, in: managedObjectContext)
        
        getAndSyncGroup(groupId: xmppGroup.groupId)
        
    }
    
    private func processGroupChangeAvatarAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) {
        DDLogDebug("ChatData/group/processGroupChangeAvatarAction")
        
        _ = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)
        
        recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: nil, in: managedObjectContext)
        
        getAndSyncGroup(groupId: xmppGroup.groupId)
        
    }
    
    private func processGroupCreateIfNotExist(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) -> ChatGroup {
        DDLogDebug("ChatData/group/processGroupCreateIfNotExist/ [\(xmppGroup.groupId)]")
        if let existingChatGroup = chatGroup(groupId: xmppGroup.groupId, in: managedObjectContext) {
            DDLogDebug("ChatData/group/processGroupCreateIfNotExist/groupExist [\(xmppGroup.groupId)]")
            return existingChatGroup
        } else {
            return addGroup(xmppGroup: xmppGroup, in: managedObjectContext)
        }
    }
    
    private func addGroup(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) -> ChatGroup {
        DDLogDebug("ChatData/group/addGroup/new [\(xmppGroup.groupId)]")

        // Add Group to database
        let chatGroup = ChatGroup(context: managedObjectContext)
        chatGroup.groupId = xmppGroup.groupId
        chatGroup.name = xmppGroup.name
        
        // Add Chat Thread
        if chatThread(type: .group, id: chatGroup.groupId, in: managedObjectContext) == nil {
            let chatThread = ChatThread(context: managedObjectContext)
            chatThread.type = ChatType.group
            chatThread.groupId = chatGroup.groupId
            chatThread.title = chatGroup.name
            chatThread.lastMsgTimestamp = nil
        }
        return chatGroup
    }
    
    private func recordGroupMessageEvent(xmppGroup: XMPPGroup, xmppGroupMember: XMPPGroupMember?, in managedObjectContext: NSManagedObjectContext) {
        let chatGroupMessage = ChatGroupMessage(context: managedObjectContext)

        if let messageId = xmppGroup.messageId {
            chatGroupMessage.id = messageId
        }
        chatGroupMessage.groupId = xmppGroup.groupId
        chatGroupMessage.timestamp = Date()
        
        let chatGroupMessageEvent = NSEntityDescription.insertNewObject(forEntityName: ChatGroupMessageEvent.entity().name!, into: managedObjectContext) as! ChatGroupMessageEvent
        chatGroupMessageEvent.sender = xmppGroup.sender
        chatGroupMessageEvent.memberUserId = xmppGroupMember?.userId
        chatGroupMessageEvent.groupName = xmppGroup.name
        
        chatGroupMessageEvent.action = {
            switch xmppGroup.action {
            case .create: return .create
            case .leave: return .leave
            case .delete: return .delete
            case .changeName: return .changeName
            case .changeAvatar: return .changeAvatar
            case .modifyAdmins: return .modifyAdmins
            case .modifyMembers: return .modifyMembers
            default: return .none
            }
        }()
        
        chatGroupMessageEvent.memberAction = {
            switch xmppGroupMember?.action {
            case .add: return .add
            case .remove: return .remove
            case .promote: return .promote
            case .demote: return .demote
            case .leave: return .leave
            default: return .none
            }
        }()
        
        chatGroupMessageEvent.groupMessage = chatGroupMessage
        
        save(managedObjectContext)
        
        if let chatThread = self.chatThread(type: .group, id: chatGroupMessage.groupId, in: managedObjectContext) {
            
            // if group feed is not enabled or if the chat already have a message or event
            if !ServerProperties.isGroupFeedEnabled || chatThread.lastMsgId != nil {
                chatThread.lastMsgId = chatGroupMessage.id
                chatThread.lastMsgUserId = chatGroupMessage.userId
                chatThread.lastMsgText = chatGroupMessageEvent.text
                chatThread.lastMsgMediaType = .none
                chatThread.lastMsgStatus = .none
                
                if ![.changeAvatar].contains(chatGroupMessageEvent.action) {
                    chatThread.lastMsgTimestamp = chatGroupMessage.timestamp
                }
            }
            
            chatThread.lastFeedUserID = chatGroupMessage.userId
            chatThread.lastFeedText = chatGroupMessageEvent.text
            
            if ![.changeAvatar, .modifyAdmins, .modifyMembers].contains(chatGroupMessageEvent.action) {
                chatThread.lastFeedTimestamp = chatGroupMessage.timestamp
            }
            // unreadCount is not incremented for group event messages
        }
    }
    
    
    private func processGroupAddMemberAction(chatGroup: ChatGroup, xmppGroupMember: XMPPGroupMember, in managedObjectContext: NSManagedObjectContext) {
        DDLogDebug("ChatData/group/processGroupAddMemberAction/member [\(xmppGroupMember.userId)]")
        guard let xmppGroupMemberType = xmppGroupMember.type else { return }
        if let existingMember = chatGroupMember(groupId: chatGroup.groupId, memberUserId: xmppGroupMember.userId, in: managedObjectContext) {
            switch xmppGroupMemberType {
            case .member:
                existingMember.type = .member
            case .admin:
                existingMember.type = .admin
            }
        } else {
            let member = ChatGroupMember(context: managedObjectContext)
            member.groupId = chatGroup.groupId
            member.userId = xmppGroupMember.userId
            switch xmppGroupMemberType {
            case .member:
                member.type = .member
            case .admin:
                member.type = .admin
            }
            member.group = chatGroup
        }
    }
}

// MARK: Group - Process Pending Tasks
extension ChatData {
    
    private func processPendingGroupChatMsgs() {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            let pendingOutboundGroupChatMsgs = self.pendingOutboundGroupChatMsgs(in: managedObjectContext)
            DDLogInfo("ChatData/processPendingGroupChatMsgs/num: \(pendingOutboundGroupChatMsgs.count)")
            
            // inject delay between between sends so msgs won't be acked and timestamped on the same second,
            // which causes display of messages to be in random order
            var timeDelay = 0.0
            pendingOutboundGroupChatMsgs.forEach { groupChatMsg in
                guard let msgTimestamp = groupChatMsg.timestamp else { return }
                guard abs(msgTimestamp.timeIntervalSinceNow) <= Date.hours(24) else { return }
                
                DDLogInfo("ChatData/processPendingGroupChatMsgs \(groupChatMsg.id)")
                let outgoingMessage = XMPPChatGroupMessage(chatGroupMessage: groupChatMsg)

                self.backgroundProcessingQueue.asyncAfter(deadline: .now() + timeDelay) {
                    self.uploadGroupChatMsgMediaAndSend(xmppGroupChatMsg: outgoingMessage)
                }
                timeDelay += 1.0
            }
        }
    }
    
    private func processRetractingGroupChatMsgs() {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            let retractingOutboundGroupChatMsgs = self.retractingOutboundGroupChatMsgs(in: managedObjectContext)
            DDLogInfo("ChatData/processRetractingGroupChatMsgs/num: \(retractingOutboundGroupChatMsgs.count)")

            retractingOutboundGroupChatMsgs.forEach { groupChatMsg in
                guard let messageID = groupChatMsg.retractID else { return }
                DDLogInfo("ChatData/processRetractingGroupChatMsgs \(groupChatMsg.id)")
                let groupID = groupChatMsg.groupId
                let msgToRetractID = groupChatMsg.id
                
                self.service.retractGroupChatMessage(messageID: messageID, groupID: groupID, messageToRetractID: msgToRetractID)
            }
        }
    }
    
    private func processPendingGroupChatSeenReceipts() {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            let pendingSeenReceipts = self.pendingGroupChatSeenReceipts(in: managedObjectContext)
            DDLogInfo("ChatData/processPendingGroupChatSeenReceipts/num: \(pendingSeenReceipts.count)")
            
            pendingSeenReceipts.forEach {
                DDLogInfo("ChatData/processPendingGroupChatSeenReceipts/seenReceipts \($0.id)")
                self.sendSeenGroupReceipt(for: $0)
            }
        }
    }
}

// MARK: Group Notifications
extension ChatData {
    
    private func showGroupNotification(for xmppChatGroupMessage: XMPPChatGroupMessage) {
        DDLogVerbose("ChatData/showGroupNotification/id \(xmppChatGroupMessage.id)")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch UIApplication.shared.applicationState {
            case .background, .inactive:
                self.presentLocalGroupNotifications(for: xmppChatGroupMessage)
            case .active:
                guard !self.isAtChatListViewTop() else {
                    DDLogVerbose("ChatData/showGroupNotification/isAtChatListViewTop/skip")
                    return
                }
                guard self.currentlyChattingInGroup != xmppChatGroupMessage.groupId else {
                    DDLogVerbose("ChatData/showGroupNotification/currentlyChattingInGroup/skip")
                    return
                }
                self.presentGroupBanner(for: xmppChatGroupMessage)
            @unknown default:
                self.presentLocalGroupNotifications(for: xmppChatGroupMessage)
            }
        }
    }
    
    private func presentGroupBanner(for xmppChatGroupMessage: XMPPChatGroupMessage) {
        DDLogDebug("ChatData/presentGroupBanner/id \(xmppChatGroupMessage.id)")
        let groupID = xmppChatGroupMessage.groupId
        guard let userID = xmppChatGroupMessage.userId else { return }
        guard let groupName = xmppChatGroupMessage.groupName else { return }
        
        let name = contactStore.fullName(for: userID)
        
        let title = "\(name) @ \(groupName)"
        
        var body = ""
        
        let attrMentionText = contactStore.textWithMentions(xmppChatGroupMessage.text, orderedMentions: xmppChatGroupMessage.orderedMentions)
        
        body += attrMentionText?.string ?? ""
        
        if !xmppChatGroupMessage.media.isEmpty {
            var mediaStr = "📷"
            if let firstMedia = xmppChatGroupMessage.media.first {
                if firstMedia.type == .video {
                    mediaStr = "📹"
                }
            }
            
            if body.isEmpty {
                body = mediaStr
            } else {
                body = "\(mediaStr) \(body)"
            }
        }
        
        Banner.show(title: title, body: body, groupID: groupID, using: MainAppContext.shared.avatarStore)
    }
    
    private func presentLocalGroupNotifications(for xmppChatGroupMessage: XMPPChatGroupMessage) {
        DDLogDebug("ChatData/presentLocalGroupNotifications/id \(xmppChatGroupMessage.id)")
        guard let userID = xmppChatGroupMessage.userId else { return }
        
        var notifications: [UNMutableNotificationContent] = []
        
        let protoContainer = xmppChatGroupMessage.protoContainer
        let protobufData = try? protoContainer.serializedData()
                
        let metadata = NotificationMetadata(contentId: xmppChatGroupMessage.id,
                                            contentType: .groupChatMessage,
                                            fromId: userID,
                                            data: protobufData,
                                            timestamp: xmppChatGroupMessage.timestamp)
        metadata.groupId = xmppChatGroupMessage.groupId
        metadata.groupName = xmppChatGroupMessage.groupName
        
        let notification = UNMutableNotificationContent()
        notification.title = contactStore.fullName(for: userID)
        notification.populate(withDataFrom: protoContainer, notificationMetadata: metadata, mentionNameProvider: { userID in
            contactStore.mentionName(for: userID, pushName: protoContainer.mentionPushName(for: userID))
        })
        
        notification.userInfo[NotificationMetadata.userInfoKey] = metadata.rawData
        notifications.append(notification)
        
        let notificationCenter = UNUserNotificationCenter.current()
        notifications.forEach { (notificationContent) in
            notificationCenter.add(UNNotificationRequest(identifier: UUID().uuidString, content: notificationContent, trigger: nil))
            incrementApplicationIconBadgeNumber()
        }
        
    }
}

extension ChatData: HalloChatDelegate {

    // MARK: XMPP Chat Delegates
    
    func halloService(_ halloService: HalloService, didReceiveMessageReceipt receipt: HalloReceipt, ack: (() -> Void)?) {
        DDLogDebug("ChatData/didReceiveMessageReceipt [\(receipt.itemId)] \(receipt)")
        
        switch receipt.thread {
        case .none:
            processInboundOneToOneMessageReceipt(with: receipt)
            break
        case .group(let groupId):
            processInboundGroupMessageReceipt(with: receipt, for: groupId)
            break
        default: break
        }

        ack?()
    }

    func halloService(_ halloService: HalloService, didRerequestMessage messageID: String, from userID: UserID, ack: (() -> Void)?) {
        DDLogDebug("ChatData/didRerequestMessage [\(messageID)]")

        handleRerequest(for: messageID, from: userID)
        ack?()
    }

    func halloService(_ halloService: HalloService, didSendMessageReceipt receipt: HalloReceipt) {
        switch receipt.thread {
        case .none:
            self.updateChatMessage(with: receipt.itemId) { (chatMessage) in
                DDLogDebug("ChatData/oneToOne/didSendMessageReceipt [\(receipt.itemId)]")
                guard chatMessage.incomingStatus == .haveSeen else { return }
                chatMessage.incomingStatus = .sentSeenReceipt
            }
            break
        case .group(_):
            self.updateChatGroupMessage(with: receipt.itemId) { (chatGroupMessage) in
                DDLogDebug("ChatData/group/didSendMessageReceipt [\(receipt.itemId)]")
                guard chatGroupMessage.inboundStatus == .haveSeen else { return }
                chatGroupMessage.inboundStatus = .sentSeenReceipt
            }
            break
        default: break
        }
    }
    
    func halloService(_ halloService: HalloService, didReceiveGroupChatMessage message: HalloGroupChatMessage) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.didGetAGroupChatMsg.send(message.groupId)
            
            let isAppActive = UIApplication.shared.applicationState == .active
            
            self.performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
                guard let self = self else { return }
                self.processInboundChatGroupMessage(xmppChatGroupMessage: message, using: managedObjectContext, isAppActive: isAppActive)
            }
        }
    }

    func halloService(_ halloService: HalloService, didReceiveGroupMessage group: HalloGroup) {
        processIncomingXMPPGroup(group)
    }
}


extension XMPPChatMessage {
    
    // for outbound message
    init(chatMessage: ChatMessage) {
        self.id = chatMessage.id
        self.fromUserId = chatMessage.fromUserId
        self.toUserId = chatMessage.toUserId
        self.text = chatMessage.text
        self.feedPostId = chatMessage.feedPostId
        self.feedPostMediaIndex = chatMessage.feedPostMediaIndex
        
        self.chatReplyMessageID = chatMessage.chatReplyMessageID
        self.chatReplyMessageSenderID = chatMessage.chatReplyMessageSenderID
        self.chatReplyMessageMediaIndex = chatMessage.chatReplyMessageMediaIndex
        self.rerequestCount = Int32(chatMessage.resendAttempts)
        
        if let media = chatMessage.media {
            self.media = media.sorted(by: { $0.order < $1.order }).map{ XMPPChatMedia(chatMedia: $0) }
        } else {
            self.media = []
        }
    }

    init(_ protoChat: Clients_ChatMessage, timestamp: Int64, from fromUserID: UserID, to toUserID: UserID, id: String, retryCount: Int32) {
        self.id = id
        self.fromUserId = fromUserID
        self.toUserId = toUserID
        self.timestamp = TimeInterval(timestamp)
        self.retryCount = retryCount
        self.rerequestCount = 0 // we don't care about rerequest count for incoming messages
        
        text = protoChat.text.isEmpty ? nil : protoChat.text
        media = protoChat.media.compactMap { XMPPChatMedia(protoMedia: $0) }
        feedPostId = protoChat.feedPostID.isEmpty ? nil : protoChat.feedPostID
        feedPostMediaIndex = protoChat.feedPostMediaIndex
        
        chatReplyMessageID = protoChat.chatReplyMessageID.isEmpty ? nil : protoChat.chatReplyMessageID
        chatReplyMessageSenderID = protoChat.chatReplyMessageSenderID.isEmpty ? nil : protoChat.chatReplyMessageSenderID
        chatReplyMessageMediaIndex = protoChat.chatReplyMessageMediaIndex
    }
}

extension Clients_ChatMessage {
    init?(containerData: Data) {
        if let protoContainer = try? Clients_Container(serializedData: containerData),
            protoContainer.hasChatMessage
        {
            // Binary protocol
            self = protoContainer.chatMessage
        } else if let decodedData = Data(base64Encoded: containerData, options: .ignoreUnknownCharacters),
            let protoContainer = try? Clients_Container(serializedData: decodedData),
            protoContainer.hasChatMessage
        {
            // Legacy Base64 protocol
            self = protoContainer.chatMessage
        } else {
            return nil
        }
    }
}
