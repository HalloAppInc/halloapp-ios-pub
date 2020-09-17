//
//  HalloApp
//
//  Created by Tony Jiang on 4/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Combine
import Core
import XMPPFramework

typealias ChatAck = (id: String, timestamp: Date?)

typealias ChatPresenceInfo = (userID: UserID, presence: PresenceType?, lastSeen: Date?)

typealias ChatMessageID = String
typealias ChatGroupMessageID = String
typealias GroupID = String

public enum ChatType: Int16 {
    case oneToOne = 0
    case group = 1
}

public enum UserPresenceType: Int16 {
    case none = 0
    case available = 1
    case away = 2
}

class ChatData: ObservableObject {
    public var currentPage: Int = 0
    
    let didChangeUnreadThreadCount = PassthroughSubject<Int, Never>()
    let didChangeUnreadCount = PassthroughSubject<Int, Never>()
    let didGetCurrentChatPresence = PassthroughSubject<(UserPresenceType, Date?), Never>()
    
    private let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.chat")
    
    private let userData: UserData
    private var service: HalloService
    private let mediaUploader: MediaUploader
    private var cancellableSet: Set<AnyCancellable> = []
    
    private var currentlyChattingWithUserId: String? = nil
    private var isSubscribedToCurrentUser: Bool = false
    
    private var currentlyChattingInGroup: GroupID? = nil
    
    private var unreadThreadCount: Int = 0 {
        didSet {
            self.didChangeUnreadThreadCount.send(unreadThreadCount)
//            DispatchQueue.main.async {
//                UIApplication.shared.applicationIconBadgeNumber = self.unreadThreadCount
//            }
        }
    }
    
    private var unreadMessageCount: Int = 0 {
        didSet {
            self.didChangeUnreadCount.send(unreadMessageCount)
        }
    }

    private let downloadQueue = DispatchQueue(label: "com.halloapp.chat.download", qos: .userInitiated)
    private let maxNumDownloads: Int = 1
    private var currentlyDownloading: [URL] = [] // TODO: not currently used, re-evaluate if it's needed
    private let maxTries: Int = 10

    init(service: HalloService, userData: UserData) {
        
        self.service = service
        self.userData = userData
        mediaUploader = MediaUploader(service: service)

        self.service.chatDelegate = self

        mediaUploader.resolveMediaPath = { relativePath in
            return MainAppContext.chatMediaDirectoryURL.appendingPathComponent(relativePath, isDirectory: false)
        }
        
        cancellableSet.insert(
            service.didGetChatAck.sink { [weak self] xmppAck in
                DDLogInfo("ChatData/gotAck \(xmppAck)")
                guard let self = self else { return }
                self.processIncomingChatAck(xmppAck)
            }
        )
        
        cancellableSet.insert(
            service.didGetNewChatMessage.sink { [weak self] xmppMessage in
                DDLogInfo("ChatData/newMsg \(xmppMessage)")
                self?.processIncomingXMPPChatMessage(xmppMessage)
            }
        )
        
        cancellableSet.insert(
            service.didConnect.sink { [weak self] in
                guard let self = self else { return }
                DDLogInfo("ChatData/onConnect")
                
                if (UIApplication.shared.applicationState == .active) {
                    DDLogInfo("ChatData/onConnect/sendPresence")
                    self.sendPresence(type: .available)
                    
                    if let currentUser = self.currentlyChattingWithUserId {
                        if !self.isSubscribedToCurrentUser {
                            self.subscribeToPresence(to: currentUser)
                        }
                    }
                } else {
                    DDLogDebug("ChatData/onConnect/appNotActive")
                }
                
                self.performSeriallyOnBackgroundContext { (managedObjectContext) in
                    let pendingOutgoingChatMessages = self.pendingOutgoingChatMessages(in: managedObjectContext)
                    
                    // inject delay between batch sends so that they won't be timestamped the same time,
                    // which causes display of messages to be in mixed order
                    var timeDelay = 0.0
                    pendingOutgoingChatMessages.forEach {
                        DDLogInfo("ChatData/onConnect/processPending/chatMessages \($0.id)")
                        let xmppChatMessage = XMPPChatMessage(chatMessage: $0)
                        self.backgroundProcessingQueue.asyncAfter(deadline: .now() + timeDelay) {
                            MainAppContext.shared.service.sendChatMessage(xmppChatMessage, encryption: nil)
                        }
                        timeDelay += 1.0
                    }

                    let pendingOutgoingSeenReceipts = self.pendingOutgoingSeenReceipts(in: managedObjectContext)
                    pendingOutgoingSeenReceipts.forEach {
                        DDLogInfo("ChatData/onConnect/processPending/seenReceipts \($0.id)")
                        self.sendSeenReceipt(for: $0)
                    }
                }
                //TODO: pending group
                
                // TODO: Eventually should move to checking for internet connectivity with a reachability manager instead of xmpp connection
                if (UIApplication.shared.applicationState == .active) {
                    self.processPendingChatMessageMedia()
                    self.processPendingChatGroupMessageMedia()
                }
            }
        )
        
        cancellableSet.insert(
            service.didGetPresence.sink { [weak self] xmppPresence in
                DDLogInfo("ChatData/gotPresence \(xmppPresence)")
                guard let self = self else { return }
                self.processIncomingPresence(xmppPresence)
            }
        )
        
        /** gotcha: use Combine sink instead of notificationCenter.addObserver because for some reason if the user flicks the app to the background and 3
            really quickly, the observer doesn't fire
         */
        cancellableSet.insert(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification).sink { [weak self] notification in
                guard let self = self else { return }
                self.sendPresence(type: .available)
                if let currentlyChattingWithUserId = self.currentlyChattingWithUserId {
                    self.performSeriallyOnBackgroundContext { (managedObjectContext) in
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
    }
    
    func populateThreadsWithSymmetricContacts() {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            let contacts = AppContext.shared.contactStore.allInNetworkContacts(sorted: true)
            for contact in contacts {
                guard let userId = contact.userId else { continue }
                if let chatThread = self.chatThread(type: ChatType.oneToOne, id: userId, in: managedObjectContext) {
                    guard chatThread.lastMsgTimestamp == nil else { continue }
                    if chatThread.title != AppContext.shared.contactStore.fullName(for: userId) {
                        DDLogDebug("ChatData/populateThreads/contact/rename \(userId)")
                        self.updateChatThread(type: .oneToOne, for: userId) { (chatThread) in
                            chatThread.title = AppContext.shared.contactStore.fullName(for: userId)
                        }
                    }
                } else {
                    DDLogInfo("ChatData/populateThreads/contact/new \(userId)")
                    let chatThread = NSEntityDescription.insertNewObject(forEntityName: ChatThread.entity().name!, into: managedObjectContext) as! ChatThread
                    chatThread.title = AppContext.shared.contactStore.fullName(for: userId)
                    chatThread.chatWithUserId = userId
                    chatThread.lastMsgUserId = userId
                    chatThread.lastMsgText = "Hi there! I’m using HalloApp"
                    chatThread.unreadCount = 0
                    self.save(managedObjectContext)
                }
            }
        }
        // TODO: take care of deletes, ie. user removes contact from address book
    }


    func processPendingChatMessageMedia() {
        guard self.currentlyDownloading.count < self.maxNumDownloads else { return }
        
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            
            let pendingMessagesWithMedia = self.pendingIncomingChatMessagesMedia(in: managedObjectContext)
            
            for chatMessage in pendingMessagesWithMedia {
                
                guard let media = chatMessage.media else { continue }
                
                let sortedMedia = media.sorted(by: { $0.order < $1.order })
                
                for med in sortedMedia {
                
                    guard med.incomingStatus == ChatMedia.IncomingStatus.pending else { continue }
                    guard med.numTries <= self.maxTries else { continue }
                    guard let url = med.url else { continue }
                    guard !self.currentlyDownloading.contains(url) else { continue }

                    let threadId = chatMessage.fromUserId
                    let messageId = chatMessage.id
                    let order = med.order
                    let key = med.key
                    let sha = med.sha256
                    let type: FeedMediaType = med.type == ChatMessageMediaType.image ? FeedMediaType.image : FeedMediaType.video
                
                    // save attempts
                    self.updateChatMessage(with: messageId) { (chatMessage) in
                        if let index = chatMessage.media?.firstIndex(where: { $0.order == order } ) {
                            chatMessage.media?[index].numTries += 1
                        }
                    }
                    
                    _ = ChatMediaDownloader(url: url, completion: { (outputUrl) in

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
                        
                        self.updateChatMessage(with: messageId) { (chatMessage) in
                            if let index = chatMessage.media?.firstIndex(where: { $0.order == order } ) {
                                let relativePath = self.relativePath(from: fileURL)
                                chatMessage.media?[index].relativeFilePath = relativePath
                                chatMessage.media?[index].incomingStatus = .downloaded
                                
                                // hack: force a change so frc can pick up the change
                                let fromUserId = chatMessage.fromUserId
                                chatMessage.fromUserId = fromUserId
                            }
                        }
                        self.processPendingChatMessageMedia()
                    })
                }
            }
        }
    }
    
    // TODO: need to refactor, have chat and group share this component
    func processPendingChatGroupMessageMedia() {
        guard self.currentlyDownloading.count < self.maxNumDownloads else { return }
        
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            
            let pendingMessagesWithMedia = self.pendingInboundChatGroupMessagesMedia(in: managedObjectContext)
            
            for chatGroupMessage in pendingMessagesWithMedia {
                
                guard let media = chatGroupMessage.media else { continue }
                
                let sortedMedia = media.sorted(by: { $0.order < $1.order })
                
                for med in sortedMedia {
                
                    guard med.incomingStatus == ChatMedia.IncomingStatus.pending else { continue }
                    guard med.numTries <= self.maxTries else { continue }
                    guard let url = med.url else { continue }
                    guard !self.currentlyDownloading.contains(url) else { continue }

                    let threadId = chatGroupMessage.groupId
                    let messageId = chatGroupMessage.id
                    let order = med.order
                    let key = med.key
                    let sha = med.sha256
                    let type: FeedMediaType = med.type == ChatMessageMediaType.image ? FeedMediaType.image : FeedMediaType.video
                
                    // save attempts
                    self.updateChatGroupMessage(with: messageId) { (chatGroupMessage) in
                        if let index = chatGroupMessage.media?.firstIndex(where: { $0.order == order } ) {
                            chatGroupMessage.media?[index].numTries += 1
                        }
                    }
                    
                    _ = ChatMediaDownloader(url: url, completion: { (outputUrl) in

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
                        
                        self.updateChatGroupMessage(with: messageId) { (chatGroupMessage) in
                            if let index = chatGroupMessage.media?.firstIndex(where: { $0.order == order } ) {
                                let relativePath = self.relativePath(from: fileURL)
                                chatGroupMessage.media?[index].relativeFilePath = relativePath
                                chatGroupMessage.media?[index].incomingStatus = .downloaded
                                
                                // hack: force a change so frc can pick up the change
                                let groupId = chatGroupMessage.groupId
                                chatGroupMessage.groupId = groupId
                            }
                        }
                        self.processPendingChatGroupMessageMedia()
                    })
                }
            }
        }
    }
    

    
    // MARK: Fetch Controller
    
