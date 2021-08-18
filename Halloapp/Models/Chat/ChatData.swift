//
//  HalloApp
//
//  Created by Tony Jiang on 4/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreData
import Foundation
import UIKit
import Intents
import IntentsUI

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
    
    let didGetMediaUploadProgress = PassthroughSubject<(String, Float), Never>()
    let didGetMediaDownloadProgress = PassthroughSubject<(String, Int, Double), Never>()
    
    let didGetAGroupFeed = PassthroughSubject<GroupID, Never>()
    let didGetAChatMsg = PassthroughSubject<UserID, Never>()
    let didGetAGroupEvent = PassthroughSubject<GroupID, Never>()
    
    private let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.chat")
    
    private let userData: UserData
    private let contactStore: ContactStoreMain
    private var service: HalloService
    private let mediaUploader: MediaUploader
    private let imageServer = ImageServer()
    private let groupList = GroupList()
    
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
    
    private let uploadQueue = DispatchQueue(label: "com.halloapp.chat.upload")
    
    private let downloadQueue = DispatchQueue(label: "com.halloapp.chat.download")
    private let maxNumDownloads: Int = 3
    private var currentlyDownloading: [URL] = []
    private let maxTries: Int = 100
    
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
    
    func deletePersistentContainer() {
        do {
            try FileManager.default.removeItem(at: MainAppContext.chatStoreURL)
            DDLogInfo("ChatData/deletePersistentContainer: Deleted chat data")
        } catch {
            DDLogError("ChatData/deletePersistentContainer: Error deleting chat data: \(error)")
        }
    }
    
    var viewContext: NSManagedObjectContext
    private var bgContext: NSManagedObjectContext
    
    private struct UserDefaultsKey {
        static let persistentStoreUserID = "chat.store.userID"  // deprecated, remove after cleanup
        static let persistentAppVersion = "ChatDataAppVersion"
        static let GroupsLastSyncTime = "GroupsLastSyncTime"
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
        
        cancellableSet.insert(
            mediaUploader.uploadProgressDidChange.sink { [weak self] (groupId, progress) in
                guard let self = self else { return }
                guard let chatMessage = self.chatMessage(with: groupId) else { return }                
                self.didGetMediaUploadProgress.send((chatMessage.id, progress))
            }
        )

        var shouldGetGroupsList = false

        cancellableSet.insert(
            service.didGetChatAck.sink { [weak self] chatAck in
                guard let self = self else { return }
                DDLogInfo("ChatData/didGetChatAck \(chatAck.id)")
                self.processInboundChatAck(chatAck)
            }
        )

        cancellableSet.insert(
            service.didGetNewChatMessage.sink { [weak self] incomingMessage in
                self?.processIncomingChatMessage(incomingMessage)
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
                    let isInbound = feedPost.userId != MainAppContext.shared.userData.userId
                    DDLogInfo("ChatData/didMergeFeedPost")

                    self.didGetAGroupFeed.send(groupID)

                    self.performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
                        guard let self = self else { return }
                        self.updateThreadWithGroupFeed(postID, isInbound: isInbound, using: managedObjectContext)
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
                    
                    var groupThreadIDs = self.groupThreads().compactMap({ $0.groupId })
                    
                    statesList.forEach({ (groupID, state) in
                        switch state {
                        case .noPosts:
                            break
                        case .newPosts(let numNew, _):
                            self.setThreadUnreadFeedCount(type: .group, for: groupID, num: Int32(numNew))
                        case .seenPosts(_):
                            self.updateChatThread(type: .group, for: groupID, block: { thread in
                                guard thread.unreadFeedCount > 0 else { return }
                                thread.unreadFeedCount = 0
                                self.updateUnreadThreadGroupsCount()
                            })
                        }
                        
                        groupThreadIDs.removeAll(where: { $0 == groupID })
                    })
                    
                    // leftover groupThreadIDs not found in groupFeedStates mean those groups do not have
                    // any posts in feed and should reset its unread counter to 0
                    groupThreadIDs.forEach({
                        self.updateChatThread(type: .group, for: $0, block: { thread in
                            guard thread.unreadFeedCount > 0 else { return }
                            thread.unreadFeedCount = 0
                            self.updateUnreadThreadGroupsCount()
                        })
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

                if (UIApplication.shared.applicationState == .active) {
                    DDLogDebug("ChatData/didConnect/currentlyDownloading/num/\(self.currentlyDownloading.count)/removeAll")
                    self.removeAllCurrentDownloads()
                    self.processInboundPendingChatMsgMedia()
                }

                // cleanup: remove old key for at least a few builds from 117 onward
                if MainAppContext.shared.userDefaults?.string(forKey: UserDefaultsKey.persistentStoreUserID) != nil {
                    MainAppContext.shared.userDefaults.removeObject(forKey: UserDefaultsKey.persistentStoreUserID)
                }

                if MainAppContext.shared.userDefaults?.string(forKey: UserDefaultsKey.persistentAppVersion) != MainAppContext.appVersionForDisplay {
                    DDLogInfo("ChatData/app version change from stored version of: \(MainAppContext.shared.userDefaults?.string(forKey: UserDefaultsKey.persistentAppVersion) ?? "")")
                    MainAppContext.shared.userDefaults?.setValue(MainAppContext.appVersionForDisplay, forKey: UserDefaultsKey.persistentAppVersion)
                    shouldGetGroupsList = true
                }

                if let groupLastSyncDouble = MainAppContext.shared.userDefaults?.double(forKey: UserDefaultsKey.GroupsLastSyncTime) {
                    let groupLastSyncDate = Date(timeIntervalSince1970: groupLastSyncDouble)

                    if let diff = Calendar.current.dateComponents([.second], from: groupLastSyncDate, to: Date()).second, diff > ServerProperties.groupSyncTime {
                        DDLogInfo("ChatData/groups haven't sync for a while, sync now")
                        shouldGetGroupsList = true
                    }
                }

                if shouldGetGroupsList {
                    self.getGroupsList()
                    shouldGetGroupsList = false
                    MainAppContext.shared.userDefaults?.setValue(Date().timeIntervalSince1970, forKey: UserDefaultsKey.GroupsLastSyncTime)
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

                // clear the typing indicators
                self.chatStateInfoList.removeAll()
                self.didGetChatStateInfo.send()
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

        groupList.listenForChanges(using: bgContext)
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

    func populateThreadsWithAllContacts() {
        let contactStore = MainAppContext.shared.contactStore
        let contacts = contactStore.allRegisteredContacts(sorted: true)
        DDLogInfo("ChatData/populateThreadsWithAllContacts/allInNetworkContacts: \(contacts.count)")
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
                        DDLogDebug("ChatData/updateThreads/contact/rename \(userId)")
                        self.updateChatThread(type: .oneToOne, for: userId) { (chatThread) in
                            chatThread.title = fullName
                        }
                    }
                } else {
                    
                    DDLogInfo("ChatData/updateThreads/contact/new \(userId)")
                    let chatThread = ChatThread(context: managedObjectContext)
                    chatThread.title = fullName
                    chatThread.chatWithUserId = userId
                    chatThread.lastMsgUserId = userId
                    chatThread.lastMsgText = nil
                    if areNewUsers {
                        chatThread.lastMsgTimestamp = timestampForNewThreads
                    }
                    chatThread.unreadCount = 0
                    chatThread.isNew = areNewUsers
                }
            }

            // save updates
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }

            /* remove empty threads of users not in the address book */
            let emptyOneToOneChatThreads = self.emptyOneToOneChatThreads(in: managedObjectContext)
            emptyOneToOneChatThreads.forEach({
                guard let chatWithUserID = $0.chatWithUserId else { return }
                guard userIDs[chatWithUserID] == nil else { return }
                DDLogInfo("ChatData/updateThreads/emptyOneToOneChatThreads/remove \(chatWithUserID)")
                self.deleteChat(chatThreadId: chatWithUserID)
            })

            // save deletes
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }

    private func appendToCurrentDownloads(url: URL?) {
        guard let url = url else { return }
        downloadQueue.sync { [weak self] in
            self?.currentlyDownloading.append(url)
        }
    }

    private func removeAllCurrentDownloads() {
        downloadQueue.sync { [weak self] in
            self?.currentlyDownloading.removeAll()
        }
    }

    private func removeFromCurrentDownloads(url: URL?) {
        guard let url = url else { return }
        downloadQueue.sync { [weak self] in
            guard let self = self else { return }
            if let index = self.currentlyDownloading.firstIndex(of: url) {
                self.currentlyDownloading.remove(at: index)
            }
        }
    }

    func processInboundPendingChatMsgMedia() {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            guard self.currentlyDownloading.count <= self.maxNumDownloads else { return }

            let pendingMessagesWithMedia = self.pendingIncomingChatMessagesMedia(in: managedObjectContext)
            
            for chatMessage in pendingMessagesWithMedia {
                
                guard let media = chatMessage.media else { continue }
                
                let sortedMedia = media.sorted(by: { $0.order < $1.order })
                guard let med = sortedMedia.first(where: {
                    guard let url = $0.url else { return false }
                    guard $0.incomingStatus == .pending else { return false }
                    guard !self.currentlyDownloading.contains(url) else { return false }
                    if $0.numTries > self.maxTries {
                        DDLogDebug("ChatData/processInboundPendingChatMsgMedia/\(chatMessage.id)/media/order/\($0.order)/reached maxTries: \(self.maxTries), numTries: \($0.numTries)")
                        return false
                    }
                    return true
                } ) else { continue }
                
                DDLogDebug("ChatData/processInboundPendingChatMsgMedia/\(chatMessage.id)/media/order/\(med.order)")
                
                guard let url = med.url else { continue }
                
                self.appendToCurrentDownloads(url: url)

                let threadId = chatMessage.fromUserId
                let messageId = chatMessage.id
                let order = med.order
                let key = med.key
                let sha = med.sha256
                let type: FeedMediaType = {
                    switch med.type {
                    case .image:
                        return .image
                    case .video:
                        return .video
                    case .audio:
                        return .audio
                    }
                } ()
            
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
                    self.removeFromCurrentDownloads(url: url)
                    
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
                        DDLogDebug("ChatData/processInboundPendingChatMsgMedia/\(chatMessage.id)/media/order/\(med.order)/could not decrypt media data")
                        return
                    }

                    MainAppContext.shared.uploadData.update(upload: decryptedData, key: key, sha256: sha, downloadURL: url)

                    let fileExtension: String = {
                        switch type {
                        case .image:
                            return "jpg"
                        case .video:
                            return "mp4"
                        case .audio:
                            return "aac"
                        }
                    } ()
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
                    do {
                        if FileManager.default.fileExists(atPath: fileURL.path) {
                            DDLogDebug("ChatData/processInboundPendingChatMsgMedia/\(chatMessage.id)/media/order/\(med.order)/previous file exists, try removing first: \(fileURL.path)")
                            try FileManager.default.removeItem(atPath: fileURL.path)
                        }
                    }
                    catch {
                        DDLogError("ChatData/processInboundPendingChatMsgMedia/\(chatMessage.id)/media/order/\(med.order)/remove previous file error: \(error)")
                    }

                    do {
                        try decryptedData.write(to: fileURL, options: [])
                    }
                    catch {
                        DDLogError("ChatData/processInboundPendingChatMsgMedia/\(chatMessage.id)/media/order/\(med.order)/can't write error: \(error)")
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
            chatMessage.serverTimestamp = serverTimestamp

            self.processPendingChatMsgs()
        }

        // search for retracting 1-1 message
        updateRetractingChatMessage(for: messageID) { (chatMessage) in
            DDLogDebug("ChatData/processInboundChatAck/updateRetractingChatMessage/ [\(messageID)]")
            chatMessage.outgoingStatus = .retracted
            
            self.updateChatThreadStatus(type: .oneToOne, for: chatMessage.toUserId, messageId: messageID) { (chatThread) in
                chatThread.lastMsgStatus = .retracted
            }
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

        let fileExtension: String = {
            switch chatMedia.type {
            case .image:
                return "jpg"
            case .video:
                return "mp4"
            case .audio:
                return "aac"
            }
        } ()
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
    
    // TODO(murali@): need to do some sort of migration for the existing media elements in the db.
    func copyMediaToQuotedMedia(fromDir: URL, fromPath: String?, to quotedMedia: ChatQuotedMedia) throws {
        guard let fromRelativePath = fromPath else {
            return
        }
        let fromURL = fromDir.appendingPathComponent(fromRelativePath, isDirectory: false)
        DDLogInfo("ChatData/copyMediaToQuotedMedia/fromURL: \(fromURL)")

        // Store references to the quoted media directory and file path.
        if fromDir == MainAppContext.chatMediaDirectoryURL {
            quotedMedia.mediaDirectory = .chatMedia
        } else if fromDir == MainAppContext.mediaDirectoryURL {
            quotedMedia.mediaDirectory = .media
        }
        quotedMedia.relativeFilePath = fromRelativePath

        // Generate thumbnail for the media: so that each message can have its own copy.
        let previewImage: UIImage?
        switch quotedMedia.type {
        case .image:
            previewImage = UIImage(contentsOfFile: fromURL.path)
        case .video:
            previewImage = VideoUtils.videoPreviewImage(url: fromURL)
        case .audio:
            previewImage = nil // no image to preview
        }
        guard let img = previewImage else {
            DDLogError("ChatData/copyMediaToQuotedMedia/unable to generate thumbnail image for media url: \(fromURL)")
            return
        }
        quotedMedia.previewData = VideoUtils.previewImageData(image: img)
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
        var mergedMessages = [(SharedChatMessage, ChatMessage)]()
        for message in messages {
            let messageId: ChatMessageID = message.id
            DDLogInfo("ChatData/mergeSharedData/message/\(messageId)")

            if let existingChatmessage = chatMessage(with: messageId, in: managedObjectContext) {
                if existingChatmessage.incomingStatus == .rerequesting &&
                    (message.status == .received || message.status == .acked) {
                    DDLogInfo("ChatData/mergeSharedData/already-exists [\(messageId)] override failed decryption.")
                } else {
                    DDLogError("ChatData/mergeSharedData/already-exists [\(messageId)] dont override.")
                    continue
                }
            }
            DDLogInfo("ChatData/mergeSharedData/merging message/\(messageId)")

            let chatContent: ChatContent?
            let chatContext: ChatContext?
            if let clientChatMsgPb = message.clientChatMsgPb {
                if let chatContainer = try? Clients_ChatContainer(serializedData: clientChatMsgPb) {
                    chatContent = chatContainer.chatContent
                    chatContext = chatContainer.chatContext
                } else if let clientChat = try? Clients_ChatMessage(serializedData: clientChatMsgPb) {
                    chatContent = clientChat.chatContent
                    chatContext = clientChat.chatContext
                } else {
                    DDLogError("ChatData/mergeSharedData/failed to extract clientChatMsg: [\(clientChatMsgPb.bytes)]")
                    continue
                }
            } else {
                chatContent = nil
                chatContext = nil
            }

            let chatMessage = NSEntityDescription.insertNewObject(forEntityName: ChatMessage.entity().name!, into: managedObjectContext) as! ChatMessage
            chatMessage.id = messageId
            chatMessage.toUserId = message.toUserId
            chatMessage.fromUserId = message.fromUserId
            chatMessage.feedPostId = chatContext?.feedPostID
            chatMessage.feedPostMediaIndex = chatContext?.feedPostMediaIndex ?? 0
            chatMessage.chatReplyMessageID = chatContext?.chatReplyMessageID
            chatMessage.chatReplyMessageSenderID = chatContext?.chatReplyMessageSenderID
            chatMessage.chatReplyMessageMediaIndex = chatContext?.chatReplyMessageMediaIndex ?? 0
            chatMessage.timestamp = message.timestamp // is this okay for tombstones?
            chatMessage.serverTimestamp = message.serverTimestamp
            DDLogDebug("ChatData/mergeSharedData/ChatData/\(messageId)/serialId [\(message.serialID)]")
            chatMessage.serialID = message.serialID

            // message could be incoming or outgoing.
            DDLogInfo("ChatData/mergeSharedData/message/\(messageId), status: \(message.status)")
            switch message.status {
            case .none:
                chatMessage.incomingStatus = .none
                chatMessage.outgoingStatus = .error
            case .sent:
                chatMessage.incomingStatus = .none
                chatMessage.outgoingStatus = .sentOut
            case .received, .acked:
                chatMessage.incomingStatus = .none
                chatMessage.outgoingStatus = .none
            case .sendError:
                chatMessage.incomingStatus = .none
                chatMessage.outgoingStatus = .error
            case .decryptionError, .rerequesting:
                // this is for tombstones.
                chatMessage.incomingStatus = .rerequesting
                chatMessage.outgoingStatus = .none
                mergedMessages.append((message, chatMessage))
                continue
            }
            // Check if the message is an incoming message.
            let isIncomingMsg = message.status == .received || message.status == .acked

            switch chatContent {
            case .album(let text, _):
                chatMessage.text = text
            case .text(let text):
                chatMessage.text = text
            case .voiceNote(_):
                chatMessage.text = ""
            case .unsupported(let data):
                chatMessage.rawData = data
                // Overwrite incoming status for unsupported messages
                chatMessage.incomingStatus = .unsupported
            case .none:
                chatMessage.text = message.text
            }

            var lastMsgMediaType: ChatThread.LastMediaType = .none
            message.media?.forEach { media in
                DDLogInfo("ChatData/mergeSharedData/message/\(messageId)/add-media [\(media)], status: \(media.status)")
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
                case .audio:
                    chatMedia.type = .audio
                    if lastMsgMediaType == .none {
                        lastMsgMediaType = .audio
                    }
                }
                // set incoming and outgoing status.
                switch media.status {
                case .none:
                    chatMedia.incomingStatus = isIncomingMsg ? .pending : .none
                    chatMedia.outgoingStatus = .none
                case .downloaded:
                    chatMedia.incomingStatus = .downloaded
                    chatMedia.outgoingStatus = .none
                case .uploaded:
                    chatMedia.incomingStatus = .none
                    chatMedia.outgoingStatus = .uploaded
                case .error, .uploading:
                    chatMedia.incomingStatus = .none
                    chatMedia.outgoingStatus = .error
                }
                chatMedia.url = media.url
                chatMedia.uploadUrl = media.uploadUrl
                chatMedia.size = media.size
                chatMedia.key = media.key
                chatMedia.order = media.order
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

            // Process quoted content.
            if let feedPostId = chatMessage.feedPostId, !feedPostId.isEmpty {
                // Process Quoted Feedpost
                if let quotedFeedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId) {
                    copyQuoted(to: chatMessage, from: quotedFeedPost, using: managedObjectContext)
                }
            } else if let chatReplyMsgId = chatMessage.chatReplyMessageID, !chatReplyMsgId.isEmpty {
                // Process Quoted Message: these messages could be in the main database or in the shared database.
                // so we first lookup the main database and then our list of mergedMessages.
                // we ensure that messages are fetched in the correct order.
                if let quotedChatMessage = MainAppContext.shared.chatData.chatMessage(with: chatReplyMsgId) {
                    copyQuoted(to: chatMessage, from: quotedChatMessage, using: managedObjectContext)
                } else if let quotedChatMessage = mergedMessages.first(where: { $0.1.id == chatReplyMsgId })?.1 {
                    copyQuoted(to: chatMessage, from: quotedChatMessage, using: managedObjectContext)
                }
            }

            // TODO(murali@): this code is duplicated.
            let threadId = isIncomingMsg ? chatMessage.fromUserId : chatMessage.toUserId
            let isCurrentlyChattingWithUser = isCurrentlyChatting(with: threadId)
            if let chatThread = chatThread(type: ChatType.oneToOne, id: threadId, in: managedObjectContext) {
                chatThread.lastMsgId = chatMessage.id
                chatThread.lastMsgUserId = chatMessage.fromUserId
                chatThread.lastMsgText = chatMessage.text
                chatThread.lastMsgMediaType = lastMsgMediaType
                chatThread.lastMsgStatus = .none
                chatThread.lastMsgTimestamp = chatMessage.timestamp
                if isIncomingMsg {
                    chatThread.unreadCount = isCurrentlyChattingWithUser ? 0 : chatThread.unreadCount + 1
                }
            } else {
                let chatThread = NSEntityDescription.insertNewObject(forEntityName: ChatThread.entity().name!, into: managedObjectContext) as! ChatThread
                chatThread.chatWithUserId = threadId
                chatThread.lastMsgId = chatMessage.id
                chatThread.lastMsgUserId = chatMessage.fromUserId
                chatThread.lastMsgText = chatMessage.text
                chatThread.lastMsgMediaType = lastMsgMediaType
                chatThread.lastMsgStatus = .none
                chatThread.lastMsgTimestamp = chatMessage.timestamp
                if isIncomingMsg {
                    chatThread.unreadCount = 1
                }
            }
            mergedMessages.append((message, chatMessage))
        }
        save(managedObjectContext)

        mergedMessages.forEach({ (sharedMsg, chatMsg) in
            unreadMessageCount += 1
            updateUnreadChatsThreadCount()
            if let senderClientVersion = sharedMsg.senderClientVersion, let chatTimestamp = chatMsg.timestamp, let serverMsgPb = sharedMsg.serverMsgPb {
                do {
                    var error: DecryptionError? = nil
                    if let rawValue = sharedMsg.decryptionError {
                        error = DecryptionError(rawValue: rawValue)
                    }
                    let serverMsg = try Server_Msg(serializedData: serverMsgPb)
                    reportDecryptionResult(
                        error: error,
                        messageID: chatMsg.id,
                        timestamp: chatTimestamp,
                        sender: UserAgent(string: senderClientVersion),
                        rerequestCount: Int(serverMsg.rerequestCount),
                        isSilent: false)
                    DDLogInfo("ChatData/mergeSharedData/reported decryption result \(sharedMsg.decryptionError ?? "no-error") for msg: \(chatMsg.id)")
                } catch {
                    DDLogError("ChatData/mergeSharedData/Unable to initialize Server_Msg")
                }
            } else {
                DDLogError("ChatData/mergeSharedData/could not report decryption result, messageId: \(chatMsg.id)")
            }
            didGetAChatMsg.send(chatMsg.fromUserId)
        })

        // download chat message media
        processInboundPendingChatMsgMedia()

        DDLogInfo("ChatData/mergeSharedData/finished")

        sharedDataStore.delete(messages: messages) {
            completion()
        }
    }

    // TODO: duplicate code from ProtoService.swift
    private func reportDecryptionResult(error: DecryptionError?, messageID: String, timestamp: Date, sender: UserAgent?, rerequestCount: Int, isSilent: Bool) {
        AppContext.shared.eventMonitor.count(.decryption(error: error, sender: sender))
        if let sender = sender {
            MainAppContext.shared.cryptoData.update(
                messageID: messageID,
                timestamp: timestamp,
                result: error?.rawValue ?? "success",
                rerequestCount: rerequestCount,
                sender: sender,
                isSilent: isSilent)
        } else {
            DDLogError("ChatData/reportDecryptionResult/\(messageID)/decrypt/error missing sender user agent")
        }
    }

    // This function can nicely copy references to quoted feed post or quoted message to the new chatMessage.
    private func copyQuoted(to chatMessage: ChatMessage, from chatQuoted: ChatQuotedProtocol, using managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("ChatData/copyQuoted/message/\(chatMessage.id), chatQuotedType: \(chatQuoted.type)")
        let quoted = NSEntityDescription.insertNewObject(forEntityName: ChatQuoted.entity().name!, into: managedObjectContext) as! ChatQuoted
        quoted.type = chatQuoted.type
        quoted.userId = chatQuoted.userId
        quoted.text = chatQuoted.text
        quoted.message = chatMessage

        quoted.mentions = {
            guard let mentions = chatQuoted.mentions, !mentions.isEmpty else { return nil }
            var chatMentions = Set<ChatMention>()
            for mention in mentions {
                let chatMention = NSEntityDescription.insertNewObject(forEntityName: ChatMention.entity().name!, into: managedObjectContext) as! ChatMention
                chatMention.index = mention.index
                chatMention.userID = mention.userID
                chatMention.name = mention.name
                chatMentions.insert(chatMention)
            }
            return chatMentions
        }()

        // TODO: Why Int16? - other classes have Int32 for the order attribute.
        var mediaIndex: Int16 = 0
        var mediaFromDir: URL = MainAppContext.mediaDirectoryURL
        // Ensure Id of the quoted object is not empty - postId/msgId.
        if let feedPostId = chatMessage.feedPostId, !feedPostId.isEmpty {
            mediaIndex = Int16(chatMessage.feedPostMediaIndex)
            mediaFromDir = MainAppContext.mediaDirectoryURL
        } else if let chatReplyMessageID = chatMessage.chatReplyMessageID, !chatReplyMessageID.isEmpty {
            mediaIndex = Int16(chatMessage.chatReplyMessageMediaIndex)
            mediaFromDir = MainAppContext.chatMediaDirectoryURL
        }
        if let chatQuotedMediaItem = chatQuoted.mediaList.first(where: { $0.order == mediaIndex }) {
            DDLogInfo("ChatData/copyQuoted/message/\(chatMessage.id), chatQuotedMediaIndex: \(chatQuotedMediaItem.order)")
            let quotedMedia = NSEntityDescription.insertNewObject(forEntityName: ChatQuotedMedia.entity().name!, into: managedObjectContext) as! ChatQuotedMedia
            quotedMedia.type = chatQuotedMediaItem.quotedMediaType
            quotedMedia.order = chatQuotedMediaItem.order
            quotedMedia.width = Float(chatQuotedMediaItem.width)
            quotedMedia.height = Float(chatQuotedMediaItem.height)
            quotedMedia.quoted = quoted
            do {
                try copyMediaToQuotedMedia(fromDir: mediaFromDir, fromPath: chatQuotedMediaItem.relativeFilePath, to: quotedMedia)
            } catch {
                DDLogError("ChatData/new-msg/quoted/copy-media/error [\(error)]")
            }
        }
    }
    
    private func incrementApplicationIconBadgeNumber() {
        DispatchQueue.main.async {
            let badgeNum = MainAppContext.shared.applicationIconBadgeNumber
            MainAppContext.shared.applicationIconBadgeNumber = badgeNum == -1 ? 1 : badgeNum + 1
        }
    }
    
    // MARK: Helpers
    
    private func isAtChatListViewTop() -> Bool {
        guard let keyWindow = UIApplication.shared.windows.filter({$0.isKeyWindow}).first else { return false }
        guard let topController = keyWindow.rootViewController else { return false }
        guard let homeView = topController as? UITabBarController else { return false }
        
        guard homeView.selectedIndex == 2 else { return false }
        guard let navigationController = homeView.selectedViewController as? UINavigationController else { return false }
        guard let chatListViewController = navigationController.topViewController as? ChatListViewController else { return false }

        return chatListViewController.isScrolledFromTop(by: 100)
    }
}

extension ChatData {

    // MARK: Thread
    
    func markSeenMessages(type: ChatType, for id: String, in managedObjectContext: NSManagedObjectContext) {
        guard type == .oneToOne else { return }

        let unseenChatMsgs = unseenChatMessages(with: id, in: managedObjectContext)
        
        unseenChatMsgs.forEach {
            sendSeenReceipt(for: $0)
            $0.incomingStatus = ChatMessage.IncomingStatus.haveSeen
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

    func updateUnreadChatsThreadCount() {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            let threads = self.chatThreads(predicate: NSPredicate(format: "groupId = nil && unreadCount > 0"), in: managedObjectContext)
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

    func emptyOneToOneChatThreads(in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatThread] {
        return chatThreads(predicate: NSPredicate(format: "groupId == nil AND lastMsgId == nil"), in: managedObjectContext)
    }

    func groupThreadsWithExpiredPosts(expiredPostIDs: [FeedPostID], in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatThread] {
        return chatThreads(predicate: NSPredicate(format: "groupId != nil && lastFeedId IN %@", expiredPostIDs), in: managedObjectContext)
    }

    func groupThreads(in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatThread] {
        return chatThreads(predicate: NSPredicate(format: "groupId != nil"), in: managedObjectContext)
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

    func updateThreadPreviewsOfExpiredPosts(expiredPostIDs: [FeedPostID]) {

        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            let groupThreadsWithExpiredPosts = self.groupThreadsWithExpiredPosts(expiredPostIDs: expiredPostIDs, in: managedObjectContext)
            DDLogVerbose("ChatData/deletePreviewsOfExpiredPosts/groupThreadsWithExpiredPosts num: \(groupThreadsWithExpiredPosts)")

            for thread in groupThreadsWithExpiredPosts {
                // reset everything except for timestamp to keep order
                thread.lastFeedId = nil
                thread.lastFeedUserID = nil
                thread.lastFeedStatus = .none
                thread.lastFeedText = nil
                thread.lastFeedMediaType = .none
            }
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
        default:
            return
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
        
        addIntent(toUserId: toUserId)
    }
    
    func createChatMsg(toUserId: String,
                     text: String,
                     media: [PendingMedia],
                     feedPostId: String?,
                     feedPostMediaIndex: Int32,
                     chatReplyMessageID: String? = nil,
                     chatReplyMessageSenderID: UserID? = nil,
                     chatReplyMessageMediaIndex: Int32) {
        
        let messageId = PacketID.generate()
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
        let serialID = MainAppContext.shared.getchatMsgSerialId()
        DDLogDebug("ChatData/createChatMsg/\(messageId)/serialId [\(serialID)]")
        chatMessage.serialID = serialID

        var lastMsgMediaType: ChatThread.LastMediaType = .none // going with the first media
        
        for (index, mediaItem) in media.enumerated() {
            DDLogDebug("ChatData/createChatMsg/\(messageId)/add-media [\(mediaItem)]")
            guard let mediaItemSize = mediaItem.size,
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
            case .audio:
                chatMedia.type = .audio
                if lastMsgMediaType == .none {
                    lastMsgMediaType = .audio
                }
            }
            chatMedia.outgoingStatus = isMsgToYourself ? .uploaded : .pending
            chatMedia.url = mediaItem.url
            chatMedia.uploadUrl = mediaItem.uploadUrl
            chatMedia.size = mediaItemSize
            chatMedia.key = ""
            chatMedia.sha256 = ""
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
                quotedMedia.type = {
                    switch quotedChatMessageMedia.type {
                    case .image:
                        return .image
                    case .video:
                        return .video
                    case .audio:
                        return .audio
                    }
                } ()

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
            processPendingChatMsgs()
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
        var isMsgStale: Bool = false
        let totalUploads = mediaItemsToUpload.count
        DDLogInfo("ChatData/uploadChatMsgMediaAndSend/\(msgID)/starting [\(totalUploads)]")

        let uploadGroup = DispatchGroup()
        let uploadCompletion: (Result<MediaUploader.UploadDetails, Error>) -> Void = { result in
            switch result {
            case .failure(_):
                numberOfFailedUploads += 1

                if let msgTimestamp = chatMsg.timestamp, let diff = Calendar.current.dateComponents([.hour], from: msgTimestamp, to: Date()).hour, diff > 24 {
                    isMsgStale = true
                }
            default:
                break
            }

            uploadGroup.leave()
        }

        for mediaItem in mediaItemsToUpload {
            let mediaIndex = mediaItem.order
            uploadGroup.enter()

            DDLogDebug("ChatData/process-mediaItem: \(msgID)/\(mediaItem.order), index: \(mediaIndex)")
            if let relativeFilePath = mediaItem.relativeFilePath, mediaItem.sha256.isEmpty && mediaItem.key.isEmpty {
                let url = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(relativeFilePath, isDirectory: false)
                let output = url.deletingPathExtension().appendingPathExtension("processed").appendingPathExtension(url.pathExtension)
                let type: FeedMediaType = {
                    switch mediaItem.type {
                    case .image:
                        return .image
                    case .video:
                        return .video
                    case .audio:
                        return .audio
                    }
                } ()

                imageServer.prepare(type, url: url, output: output) { [weak self] in
                    guard let self = self else { return }

                    switch $0 {
                    case .success(let result):
                        let path = self.relativePath(from: output)
                        DDLogDebug("ChatData/process-mediaItem/success: \(msgID)/\(mediaIndex)")
                        self.updateChatMessage(with: msgID, block: { msg in
                            guard let media = msg.media?.first(where: { $0.order == mediaIndex }) else {
                                DDLogError("ChatData/process-mediaItem/failed to save/msgId: \(msgID)/\(mediaIndex)")
                                return
                            }

                            media.size = result.size
                            media.key = result.key
                            media.sha256 = result.sha256
                            media.relativeFilePath = path
                            DDLogDebug("ChatData/updating chat message: \(msgID), relativeFilePath: \(path ?? "nil")")
                        }) {
                            self.uploadChat(msgID: msgID, mediaIndex: mediaIndex, completion: uploadCompletion)
                        }
                    case .failure(_):
                        DDLogDebug("ChatData/process-mediaItem/failure: \(msgID)/\(mediaIndex)")
                        numberOfFailedUploads += 1

                        self.updateChatMessage(with: msgID, block: { msg in
                            guard let media = msg.media?.first(where: { $0.order == mediaIndex }) else { return }
                            media.outgoingStatus = .error
                            media.numTries += 1
                        }) {
                            uploadGroup.leave()
                        }
                    }
                }
            } else {
                DDLogDebug("ChatData/process-mediaItem/processed already: \(msgID)/\(mediaIndex)")
                uploadChat(msgID: msgID, mediaIndex: mediaIndex, completion: uploadCompletion)
            }
        }

        uploadGroup.notify(queue: backgroundProcessingQueue) { [weak self] in
            guard let self = self else { return }
            DDLogInfo("ChatData/uploadChatMsgMediaAndSend/finish/\(msgID) failed/total: \(numberOfFailedUploads)/\(totalUploads)")
            if numberOfFailedUploads > 0 {
                if isMsgStale {
                    self.updateChatMessage(with: msgID) { msg in
                        msg.outgoingStatus = .error
                    }
                }
            } else {
                self.send(message: XMPPChatMessage(chatMessage: chatMsg))
            }

        }
    }

    private func uploadChat(msgID: String, mediaIndex: Int16, completion: @escaping (Result<MediaUploader.UploadDetails, Error>) -> Void) {
        guard let msg = chatMessage(with: msgID, in: bgContext),
              let chatMedia = msg.media?.first(where: { $0.order == mediaIndex }) else {
            DDLogError("ChatData/uploadChat/fetch msg and media \(msgID)/\(mediaIndex) - missing")
            return
        }

        DDLogDebug("ChatData/uploadChat/media \(msgID)/\(chatMedia.order), index:\(mediaIndex), path: \(chatMedia.relativeFilePath ?? "nil")")
        guard let relativeFilePath = chatMedia.relativeFilePath else {
            DDLogError("ChatData/uploadChat/\(msgID)/\(mediaIndex) missing file path")
            return completion(.failure(MediaUploadError.invalidUrls))
        }
        let processed = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(relativeFilePath, isDirectory: false)

        MainAppContext.shared.uploadData.fetch(upload: processed) { [weak self] upload in
            guard let self = self else { return }

            // Lookup object from coredata again instead of passing around the object across threads.
            DDLogInfo("ChatData/uploadChat/fetch upload hash \(msgID)/\(mediaIndex)")
            guard let msg = self.chatMessage(with: msgID, in: self.bgContext),
                  let media = msg.media?.first(where: { $0.order == mediaIndex }) else {
                DDLogError("ChatData/uploadChat/fetch msg and media \(msgID)/\(mediaIndex) - missing")
                return
            }

            if let url = upload?.url {
                DDLogInfo("Media \(processed) has been uploaded before at \(url).")
                if let uploadUrl = media.uploadUrl {
                    DDLogInfo("ChatData/uploadChat/upload url is supposed to be nil here/\(msgID)/\(media.order), uploadUrl: \(uploadUrl)")
                    // we set it to be nil here explicitly.
                    media.uploadUrl = nil
                }
                media.url = url
            } else {
                DDLogInfo("ChatData/uploadChat/uploading media now/\(msgID)/\(media.order), index:\(mediaIndex)")
            }

            self.mediaUploader.upload(media: media, groupId: msgID, didGetURLs: { (mediaURLs) in
                DDLogInfo("ChatData/uploadChatMsgMediaAndSend/\(msgID)/\(mediaIndex)/acquired-urls [\(mediaURLs)]")

                // Save URLs acquired during upload to the database.
                self.updateChatMessage(with: msgID) { msg in
                    guard let media = msg.media?.first(where: { $0.order == mediaIndex }) else { return }

                    switch mediaURLs {
                    case .getPut(let getURL, let putURL):
                        media.url = getURL
                        media.uploadUrl = putURL
                    case .patch(let patchURL):
                        media.uploadUrl = patchURL
                    case .download(let downloadURL):
                        media.url = downloadURL
                    }
                }
            }) { (uploadResult) in
                DDLogInfo("ChatData/uploadChatMsgMediaAndSend/\(msgID)/\(mediaIndex)/finished result=[\(uploadResult)]")

                // Save URLs acquired during upload to the database.
                self.updateChatMessage(with: msgID, block: { msg in
                    guard let media = msg.media?.first(where: { $0.order == mediaIndex }) else { return }

                    switch uploadResult {
                    case .success(let details):
                        media.url = details.downloadURL
                        media.outgoingStatus = .uploaded

                        if media.url == upload?.url, let key = upload?.key, let sha256 = upload?.sha256 {
                            media.key = key
                            media.sha256 = sha256
                        }

                        MainAppContext.shared.uploadData.update(upload: processed, key: media.key, sha256: media.sha256, downloadURL: media.url!)
                    case .failure(_):
                        media.outgoingStatus = .error
                        media.numTries += 1
                    }
                }) {
                    completion(uploadResult)
                }
            }
        }
    }

    private func send(message: ChatMessageProtocol) {
        service.sendChatMessage(message) { _ in }
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
        let messageID = PacketID.generate()
                
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
    
    /// Donates an intent to Siri for improved suggestions when sharing content.
    ///
    /// Intents are used by iOS to provide contextual suggestions to the user for certain interactions. In this case, we are suggesting the user send another message to the user they just shared with.
    /// For more information, see [this documentation](https://developer.apple.com/documentation/sirikit/insendmessageintent)\.
    /// - Parameter toUserId: The user ID for the person the user just shared with
    /// - Remark: This is different from the implementation in `ShareComposerViewController.swift` because `MainAppContext` isn't available in the share extension.
    private func addIntent(toUserId: UserID) {
        if #available(iOS 14.0, *) {
            let recipient = INSpeakableString(spokenPhrase: MainAppContext.shared.contactStore.fullName(for: toUserId))
            let sendMessageIntent = INSendMessageIntent(recipients: nil,
                                                        content: nil,
                                                        speakableGroupName: recipient,
                                                        conversationIdentifier: ConversationID(id: toUserId, type: .chat).description,
                                                        serviceName: nil, sender: nil)
            
            let potentialUserAvatar = MainAppContext.shared.avatarStore.userAvatar(forUserId: toUserId).image
            guard let defaultAvatar = UIImage(named: "AvatarUser") else { return }
            
            // Have to convert UIImage to data and then NIImage because NIImage(uiimage: UIImage) initializer was throwing exception
            guard let userAvaterUIImage = (potentialUserAvatar ?? defaultAvatar).pngData() else { return }
            let userAvatar = INImage(imageData: userAvaterUIImage)
            
            sendMessageIntent.setImage(userAvatar, forParameterNamed: \.speakableGroupName)
            
            let interaction = INInteraction(intent: sendMessageIntent, response: nil)
            interaction.donate(completion: { error in
                if let error = error {
                    DDLogDebug("ChatViewController/sendMessage/\(error.localizedDescription)")
                }
            })
        }
    }
    
    // MARK: 1-1 Core Data Fetching
    
    private func chatMessages(  predicate: NSPredicate? = nil,
                                sortDescriptors: [NSSortDescriptor]? = nil,
                                limit: Int? = nil,
                                in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatMessage] {
        let managedObjectContext = managedObjectContext ?? self.viewContext
        let fetchRequest: NSFetchRequest<ChatMessage> = ChatMessage.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        if let fetchLimit = limit { fetchRequest.fetchLimit = fetchLimit }
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
            NSSortDescriptor(keyPath: \ChatMessage.serialID, ascending: true),
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
    
    func retractingOutboundChatMsgs(in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true)
        ]
        return chatMessages(predicate: NSPredicate(format: "outgoingStatusValue = %d", ChatMessage.OutgoingStatus.retracting.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
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

    func haveMessagedBefore(userID: UserID, in managedObjectContext: NSManagedObjectContext? = nil) -> Bool {
        let predicate = NSPredicate(format: "fromUserId = %@ AND toUserId = %@", userData.userId, userID)
        let fetchLimit = 1
        return (chatMessages(predicate: predicate, limit: fetchLimit, in: managedObjectContext).count > 0) ? true : false
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
                guard let self = self else { return }
                self.populateThreadsWithAllContacts()
                self.updateUnreadChatsThreadCount()
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

        // quoted media item will be deleted - when the main chat message containing that media object is deleted.
        // this message only contains a reference to it - so quoted media should not be deleted.
        if let quoted = chatMessage.quoted {
            DDLogDebug("ChatData/deleteMedia/quoted ")
            if let quotedMedia = quoted.media {
                quotedMedia.forEach { (media) in
                    if media.mediaDir == nil {
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
    
    private func processIncomingChatMessage(_ incomingMessage: IncomingChatMessage) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let isAppActive = UIApplication.shared.applicationState == .active
            
            self.performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
                guard let self = self else { return }
                switch incomingMessage {
                case .decrypted(let chatMessage):
                    DDLogInfo("ChatData/processIncomingChatMessage \(chatMessage.id)")
                    self.processInboundChatMessage(xmppChatMessage: chatMessage, using: managedObjectContext, isAppActive: isAppActive)
                    self.didGetAChatMsg.send(chatMessage.fromUserId)
                case .notDecrypted(let tombstone):
                    DDLogInfo("ChatData/processIncomingChatMessage/tombstone \(tombstone.id)")
                    self.processInboundTombstone(tombstone, using: managedObjectContext)
                    self.didGetAChatMsg.send(tombstone.from)
                }
            }
        }
    }

    private func processInboundTombstone(_ tombstone: ChatMessageTombstone, using managedObjectContext: NSManagedObjectContext) {
        guard self.chatMessage(with: tombstone.id, in: managedObjectContext) == nil else {
            DDLogInfo("ChatData/processInboundTombstone/skipping [already exists]")
            return
        }

        let chatMessage = NSEntityDescription.insertNewObject(forEntityName: ChatMessage.entity().name!, into: managedObjectContext) as! ChatMessage
        chatMessage.id = tombstone.id
        chatMessage.toUserId = tombstone.to
        chatMessage.fromUserId = tombstone.from
        chatMessage.timestamp = tombstone.timestamp
        let serialID = MainAppContext.shared.getchatMsgSerialId()
        DDLogDebug("ChatData/processInboundTombstone/\(tombstone.id)/serialId [\(serialID)]")
        chatMessage.serialID = serialID
        chatMessage.incomingStatus = .rerequesting
        chatMessage.outgoingStatus = .none

        save(managedObjectContext)
    }
    
    private func isCurrentlyChatting(with userId: UserID) -> Bool {
        if let currentlyChattingWithUserId = self.currentlyChattingWithUserId {
            if userId == currentlyChattingWithUserId {
                return true
            }
        }
        return false
    }

    private func processInboundChatMessage(xmppChatMessage: ChatMessageProtocol, using managedObjectContext: NSManagedObjectContext, isAppActive: Bool) {
        let existingChatMessage = chatMessage(with: xmppChatMessage.id, in: managedObjectContext)
        if let existingChatMessage = existingChatMessage, existingChatMessage.incomingStatus != .rerequesting {
            // This is expected if we rerequest a message where decryption failed but a plaintext version was included
            DDLogInfo("ChatData/process/already-exists [\(xmppChatMessage.id)]")
            return
        }

        let isCurrentlyChattingWithUser = isCurrentlyChatting(with: xmppChatMessage.fromUserId)
        DDLogDebug("ChatData/processInboundChatMessage [\(xmppChatMessage.id)]")
        let chatMessage: ChatMessage = {
            guard let existingChatMessage = existingChatMessage else {
                DDLogDebug("ChatData/process/new [\(xmppChatMessage.id)]")
                return NSEntityDescription.insertNewObject(forEntityName: ChatMessage.entity().name!, into: managedObjectContext) as! ChatMessage
            }
            DDLogDebug("ChatData/process/updating rerequested message [\(xmppChatMessage.id)]")
            return existingChatMessage
        }()

        chatMessage.id = xmppChatMessage.id
        chatMessage.toUserId = xmppChatMessage.toUserId
        chatMessage.fromUserId = xmppChatMessage.fromUserId
        chatMessage.feedPostId = xmppChatMessage.context.feedPostID
        chatMessage.feedPostMediaIndex = xmppChatMessage.context.feedPostMediaIndex
        
        chatMessage.chatReplyMessageID = xmppChatMessage.context.chatReplyMessageID
        chatMessage.chatReplyMessageSenderID = xmppChatMessage.context.chatReplyMessageSenderID
        chatMessage.chatReplyMessageMediaIndex = xmppChatMessage.context.chatReplyMessageMediaIndex
        
        chatMessage.incomingStatus = .none
        chatMessage.outgoingStatus = .none
        
        if let ts = xmppChatMessage.timeIntervalSince1970 {
            chatMessage.timestamp = Date(timeIntervalSince1970: ts)
        } else {
            chatMessage.timestamp = Date()
        }
        let serialID = MainAppContext.shared.getchatMsgSerialId()
        DDLogDebug("ChatData/processInboundChatMessage/\(xmppChatMessage.id)/serialId [\(serialID)]")
        chatMessage.serialID = serialID
        
        var lastMsgMediaType: ChatThread.LastMediaType = .none // going with the first media found
        
        // Process chat content
        switch xmppChatMessage.content {
        case .album(let text, let media):
            chatMessage.text = text
            for (index, xmppMedia) in media.enumerated() {
                guard let downloadUrl = xmppMedia.url else { continue }

                DDLogDebug("ChatData/process/new/add-media [\(downloadUrl)]")
                let chatMedia = ChatMedia(context: managedObjectContext)

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
                case .audio:
                    chatMedia.type = .audio
                    if lastMsgMediaType == .none {
                        lastMsgMediaType = .audio
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
        case .voiceNote(let xmppMedia):
            guard let downloadUrl = xmppMedia.url else { break }

            DDLogDebug("ChatData/process/new/add-media [\(downloadUrl)]")

            chatMessage.text = ""
            lastMsgMediaType = .audio

            let chatMedia = ChatMedia(context: managedObjectContext)
            chatMedia.type = .audio
            chatMedia.incomingStatus = .pending
            chatMedia.outgoingStatus = .none
            chatMedia.url = xmppMedia.url
            chatMedia.size = xmppMedia.size
            chatMedia.key = xmppMedia.key
            chatMedia.order = 0
            chatMedia.sha256 = xmppMedia.sha256
            chatMedia.message = chatMessage
        case .text(let text):
            chatMessage.text = text
        case .unsupported(let data):
            chatMessage.rawData = data
            chatMessage.incomingStatus = .unsupported
        }

        // Process quoted content.
        if let feedPostId = xmppChatMessage.context.feedPostID {
            // Process Quoted Feedpost
            if let quotedFeedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId) {
                copyQuoted(to: chatMessage, from: quotedFeedPost, using: managedObjectContext)
            }
        } else if let chatReplyMsgId = xmppChatMessage.context.chatReplyMessageID {
            // Process Quoted Message
            if let quotedChatMessage = MainAppContext.shared.chatData.chatMessage(with: chatReplyMsgId) {
                copyQuoted(to: chatMessage, from: quotedChatMessage, using: managedObjectContext)
            }
        }

        save(managedObjectContext) // extra save

        // Update Chat Thread
        if let chatThread = self.chatThread(type: ChatType.oneToOne, id: chatMessage.fromUserId, in: managedObjectContext) {
            // do an extra save since fetchedcontroller have issues with detecting re-ordering changes for properties
            // that started out as nil (and possibly when it's just mixed with other changes)
            chatThread.lastMsgTimestamp = chatMessage.timestamp
            save(managedObjectContext)

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

        save(managedObjectContext)

        if isCurrentlyChattingWithUser && isAppActive && (chatMessage.incomingStatus != .unsupported) {
            self.sendSeenReceipt(for: chatMessage)
            self.updateChatMessage(with: chatMessage.id) { (chatMessage) in
                chatMessage.incomingStatus = .haveSeen
            }
        } else {
            self.unreadMessageCount += 1
            self.updateUnreadChatsThreadCount()
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
        backgroundProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            let pendingOutgoingChatMessages = self.pendingOutgoingChatMessages(in: self.bgContext)
            DDLogInfo("ChatData/processPendingChatMsgs/num: \(pendingOutgoingChatMessages.count)")

            pendingOutgoingChatMessages.forEach{ pendingMsg in
                let xmppChatMsg = XMPPChatMessage(chatMessage: pendingMsg)
                self.backgroundProcessingQueue.async { [weak self] in
                    guard let self = self else { return }
                    self.uploadChatMsgMediaAndSend(xmppChatMsg)
                }
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
        
        let body: String

        switch xmppChatMessage.content {
        case .text(let text):
            body = text
        case .album(let text, let media):
            let mediaStr: String? = {
                guard let firstMedia = media.first else { return nil }
                switch firstMedia.mediaType {
                case .image: return "📷"
                case .video: return "📹"
                case .audio: return "🎤"
                }
            }()
            body = [mediaStr, text].compactMap { $0 }.joined(separator: " ")
        case .voiceNote(_):
            body =  "🎤"
        case .unsupported(_):
            body = ""
        }
        
        Banner.show(title: title, body: body, userID: userID, using: MainAppContext.shared.avatarStore)
    }
    
    private func presentLocalOneToOneNotifications(for xmppChatMessage: ChatMessageProtocol) {
        DDLogDebug("ChatData/presentLocalOneToOneNotifications")
        let userID = xmppChatMessage.fromUserId
        
        guard let ts = xmppChatMessage.timeIntervalSince1970 else { return }
        let timestamp = Date(timeIntervalSinceReferenceDate: ts)
        let protoContainer = xmppChatMessage.protoContainer
        let protobufData = try? protoContainer?.serializedData()
        let metadata = NotificationMetadata(contentId: xmppChatMessage.id,
                                            contentType: .chatMessage,
                                            fromId: userID,
                                            timestamp: timestamp,
                                            data: protobufData,
                                            messageId: xmppChatMessage.id)
        // create and add a notification to the notification center.
        NotificationRequest.createAndShow(from: metadata) { [weak self] error in
            guard let self = self else {
                return
            }
            if let error = error {
                DDLogInfo("ChatData/NotificationRequest/failed/error: \(error)")
            } else {
                self.incrementApplicationIconBadgeNumber()
            }
        }
    }
}

extension ChatData {

    public typealias GroupActionCompletion = (Error?) -> Void

    // MARK: Group Actions
    
    public func createGroup(name: String, description: String, members: [UserID], data: Data?, completion: @escaping ServiceRequestCompletion<String>) {
        
        MainAppContext.shared.service.createGroup(name: name, members: members) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let groupID):
                let dispatchGroup = DispatchGroup()

                if !description.isEmpty {
                    dispatchGroup.enter()
                    self.changeGroupDescription(groupID: groupID, description: description) { result in
                    
                        dispatchGroup.leave() // the group can be created regardless if description update succeeds or not
                    }
                }

                if let data = data {
                    dispatchGroup.enter()
                    self.changeGroupAvatar(groupID: groupID, data: data) { result in
                        dispatchGroup.leave() // the group can be created regardless if avatar update succeeds or not
                    }
                }
                
                dispatchGroup.notify(queue: self.backgroundProcessingQueue) {
                    completion(.success(groupID))
                }
            case .failure(let error):
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
                DDLogError("ChatData/changeGroupName/error \(error)")
                completion(.failure(error))
            }
        }
    }
    
    public func changeGroupAvatar(groupID: GroupID, data: Data?, completion: @escaping ServiceRequestCompletion<Void>) {
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
                DDLogError("ChatData/changeGroupAvatar/error \(error)")
            }
        }
    }

    public func changeGroupDescription(groupID: GroupID, description: String, completion: @escaping ServiceRequestCompletion<Void>) {
        DDLogInfo("ChatData/changeGroupDescription")
        MainAppContext.shared.service.changeGroupDescription(groupID: groupID, description: description) { [weak self] result in
            guard let self = self else { return }
     
            switch result {
            case .success(let desc):
                self.updateChatGroup(with: groupID, block: { (chatGroup) in
                    chatGroup.desc = desc
                }, performAfterSave: {
                    completion(.success(()))
                })
            case .failure(let error):
                DDLogError("ChatData/changeGroupDescription/error \(error)")
            }
        }
    }

    public func setGroupBackground(groupID: GroupID, background: Int32, completion: @escaping ServiceRequestCompletion<Void>) {
        MainAppContext.shared.service.setGroupBackground(groupID: groupID, background: background) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.updateChatGroup(with: groupID, block: { (chatGroup) in
                    guard chatGroup.background != background else { return }
                    chatGroup.background = background
                }, performAfterSave: {
                    completion(.success(()))
                })
            case .failure(let error):
                DDLogError("CreateGroupViewController/createAction/error \(error)")
                completion(.failure(error))
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
            guard let self = self else { return }
            switch result {
            case .success(let group):
                self.syncGroup(group)
            case .failure(let error):
                switch error {
                case .serverError(let reason):
                    switch reason {
                    case "not_member":
                        DDLogInfo("ChatData/group/getGroupInfo/error/not_member/removing user")
                        self.deleteChatGroupMember(groupId: groupId, memberUserId: MainAppContext.shared.userData.userId)
                    default:
                        DDLogError("ChatData/group/getGroupInfo/error \(error)")
                    }
                default:
                    DDLogError("ChatData/group/getGroupInfo/error \(error)")
                }
            }
        }
    }

    func syncGroupIfNeeded(for groupId: GroupID) {
        guard let group = chatGroup(groupId: groupId) else { return }
        guard MainAppContext.shared.chatData.chatGroupMember(groupId: groupId, memberUserId: MainAppContext.shared.userData.userId) != nil else { return }

        if let lastSync = group.lastSync {
            guard let diff = Calendar.current.dateComponents([.hour], from: lastSync, to: Date()).hour, diff > 24 else {
                return
            }
        }

        MainAppContext.shared.chatData.getAndSyncGroup(groupId: groupId)
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
            if chatGroup.desc != xmppGroup.description {
                chatGroup.desc = xmppGroup.description
            }
            if chatGroup.avatar != xmppGroup.avatarID {
                chatGroup.avatar = xmppGroup.avatarID
                if let avatarID = xmppGroup.avatarID {
                    MainAppContext.shared.avatarStore.updateOrInsertGroupAvatar(for: chatGroup.groupId, with: avatarID)
                }
            }
            if chatGroup.background != xmppGroup.background {
                chatGroup.background = xmppGroup.background
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
    
    // MARK: Group Background

    static public func getThemeColor(for theme: Int32) -> UIColor {
        let colorName = "Theme\(String(theme))"
        guard let color = UIColor(named: colorName) else { return UIColor.label }

        return color
    }

    static public func getThemeBackgroundColor(for theme: Int32) -> UIColor {
        let colorName = "Theme\(String(theme))Bg"
        guard let color = UIColor(named: colorName) else { return UIColor.primaryBg }

        return color
    }

    // MARK: Group Invite Link

    static public func parseInviteURL(url: URL?) -> String? {
        guard let url = url else { return nil }
        guard let components = NSURLComponents(url: url, resolvingAgainstBaseURL: true) else { return nil }

        guard let scheme = components.scheme?.lowercased() else { return nil }
        guard let host = components.host?.lowercased() else { return nil }
        guard let path = components.path?.lowercased() else { return nil }

        if scheme == "https" {
            guard host == "halloapp.com" || host == "www.halloapp.com" else { return nil }
            guard path == "/invite/" else { return nil }
        } else if scheme == "halloapp" {
            guard host == "invite" else { return nil }
            guard path == "/" else { return nil }
        }

        guard let params = components.queryItems else { return nil }
        guard let inviteLink = params.first(where: { $0.name == "g" })?.value else { return nil }

        return inviteLink
    }
    
    func proceedIfNotGroupInviteLink(_ url: URL) -> Bool {
        guard let inviteToken = ChatData.parseInviteURL(url: url) else { return true }
        MainAppContext.shared.userData.groupInviteToken = inviteToken
        MainAppContext.shared.didGetGroupInviteToken.send()
        return false
    }

    // MARK: Group Invite Link Actions

    func getGroupInviteLink(groupID: GroupID, completion: @escaping ServiceRequestCompletion<String?>) {
        DDLogDebug("ChatData/group/getGroupInviteLink/group \(groupID)")
        service.getGroupInviteLink(groupID: groupID) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let groupInviteLink):
                self.updateChatGroup(with: groupID, block: { chatGroup in
                    guard chatGroup.inviteLink != groupInviteLink.link else { return }
                    chatGroup.inviteLink = groupInviteLink.link
                }, performAfterSave: {
                    let link = groupInviteLink.link
                    completion(.success((link)))
                })
            case .failure(let error):
                DDLogError("ChatData/group/getGroupInviteLink/error \(error)")
            }
        }
    }

    func resetGroupInviteLink(groupID: GroupID, completion: @escaping ServiceRequestCompletion<String?>) {
        DDLogDebug("ChatData/group/resetGroupInviteLink/group \(groupID)")
        service.resetGroupInviteLink(groupID: groupID) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let groupInviteLink):
                self.updateChatGroup(with: groupID, block: { chatGroup in
                    guard chatGroup.inviteLink != groupInviteLink.link else { return }
                    chatGroup.inviteLink = groupInviteLink.link
                }, performAfterSave: {
                    let link = groupInviteLink.link
                    completion(.success((link)))
                })
            case .failure(let error):
                DDLogError("ChatData/group/resetGroupInviteLink/error \(error)")
            }
        }
    }

    func getGroupPreviewWithLink(inviteLink: String, completion: @escaping ServiceRequestCompletion<Server_GroupInviteLink>) {
        DDLogDebug("ChatData/group/getGroupPreviewWithLink/inviteLink \(inviteLink)")
        service.getGroupPreviewWithLink(inviteLink: inviteLink) { result in
            switch result {
            case .success(let groupInviteLink):
                completion(.success((groupInviteLink)))
            case .failure(let error):
                DDLogError("ChatData/group/getGroupPreviewWithLink/error \(error)")
                completion(.failure((error)))
            }
        }
    }

    func joinGroupWithLink(inviteLink: String, completion: @escaping ServiceRequestCompletion<Server_GroupInviteLink>) {
        DDLogDebug("ChatData/group/joinGroupWithLink/inviteLink \(inviteLink)")
        service.joinGroupWithLink(inviteLink: inviteLink) { result in
            switch result {
            case .success(let groupInviteLink):
                completion(.success((groupInviteLink)))
            case .failure(let error):
                DDLogError("ChatData/group/joinGroupWithLink/error \(error)")
                completion(.failure((error)))
            }
        }
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
    
    func groupFeedEvents(with groupID: GroupID, in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatGroupMessage] {
        let cutOffDate = Date(timeIntervalSinceNow: -Date.days(31))
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatGroupMessage.timestamp, ascending: true)
        ]
        return chatGroupMessages(predicate: NSPredicate(format: "groupId == %@ && (event.@count > 0) && timestamp >= %@", groupID, cutOffDate as NSDate), sortDescriptors: sortDescriptors, in: managedObjectContext)
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
            
            // delete feeds
            MainAppContext.shared.feedData.deletePosts(groupId: groupId)
            
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
                case .audio:
                    lastFeedMediaType = .audio
                }
            }
        }

        save(managedObjectContext) // extra save

        // Update Chat Thread
        let mentionText = contactStore.textWithMentions(groupFeedPost.text, mentions: groupFeedPost.orderedMentions)
        if let chatThread = chatThread(type: .group, id: groupID, in: managedObjectContext) {
            // extra save for fetchedcontroller to notice re-ordering changes mixed in with other changes
            chatThread.lastFeedTimestamp = groupFeedPost.timestamp
            save(managedObjectContext)
        
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
        DDLogInfo("ChatData/processIncomingGroup")
        switch xmppGroup.action {
        case .create:
            processGroupCreateAction(xmppGroup: xmppGroup, in: managedObjectContext)
        case .join:
            processGroupJoinAction(xmppGroup: xmppGroup, in: managedObjectContext)
        case .leave:
            processGroupLeaveAction(xmppGroup: xmppGroup, in: managedObjectContext)
        case .modifyMembers, .modifyAdmins:
            processGroupModifyMembersAction(xmppGroup: xmppGroup, in: managedObjectContext)
        case .changeName:
            processGroupChangeNameAction(xmppGroup: xmppGroup, in: managedObjectContext)
        case .changeDescription:
            processGroupChangeDescriptionAction(xmppGroup: xmppGroup, in: managedObjectContext)
        case .changeAvatar:
            processGroupChangeAvatarAction(xmppGroup: xmppGroup, in: managedObjectContext)
        case .setBackground:
            processGroupSetBackgroundAction(xmppGroup: xmppGroup, in: managedObjectContext)
        default: break
        }

        save(managedObjectContext)
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
            
            if xmppGroupMember.userId == MainAppContext.shared.userData.userId, xmppGroup.retryCount == 0 {
                DispatchQueue.main.async {
                    // dummy avatarview to preload group avatar for new groups with avatar
                    // nice to show avatar but not required, 2 seconds given for chance to finish downloading
                    let view = AvatarView()
                    view.configure(groupId: xmppGroup.groupId, using: MainAppContext.shared.avatarStore)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        self.showGroupAddNotification(for: xmppGroup)
                    }
                }
            }
        }
        
        if !contactNames.isEmpty {
            contactStore.addPushNames(contactNames)
        }
        
        recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: nil, in: managedObjectContext)
    }

    private func processGroupJoinAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("ChatData/group/processGroupJoinAction")
        let group = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)
        
        for xmppGroupMember in xmppGroup.members ?? [] {
            guard xmppGroupMember.action == .join else { continue }

            // add pushname first before recording message since user could be new
            var contactNames = [UserID:String]()
            if let name = xmppGroupMember.name, !name.isEmpty {
                contactNames[xmppGroupMember.userId] = name
            }
            if !contactNames.isEmpty {
                contactStore.addPushNames(contactNames)
            }

            processGroupAddMemberAction(chatGroup: group, xmppGroupMember: xmppGroupMember, in: managedObjectContext)
            recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: xmppGroupMember, in: managedObjectContext)
        }

        getAndSyncGroup(groupId: xmppGroup.groupId)
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
        let group = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)

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

            switch xmppGroupMember.action {
            case .add:
                processGroupAddMemberAction(chatGroup: group, xmppGroupMember: xmppGroupMember, in: managedObjectContext)
            case .remove:
                deleteChatGroupMember(groupId: xmppGroup.groupId, memberUserId: xmppGroupMember.userId)
            case .promote:
                if let foundMember = group.members?.first(where: { $0.userId == xmppGroupMember.userId }) {
                    foundMember.type = .admin
                }
            case .demote:
                if let foundMember = group.members?.first(where: { $0.userId == xmppGroupMember.userId }) {
                    foundMember.type = .member
                }
            default:
                break
            }

            recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: xmppGroupMember, in: managedObjectContext)

            if xmppGroupMember.action == .add, xmppGroupMember.userId == MainAppContext.shared.userData.userId, xmppGroup.retryCount == 0 {
                showGroupAddNotification(for: xmppGroup)
            }
        }

        getAndSyncGroup(groupId: xmppGroup.groupId)
    }

    private func processGroupChangeNameAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("ChatData/group/processGroupChangeNameAction")
        let group = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)
        group.name = xmppGroup.name
        updateChatThread(type: .group, for: xmppGroup.groupId) { (chatThread) in
            chatThread.title = xmppGroup.name
        }
        recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: nil, in: managedObjectContext)
        getAndSyncGroup(groupId: xmppGroup.groupId)
    }

    private func processGroupChangeDescriptionAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("ChatData/group/processGroupChangeDescriptionAction")
        _ = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)
        // bug: server is not sending description for the change_description event yet
