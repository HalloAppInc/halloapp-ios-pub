//
//  HalloApp
//
//  Created by Tony Jiang on 4/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Combine
import Core
import Foundation
import XMPPFramework

typealias ChatMessageID = String

class ChatData: ObservableObject, XMPPControllerChatDelegate {
    
    let didChangeUnreadCount = PassthroughSubject<Int, Never>()
    let didGetCurrentChatPresence = PassthroughSubject<(ChatThread.Status, Date?), Never>()
    
    private let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.chat")
    
    private var userData: UserData
    private var xmppController: XMPPControllerMain
    private var cancellableSet: Set<AnyCancellable> = []
    
    private var currentlyChattingWithUserId: String? = nil
    private var isSubscribedToCurrentUser: Bool = false
    
    private var unreadMessageCount: Int = 0 {
        didSet {
            self.didChangeUnreadCount.send(unreadMessageCount)
        }
    }

    private let downloadQueue = DispatchQueue(label: "com.halloapp.chat.download", qos: .userInitiated)
    private let maxNumDownloads: Int = 1
    private var currentlyDownloading: [URL] = []

    public func updateChatMessageCellHeight(for chatUserId: String, with cellHeight: Int) {
        self.updateChatMessage(with: chatUserId) { (chatMessage) in
            chatMessage.cellHeight = Int16(cellHeight)
        }
    }
    
    init(xmppController: XMPPControllerMain, userData: UserData) {
        
        self.xmppController = xmppController
        self.userData = userData
        self.xmppController.chatDelegate = self
        
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
                    self.processIncomingChatMessage(xmppMessage)
                }
            }
        )
        
        self.cancellableSet.insert(
            self.xmppController.didConnect.sink {
                DDLogInfo("ChatData/onConnect ")
                
                if (UIApplication.shared.applicationState == .active) {
                    DDLogInfo("ChatData/onConnect/sendPresence")
                    self.sendPresence(type: "available")
                    
                    if let currentUser = self.currentlyChattingWithUserId {
                        if !self.isSubscribedToCurrentUser {
                            self.subscribeToPresence(to: currentUser)
                        }
                    }
                } else {
                    DDLogDebug("ChatData/onConnect/sendPresence")
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
            }
        )
        
        self.cancellableSet.insert(
            xmppController.didGetPresence.sink { [weak self] xmppPresence in
                DDLogInfo("ChatData/gotPresence \(xmppPresence)")
                guard let self = self else { return }
                self.processIncomingPresence(xmppPresence)
            }
        )
        
        /** gotcha: use Combine sink instead of notificationCenter.addObserver because for some reason if the user flicks the app to the background and foreground
            really quickly, the observer doesn't fire
         */
        self.cancellableSet.insert(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification).sink { [weak self] notification in
                guard let self = self else { return }
                self.sendPresence(type: "available")
            }
        )
        
        self.cancellableSet.insert(
            NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification).sink { [weak self] notification in
                guard let self = self else { return }
                self.sendPresence(type: "away")
            }
        )
        
        self.processPendingChatMedia()
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
            if chatMessage.senderStatus != .none {
                if chatMessage.senderStatus == .pending {
                    chatMessage.senderStatus = .sentOut
                }
                if let serverTimestamp = xmppChatAck.timestamp {
                    chatMessage.timestamp = serverTimestamp
                }
            } else {
//                if chatMessage.receiverStatus == .haveSeen {
//                    chatMessage.receiverStatus = .sentSeenReceipt
//                }
            }
        }
    }
    
    private func processIncomingChatMessage(_ chatMessageEl: XMLElement) {
        guard let xmppChatMessage = XMPPChatMessage(itemElement: chatMessageEl) else {
            DDLogError("Invalid chatMessage: [\(chatMessageEl)]")
            return
        }
        
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            self.process(xmppChatMessage: xmppChatMessage, using: managedObjectContext)
        }
    }
    
    private func process(xmppChatMessage: XMPPChatMessage, using managedObjectContext: NSManagedObjectContext) {
        
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
        chatMessage.receiverStatus = .none
        chatMessage.senderStatus = .none

        if let ts = xmppChatMessage.timestamp {
            chatMessage.timestamp = Date(timeIntervalSince1970: ts)
        } else {
            chatMessage.timestamp = Date()
        }
        
        // Process chat media
        for (index, xmppMedia) in xmppChatMessage.media.enumerated() {
            DDLogDebug("ChatData/process/new/add-media [\(xmppMedia.url)]")
            let feedMedia = NSEntityDescription.insertNewObject(forEntityName: ChatMedia.entity().name!, into: managedObjectContext) as! ChatMedia
            switch xmppMedia.type {
            case .image:
                feedMedia.type = .image
            case .video:
                feedMedia.type = .video
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
            chatThread.lastMsgUserId = chatMessage.fromUserId
            chatThread.lastMsgText = chatMessage.text
            chatThread.lastMsgTimestamp = chatMessage.timestamp
            
            chatThread.unreadCount = isCurrentlyChattingWithUser ? 0 : chatThread.unreadCount + 1
        } else {
            let chatThread = NSEntityDescription.insertNewObject(forEntityName: ChatThread.entity().name!, into: managedObjectContext) as! ChatThread
            chatThread.chatWithUserId = chatMessage.fromUserId
            chatThread.lastMsgUserId = chatMessage.fromUserId
            chatThread.lastMsgText = chatMessage.text
            chatThread.lastMsgTimestamp = chatMessage.timestamp
            chatThread.unreadCount = 1
        }

        self.save(managedObjectContext)
        
        if isCurrentlyChattingWithUser {
            self.sendSeenReceipt(for: chatMessage)

            self.updateChatMessage(with: chatMessage.id) { (chatMessage) in
                chatMessage.receiverStatus = .haveSeen
            }
        } else {
            self.unreadMessageCount += 1
        }
        
//        self.presentLocalNotifications(for: chatMessage)

        // download media
//        let pendingChatMedia = self.pendingIncomingMessagesMedia(in: managedObjectContext)
    }
    
    private func presentLocalNotifications(for chatMessage: ChatMessage) {
        let notification = UNMutableNotificationContent()
        notification.title = AppContext.shared.contactStore.fullName(for: chatMessage.fromUserId)
        if let text = chatMessage.text {
            notification.body = text
        }
        notification.userInfo = [
            NotificationKey.keys.metadata: [
                NotificationKey.keys.contentType: NotificationKey.contentType.chat,
                NotificationKey.keys.fromId: chatMessage.fromUserId
            ]
        ]
        DDLogDebug("ChatData/new-msg/localNotification [\(chatMessage.id)]")
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: notification, trigger: nil))
    }
        