    private class var persistentStoreURL: URL {
        get {
            return MainAppContext.chatStoreURL
        }
    }
    
    private func loadPersistentStores(in persistentContainer: NSPersistentContainer) {
        persistentContainer.loadPersistentStores { (description, error) in
            if let error = error {
                DDLogError("Failed to load persistent store: \(error)")
                DDLogError("Deleting persistent store at [\(ChatData.persistentStoreURL.absoluteString)]")
                try! FileManager.default.removeItem(at: ChatData.persistentStoreURL)
                fatalError("Unable to load persistent store: \(error)")
            } else {
                DDLogInfo("ChatData/load-store/completed [\(description)]")
            }
        }
    }
    
    private lazy var persistentContainer: NSPersistentContainer = {
        let storeDescription = NSPersistentStoreDescription(url: ChatData.persistentStoreURL)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSMigratePersistentStoresAutomaticallyOption)
        storeDescription.setOption(NSNumber(booleanLiteral: true), forKey: NSInferMappingModelAutomaticallyOption)
        storeDescription.setValue(NSString("WAL"), forPragmaNamed: "journal_mode")
        storeDescription.setValue(NSString("1"), forPragmaNamed: "secure_delete")
        let container = NSPersistentContainer(name: "Chat")
        container.persistentStoreDescriptions = [storeDescription]
        self.loadPersistentStores(in: container)
        return container
    }()
    
    private func loadPersistentContainer() {
        let container = self.persistentContainer
        DDLogDebug("ChatData/loadPersistentStore Loaded [\(container)]")
    }
    
    private func performSeriallyOnBackgroundContext(_ block: @escaping (NSManagedObjectContext) -> Void) {
        self.backgroundProcessingQueue.async {
            let managedObjectContext = self.persistentContainer.newBackgroundContext()
            managedObjectContext.performAndWait { block(managedObjectContext) }
        }
    }
    
    var viewContext: NSManagedObjectContext {
        get {
            self.persistentContainer.viewContext.automaticallyMergesChangesFromParent = true
            return self.persistentContainer.viewContext
        }
    }
    
    private func save(_ managedObjectContext: NSManagedObjectContext) {
        DDLogVerbose("ChatData/will-save")
        do {
            try managedObjectContext.save()
            DDLogVerbose("ChatData/did-save")
        } catch {
            DDLogError("ChatData/save-error error=[\(error)]")
        }
    }
    
    // MARK: Process Inbound Acks
    
    private func processIncomingChatAck(_ xmppChatAck: ChatAck) {
        var isGroupMessage: Bool = true
        self.updateChatMessage(with: xmppChatAck.id) { (chatMessage) in
            DDLogError("ChatData/processAck/chatMessage/ [\(xmppChatAck.id)]")
            isGroupMessage = false
            
            // outgoing message
            if chatMessage.outgoingStatus != .none {
                if chatMessage.outgoingStatus == .pending {
                    
                    chatMessage.outgoingStatus = .sentOut
                
                    self.updateChatThreadStatus(type: .oneToOne, for: chatMessage.toUserId, messageId: chatMessage.id) { (chatThread) in
                        chatThread.lastMsgStatus = .sentOut
                    }
                    
                }
                if let serverTimestamp = xmppChatAck.timestamp {
                    chatMessage.timestamp = serverTimestamp
                }
            }
        }
        
        guard isGroupMessage else { return }
        
        self.updateChatGroupMessage(with: xmppChatAck.id) { (chatGroupMessage) in
            DDLogError("ChatData/processAck/groupMessage [\(xmppChatAck.id)]")
    
            // outgoing message
            if chatGroupMessage.outboundStatus != .none {
                
                if chatGroupMessage.outboundStatus == .pending {
                    
                    chatGroupMessage.outboundStatus = .sentOut
                
                    self.updateChatThreadStatus(type: .group, for: chatGroupMessage.groupId, messageId: chatGroupMessage.id) { (chatThread) in
                        chatThread.lastMsgStatus = .sentOut
                    }
                    
                }
                if let serverTimestamp = xmppChatAck.timestamp {
                    chatGroupMessage.timestamp = serverTimestamp
                }
            }
        }
        
    }
    
    
    private func presentLocalNotifications(for chatMessage: ChatMessage) {
        let notification = UNMutableNotificationContent()
        notification.title = AppContext.shared.contactStore.fullName(for: chatMessage.fromUserId)
        if let text = chatMessage.text {
            notification.body = text
        }
        
        // TODO: If we want to use this method in the future, we need to construct and save metadata to userinfo
        
        DDLogDebug("ChatData/new-msg/localNotification [\(chatMessage.id)]")
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: notification, trigger: nil))
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
    
    func copyMediaToQuotedMedia(fromPath: String?, to quotedMedia: ChatQuotedMedia) throws {
        guard let fromRelativePath = fromPath else {
            return
        }
        
        let fromURL = MainAppContext.mediaDirectoryURL.appendingPathComponent(fromRelativePath, isDirectory: false)
        
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
        guard let userId = chatGroupMessage.userId else { return }
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
            completion()
            return
        }

        performSeriallyOnBackgroundContext { managedObjectContext in
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
            
            var lastMsgMediaType: ChatThread.LastMsgMediaType = .none
            
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
}

