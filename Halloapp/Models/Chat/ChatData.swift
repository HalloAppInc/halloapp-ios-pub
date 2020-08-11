//
//  HalloApp
//
//  Created by Tony Jiang on 4/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Combine
import Core
import CryptoKit
import CryptoSwift
import Foundation
import Sodium
import XMPPFramework

typealias ChatMessageID = String

public enum UserPresenceType: Int16 {
    case none = 0
    case available = 1
    case away = 2
}

class ChatData: ObservableObject, XMPPControllerChatDelegate {
    public var currentPage: Int = 0
    
    let didChangeUnreadThreadCount = PassthroughSubject<Int, Never>()
    let didChangeUnreadCount = PassthroughSubject<Int, Never>()
    let didGetCurrentChatPresence = PassthroughSubject<(UserPresenceType, Date?), Never>()
    
    private let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.chat")
    
    private var userData: UserData
    private var xmppController: XMPPControllerMain
    private var cancellableSet: Set<AnyCancellable> = []
    
    private var currentlyChattingWithUserId: String? = nil
    private var isSubscribedToCurrentUser: Bool = false
    
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
    private var currentlyDownloading: [URL] = []
    private let maxTries: Int = 10

    public func updateChatMessageCellHeight(for chatUserId: String, with cellHeight: Int) {
        self.updateChatMessage(with: chatUserId) { (chatMessage) in
            chatMessage.cellHeight = Int16(cellHeight)
        }
    }
    
    init(xmppController: XMPPControllerMain, userData: UserData) {
        
        self.xmppController = xmppController
        self.userData = userData
        self.xmppController.chatDelegate = self
        
        self.migrateSenderStatusChatMessages()
        self.migrateReceiverStatusChatMessages()
        
        self.cancellableSet.insert(
            xmppController.didGetAck.sink { [weak self] xmppAck in
                DDLogInfo("ChatData/gotAck \(xmppAck)")
                guard let self = self else { return }
                self.processIncomingChatAck(xmppAck)
            }
        )
        
        self.cancellableSet.insert(
            xmppController.didGetNewChatMessage.sink { [weak self] xmppMessage in
                if xmppMessage.element(forName: "chat") != nil {
                    DDLogInfo("ChatData/newMsg \(xmppMessage)")
                    guard let self = self else { return }
                    self.processIncomingXMPPChatMessage(xmppMessage)
                }
            }
        )
        
        self.cancellableSet.insert(
            self.xmppController.didConnect.sink {
                DDLogInfo("ChatData/onConnect")
                
                if (UIApplication.shared.applicationState == .active) {
                    DDLogInfo("ChatData/onConnect/sendPresence")
                    self.sendPresence(type: "available")
                    
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
                        let xmppChatMessage = XMPPChatMessage(chatMessage: $0).xmppElement
                        self.backgroundProcessingQueue.asyncAfter(deadline: .now() + timeDelay) {
                            MainAppContext.shared.xmppController.xmppStream.send(xmppChatMessage)
                        }
                        timeDelay += 1.0
                    }

                    let pendingOutgoingSeenReceipts = self.pendingOutgoingSeenReceipts(in: managedObjectContext)
                    pendingOutgoingSeenReceipts.forEach {
                        DDLogInfo("ChatData/onConnect/processPending/seenReceipts \($0.id)")
                        self.sendSeenReceipt(for: $0)
                    }
                }
                
                // TODO: Eventually should move to checking for internet connectivity with a reachability manager instead of xmpp connection
                if (UIApplication.shared.applicationState == .active) {
                    self.processPendingChatMedia()
                }
                
            }
    
        )
        
        self.cancellableSet.insert(
            xmppController.didGetPresence.sink { [weak self] xmppPresence in
                DDLogInfo("ChatData/gotPresence \(xmppPresence)")
                guard let self = self else { return }
                self.processIncomingPresence(xmppPresence)
            }
        )
        