//    func copyDownloadedMedia(fromUrl: URL, to quotedMedia: ChatQuotedMedia) throws {
//        guard let fromRelativePath = fromPath else {
//            return
//        }
//
//        let fromURL = AppContext.mediaDirectoryURL.appendingPathComponent(fromRelativePath, isDirectory: false)
//
//        // append unique id to allow multiple quoted messages of the same feedpost so each message can be deleted independently in the future
//
//        var pathComponents = fromRelativePath.components(separatedBy: ".")
//
//        guard pathComponents.count > 1 else {
//            return
//        }
//
//        pathComponents[0] += "-\(UUID().uuidString)"
//
//        let newPath = "\(pathComponents[0]).\(pathComponents[1])"
//
//        let toURL = AppContext.chatMediaDirectoryURL.appendingPathComponent(newPath, isDirectory: false)
//
//        try FileManager.default.createDirectory(at: toURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
//
//        try FileManager.default.copyItem(at: fromURL, to: toURL)
//        quotedMedia.relativeFilePath = newPath
//    }
    
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
        
        let toURL = MainAppContext.chatMediaDirectoryURL.appendingPathComponent(newPath, isDirectory: false)
        
        try FileManager.default.createDirectory(at: toURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)

        try FileManager.default.copyItem(at: fromURL, to: toURL)
        quotedMedia.relativeFilePath = newPath
    }
    
    func sendSeenReceipt(for chatMessage: ChatMessage) {
        self.xmppController.sendSeenReceipt(XMPPReceipt.seenReceipt(for: chatMessage), to: chatMessage.fromUserId)
    }
    
    func sendMessage(toUserId: String, text: String, media: [PendingChatMessageMedia], feedPostId: String, feedPostMediaIndex: Int32) {
        let xmppChatMessage = XMPPChatMessage(toUserId: toUserId, text: text, media: [], feedPostId: feedPostId, feedPostMediaIndex: feedPostMediaIndex)
        
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
        chatMessage.receiverStatus = .none
        chatMessage.senderStatus = .pending
        chatMessage.timestamp = Date()

        for (index, mediaItem) in media.enumerated() {
            DDLogDebug("ChatData/new-msg/add-media [\(mediaItem.url!)]")
            let chatMedia = NSEntityDescription.insertNewObject(forEntityName: ChatMedia.entity().name!, into: managedObjectContext) as! ChatMedia
            chatMedia.type = mediaItem.type
            chatMedia.outgoingStatus = .uploaded // For now we're only posting when all uploads are completed.
            chatMedia.url = mediaItem.url!
            chatMedia.size = mediaItem.size!
            chatMedia.key = mediaItem.key!
            chatMedia.sha256 = mediaItem.sha256!
            chatMedia.order = Int16(index)
            chatMedia.message = chatMessage

            // TODO: save the media to file directory
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
            chatThread.lastMsgUserId = chatMessage.fromUserId
            chatThread.lastMsgText = chatMessage.text
            chatThread.lastMsgTimestamp = chatMessage.timestamp
        } else {
            DDLogDebug("ChatData/new-msg/new-thread")
            let chatThread = NSEntityDescription.insertNewObject(forEntityName: ChatThread.entity().name!, into: managedObjectContext) as! ChatThread
            chatThread.chatWithUserId = chatMessage.toUserId
            chatThread.lastMsgUserId = chatMessage.fromUserId
            chatThread.lastMsgText = chatMessage.text
            chatThread.lastMsgTimestamp = chatMessage.timestamp
            chatThread.unreadCount = 0
        }
        
        self.save(managedObjectContext)
        MainAppContext.shared.xmppController.xmppStream.send(xmppChatMessage.xmppElement)
    }

    // MARK: Fetching Messages

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
        return self.chatMessages(predicate: NSPredicate(format: "fromUserId = %@ && toUserId = %@ && (receiverStatusValue = %d OR receiverStatusValue = %d)", fromUserId, userData.userId, ChatMessage.ReceiverStatus.none.rawValue, ChatMessage.ReceiverStatus.haveSeen.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }
    
    func pendingOutgoingChatMessages(in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true)
        ]
        return self.chatMessages(predicate: NSPredicate(format: "fromUserId = %@ && senderStatusValue = %d", userData.userId, ChatMessage.SenderStatus.pending.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }
    
    func pendingOutgoingSeenReceipts(in managedObjectContext: NSManagedObjectContext? = nil) -> [ChatMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true)
        ]
        return self.chatMessages(predicate: NSPredicate(format: "fromUserId = %@ && receiverStatusValue = %d", userData.userId, ChatMessage.ReceiverStatus.haveSeen.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
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
    
    private func updateChatThread(for id: String, block: @escaping (ChatThread) -> Void) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            guard let chatThread = self.chatThread(chatWithUserId: id, in: managedObjectContext) else {
                DDLogError("ChatData/update-chatThread/missing-post [\(id)]")
                return
            }
            DDLogVerbose("ChatData/update-chatThread [\(id)]")
            block(chatThread)
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    func markThreadAsRead(for chatWithUserId: String) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            
            if let chatThread = self.chatThread(chatWithUserId: chatWithUserId, in: managedObjectContext) {
                if chatThread.unreadCount != 0 {
                    chatThread.unreadCount = 0
                }
            }

            let unseenChatMessages = self.unseenChatMessages(with: chatWithUserId, in: managedObjectContext)
                        
            unseenChatMessages.forEach {
                self.sendSeenReceipt(for: $0)
                $0.receiverStatus = ChatMessage.ReceiverStatus.haveSeen
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

    // MARK: Presence
    
    private func processIncomingPresence(_ xmppPresence: XMPPPresence) {
        guard let fromUserId = xmppPresence.from?.user else {
            return
        }

        var presenceStatus = ChatThread.Status.available
        var presenceLastSeen: Date?
        
        if let status = xmppPresence.type {
            if status == "away" {
                presenceStatus = ChatThread.Status.away
                presenceLastSeen = Date(timeIntervalSince1970: xmppPresence.attributeDoubleValue(forName: "last_seen"))
            }
        }
        
        // update core data
        self.updateChatThread(for: fromUserId) { (chatThread) in
            if chatThread.status != presenceStatus {
                chatThread.status = presenceStatus
            }
            if let lastSeen = presenceLastSeen {
                if chatThread.lastSeenTimestamp != lastSeen {
                    chatThread.lastSeenTimestamp = lastSeen
                }
            }
        }
        
        // notify chat screen
        if let currentlyChattingWithUserId = self.currentlyChattingWithUserId {
            if currentlyChattingWithUserId == fromUserId {
                if presenceLastSeen == nil {
                    let chatThread = self.chatThread(chatWithUserId: fromUserId)
                    presenceLastSeen = chatThread?.lastSeenTimestamp
                }
                self.didGetCurrentChatPresence.send((presenceStatus, presenceLastSeen))
            }
        }

    }
    
    // MARK: XMPPControllerChatDelegate

    func xmppController(_ xmppController: XMPPController, didReceiveMessageReceipt receipt: XMPPReceipt, in xmppMessage: XMPPMessage?) {
    
        self.updateChatMessage(with: receipt.itemId) { (chatMessage) in
            if chatMessage.senderStatus != .seen {
                if receipt.type == .delivery {
                    chatMessage.senderStatus = .delivered
                } else if receipt.type == .read {
                    chatMessage.senderStatus = .seen
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

            if chatMessage.receiverStatus == .haveSeen {
                chatMessage.receiverStatus = .sentSeenReceipt
            }
            
        }
    }
}

struct XMPPChatMessage {
    let id: String
    let fromUserId: UserID
    let toUserId: UserID
    let text: String?
    let media: [XMPPChatMedia]
    let feedPostId: String?
    let feedPostMediaIndex: Int32
    var timestamp: TimeInterval?

    init(toUserId: String, text: String?, media: [PendingChatMessageMedia]?, feedPostId: String?, feedPostMediaIndex: Int32) {
        self.id = UUID().uuidString
        self.fromUserId = MainAppContext.shared.userData.userId
        self.toUserId = toUserId
        self.text = text
        if let media = media?.map({ XMPPChatMedia(chatMedia: $0) }) {
            self.media = media
        } else {
            self.media = []
        }
        self.feedPostId = feedPostId
        self.feedPostMediaIndex = feedPostMediaIndex
    }

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
    
    init?(itemElement item: XMLElement) {
        guard let id = item.attributeStringValue(forName: "id") else { return nil }
        guard let toUserId = item.attributeStringValue(forName: "to")?.components(separatedBy: "@").first else { return nil }
        guard let fromUserId = item.attributeStringValue(forName: "from")?.components(separatedBy: "@").first else { return nil }
        guard let chat = item.element(forName: "chat") else { return nil }

        var text: String?, media: [XMPPChatMedia] = [], feedPostId: String?, feedPostMediaIndex: Int32 = 0
        
        if let protoContainer = Proto_Container.chatMessageContainer(from: chat) {
            if protoContainer.hasChatMessage {
                text = protoContainer.chatMessage.text.isEmpty ? nil : protoContainer.chatMessage.text
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

    var xmppElement: XMPPElement {
        get {
            let message = XMPPElement(name: "message")
            message.addAttribute(withName: "id", stringValue: id)
            message.addAttribute(withName: "to", stringValue: "\(toUserId)@s.halloapp.net")
            message.addChild({
                let chat = XMPPElement(name: "chat")
                chat.addAttribute(withName: "xmlns", stringValue: "halloapp:chat:messages")

                if let protobufData = try? self.proto.serializedData() {
                    chat.addChild(XMPPElement(name: "s1", stringValue: protobufData.base64EncodedString()))
                }
                    
                return chat
            }())
            return message
        }
    }
    
    fileprivate var proto: Proto_Container {
        get {
            var chatMessage = Proto_ChatMessage()
            if self.text != nil {
                chatMessage.text = self.text!
            }
            
            if self.feedPostId != nil {
                chatMessage.feedPostID = self.feedPostId!
                chatMessage.feedPostMediaIndex = self.feedPostMediaIndex
            }
            
            var container = Proto_Container()
            container.chatMessage = chatMessage
            return container
        }
    }
    
}



protocol ChatMediaProtocol {
    var url: URL { get }
    var type: ChatMessageMediaType { get }
    var size: CGSize { get }
    var key: String { get }
    var sha256: String { get }
}

extension ChatMediaProtocol {
    var protoMessage: Proto_Media {
        get {
            var media = Proto_Media()
            media.type = {
                switch type {
                case .image: return .image
                case .video: return .video
                }
            }()
            media.width = Int32(size.width)
            media.height = Int32(size.height)
            media.encryptionKey = Data(base64Encoded: key)!
            media.plaintextHash = Data(base64Encoded: sha256)!
            media.downloadURL = url.absoluteString
            return media
        }
    }
}

struct XMPPChatMedia: ChatMediaProtocol {

    let url: URL
    let type: ChatMessageMediaType
    let size: CGSize
    let key: String
    let sha256: String

    init(chatMedia: PendingChatMessageMedia) {
        self.url = chatMedia.url!
        self.type = chatMedia.type
        self.size = chatMedia.size!
        self.key = chatMedia.key!
        self.sha256 = chatMedia.sha256!
    }

    init?(urlElement: XMLElement) {
        guard let typeStr = urlElement.attributeStringValue(forName: "type") else { return nil }
        guard let type: ChatMessageMediaType = {
            switch typeStr {
            case "image": return .image
            case "video": return .video
            default: return nil
            }}() else { return nil }
        guard let urlString = urlElement.stringValue else { return nil }
        guard let url = URL(string: urlString) else { return nil }
        let width = urlElement.attributeIntegerValue(forName: "width"), height = urlElement.attributeIntegerValue(forName: "height")
        guard width > 0 && height > 0 else { return nil }
        guard let key = urlElement.attributeStringValue(forName: "key") else { return nil }
        guard let sha256 = urlElement.attributeStringValue(forName: "sha256hash") else { return nil }

        self.url = url
        self.type = type
        self.size = CGSize(width: width, height: height)
        self.key = key
        self.sha256 = sha256
    }

    init?(protoMedia: Proto_Media) {
        guard let type: ChatMessageMediaType = {
            switch protoMedia.type {
            case .image: return .image
            case .video: return .video
            default: return nil
            }}() else { return nil }
        guard let url = URL(string: protoMedia.downloadURL) else { return nil }
        let width = CGFloat(protoMedia.width), height = CGFloat(protoMedia.height)
        guard width > 0 && height > 0 else { return nil }

        self.url = url
        self.type = type
        self.size = CGSize(width: width, height: height)
        self.key = protoMedia.encryptionKey.base64EncodedString()
        self.sha256 = protoMedia.plaintextHash.base64EncodedString()
    }
}


extension Proto_Container {
    static func chatMessageContainer(from entry: XMLElement) -> Proto_Container? {
        guard let s1 = entry.element(forName: "s1")?.stringValue else { return nil }
        guard let data = Data(base64Encoded: s1, options: .ignoreUnknownCharacters) else { return nil }
        do {
            let protoContainer = try Proto_Container(serializedData: data)
            if protoContainer.hasChatMessage {
                return protoContainer
            }
        }
        catch {
            DDLogError("xmpp/chatmessage/invalid-protobuf")
        }
        return nil
    }
}

extension XMPPReceipt {

    static func seenReceipt(for chatMessage: ChatMessage) -> XMPPReceipt {
        return XMPPReceipt(itemId: chatMessage.id, userId: chatMessage.fromUserId, type: .read, timestamp: nil, thread: .none)
    }
}