extension ChatData {

    // MARK: Thread
    
    func markSeenMessages(type: ChatType, for id: String, in managedObjectContext: NSManagedObjectContext) {
        
        if type == .oneToOne {
            let unseenChatMessages = self.unseenChatMessages(with: id, in: managedObjectContext)
            
            unseenChatMessages.forEach {
                self.sendSeenReceipt(for: $0)
                $0.incomingStatus = ChatMessage.IncomingStatus.haveSeen
            }
        } else if type == .group {
            let unseenChatGroupMessages = self.unseenChatGroupMessages(with: id, in: managedObjectContext)
            
            unseenChatGroupMessages.forEach {
                self.sendSeenGroupReceipt(for: $0)
                $0.inboundStatus = ChatGroupMessage.InboundStatus.haveSeen
            }
        }
        
        if managedObjectContext.hasChanges {
            self.save(managedObjectContext)
        }
        
    }
    
    func markThreadAsRead(type: ChatType, for id: String) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            
            if let chatThread = self.chatThread(type: type, id: id, in: managedObjectContext) {
                if chatThread.unreadCount != 0 {
                    chatThread.unreadCount = 0
                }
            }
            
            self.markSeenMessages(type: type, for: id, in: managedObjectContext)
            
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    func updateUnreadThreadCount() {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            let threads = self.chatThreads(predicate: NSPredicate(format: "unreadCount > 0"), in: managedObjectContext)
            self.unreadThreadCount = Int(threads.count)
        }
    }
    
    func updateUnreadMessageCount() {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            let threads = self.chatThreads(predicate: NSPredicate(format: "unreadCount > 0"), in: managedObjectContext)
            self.unreadMessageCount = Int(threads.reduce(0) { $0 + $1.unreadCount })
        }
    }
    
    func saveDraft(type: ChatType, for groupId: GroupID, with draft: String?) {
        updateChatThread(type: type, for: groupId) { chatThread in
            guard chatThread.draft != draft else { return }
            chatThread.draft = draft
        }
    }

    //MARK: Thread Core Data Fetching
    
    private func chatThreads(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatThread] {
        let managedObjectContext = managedObjectContext ?? self.viewContext
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
            return self.chatThreads(predicate: NSPredicate(format: "groupId == %@", id), in: managedObjectContext).first
        } else {
            return self.chatThreads(predicate: NSPredicate(format: "chatWithUserId == %@", id), in: managedObjectContext).first
        }
    }
    
    func chatThreadStatus(type: ChatType, id: String, messageId: String, in managedObjectContext: NSManagedObjectContext? = nil) -> ChatThread? {
        if type == .group {
            return self.chatThreads(predicate: NSPredicate(format: "groupId == %@ AND lastMsgId == %@", id, messageId), in: managedObjectContext).first
        } else {
            return self.chatThreads(predicate: NSPredicate(format: "chatWithUserId == %@ AND lastMsgId == %@", id, messageId), in: managedObjectContext).first
        }
    }
    
    // MARK: Thread Core Data Updating
    
    private func updateChatThread(type: ChatType, for id: String, block: @escaping (ChatThread) -> Void) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
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
            guard let chatThread = self.chatThreadStatus(type: type, id: id, messageId: messageId, in: managedObjectContext) else {
                DDLogError("ChatData/update-chatThread/missing-msg-in-thread [\(id)] [\(messageId)]")
                return
            }
            DDLogVerbose("ChatData/update-chatThreadStatus [\(id)]")
            block(chatThread)
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
}

extension ChatData {
    
    // MARK: 1-1
    
    func setCurrentlyChattingWithUserId(for chatWithUserId: String?) {
        currentlyChattingWithUserId = chatWithUserId
        isSubscribedToCurrentUser = false
    }
            
    // MARK: 1-1 Sending Messages
    