        /** gotcha: use Combine sink instead of notificationCenter.addObserver because for some reason if the user flicks the app to the background and 3
            really quickly, the observer doesn't fire
         */
        self.cancellableSet.insert(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification).sink { [weak self] notification in
                guard let self = self else { return }
                self.sendPresence(type: "available")
                
                if let currentlyChattingWithUserId = self.currentlyChattingWithUserId {
 
                    self.performSeriallyOnBackgroundContext { (managedObjectContext) in

                        self.markSeenMessages(for: currentlyChattingWithUserId, in: managedObjectContext)

                    }

                }
                
            }
        )
        
        self.cancellableSet.insert(
            NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification).sink { [weak self] notification in
                guard let self = self else { return }
                self.sendPresence(type: "away")
            }
        )
        
        
        
    }
    
    func populateThreadsWithSymmetricContacts() {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            let contacts = AppContext.shared.contactStore.allRegisteredContacts(sorted: true)
            for contact in contacts {
                guard let userId = contact.userId else { continue }
                if let chatThread = self.chatThread(chatWithUserId: userId) {
                    guard chatThread.lastMsgTimestamp == nil else { continue }
                    if chatThread.title != AppContext.shared.contactStore.fullName(for: userId) {
                        DDLogDebug("ChatData/populateThreads/contact/rename \(userId)")
                        self.updateChatThread(for: userId) { (chatThread) in
                            chatThread.title = AppContext.shared.contactStore.fullName(for: userId)
                        }
                    }
                } else {
                    DDLogInfo("ChatData/populateThreads/contact/new \(userId)")
                    let chatThread = NSEntityDescription.insertNewObject(forEntityName: ChatThread.entity().name!, into: managedObjectContext) as! ChatThread
                    chatThread.title = AppContext.shared.contactStore.fullName(for: userId)
                    chatThread.chatWithUserId = userId
                    chatThread.lastMsgUserId = userId
                    chatThread.lastMsgText = contact.phoneNumber ?? ""
                    chatThread.unreadCount = 0
                    self.save(managedObjectContext)
                }
            }
        }
        // TODO: take care of deletes, ie. user removes contact from address book
    }
    
    func processPendingChatMedia() {

        guard self.currentlyDownloading.count < self.maxNumDownloads else { return }
        
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            
            let pendingMessagesWithMedia = self.pendingIncomingMessagesMedia(in: managedObjectContext)
            
            for chatMessage in pendingMessagesWithMedia {
                
                guard let media = chatMessage.media else { continue }
                
                let sortedMedia = media.sorted(by: { $0.order < $1.order })
                
                for med in sortedMedia {
                
                    guard med.incomingStatus == ChatMedia.IncomingStatus.pending else { continue }
                    guard med.numTries <= self.maxTries else { continue }
                    guard !self.currentlyDownloading.contains(med.url) else { continue }

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
                    
                    _ = ChatMediaDownloader(url: med.url, completion: { (outputUrl) in

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

                        self.processPendingChatMedia()
                        
                    })
                    
                }
                
            }
            
        }
    
    }
    
    private func sendPresence(type: String) {
        guard AppContext.shared.xmppController.isConnected else { return }
        DDLogInfo("ChatData/sendPresence \(type)")
        let xmppJID = XMPPJID(user: userData.userId, domain: "s.halloapp.net", resource: nil)
        let xmppPresence = XMPPPresence(type: type, to: xmppJID)
        MainAppContext.shared.xmppController.xmppStream.send(xmppPresence)
    }
    
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
    
    private func processIncomingChatAck(_ xmppChatAck: XMPPAck) {
        self.updateChatMessage(with: xmppChatAck.id) { (chatMessage) in
            DDLogError("ChatData/processAck [\(xmppChatAck.id)]")

            // outgoing message
            if chatMessage.outgoingStatus != .none {
                if chatMessage.outgoingStatus == .pending {
                    
                    chatMessage.outgoingStatus = .sentOut
                
                    self.updateChatThreadStatus(for: chatMessage.toUserId, messageId: chatMessage.id) { (chatThread) in
                        chatThread.lastMsgStatus = .sentOut
                    }
                    
                }
                if let serverTimestamp = xmppChatAck.timestamp {
                    chatMessage.timestamp = serverTimestamp
                }
            }
            
            
            
        }
    }
    
    private func processIncomingXMPPChatMessage(_ chatMessageEl: XMLElement) {
        guard let xmppChatMessage = XMPPChatMessage(itemElement: chatMessageEl) else {
            DDLogError("Invalid chatMessage: [\(chatMessageEl)]")
            return
        }
        
        let isAppActive = UIApplication.shared.applicationState == .active
        
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            self.processIncomingChatMessage(xmppChatMessage: xmppChatMessage, using: managedObjectContext, isAppActive: isAppActive)
        }
    }
    
    private func processIncomingChatMessage(xmppChatMessage: XMPPChatMessage, using managedObjectContext: NSManagedObjectContext, isAppActive: Bool) {
        
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

        if let ts = xmppChatMessage.timestamp {
            chatMessage.timestamp = Date(timeIntervalSince1970: ts)
        } else {
            chatMessage.timestamp = Date()
        }
        
        var lastMsgMediaType: ChatThread.LastMsgMediaType = .none // going with the first media found
        
        // Process chat media
        for (index, xmppMedia) in xmppChatMessage.media.enumerated() {
            DDLogDebug("ChatData/process/new/add-media [\(xmppMedia.url)]")
            let feedMedia = NSEntityDescription.insertNewObject(forEntityName: ChatMedia.entity().name!, into: managedObjectContext) as! ChatMedia
            switch xmppMedia.type {
            case .image:
                feedMedia.type = .image
                if lastMsgMediaType == .none {
                    lastMsgMediaType = .image
                }
            case .video:
                feedMedia.type = .video
                if lastMsgMediaType == .none {
                    lastMsgMediaType = .video
                }
            }
            feedMedia.incomingStatus = .pending
            feedMedia.outgoingStatus = .none
            feedMedia.url = xmppMedia.url
            feedMedia.size = xmppMedia.size
            feedMedia.key = xmppMedia.key
            feedMedia.order = Int16(index)
            feedMedia.sha256 = xmppMedia.sha256
            feedMedia.message = chatMessage
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
        if let chatThread = self.chatThread(chatWithUserId: chatMessage.fromUserId, in: managedObjectContext) {
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

        // download media
        self.processPendingChatMedia()
        
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
            
    func copyPendingToChatMedia(fromUrl: URL?, to chatMedia: ChatMedia, chatMessage: ChatMessage) throws {
        guard let fromUrl = fromUrl else {
            return
        }
                
        let threadId = chatMessage.toUserId
        let messageId = chatMessage.id
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

        try FileManager.default.copyItem(at: fromUrl, to: toUrl)
        
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
        DDLogInfo("ChatData/sendSeenReceipts \(chatMessage.id)")
        self.xmppController.sendSeenReceipt(XMPPReceipt.seenReceipt(for: chatMessage), to: chatMessage.fromUserId)
    }
    
    func sendMessage(toUserId: String, text: String, media: [PendingMedia], feedPostId: String?, feedPostMediaIndex: Int32) {
        let xmppChatMessage = XMPPChatMessage(toUserId: toUserId, text: text, media: media, feedPostId: feedPostId, feedPostMediaIndex: feedPostMediaIndex)
        
        // Create and save new ChatMessage object.
        let managedObjectContext = self.persistentContainer.viewContext
        DDLogDebug("ChatData/new-msg/create")
        let chatMessage = NSEntityDescription.insertNewObject(forEntityName: ChatMessage.entity().name!, into: managedObjectContext) as! ChatMessage
        chatMessage.id = xmppChatMessage.id
        chatMessage.toUserId = xmppChatMessage.toUserId
        chatMessage.fromUserId = xmppChatMessage.fromUserId
        chatMessage.text = xmppChatMessage.text
        chatMessage.feedPostId = xmppChatMessage.feedPostId
        chatMessage.feedPostMediaIndex = xmppChatMessage.feedPostMediaIndex
        chatMessage.incomingStatus = .none
        chatMessage.outgoingStatus = .pending
        chatMessage.timestamp = Date()

        var lastMsgMediaType: ChatThread.LastMsgMediaType = .none // going with the first media
        
        for (index, mediaItem) in media.enumerated() {
            DDLogDebug("ChatData/new-msg/add-media [\(mediaItem.url!)]")
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
            chatMedia.outgoingStatus = .uploaded // For now we're only posting when all uploads are completed.
            chatMedia.url = mediaItem.url!
            chatMedia.size = mediaItem.size!
            chatMedia.key = mediaItem.key!
            chatMedia.sha256 = mediaItem.sha256!
            chatMedia.order = Int16(index)
            chatMedia.message = chatMessage

            do {
                try self.copyPendingToChatMedia(fromUrl: mediaItem.fileURL, to: chatMedia, chatMessage: chatMessage)
            }
            catch {
                DDLogError("ChatData/new-msg/media/copy-media/error [\(error)]")
            }
        }
        
        // Create and save Quoted
        if xmppChatMessage.feedPostId != nil {
            if let feedPost = MainAppContext.shared.feedData.feedPost(with: xmppChatMessage.feedPostId!) {
                let quoted = NSEntityDescription.insertNewObject(forEntityName: ChatQuoted.entity().name!, into: managedObjectContext) as! ChatQuoted
                quoted.type = .feedpost
                quoted.userId = feedPost.userId
                quoted.text = feedPost.text
                quoted.message = chatMessage
                
                if feedPost.media != nil {
                    if let feedPostMedia = feedPost.media!.first(where: { $0.order == xmppChatMessage.feedPostMediaIndex }) {
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
        if let chatThread = self.chatThread(chatWithUserId: chatMessage.toUserId, in: managedObjectContext) {
            DDLogDebug("ChatData/new-msg/update-thread")
            chatThread.lastMsgId = chatMessage.id
            chatThread.lastMsgUserId = chatMessage.fromUserId
            chatThread.lastMsgText = chatMessage.text
            chatThread.lastMsgMediaType = lastMsgMediaType
            chatThread.lastMsgStatus = .pending
            chatThread.lastMsgTimestamp = chatMessage.timestamp
        } else {
            DDLogDebug("ChatData/new-msg/new-thread")
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
        self.save(managedObjectContext)
        
        xmppChatMessage.encryptXMPPElement() { xmppEl in
            MainAppContext.shared.xmppController.xmppStream.send(xmppEl)
        }
    }
    
    // MARK: Fetching Messages

    func senderStatusChatMessages(in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true)
        ]
        return self.chatMessages(predicate: NSPredicate(format: "senderStatusValue != 0 AND outgoingStatusValue = 0"), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }
    
    func receiverStatusChatMessages(in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true)
        ]
        return self.chatMessages(predicate: NSPredicate(format: "receiverStatusValue != 0 AND incomingStatusValue = 0"), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }
    
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
    
    func pendingIncomingMessagesMedia(in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true)
        ]
        return self.chatMessages(predicate: NSPredicate(format: "ANY media.incomingStatusValue == %d", ChatMedia.IncomingStatus.pending.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }
    
    // MARK: Fetching Threads
    
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
    
    func chatThread(chatWithUserId id: String, in managedObjectContext: NSManagedObjectContext? = nil) -> ChatThread? {
        return self.chatThreads(predicate: NSPredicate(format: "chatWithUserId == %@", id), in: managedObjectContext).first
    }
    
    func chatThreadStatus(chatWithUserId: String, messageId: String, in managedObjectContext: NSManagedObjectContext? = nil) -> ChatThread? {
        return self.chatThreads(predicate: NSPredicate(format: "chatWithUserId == %@ AND lastMsgId == %@", chatWithUserId, messageId), in: managedObjectContext).first
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
    
    func subscribeToPresence(to chatWithUserId: String) {
        guard AppContext.shared.xmppController.isConnected else { return }
        guard !self.isSubscribedToCurrentUser else { return }
        self.isSubscribedToCurrentUser = true
        DDLogDebug("ChatData/subscribeToPresence [\(chatWithUserId)]")
        let message = XMPPElement(name: "presence")
        message.addAttribute(withName: "to", stringValue: "\(chatWithUserId)@s.halloapp.net")
        message.addAttribute(withName: "type", stringValue: "subscribe")
        MainAppContext.shared.xmppController.xmppStream.send(message)
    }
    
    // MARK: Update Thread
    
    private func updateChatThread(for chatWithUserId: String, block: @escaping (ChatThread) -> Void) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            guard let chatThread = self.chatThread(chatWithUserId: chatWithUserId, in: managedObjectContext) else {
                DDLogError("ChatData/update-chatThread/missing-thread [\(chatWithUserId)]")
                return
            }
            DDLogVerbose("ChatData/update-chatThread [\(chatWithUserId)]")
            block(chatThread)
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    private func updateChatThreadStatus(for chatWithUserId: String, messageId: String, block: @escaping (ChatThread) -> Void) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            guard let chatThread = self.chatThreadStatus(chatWithUserId: chatWithUserId, messageId: messageId, in: managedObjectContext) else {
                DDLogError("ChatData/update-chatThread/missing-msg-in-thread [\(chatWithUserId)] [\(messageId)]")
                return
            }
            DDLogVerbose("ChatData/update-chatThreadStatus [\(chatWithUserId)]")
            block(chatThread)
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    func markSeenMessages(for chatWithUserId: String, in managedObjectContext: NSManagedObjectContext) {
        let unseenChatMessages = self.unseenChatMessages(with: chatWithUserId, in: managedObjectContext)
                    
        unseenChatMessages.forEach {
            self.sendSeenReceipt(for: $0)
            $0.incomingStatus = ChatMessage.IncomingStatus.haveSeen
        }
        
        if managedObjectContext.hasChanges {
            self.save(managedObjectContext)
        }
        
    }
    
    func markThreadAsRead(for chatWithUserId: String) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            
            if let chatThread = self.chatThread(chatWithUserId: chatWithUserId, in: managedObjectContext) {
                if chatThread.unreadCount != 0 {
                    chatThread.unreadCount = 0
                }
            }

            self.markSeenMessages(for: chatWithUserId, in: managedObjectContext)

            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }

    func migrateSenderStatusChatMessages() {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            
            let messages = self.senderStatusChatMessages(in: managedObjectContext)
            DDLogDebug("ChatData/migrateSenderStatusChatMessages \(messages.count)")
  
            messages.forEach {
                $0.outgoingStatusValue = $0.senderStatusValue
            }

            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    func migrateReceiverStatusChatMessages() {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            
            let messages = self.receiverStatusChatMessages(in: managedObjectContext)
            DDLogDebug("ChatData/migrateReceiverStatusChatMessages \(messages.count)")
            
            messages.forEach {
                $0.incomingStatusValue = $0.receiverStatusValue
            }
            
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    // MARK: Update Message
    
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
    
    func setCurrentlyChattingWithUserId(for chatWithUserId: String?) {
        self.currentlyChattingWithUserId = chatWithUserId
        self.isSubscribedToCurrentUser = false
    }

    
    // MARK: Delete Thread
    
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
            if let chatThread = self.chatThread(chatWithUserId: chatThreadId, in: managedObjectContext) {
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
                DDLogInfo("FeedData/delete-expired/finished")
            }
            catch {
                DDLogError("FeedData/delete-expired/error  [\(error)]")
                return
            }
            self.save(managedObjectContext)
            
            self.populateThreadsWithSymmetricContacts()
        }
        
    }
    
    // MARK: Presence
    
    private func processIncomingPresence(_ xmppPresence: XMPPPresence) {
        guard let fromUserId = xmppPresence.from?.user else { return }

        var presenceStatus = UserPresenceType.none
        var presenceLastSeen: Date?
        
        if let status = xmppPresence.type {
            if status == "away" {
                presenceStatus = UserPresenceType.away
                presenceLastSeen = Date(timeIntervalSince1970: xmppPresence.attributeDoubleValue(forName: "last_seen"))
            } else if status == "available" {
                presenceStatus = UserPresenceType.available
                presenceLastSeen = Date(timeIntervalSince1970: xmppPresence.attributeDoubleValue(forName: "last_seen"))
            }
        }
                
        // notify chatViewController
        guard let currentlyChattingWithUserId = self.currentlyChattingWithUserId else { return }
        guard currentlyChattingWithUserId == fromUserId else { return }
        self.didGetCurrentChatPresence.send((presenceStatus, presenceLastSeen))
    }
    
    // MARK: XMPPControllerChatDelegate

    func xmppController(_ xmppController: XMPPController, didReceiveMessageReceipt receipt: XMPPReceipt, in xmppMessage: XMPPMessage?) {
    
        self.updateChatMessage(with: receipt.itemId) { (chatMessage) in
            if chatMessage.outgoingStatus != .seen {
                if receipt.type == .delivery {
                    chatMessage.outgoingStatus = .delivered
                    
                    self.updateChatThreadStatus(for: chatMessage.toUserId, messageId: chatMessage.id) { (chatThread) in
                        chatThread.lastMsgStatus = .delivered
                    }
                    
                } else if receipt.type == .read {
                    chatMessage.outgoingStatus = .seen

                    self.updateChatThreadStatus(for: chatMessage.toUserId, messageId: chatMessage.id) { (chatThread) in
                        chatThread.lastMsgStatus = .seen
                    }
                    
                }
            }
        }
        if let message = xmppMessage {
            xmppController.sendAck(for: message)
        }
    }

    func xmppController(_ xmppController: XMPPController, didSendMessageReceipt receipt: XMPPReceipt) {
        self.updateChatMessage(with: receipt.itemId) { (chatMessage) in
            DDLogError("ChatData/processReceiptAck [\(receipt.itemId)]")

            if chatMessage.incomingStatus == .haveSeen {
                chatMessage.incomingStatus = .sentSeenReceipt
            }
            
        }
    }
    
    func mergeSharedData(using sharedDataStore: SharedDataStore, completion: @escaping (() -> Void)) {
        let messages = sharedDataStore.messages()
        
        guard !messages.isEmpty else {
            completion()
            return
        }
        
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            for message in messages {
                guard self.chatMessage(with: message.id, in: managedObjectContext) == nil else {
                    DDLogError("ChatData/mergeSharedData/already-exists [\(message.id)]")
                    continue
                }
                
                DDLogDebug("ChatData/mergeSharedData/new [\(message.id)]")
                
                let chatMessage = NSEntityDescription.insertNewObject(forEntityName: ChatMessage.entity().name!, into: managedObjectContext) as! ChatMessage
                chatMessage.id = message.id
                chatMessage.toUserId = message.toUserId
                chatMessage.fromUserId = message.fromUserId
                chatMessage.text = message.text
                chatMessage.feedPostId = nil
                chatMessage.feedPostMediaIndex = 0
                chatMessage.incomingStatus = .none
                chatMessage.outgoingStatus = .sentOut
                chatMessage.timestamp = message.timestamp
                
                var lastMsgMediaType: ChatThread.LastMsgMediaType = .none
                
                if let messageMedia = message.media {
                    for (index, media) in messageMedia.enumerated() {
                        DDLogDebug("ChatData/mergeSharedData/new/add-media [\(media.url)]")
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
                        chatMedia.incomingStatus = .none
                        chatMedia.outgoingStatus = .uploaded
                        chatMedia.url = media.url
                        chatMedia.size = media.size
                        chatMedia.key = media.key
                        chatMedia.order = Int16(index)
                        chatMedia.sha256 = media.sha256
                        chatMedia.message = chatMessage
                        
                        do {
                            try self.copyPendingToChatMedia(fromUrl: SharedDataStore.fileURL(forRelativeFilePath: media.relativeFilePath), to: chatMedia, chatMessage: chatMessage)
                        } catch {
                            DDLogError("ChatData/mergeSharedData/media/copy-media/error [\(error)]")
                        }
                    }
                }
                
                // Update Chat Thread
                if let chatThread = self.chatThread(chatWithUserId: chatMessage.toUserId, in: managedObjectContext) {
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
            
            DispatchQueue.main.async {
                // Save will trigger a UI refresh
                self.save(managedObjectContext)
            }
            DDLogInfo("ChatData/mergeSharedData/finished")
            
            sharedDataStore.delete(messages) {
                completion()
            }
        }
    }
}

extension XMPPChatMessage {
    init(chatMessage: ChatMessage) {
        self.id = chatMessage.id
        self.fromUserId = chatMessage.fromUserId
        self.toUserId = chatMessage.toUserId
        self.text = chatMessage.text
        self.feedPostId = chatMessage.feedPostId
        self.feedPostMediaIndex = chatMessage.feedPostMediaIndex
        
        // TODO: Media
        self.media = []
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
    
    func encryptXMPPElement(completion: @escaping (XMPPElement) -> Void) {
        let element = self.xmppElement
        guard let chat = element.element(forName: "chat") else { return }
        
        guard let s1 = chat.element(forName: "s1") else { return }
        guard let encStringValue = s1.stringValue else { return }
        
        guard let unencryptedData = Data(base64Encoded: encStringValue, options: .ignoreUnknownCharacters) else { return }
        
        MainAppContext.shared.keyData.wrapMessage(for: self.toUserId, unencrypted: unencryptedData) { (data, identityKey, oneTimeKeyId) in
            if let data = data {
//                chat.remove(forName: "s1")
                chat.addChild({
                    let enc = XMPPElement(name: "enc", stringValue: data.base64EncodedString())
                    if let identityKey = identityKey {
                        enc.addAttribute(withName: "identity_key", stringValue: identityKey.base64EncodedString())
                        if oneTimeKeyId >= 0 {
                            enc.addAttribute(withName: "one_time_pre_key_id", stringValue: String(oneTimeKeyId))
                        }
                    }
                    return enc
                }())
            }
            return completion(element)
        }
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

extension XMPPReceipt {

    static func seenReceipt(for chatMessage: ChatMessage) -> XMPPReceipt {
        return XMPPReceipt(itemId: chatMessage.id, userId: chatMessage.fromUserId, type: .read, timestamp: nil, thread: .none)
    }
}