//        group.desc = xmppGroup.description
        save(managedObjectContext)
        recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: nil, in: managedObjectContext)
        getAndSyncGroup(groupId: xmppGroup.groupId)
    }

    private func processGroupChangeAvatarAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("ChatData/group/processGroupChangeAvatarAction")
        let group = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)
        group.avatar = xmppGroup.avatarID
        if let avatarID = xmppGroup.avatarID {
            MainAppContext.shared.avatarStore.updateOrInsertGroupAvatar(for: group.groupId, with: avatarID)
        }
        recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: nil, in: managedObjectContext)
        getAndSyncGroup(groupId: xmppGroup.groupId)
    }

    private func processGroupSetBackgroundAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("ChatData/group/processGroupSetBackgroundAction")
        let group = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)
        group.background = xmppGroup.background
        save(managedObjectContext)
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
            chatThread.lastFeedTimestamp = Date()
        }
        return chatGroup
    }
    
    private func recordGroupMessageEvent(xmppGroup: XMPPGroup, xmppGroupMember: XMPPGroupMember?, in managedObjectContext: NSManagedObjectContext) {

        // hack: skip recording the event(s) of an avatar change and/or description change if the changes are done at group creation,
        // since server api require separate requests for them but we want to show only the group creation event
        // rough check by comparing if the last event (also first) was a group creation event and if avatar/description changes happened right after
        let groupFeedEventsList = groupFeedEvents(with: xmppGroup.groupId, in: managedObjectContext)
        if let lastMsg = groupFeedEventsList.last,
           let lastMsgEvent = lastMsg.event,
           [.create].contains(lastMsgEvent.action),
           lastMsgEvent.memberUserId == xmppGroupMember?.userId,
           let createEventTimestamp = lastMsg.timestamp,
           [.changeAvatar, .changeDescription].contains(xmppGroup.action),
           let diff = Calendar.current.dateComponents([.second], from: createEventTimestamp, to: Date()).second,
           diff < 3 {
            return
        }

        let chatGroupMessage = ChatGroupMessage(context: managedObjectContext)

        if let messageId = xmppGroup.messageId {
            chatGroupMessage.id = messageId
        }
        chatGroupMessage.groupId = xmppGroup.groupId
        chatGroupMessage.timestamp = Date()

        let chatGroupMessageEvent = ChatGroupMessageEvent(context: managedObjectContext)
        chatGroupMessageEvent.sender = xmppGroup.sender
        chatGroupMessageEvent.memberUserId = xmppGroupMember?.userId
        chatGroupMessageEvent.groupName = xmppGroup.name

        chatGroupMessageEvent.action = {
            switch xmppGroup.action {
            case .create: return .create
            case .join: return .join
            case .leave: return .leave
            case .delete: return .delete
            case .changeName: return .changeName
            case .changeDescription: return .changeDescription
            case .changeAvatar: return .changeAvatar
            case .setBackground: return .setBackground
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

        if let chatThread = self.chatThread(type: .group, id: chatGroupMessage.groupId, in: managedObjectContext) {

            chatThread.lastFeedUserID = chatGroupMessage.userId
            chatThread.lastFeedText = chatGroupMessageEvent.text
            chatThread.lastFeedTimestamp = chatGroupMessage.timestamp

            // unreadCount is not incremented for group event messages
        }
        
        save(managedObjectContext)

        didGetAGroupEvent.send(chatGroupMessage.groupId)
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

// MARK: Group Notifications
extension ChatData {

    private func showGroupAddNotification(for xmppGroup: XMPPGroup) {
        DDLogVerbose("ChatData/showGroupAddNotification/id \(xmppGroup.groupId)")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch UIApplication.shared.applicationState {
            case .background, .inactive:
                self.presentLocalGroupAddNotifications(for: xmppGroup)
            case .active:
                self.presentGroupAddBanner(for: xmppGroup)
            @unknown default:
                self.presentLocalGroupAddNotifications(for: xmppGroup)
            }
        }
    }

    private func presentGroupAddBanner(for xmppGroup: XMPPGroup) {
        DDLogDebug("ChatData/presentGroupAddBanner/id \(xmppGroup.groupId)")
        let groupID = xmppGroup.groupId
        guard let userID = xmppGroup.sender else { return }
        let groupName = xmppGroup.name

        let name = contactStore.fullName(for: userID)

        let title = "\(name) @ \(groupName)"
        let body = Localizations.groupsAddNotificationBody

        Banner.show(title: title, body: body, groupID: groupID, using: MainAppContext.shared.avatarStore)
    }

    private func presentLocalGroupAddNotifications(for xmppGroup: XMPPGroup) {
        DDLogDebug("ChatData/presentLocalGroupAddNotifications/groupID \(xmppGroup.groupId)")
        guard let messageID = xmppGroup.messageId else { return }
        guard let userID = xmppGroup.sender else { return }

        let metadata = NotificationMetadata(contentId: messageID,
                                            contentType: .groupAdd,
                                            fromId: userID,
                                            timestamp: nil,
                                            data: nil,
                                            messageId: messageID)
        metadata.groupId = xmppGroup.groupId
        metadata.groupName = xmppGroup.name
        // create and add a notification to the notification center.
        NotificationRequest.createAndShow(from: metadata)
    }

}

extension ChatData: HalloChatDelegate {

    // MARK: XMPP Chat Delegates

    func halloService(_ halloService: HalloService, didReceiveMessageReceipt receipt: HalloReceipt, ack: (() -> Void)?) {
        DDLogDebug("ChatData/didReceiveMessageReceipt [\(receipt.itemId)] \(receipt)")
        guard receipt.thread == .none else {
            DDLogError("ChatData/didReceiveMessageReceipt/error [unexpected-thread] [\(receipt.thread)]")
            ack?()
            return
        }
        processInboundOneToOneMessageReceipt(with: receipt)
        ack?()
    }

    func halloService(_ halloService: HalloService, didRerequestMessage messageID: String, from userID: UserID, ack: (() -> Void)?) {
        DDLogDebug("ChatData/didRerequestMessage [\(messageID)]")

        handleRerequest(for: messageID, from: userID)
        ack?()
    }

    func halloService(_ halloService: HalloService, didSendMessageReceipt receipt: HalloReceipt) {
        guard receipt.thread == .none else { return }

        updateChatMessage(with: receipt.itemId) { (chatMessage) in
            DDLogDebug("ChatData/oneToOne/didSendMessageReceipt [\(receipt.itemId)]")
            guard chatMessage.incomingStatus == .haveSeen else { return }
            chatMessage.incomingStatus = .sentSeenReceipt
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
        self.context = ChatContext(
            feedPostID: chatMessage.feedPostId,
            feedPostMediaIndex: chatMessage.feedPostMediaIndex,
            chatReplyMessageID: chatMessage.chatReplyMessageID,
            chatReplyMessageMediaIndex: chatMessage.chatReplyMessageMediaIndex,
            chatReplyMessageSenderID: chatMessage.chatReplyMessageSenderID)
        self.rerequestCount = Int32(chatMessage.resendAttempts)
        
        if let media = chatMessage.media, !media.isEmpty {
            if media.count == 1, let item = media.first, item.type == .audio {
                self.content = .voiceNote(XMPPChatMedia(chatMedia: item))
            } else {
                self.content = .album(
                    chatMessage.text,
                    media.sorted(by: { $0.order < $1.order }).map{ XMPPChatMedia(chatMedia: $0) })
            }
        } else {
            self.content = .text(chatMessage.text ?? "")
        }
    }

    init(content: ChatContent, context: ChatContext, timestamp: Int64, from fromUserID: UserID, to toUserID: UserID, id: String, retryCount: Int32, rerequestCount: Int32) {
        self.id = id
        self.fromUserId = fromUserID
        self.toUserId = toUserID
        self.timestamp = TimeInterval(timestamp)
        self.retryCount = retryCount
        self.rerequestCount = rerequestCount
        self.content = content
        self.context = context
    }
}