    func sendMessage(toUserId: String, text: String, media: [PendingMedia], feedPostId: String?, feedPostMediaIndex: Int32) {
        let messageId = UUID().uuidString

        // Create and save new ChatMessage object.
        let managedObjectContext = self.persistentContainer.viewContext
        DDLogDebug("ChatData/new-msg/\(messageId)")
        let chatMessage = NSEntityDescription.insertNewObject(forEntityName: ChatMessage.entity().name!, into: managedObjectContext) as! ChatMessage
        chatMessage.id = messageId
        chatMessage.toUserId = toUserId
        chatMessage.fromUserId = userData.userId
        chatMessage.text = text
        chatMessage.feedPostId = feedPostId
        chatMessage.feedPostMediaIndex = feedPostMediaIndex
        chatMessage.incomingStatus = .none
        chatMessage.outgoingStatus = .pending
        chatMessage.timestamp = Date()

        var lastMsgMediaType: ChatThread.LastMsgMediaType = .none // going with the first media
        
        for (index, mediaItem) in media.enumerated() {
            DDLogDebug("ChatData/new-msg/\(messageId)/add-media [\(mediaItem)]")

            let chatMedia = NSEntityDescription.insertNewObject(forEntityName: ChatMedia.entity().name!, into: managedObjectContext) as! ChatMedia
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
            chatMedia.size = mediaItem.size!
            chatMedia.key = mediaItem.key!
            chatMedia.sha256 = mediaItem.sha256!
            chatMedia.order = Int16(index)
            chatMedia.message = chatMessage

            do {
                try copyFiles(toChatMedia: chatMedia, fileUrl: mediaItem.fileURL!, encryptedFileUrl: mediaItem.encryptedFileUrl)
            }
            catch {
                DDLogError("ChatData/new-msg/\(messageId)/copy-media/error [\(error)]")
            }
        }
        
        // Create and save Quoted
        if let feedPostId = feedPostId, let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId) {
            let quoted = NSEntityDescription.insertNewObject(forEntityName: ChatQuoted.entity().name!, into: managedObjectContext) as! ChatQuoted
            quoted.type = .feedpost
            quoted.userId = feedPost.userId
            quoted.text = feedPost.text
            quoted.message = chatMessage

            if let feedPostMedia = feedPost.media?.first(where: { $0.order == feedPostMediaIndex }) {
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
                    try copyMediaToQuotedMedia(fromPath: feedPostMedia.relativeFilePath, to: quotedMedia)
                }
                catch {
                    DDLogError("ChatData/new-msg/\(messageId)/quoted/copy-media/error [\(error)]")
                }
            }
        }
        
        // Update Chat Thread
        if let chatThread = self.chatThread(type: ChatType.oneToOne, id: chatMessage.toUserId, in: managedObjectContext) {
            DDLogDebug("ChatData/new-msg/ update-thread")
            chatThread.lastMsgId = chatMessage.id
            chatThread.lastMsgUserId = chatMessage.fromUserId
            chatThread.lastMsgText = chatMessage.text
            chatThread.lastMsgMediaType = lastMsgMediaType
            chatThread.lastMsgStatus = .pending
            chatThread.lastMsgTimestamp = chatMessage.timestamp
        } else {
            DDLogDebug("ChatData/new-msg/\(messageId)/new-thread")
            let chatThread = NSEntityDescription.insertNewObject(forEntityName: ChatThread.entity().name!, into: managedObjectContext) as! ChatThread
            chatThread.chatWithUserId = chatMessage.toUserId
            chatThread.lastMsgId = chatMessage.id
            chatThread.lastMsgUserId = chatMessage.fromUserId
            chatThread.lastMsgText = chatMessage.text
            chatThread.lastMsgMediaType = lastMsgMediaType
            chatThread.lastMsgStatus = .pending
            chatThread.lastMsgTimestamp = chatMessage.timestamp
            chatThread.unreadCount = 0
        }
        save(managedObjectContext)

        uploadMediaAndSend(chatMessage)

    }

    private func uploadMediaAndSend(_ message: ChatMessage) {

        // Either all media has already been uploaded or post does not contain media.
        guard let mediaItemsToUpload = message.media?.filter({ $0.outgoingStatus == .none || $0.outgoingStatus == .pending || $0.outgoingStatus == .error }), !mediaItemsToUpload.isEmpty else {
            send(message: message)
            return
        }

        let messageId = message.id
        var numberOfFailedUploads = 0
        let totalUploads = mediaItemsToUpload.count
        DDLogInfo("ChatData/upload-media/\(messageId)/starting [\(totalUploads)]")

        let uploadGroup = DispatchGroup()
        for mediaItem in mediaItemsToUpload {
            let mediaIndex = mediaItem.order
            uploadGroup.enter()
            mediaUploader.upload(media: mediaItem, groupId: messageId, didGetURLs: { (mediaURLs) in
                DDLogInfo("ChatData/upload-media/\(messageId)/\(mediaIndex)/acquired-urls [\(mediaURLs)]")

                // Save URLs acquired during upload to the database.
                self.updateChatMessage(with: messageId) { (chatMessage) in
                    if let media = chatMessage.media?.first(where: { $0.order == mediaIndex }) {
                        media.url = mediaURLs.get
                        media.uploadUrl = mediaURLs.put
                    }
                }
            }) { (uploadResult) in
                DDLogInfo("ChatData/upload-media/\(messageId)/\(mediaIndex)/finished result=[\(uploadResult)]")

                // Save URLs acquired during upload to the database.
                self.updateChatMessage(with: messageId) { (chatMessage) in
                    if let media = chatMessage.media?.first(where: { $0.order == mediaIndex }) {
                        switch uploadResult {
                        case .success(_):
                            media.outgoingStatus = .uploaded

                        case .failure(_):
                            numberOfFailedUploads += 1
                            media.outgoingStatus = .error
                        }
                    }

                    uploadGroup.leave()
                }
            }
        }

        uploadGroup.notify(queue: .main) {
            DDLogInfo("ChatData/upload-media/\(messageId)/all/finished [\(totalUploads-numberOfFailedUploads)/\(totalUploads)]")
            if numberOfFailedUploads > 0 {
                self.updateChatMessage(with: messageId) { (chatMessage) in
                    chatMessage.outgoingStatus = .error
                }
            } else if let chatMessage = self.chatMessage(with: messageId) {
                self.send(message: chatMessage)
            }
        }
    }

    private func send(message: ChatMessage) {
        let xmppMessage = XMPPChatMessage(chatMessage: message)
        service.sendChatMessage(xmppMessage, encryption: MainAppContext.shared.keyData.encryptOperation(for: message.toUserId))
    }
    
    // MARK: 1-1 Presence
    
    func subscribeToPresence(to chatWithUserId: String) {
        guard !self.isSubscribedToCurrentUser else { return }
        self.isSubscribedToCurrentUser = service.subscribeToPresenceIfPossible(to: chatWithUserId)
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
        return self.chatMessages(predicate: NSPredicate(format: "fromUserId = %@ && outgoingStatusValue = %d", userData.userId, ChatMessage.OutgoingStatus.pending.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }
    
    func pendingOutgoingSeenReceipts(in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true)
        ]
        return self.chatMessages(predicate: NSPredicate(format: "fromUserId = %@ && incomingStatusValue = %d", userData.userId, ChatMessage.IncomingStatus.haveSeen.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }
    
    func pendingIncomingChatMessagesMedia(in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true)
        ]
        return self.chatMessages(predicate: NSPredicate(format: "ANY media.incomingStatusValue == %d", ChatMedia.IncomingStatus.pending.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }
    
    func pendingInboundChatGroupMessagesMedia(in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatGroupMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatGroupMessage.timestamp, ascending: true)
        ]
        return self.chatGroupMessages(predicate: NSPredicate(format: "ANY media.incomingStatusValue == %d", ChatMedia.IncomingStatus.pending.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }

    // MARK: 1-1 Core Data Updating
    
    private func updateChatMessage(with chatMessageId: String, block: @escaping (ChatMessage) -> Void) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
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
    
    public func updateChatMessageCellHeight(for chatMessageId: String, with cellHeight: Int) {
        updateChatMessage(with: chatMessageId) { (chatMessage) in
            chatMessage.cellHeight = Int16(cellHeight)
        }
    }
        
    // MARK: 1-1 Core Data Deleting
    
    private func deleteMedia(in chatMessage: ChatMessage) {
        DDLogDebug("ChatData/delete/message \(chatMessage.id) ")
        chatMessage.media?.forEach { (media) in
            if media.relativeFilePath != nil {
                let fileURL = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(media.relativeFilePath!, isDirectory: false)
                do {
                    DDLogDebug("ChatData/delete/message/media ")
                    try FileManager.default.removeItem(at: fileURL)
                }
                catch {
                    DDLogError("ChatData/delete/message/media/error [\(error)]")
                }
            }
            chatMessage.managedObjectContext?.delete(media)
        }
        
        if let quoted = chatMessage.quoted {
            DDLogDebug("ChatData/delete/message/quoted ")
            if let quotedMedia = quoted.media {
                quotedMedia.forEach { (media) in
                    if media.relativeFilePath != nil {
                        let fileURL = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(media.relativeFilePath!, isDirectory: false)
                        do {
                            DDLogDebug("ChatData/delete/message/quoted/media ")
                            try FileManager.default.removeItem(at: fileURL)
                        }
                        catch {
                            DDLogError("ChatData/delete/message/quoted/media/error [\(error)]")
                        }
                    }
                    quoted.managedObjectContext?.delete(media)
                }
            }
            chatMessage.managedObjectContext?.delete(quoted)
        }
    }
    
    
    func deleteChat(chatThreadId: String) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in

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
            
            self.populateThreadsWithSymmetricContacts()
        }
        
    }
}

extension ChatData {

    // MARK: 1-1 Process Inbound Messages
    
    private func processIncomingXMPPChatMessage(_ chatMessage: ChatMessageProtocol) {
        let isAppActive = UIApplication.shared.applicationState == .active
        
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            self.processIncomingChatMessage(xmppChatMessage: chatMessage, using: managedObjectContext, isAppActive: isAppActive)
        }
    }
    
    private func processIncomingChatMessage(xmppChatMessage: ChatMessageProtocol, using managedObjectContext: NSManagedObjectContext, isAppActive: Bool) {
        guard self.chatMessage(with: xmppChatMessage.id, in: managedObjectContext) == nil else {
            DDLogError("ChatData/process/already-exists [\(xmppChatMessage.id)]")
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
        chatMessage.incomingStatus = .none
        chatMessage.outgoingStatus = .none
        
        if let ts = xmppChatMessage.timeIntervalSince1970 {
            chatMessage.timestamp = Date(timeIntervalSince1970: ts)
        } else {
            chatMessage.timestamp = Date()
        }
        
        var lastMsgMediaType: ChatThread.LastMsgMediaType = .none // going with the first media found
        
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
        
        // Process Quoted
        if xmppChatMessage.feedPostId != nil {
            if let feedPost = MainAppContext.shared.feedData.feedPost(with: xmppChatMessage.feedPostId!) {
                let quoted = NSEntityDescription.insertNewObject(forEntityName: ChatQuoted.entity().name!, into: managedObjectContext) as! ChatQuoted
                quoted.type = .feedpost
                quoted.userId = feedPost.userId
                quoted.text = feedPost.text
                quoted.message = chatMessage
                
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
                            try copyMediaToQuotedMedia(fromPath: feedPostMedia.relativeFilePath, to: quotedMedia)
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
        
        //        self.presentLocalNotifications(for: chatMessage)
        
        // download chat message media
        self.processPendingChatMessageMedia()
        
    }
    
    // MARK: 1-1 Process Inbound Receipts
    
    private func processInboundOneToOneMessageReceipt(with receipt: XMPPReceipt) {
        let messageId = receipt.itemId
        let receiptType = receipt.type
        
        updateChatMessage(with: messageId) { [weak self] (chatMessage) in
            guard let self = self else { return }
            
            if chatMessage.outgoingStatus != .seen {
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
    }
}
    
extension ChatData {

    // MARK: 1-1 Presence
    
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
        self.didGetCurrentChatPresence.send((presenceStatus, presenceLastSeen))
    }
        

}

extension ChatData {
    
    public typealias GroupActionCompletion = (Error?) -> Void
    
    // MARK: Group
    
    func setCurrentlyChattingInGroup(for groupId: GroupID?) {
        currentlyChattingInGroup = groupId
    }
    
    // MARK: Group Actions
    
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
    
        self.updateChatGroup(with: xmppGroup.groupId) { [weak self] (chatGroup) in
            guard let self = self else { return }
            chatGroup.lastSync = Date()
            
            if chatGroup.name != xmppGroup.name {
                chatGroup.name = xmppGroup.name
            }
            if chatGroup.avatar != xmppGroup.avatar {
                chatGroup.avatar = xmppGroup.avatar
            }
            
            // look for users that are not members anymore
            chatGroup.orderedMembers.forEach { currentMember in
                let foundMember = xmppGroup.members.first(where: { $0.userId == currentMember.userId })
                
                if foundMember == nil {
                    chatGroup.managedObjectContext!.delete(currentMember)
                }
            }
            
            var contactNames = [UserID:String]()
            
            // see if there are new members added or needs to be updated
            xmppGroup.members.forEach { inboundMember in
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
                if let name = inboundMember.name {
                    contactNames[inboundMember.userId] = name
                }
            }
            
            if !contactNames.isEmpty {
                MainAppContext.shared.contactStore.addPushNames(contactNames)
            }
        }
    }
    
    // MARK: Group Sending Messages
    
    func sendGroupMessage(toGroupId: GroupID, text: String, media: [PendingMedia]) {
        let groupMessageId = UUID().uuidString

        // Create and save new ChatGroupMessage object.
        let managedObjectContext = self.persistentContainer.viewContext
        DDLogDebug("ChatData/group/new-msg/\(groupMessageId)")
        let chatGroupMessage = NSEntityDescription.insertNewObject(forEntityName: ChatGroupMessage.entity().name!, into: managedObjectContext) as! ChatGroupMessage
        chatGroupMessage.id = groupMessageId
        chatGroupMessage.groupId = toGroupId
        chatGroupMessage.userId = AppContext.shared.userData.userId
        chatGroupMessage.text = text
        chatGroupMessage.inboundStatus = .none
        chatGroupMessage.outboundStatus = .pending
        chatGroupMessage.timestamp = Date()

        // insert all the group members who should get this message
        if let chatGroup = self.chatGroup(groupId: toGroupId, in: managedObjectContext) {
            if let members = chatGroup.members {
                for member in members {
                    guard member.userId != MainAppContext.shared.userData.userId else { continue }
                    let messageInfo = NSEntityDescription.insertNewObject(forEntityName: ChatGroupMessageInfo.entity().name!, into: managedObjectContext) as! ChatGroupMessageInfo
                    messageInfo.chatGroupMessageId = chatGroupMessage.id
                    messageInfo.userId = member.userId
                    messageInfo.outboundStatus = .none
                    messageInfo.groupMessage = chatGroupMessage
                    messageInfo.timestamp = Date()
                }
            }
        }
        
        var lastMsgMediaType: ChatThread.LastMsgMediaType = .none // going with the first media
        
        for (index, mediaItem) in media.enumerated() {
            DDLogDebug("ChatData/group/new-msg/\(groupMessageId)/add-media [\(mediaItem)]")

            let chatMedia = NSEntityDescription.insertNewObject(forEntityName: ChatMedia.entity().name!, into: managedObjectContext) as! ChatMedia
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
            chatMedia.size = mediaItem.size!
            chatMedia.key = mediaItem.key!
            chatMedia.sha256 = mediaItem.sha256!
            chatMedia.order = Int16(index)
            chatMedia.message = nil
            chatMedia.groupMessage = chatGroupMessage

            do {
                try copyFiles(toChatMedia: chatMedia, fileUrl: mediaItem.fileURL!, encryptedFileUrl: mediaItem.encryptedFileUrl)
            }
            catch {
                DDLogError("ChatData/group/new-msg/\(groupMessageId)/copy-media/error [\(error)]")
            }
        }
        
        // Update Chat Thread
        if let chatThread = self.chatThread(type: .group, id: chatGroupMessage.groupId, in: managedObjectContext) {
            DDLogDebug("ChatData/group/new-msg/ update-thread")
            chatThread.type = .group
            chatThread.lastMsgId = chatGroupMessage.id
            chatThread.lastMsgUserId = chatGroupMessage.userId
            chatThread.lastMsgText = chatGroupMessage.text
            chatThread.lastMsgMediaType = lastMsgMediaType
            chatThread.lastMsgStatus = .pending
            chatThread.lastMsgTimestamp = chatGroupMessage.timestamp
            chatThread.draft = nil
        } else {
            DDLogDebug("ChatData/group/new-msg/\(groupMessageId)/new-thread")
            let chatThread = NSEntityDescription.insertNewObject(forEntityName: ChatThread.entity().name!, into: managedObjectContext) as! ChatThread
            chatThread.type = .group
            chatThread.groupId = chatGroupMessage.groupId
            chatThread.lastMsgId = chatGroupMessage.id
            chatThread.lastMsgUserId = chatGroupMessage.userId
            chatThread.lastMsgText = chatGroupMessage.text
            chatThread.lastMsgMediaType = lastMsgMediaType
            chatThread.lastMsgStatus = .pending
            chatThread.lastMsgTimestamp = chatGroupMessage.timestamp
            chatThread.unreadCount = 0
        }
        save(managedObjectContext)
        
        uploadGroupMediaAndSend(chatGroupMessage)
    }
    
    // TODO: consolidate this with ChatMessage
    private func uploadGroupMediaAndSend(_ groupMessage: ChatGroupMessage) {
        // Either all media has already been uploaded or post does not contain media.
        guard let mediaItemsToUpload = groupMessage.media?.filter({ $0.outgoingStatus == .none || $0.outgoingStatus == .pending || $0.outgoingStatus == .error }), !mediaItemsToUpload.isEmpty else {
            sendGroup(groupMessage: groupMessage)
            return
        }
        
        let groupMessageId = groupMessage.id
        var numberOfFailedUploads = 0
        let totalUploads = mediaItemsToUpload.count
        DDLogInfo("ChatData/group/upload-media/\(groupMessageId)/starting [\(totalUploads)]")

        let uploadGroup = DispatchGroup()
        
        for mediaItem in mediaItemsToUpload {
            let mediaIndex = mediaItem.order
            uploadGroup.enter()
            
            mediaUploader.upload(media: mediaItem, groupId: groupMessageId, didGetURLs: { (mediaURLs) in
                DDLogInfo("ChatData/group/upload-media/\(groupMessageId)/\(mediaIndex)/acquired-urls [\(mediaURLs)]")

                // Save URLs acquired during upload to the database.
                self.updateChatGroupMessage(with: groupMessageId) { (chatGroupMessage) in
                    if let media = chatGroupMessage.media?.first(where: { $0.order == mediaIndex }) {
                        media.url = mediaURLs.get
                        media.uploadUrl = mediaURLs.put
                    }
                }
            }) { (uploadResult) in
                DDLogInfo("ChatData/group/upload-media/\(groupMessageId)/\(mediaIndex)/finished result=[\(uploadResult)]")

                // Save URLs acquired during upload to the database.
                self.updateChatGroupMessage(with: groupMessageId) { (chatGroupMessage) in
                    if let media = chatGroupMessage.media?.first(where: { $0.order == mediaIndex }) {
                        switch uploadResult {
                        case .success(_):
                            media.outgoingStatus = .uploaded

                        case .failure(_):
                            numberOfFailedUploads += 1
                            media.outgoingStatus = .error
                        }
                    }

                    uploadGroup.leave()
                }
            }
        }

        uploadGroup.notify(queue: .main) {
            DDLogInfo("ChatData/group/upload-media/\(groupMessageId)/all/finished [\(totalUploads-numberOfFailedUploads)/\(totalUploads)]")
            if numberOfFailedUploads > 0 {
                self.updateChatGroupMessage(with: groupMessageId) { (chatGroupMessage) in
                    chatGroupMessage.outboundStatus = .error
                }
            } else if let chatGroupMessage = self.chatGroupMessage(with: groupMessageId) {
                self.sendGroup(groupMessage: chatGroupMessage)
            }
        }
    }
    
    private func sendGroup(groupMessage: ChatGroupMessage) {
        let xmppGroupMessage = XMPPChatGroupMessage(chatGroupMessage: groupMessage)
        service.sendGroupChatMessage(xmppGroupMessage) { _ in }
    }

    // MARK: Group Core Data Fetching
    
    private func chatGroups(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatGroup] {
        let managedObjectContext = managedObjectContext ?? self.viewContext
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
        return self.chatGroups(predicate: NSPredicate(format: "groupId == %@", id), in: managedObjectContext).first
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
        return self.chatGroupMembers(predicate: NSPredicate(format: "groupId == %@ && userId == %@", id, memberUserId), in: managedObjectContext).first
    }
    
    private func chatGroupMessages(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatGroupMessage] {
        let managedObjectContext = managedObjectContext ?? self.viewContext
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
        return self.chatGroupMessages(predicate: NSPredicate(format: "id == %@", id), in: managedObjectContext).first
    }
    
    // includes seen but not sent messages
    func unseenChatGroupMessages(with groupId: String, in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatGroupMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatGroupMessage.timestamp, ascending: true)
        ]
        return self.chatGroupMessages(predicate: NSPredicate(format: "(groupId = %@) && (event.@count == 0) && (inboundStatusValue = %d OR inboundStatusValue = %d)", groupId, ChatGroupMessage.InboundStatus.none.rawValue, ChatGroupMessage.InboundStatus.haveSeen.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
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
        return self.chatGroupMessageAllInfo(predicate: NSPredicate(format: "chatGroupMessageId == %@", messageId), in: managedObjectContext).first
    }
    
    func chatGroupMessageInfoForUser(messageId: String, userId: UserID, in managedObjectContext: NSManagedObjectContext? = nil) -> ChatGroupMessageInfo? {
        return self.chatGroupMessageAllInfo(predicate: NSPredicate(format: "chatGroupMessageId == %@ && userId == %@", messageId, userId), in: managedObjectContext).first
    }
    
    // MARK: Group Core Data Updating
    
    public func updateChatGroupMessageCellHeight(for chatGroupMessageId: String, with cellHeight: Int) {
        self.updateChatGroupMessage(with: chatGroupMessageId) { (chatGroupMessage) in
            chatGroupMessage.cellHeight = Int16(cellHeight)
        }
    }
    
    func updateChatGroup(with groupId: GroupID, block: @escaping (ChatGroup) -> Void) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
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
    
    func updateChatGroupMessage(with chatGroupMessageId: String, block: @escaping (ChatGroupMessage) -> Void) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
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
    
    func updateChatGroupMessageInfo(with chatGroupMessageId: String, userId: UserID, block: @escaping (ChatGroupMessageInfo) -> Void) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
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
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in

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
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            
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

extension ChatData {
    
    // MARK: Group Process Inbound Messages
    
    private func processInboundChatGroupMessage(xmppChatGroupMessage: XMPPChatGroupMessage, using managedObjectContext: NSManagedObjectContext, isAppActive: Bool) {
        
        guard chatGroupMessage(with: xmppChatGroupMessage.id, in: managedObjectContext) == nil else {
            DDLogError("ChatData/group/processInboundChatGroupMessage/already-exists [\(xmppChatGroupMessage.id)]")
            return
        }
        
        var isCurrentlyChattingInGroup = false
        var groupExist = true
        
        if let currentlyChattingInGroup = self.currentlyChattingInGroup {
            if xmppChatGroupMessage.groupId == currentlyChattingInGroup {
                isCurrentlyChattingInGroup = true
            }
        }
        
        // if group doesn't exist yet, add
        if chatGroup(groupId: xmppChatGroupMessage.groupId, in: managedObjectContext) == nil {
            DDLogDebug("ChatData/group/processInboundChatGroupMessage/group not exist yet [\(xmppChatGroupMessage.groupId)]")
            groupExist = false
            let chatGroup = NSEntityDescription.insertNewObject(forEntityName: ChatGroup.entity().name!, into: managedObjectContext) as! ChatGroup
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
        chatGroupMessage.inboundStatus = .none
        chatGroupMessage.outboundStatus = .none
        chatGroupMessage.timestamp = xmppChatGroupMessage.timestamp
        
        var lastMsgMediaType: ChatThread.LastMsgMediaType = .none // going with the first media found
        
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
                
        // Update Chat Thread
        if let chatThread = self.chatThread(type: .group, id: chatGroupMessage.groupId, in: managedObjectContext) {
            chatThread.lastMsgId = chatGroupMessage.id
            chatThread.lastMsgUserId = chatGroupMessage.userId
            chatThread.lastMsgText = chatGroupMessage.text
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
            chatThread.lastMsgText = chatGroupMessage.text
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
            self.sendSeenGroupReceipt(for: chatGroupMessage)
            self.updateChatGroupMessage(with: chatGroupMessage.id) { (chatGroupMessage) in
                chatGroupMessage.inboundStatus = .haveSeen
            }
        } else {
            self.updateUnreadThreadCount()
        }
        
        // add to pushnames
        if let userId = xmppChatGroupMessage.userId, let name = xmppChatGroupMessage.userName {
            MainAppContext.shared.contactStore.addPushNames([userId: name])
        }
        
//        self.presentLocalNotifications(for: chatMessage)
        
        // download chat group message media
        self.processPendingChatGroupMessageMedia()
    }
    
    // MARK: Group Process Inbound Receipts

    private func processInboundGroupMessageReceipt(with receipt: XMPPReceipt, for groupId: GroupID) {
        let messageId = receipt.itemId
        guard let receiptTimestamp = receipt.timestamp else { return }
        
  
        if receipt.type == .delivery {
            updateChatGroupMessageInfo(with: messageId, userId: receipt.userId) { [weak self] (chatGroupMessageInfo) in
                guard let self = self else { return }
                if chatGroupMessageInfo.outboundStatus == .none {
                    chatGroupMessageInfo.outboundStatus = .delivered
                    
                    chatGroupMessageInfo.timestamp = receiptTimestamp
                }
                
                let msg = chatGroupMessageInfo.groupMessage
                
                if msg.outboundStatus != .seen && msg.outboundStatus != .delivered {
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
            }
            
        } else if receipt.type == .read {
            
            updateChatGroupMessageInfo(with: messageId, userId: receipt.userId) { [weak self] (chatGroupMessageInfo) in
                guard let self = self else { return }
                if (chatGroupMessageInfo.outboundStatus == .none || chatGroupMessageInfo.outboundStatus == .delivered) {
                    chatGroupMessageInfo.outboundStatus = .seen
                    chatGroupMessageInfo.timestamp = receiptTimestamp
                }
                
                let msg = chatGroupMessageInfo.groupMessage
                if msg.outboundStatus != .seen {
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
            
    }
    
    // MARK: Group Process Inbound Actions/Events

    private func processIncomingXMPPGroup(_ group: XMPPGroup) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
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
            let groupCreator = NSEntityDescription.insertNewObject(forEntityName: ChatGroupMember.entity().name!, into: managedObjectContext) as! ChatGroupMember
            groupCreator.groupId = xmppGroup.groupId
            groupCreator.userId = sender
            groupCreator.type = .admin
            groupCreator.group = chatGroup
            
            if let userId = xmppGroup.senderName, let name = xmppGroup.senderName {
                contactNames[userId] = name
            }
        }

        // Add new Group members to database
        for (_, xmppGroupMember) in xmppGroup.members.enumerated() {
            DDLogDebug("ChatData/group/process/new/add-member [\(xmppGroupMember.userId)]")
            processGroupAddMemberAction(chatGroup: chatGroup, xmppGroupMember: xmppGroupMember, in: managedObjectContext)
            
            // add to pushnames
            if let name = xmppGroupMember.name {
                contactNames[xmppGroupMember.userId] = name
            }
        }
        
        if !contactNames.isEmpty {
            MainAppContext.shared.contactStore.addPushNames(contactNames)
        }
        
        recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: nil, in: managedObjectContext)
    }

    private func processGroupLeaveAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) {
        
        _ = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)
        
        for (_, xmppGroupMember) in xmppGroup.members.enumerated() {
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
        for (_, xmppGroupMember) in xmppGroup.members.enumerated() {
            DDLogDebug("ChatData/group/process/modifyMembers [\(xmppGroupMember.userId)]")
            
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
    
    private func processGroupCreateIfNotExist(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) -> ChatGroup {
        DDLogDebug("ChatData/group/processGroupCreateIfNotExist/ [\(xmppGroup.groupId)]")
        if let existingChatGroup = chatGroup(groupId: xmppGroup.groupId, in: managedObjectContext) {
            DDLogDebug("ChatData/group/processGroupCreateIfNotExist/groupExist [\(xmppGroup.groupId)]")
            return existingChatGroup
        } else {
            
            // Add new Group to database
            DDLogDebug("ChatData/group/processGroupCreateIfNotExist/new [\(xmppGroup.groupId)]")
            let chatGroup = NSEntityDescription.insertNewObject(forEntityName: ChatGroup.entity().name!, into: managedObjectContext) as! ChatGroup
            chatGroup.groupId = xmppGroup.groupId
            chatGroup.name = xmppGroup.name
            
            // Add Chat Thread
            if self.chatThread(type: .group, id: chatGroup.groupId, in: managedObjectContext) == nil {
                let chatThread = NSEntityDescription.insertNewObject(forEntityName: ChatThread.entity().name!, into: managedObjectContext) as! ChatThread
                chatThread.type = ChatType.group
                chatThread.groupId = chatGroup.groupId
                chatThread.title = chatGroup.name
                chatThread.lastMsgTimestamp = Date()
            }
            return chatGroup
        }
    }
    
    private func recordGroupMessageEvent(xmppGroup: XMPPGroup, xmppGroupMember: XMPPGroupMember?, in managedObjectContext: NSManagedObjectContext) {
        let chatGroupMessage = NSEntityDescription.insertNewObject(forEntityName: ChatGroupMessage.entity().name!, into: managedObjectContext) as! ChatGroupMessage
        if let messageId = xmppGroup.messageId {
            chatGroupMessage.id = messageId
        }
        chatGroupMessage.groupId = xmppGroup.groupId
        chatGroupMessage.timestamp = Date()
        
        let chatGroupMessageEvent = NSEntityDescription.insertNewObject(forEntityName: ChatGroupMessageEvent.entity().name!, into: managedObjectContext) as! ChatGroupMessageEvent
        chatGroupMessageEvent.sender = xmppGroup.sender
        chatGroupMessageEvent.memberUserId = xmppGroupMember?.userId
        
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
            chatThread.lastMsgId = chatGroupMessage.id
            chatThread.lastMsgUserId = chatGroupMessage.userId
            chatThread.lastMsgText = chatGroupMessageEvent.text
            chatThread.lastMsgMediaType = .none
            chatThread.lastMsgStatus = .none
            chatThread.lastMsgTimestamp = chatGroupMessage.timestamp
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
            let member = NSEntityDescription.insertNewObject(forEntityName: ChatGroupMember.entity().name!, into: managedObjectContext) as! ChatGroupMember
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


extension ChatData: HalloChatDelegate {

    // MARK: XMPP Chat Delegates
    
    func halloService(_ halloService: HalloService, didReceiveMessageReceipt receipt: HalloReceipt, ack: (() -> Void)?) {
        DDLogDebug("ChatData/didReceiveMessageReceipt [\(receipt.itemId)]")
        
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
        let isAppActive = UIApplication.shared.applicationState == .active
        
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            self.processInboundChatGroupMessage(xmppChatGroupMessage: message, using: managedObjectContext, isAppActive: isAppActive)
        }
    }

    func halloService(_ halloService: HalloService, didReceiveGroupMessage group: HalloGroup) {
        processIncomingXMPPGroup(group)
    }
}


extension XMPPChatMessage {
    
    // used for outgoing chat messages
    init(chatMessage: ChatMessage) {
        self.id = chatMessage.id
        self.fromUserId = chatMessage.fromUserId
        self.toUserId = chatMessage.toUserId
        self.text = chatMessage.text
        self.feedPostId = chatMessage.feedPostId
        self.feedPostMediaIndex = chatMessage.feedPostMediaIndex
        
        if let media = chatMessage.media {
            self.media = media.sorted(by: { $0.order < $1.order }).map{ XMPPChatMedia(chatMedia: $0) }
        } else {
            self.media = []
        }
    }
    
    // init incoming message
    init?(itemElement item: XMLElement) {
        guard let id = item.attributeStringValue(forName: "id") else { return nil }
        guard let toUserId = item.attributeStringValue(forName: "to")?.components(separatedBy: "@").first else { return nil }
        guard let fromUserId = item.attributeStringValue(forName: "from")?.components(separatedBy: "@").first else { return nil }
        guard let chat = item.element(forName: "chat") else { return nil }
        
        var text: String?, media: [XMPPChatMedia] = [], feedPostId: String?, feedPostMediaIndex: Int32 = 0
        
        if let protoContainer = Proto_Container.unwrapMessage(for: fromUserId, from: chat) {
            if protoContainer.hasChatMessage {
                text = protoContainer.chatMessage.text.isEmpty ? nil : protoContainer.chatMessage.text
                
                DDLogInfo("ChatData/XMPPChatMessage/decryptedMessage: \(text ?? "")")
                
                media = protoContainer.chatMessage.media.compactMap { XMPPChatMedia(protoMedia: $0) }
                
                feedPostId = protoContainer.chatMessage.feedPostID.isEmpty ? nil : protoContainer.chatMessage.feedPostID
                feedPostMediaIndex = protoContainer.chatMessage.feedPostMediaIndex
            }
        }
            
        else if let protoContainer = Proto_Container.chatMessageContainer(from: chat) {
            if protoContainer.hasChatMessage {
                text = protoContainer.chatMessage.text.isEmpty ? nil : protoContainer.chatMessage.text
                DDLogInfo("ChatData/XMPPChatMessage/plainText: \(text ?? "")")
                
                media = protoContainer.chatMessage.media.compactMap { XMPPChatMedia(protoMedia: $0) }
                
                feedPostId = protoContainer.chatMessage.feedPostID.isEmpty ? nil : protoContainer.chatMessage.feedPostID
                feedPostMediaIndex = protoContainer.chatMessage.feedPostMediaIndex
            }
        }
        
        self.id = id
        self.fromUserId = fromUserId
        self.toUserId = toUserId
        self.text = text
        
        self.feedPostId = feedPostId
        self.feedPostMediaIndex = feedPostMediaIndex
        self.media = media
        
        self.timestamp = chat.attributeDoubleValue(forName: "timestamp")
    }
}


extension Proto_Container {
    static func unwrapMessage(for userId: String, from entry: XMLElement) -> Proto_Container? {
        guard let protoContainerData = MainAppContext.shared.keyData.unwrapMessage(for: userId, from: entry) else { return nil }
        do {
            let protoContainer = try Proto_Container(serializedData: protoContainerData)
            return protoContainer
        } catch {
            DDLogError("xmpp/chatmessage/unwrapMessage/invalid-protobuf")
        }
        return nil
    }
}
