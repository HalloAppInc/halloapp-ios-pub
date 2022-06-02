//
//  HalloApp
//
//  Created by Tony Jiang on 4/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import CryptoKit
import CoreData
import Foundation
import Intents
import IntentsUI
import UIKit

typealias ChatAck = (id: String, timestamp: Date?)

typealias ChatPresenceInfo = (userID: UserID, presence: PresenceType?, lastSeen: Date?)

typealias ChatStateInfo = (from: UserID, threadType: ChatType, threadID: String, type: ChatState, timestamp: Date?)
typealias ChatRetractInfo = (from: UserID, threadType: ChatType, threadID: String, messageID: String)

public enum UserPresenceType: Int16 {
    case none = 0
    case available = 1
    case away = 2
}

class ChatData: ObservableObject {

    public var currentPage: Int = 0

    let didChangeUnreadThreadCount = PassthroughSubject<Int, Never>()
    let didChangeUnreadThreadGroupsCount = PassthroughSubject<Int, Never>()
    let didGetCurrentChatPresence = PassthroughSubject<(UserPresenceType, Date?), Never>()
    let didGetChatStateInfo = PassthroughSubject<Void, Never>()
    
    let didGetMediaUploadProgress = PassthroughSubject<(String, Float), Never>()
    
    let didGetAGroupFeed = PassthroughSubject<GroupID, Never>()
    let didGetAChatMsg = PassthroughSubject<UserID, Never>()
    let didGetAGroupEvent = PassthroughSubject<GroupID, Never>()
    let didResetGroupInviteLink = PassthroughSubject<GroupID, Never>()
    let didUserPresenceChange = PassthroughSubject<PresenceType, Never>()
    
    private let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.chat")
    private lazy var downloadManager: FeedDownloadManager = {
        let downloadManager = FeedDownloadManager(mediaDirectoryURL: MainAppContext.commonMediaStoreURL)
        downloadManager.delegate = self
        return downloadManager
    }()
    
    private let userData: UserData
    private let mainDataStore: MainDataStore
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

    private let uploadQueue = DispatchQueue(label: "com.halloapp.chat.upload")
    
    private let downloadQueue = DispatchQueue(label: "com.halloapp.chat.download")
    private let maxNumDownloads: Int = 3
    private var currentlyDownloading: [URL] = []
    private let maxTries: Int = 100
    

    
    var viewContext: NSManagedObjectContext { mainDataStore.viewContext } // should access only from main queue

    private struct UserDefaultsKey {
        static let persistentAppVersion = "ChatDataAppVersion"
        static let GroupsLastSyncTime = "GroupsLastSyncTime"
    }
    
    private var cancellableSet: Set<AnyCancellable> = []
    
    init(service: HalloService, contactStore: ContactStoreMain, mainDataStore: MainDataStore, userData: UserData) {
        self.service = service
        self.contactStore = contactStore
        self.userData = userData
        self.mainDataStore = mainDataStore
        
        self.mediaUploader = MediaUploader(service: service)

        self.service.chatDelegate = self
        
        cancellableSet.insert(
            mediaUploader.uploadProgressDidChange.receive(on: DispatchQueue.main).sink { [weak self] groupId in
                guard let self = self else { return }
                guard let chatMessage = self.chatMessage(with: groupId, in: self.viewContext) else { return }
                self.updateSendingProgress(for: chatMessage)
            }
        )

        cancellableSet.insert(
            ImageServer.shared.progress.receive(on: DispatchQueue.main).sink { [weak self] id in
                guard let self = self else { return }
                guard let chatMessage = self.chatMessage(with: id, in: self.viewContext) else { return }
                self.updateSendingProgress(for: chatMessage)
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

        cancellableSet.insert(
            // TODO: Move all presence logic to its own file.
            didUserPresenceChange.sink(receiveValue: { [weak self] presenceType in
                DDLogInfo("ChatData/didUserPresenceChange: \(presenceType)")
                self?.service.sendPresenceIfPossible(presenceType)
            })
        )

        cancellableSet.insert(
            mainDataStore.didClearStore.sink {
                do {
                    DDLogInfo("ChatData/didClearStore/clear-media starting")
                    try FileManager.default.removeItem(at: MediaDirectory.chatMedia.url)
                    DDLogInfo("ChatData/didClearStore/clear-media finished")
                }
                catch {
                    DDLogError("ChatData/didClearStore/clear-media/error [\(error)]")
                }
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
                MainAppContext.shared.feedData.didMergeFeedPost.sink { [weak self] postID in
                    guard let self = self else { return }
                    
                    self.performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
                        guard let self = self else { return }
                        guard let feedPost = MainAppContext.shared.feedData.feedPost(with: postID, in: managedObjectContext) else { return }
                        guard let groupID = feedPost.groupId else { return }

                        let isInbound = feedPost.userId != MainAppContext.shared.userData.userId
                        DDLogInfo("ChatData/didMergeFeedPost: \(postID)")

                        self.updateThreadWithGroupFeed(postID, isInbound: isInbound, using: managedObjectContext)
                        self.didGetAGroupFeed.send(groupID)
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

                    self.performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
                        guard let self = self else { return }

                        var groupThreadIDs = self.groupThreads(in: managedObjectContext).compactMap({ $0.groupId })

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
                }
            )

            self.cancellableSet.insert(
                // Update chat thread when calls are done.
                MainAppContext.shared.callManager.didCallComplete.sink { [weak self] callID in
                    guard let self = self else { return }
                    MainAppContext.shared.mainDataStore.performSeriallyOnBackgroundContext { context in
                        guard let call = MainAppContext.shared.mainDataStore.call(with: callID, in: context) else {
                            return
                        }
                        let peerUserID = call.peerUserID
                        let isAudioCall = call.isAudioCall
                        let isVideoCall = call.isVideoCall
                        let isMissedCall = call.isMissedCall
                        let isOutgoingCall = call.isOutgoing
                        let duration: TimeInterval = call.durationMs / 1000
                        let durationString = self.durationString(duration) ?? ""

                        self.updateChatThread(type: .oneToOne, for: peerUserID, block: {
                            if isAudioCall {
                                if isOutgoingCall {
                                    $0.lastMsgText = durationString
                                    $0.lastMsgMediaType = .outgoingAudioCall
                                } else if isMissedCall {
                                    $0.lastMsgText = ""
                                    $0.lastMsgMediaType = .missedAudioCall
                                } else {
                                    $0.lastMsgText = durationString
                                    $0.lastMsgMediaType = .incomingAudioCall
                                }
                            } else if isVideoCall {
                                if isOutgoingCall {
                                    $0.lastMsgText = durationString
                                    $0.lastMsgMediaType = .outgoingVideoCall
                                } else if isMissedCall {
                                    $0.lastMsgText = ""
                                    $0.lastMsgMediaType = .missedVideoCall
                                } else {
                                    $0.lastMsgText = durationString
                                    $0.lastMsgMediaType = .incomingVideoCall
                                }
                            }
                            // Update unread count if it is a missed call.
                            if isMissedCall {
                                if !self.isCurrentlyChatting(with: peerUserID) {
                                    $0.unreadCount += 1
                                    self.updateUnreadChatsThreadCount()
                                }
                            }
                            $0.lastMsgId = callID
                            $0.lastMsgTimestamp = call.timestamp
                            $0.lastMsgStatus = .none
                        }, performAfterSave: nil)
                    }
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
                    self.checkViewAndSendPresence(type: .available)

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
                self.processPendingPlayedReceipts()

                if (UIApplication.shared.applicationState == .active) {
                    DDLogDebug("ChatData/didConnect/currentlyDownloading/num/\(self.currentlyDownloading.count)/removeAll")
                    self.removeAllCurrentDownloads()
                    self.processInboundPendingChatMsgMedia()
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
                self.performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
                    self?.processInboundChatRetractInBg(chatRetractInfo, in: managedObjectContext)
                }
            }
        )

        /** gotcha: use Combine sink instead of notificationCenter.addObserver because for some reason if the user flicks the app to the background and back
            really quickly, the observer doesn't fire
         */
        cancellableSet.insert(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification).sink { [weak self] notification in
                guard let self = self else { return }
                self.checkViewAndSendPresence(type: .available)
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
                self.checkViewAndSendPresence(type: .away)
            }
        )

        cancellableSet.insert(contactStore.didCompleteInitialSync.sink { [weak self] in
            DDLogInfo("ChatData/sink/didCompleteInitialSync")
            DispatchQueue.main.async { [weak self] in
                self?.populateThreadsWithInitialRegisteredContacts()
            }
        })

        cancellableSet.insert(contactStore.didDiscoverNewUsers.sink { [weak self] (userIDs) in
            DDLogInfo("ChatData/sink/didDiscoverNewUsers/count: \(userIDs.count)")

            contactStore.performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
                var contactsDict = [UserID:String]()
                userIDs.forEach {
                    contactsDict[$0] = contactStore.fullName(for: $0, in: managedObjectContext)
                }
                self?.updateThreadsWithDiscoveredUsers(for: contactsDict)
            }
        })

        cancellableSet.insert(
            userData.didLogIn.sink {
                DDLogInfo("ChatData/didLogIn")
                shouldGetGroupsList = true
            }
        )

        resetUnreadForDeletedSampleGroup()

        DispatchQueue.main.async {
            self.cleanUpOldUploadData()
        }
    }

    // TODO: Move these functions to a util function somewhere.
    private func durationString(_ timeInterval: TimeInterval) -> String? {
        guard timeInterval > 0 else {
            return nil
        }
        return Self.durationFormatter.string(from: timeInterval)
    }

    private static var durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private func updateSendingProgress(for message: ChatMessage) {
        guard let count = message.media?.count, count > 0 else { return }

        var (processingCount, processingProgress) = ImageServer.shared.progress(for: message.id)
        var (uploadCount, uploadProgress) = mediaUploader.uploadProgress(forGroupId: message.id)

        processingProgress = processingProgress * Float(processingCount) / Float(count)
        uploadProgress = uploadProgress * Float(uploadCount) / Float(count)

        self.didGetMediaUploadProgress.send((message.id, (processingProgress + uploadProgress) / 2))
    }

    // MARK: Migration

    func migrate(from oldAppVersion: String?) {
        processUnsupportedItems()
    }

    func migrateLegacyMessages(_ legacyMessages: [ChatMessageLegacy]) throws {
        try mainDataStore.saveSeriallyOnBackgroundContextAndWait { context in
            DDLogInfo("ChatData/migrateLegacyMessages/begin [\(legacyMessages.count)]")
            legacyMessages.forEach { self.migrateLegacyMessage($0, in: context) }
            DDLogInfo("ChatData/migrateLegacyMessages/finished [\(legacyMessages.count)]")
        }
    }

    func migrateLegacyThreads(_ legacyThreads: [ChatThreadLegacy]) throws {
        try mainDataStore.saveSeriallyOnBackgroundContextAndWait { context in
            DDLogInfo("ChatData/migrateLegacyThreads/begin [\(legacyThreads.count)]")
            legacyThreads.forEach { self.migrateLegacyThread($0, in: context) }
            DDLogInfo("ChatData/migrateLegacyThreads/finished [\(legacyThreads.count)]")
        }
    }

    func migrateLegacyGroups(_ legacyGroups: [ChatGroupLegacy]) throws {
        try mainDataStore.saveSeriallyOnBackgroundContextAndWait { context in
            DDLogInfo("ChatData/migrateLegacyGroups/begin [\(legacyGroups.count)]")
            legacyGroups.forEach { self.migrateLegacyGroup($0, in: context) }
            DDLogInfo("ChatData/migrateLegacyGroups/finished [\(legacyGroups.count)]")
        }
    }

    func migrateLegacyChatEvents(_ legacyChatEvents: [ChatEventLegacy]) throws {
        try mainDataStore.saveSeriallyOnBackgroundContextAndWait { context in
            DDLogInfo("ChatData/migrateLegacyGroups/begin [\(legacyChatEvents.count)]")
            legacyChatEvents.forEach { self.migrateLegacyChatEvent($0, in: context) }
            DDLogInfo("ChatData/migrateLegacyGroups/finished [\(legacyChatEvents.count)]")
        }
    }

    private func migrateLegacyMessage(_ legacy: ChatMessageLegacy, in managedObjectContext: NSManagedObjectContext) {
        let message: ChatMessage = {
            if let message = chatMessage(with: legacy.id, in: managedObjectContext) {
                DDLogInfo("ChatData/migrateLegacyChat/existing/\(legacy.id)")
                return message
            } else {
                DDLogInfo("ChatData/migrateLegacyChat/new/\(legacy.id)")
                return ChatMessage(context: managedObjectContext)
            }
        }()

        message.id = legacy.id
        message.serialID = legacy.serialID
        message.fromUserID = legacy.fromUserId
        message.toUserID = legacy.toUserId

        message.rawText = legacy.text
        message.rawData = legacy.rawData

        message.feedPostID = legacy.feedPostId
        message.feedPostMediaIndex = legacy.feedPostMediaIndex

        message.chatReplyMessageID = legacy.chatReplyMessageID
        message.chatReplyMessageSenderID = legacy.chatReplyMessageSenderID
        message.chatReplyMessageMediaIndex = legacy.chatReplyMessageMediaIndex

        message.incomingStatus = legacy.incomingStatus
        message.outgoingStatus = legacy.outgoingStatus

        message.resendAttempts = legacy.resendAttempts
        message.retractID = legacy.retractID

        message.timestamp = legacy.timestamp
        message.serverTimestamp = legacy.serverTimestamp

        message.cellHeight = legacy.cellHeight

        if let quoted = legacy.quoted {
            migrateLegacyQuoted(quoted, toMessage: message, in: managedObjectContext)
        }

        // Remove and recreate media
        message.media?.forEach { managedObjectContext.delete($0) }
        legacy.media?.forEach {
            self.migrateLegacyMedia($0, toMessage: message, in: managedObjectContext)
        }

        // Remove and recreate link previews
        message.linkPreviews?.forEach { managedObjectContext.delete($0) }
        legacy.linkPreviews?.forEach {
            self.migrateLegacyLinkPreview($0, toMessage: message, in: managedObjectContext)
        }

        DDLogInfo("ChatData/migrateLegacyMessage/finished/\(legacy.id)")
    }

    private func migrateLegacyThread(_ legacy: ChatThreadLegacy, in managedObjectContext: NSManagedObjectContext) {

        let thread: CommonThread

        switch legacy.type {
        case .oneToOne:
            guard let userID = legacy.chatWithUserId else {
                DDLogError("ChatData/migrateLegacyThread/oneToOne/aborting [missing userID]")
                return
            }
            if let existingThread = chatThread(type: .oneToOne, id: userID, in: managedObjectContext) {
                DDLogInfo("ChatData/migrateLegacyThread/oneToOne/existing/\(userID)")
                thread = existingThread
            } else {
                thread = CommonThread(context: managedObjectContext)
                thread.userID = userID
                thread.lastText = legacy.lastMsgText
                thread.lastContentID = legacy.lastMsgId
                thread.lastUserID = legacy.lastMsgUserId
                thread.lastMsgStatus = legacy.lastMsgStatus
                thread.lastTimestamp = legacy.lastMsgTimestamp
                thread.lastMediaType = legacy.lastMsgMediaType
                DDLogInfo("ChatData/migrateLegacyThread/oneToOne/new/\(userID)")
            }
        case .group:
            guard let groupID = legacy.groupId else {
                DDLogError("ChatData/migrateLegacyThread/group/aborting [missing groupID]")
                return
            }
            if let existingThread = chatThread(type: .group, id: groupID, in: managedObjectContext) {
                DDLogInfo("ChatData/migrateLegacyThread/group/existing/\(groupID)")
                thread = existingThread
            } else {
                thread = CommonThread(context: managedObjectContext)
                thread.groupID = groupID
                thread.lastText = legacy.lastFeedText
                thread.lastContentID = legacy.lastFeedId
                thread.lastUserID = legacy.lastFeedUserID
                thread.lastFeedStatus = legacy.lastFeedStatus
                thread.lastTimestamp = legacy.lastFeedTimestamp
                thread.lastMediaType = legacy.lastFeedMediaType
                DDLogInfo("ChatData/migrateLegacyThread/group/new/\(groupID)")
            }
        }
        thread.title = legacy.title
        thread.type = legacy.type
        thread.isNew = legacy.isNew
        thread.unreadCount = legacy.unreadCount

        DDLogInfo("ChatData/migrateLegacyThread/finished")
    }

    private func migrateLegacyGroup(_ legacy: ChatGroupLegacy, in managedObjectContext: NSManagedObjectContext) {
        let group: Group = {
            if let group = chatGroup(groupId: legacy.groupId, in: managedObjectContext) {
                DDLogInfo("ChatData/migrateLegacyGroup/existing/\(legacy.groupId)")
                return group
            } else {
                DDLogInfo("ChatData/migrateLegacyGroup/new/\(legacy.groupId)")
                return Group(context: managedObjectContext)
            }
        }()
        group.id = legacy.groupId
        group.name = legacy.name
        group.avatarID = legacy.avatar
        group.background = legacy.background
        group.desc = legacy.desc
        group.maxSize = legacy.maxSize
        group.lastSync = legacy.lastSync
        group.inviteLink = legacy.inviteLink

        // Remove and recreate members
        group.members?.forEach { managedObjectContext.delete($0) }
        legacy.members?.forEach {
            self.migrateLegacyGroupMember($0, toGroup: group, in: managedObjectContext)
        }

        DDLogInfo("ChatData/migrateLegacyGroup/finished/\(legacy.groupId)")
    }

    private func migrateLegacyChatEvent(_ legacy: ChatEventLegacy, in managedObjectContext: NSManagedObjectContext) {

        let fetchRequest = ChatEvent.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "userID == %@ AND timestamp == %@", legacy.userID, legacy.timestamp as NSDate)

        do {
            let events = try managedObjectContext.fetch(fetchRequest)
            guard events.isEmpty else {
                DDLogInfo("ChatData/migrateLegacyChatEvent/skipping [found match]")
                return
            }
        } catch {
            return
        }

        DDLogInfo("ChatData/migrateLegacyChatEvent/new")
        let event = ChatEvent(context: managedObjectContext)
        event.typeValue = legacy.typeValue
        event.userID = legacy.userID
        event.timestamp = legacy.timestamp
        DDLogInfo("ChatData/migrateLegacyChatEvent/finished")
    }

    public func recordNewChatEvent(userID: UserID, type: ChatEventType) {
        mainDataStore.saveSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            DDLogInfo("ChatData/recordNewChatEvent/ \(type) for: \(userID)")

            if type == .whisperKeysChange {
                let ownUserID = AppContext.shared.userData.userId
                let predicate = NSPredicate(format: "(fromUserID = %@ AND toUserID = %@) || (toUserID = %@ AND fromUserID = %@)", userID, ownUserID, userID, ownUserID)
                guard self.chatMessages(predicate: predicate, limit: 1, in: managedObjectContext).count > 0 else {
                    DDLogInfo("ChatData/recordNewChatEvent/\(userID)/no messages yet, skip recording keys change event")
                    return
                }
            }

            let chatEvent = ChatEvent(context: managedObjectContext)
            chatEvent.userID = userID
            chatEvent.type = type
            chatEvent.timestamp = Date()
        }
    }

    private func migrateLegacyQuoted(_ legacy: ChatQuotedLegacy, toMessage message: ChatMessage, in managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("ChatData/migrateLegacyQuoted/new")
        let quoted = ChatQuoted(context: managedObjectContext)
        quoted.userID = legacy.userId
        quoted.typeValue = legacy.typeValue
        quoted.message = message
        quoted.rawText = legacy.text
        quoted.mentions = legacy.mentions?.map {
            MentionData(index: $0.index, userID: $0.userID, name: $0.name)
        } ?? []

        // Remove and recreate media
        quoted.media?.forEach { managedObjectContext.delete($0) }
        legacy.media?.forEach { self.migrateLegacyQuotedMedia($0, toQuoted: quoted, in: managedObjectContext) }
        DDLogInfo("ChatData/migrateLegacyQuoted/finished")
    }

    private func migrateLegacyLinkPreview(_ legacy: ChatLinkPreview, toMessage message: ChatMessage, in managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("ChatData/migrateLegacyLinkPreview/new/\(legacy.id)")
        let linkPreview = chatLinkPreview(with: legacy.id, in: managedObjectContext) ?? CommonLinkPreview(context: managedObjectContext)
        linkPreview.id = legacy.id
        linkPreview.desc = legacy.desc
        linkPreview.title = legacy.title
        linkPreview.url = legacy.url

        // Remove and recreate media
        linkPreview.media?.forEach { managedObjectContext.delete($0) }
        legacy.media?.forEach { self.migrateLegacyMedia($0, toLinkPreview: linkPreview, in: managedObjectContext) }

        linkPreview.message = message
        DDLogInfo("ChatData/migrateLegacyLinkPreview/finished/\(legacy.id)")
    }

    private func migrateLegacyMedia(_ legacy: ChatMedia, toMessage message: ChatMessage? = nil, toLinkPreview linkPreview: CommonLinkPreview? = nil, in managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("ChatData/migrateLegacyMedia/new [order: \(legacy.order)")

        let media = CommonMedia(context: managedObjectContext)
        media.typeValue = legacy.typeValue
        media.relativeFilePath = legacy.relativeFilePath
        media.url = legacy.url
        media.uploadURL = legacy.uploadUrl
        media.incomingStatus = legacy.incomingStatus
        media.outgoingStatus = legacy.outgoingStatus
        media.width = legacy.width
        media.height = legacy.height
        media.key = legacy.key
        media.sha256 = legacy.sha256
        media.order = legacy.order
        media.blobVersion = legacy.blobVersion
        media.chunkSize = legacy.chunkSize
        media.blobSize = legacy.blobSize
        media.numTries = legacy.numTries

        media.mediaDirectory = .chatMedia

        media.message = message
        media.linkPreview = linkPreview
        DDLogInfo("ChatData/migrateLegacyMedia/finished")
    }

    private func migrateLegacyQuotedMedia(_ legacy: ChatQuotedMedia, toQuoted quoted: ChatQuoted, in managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("ChatData/migrateLegacyQuotedMedia/new [order: \(legacy.order)")

        let media = CommonMedia(context: managedObjectContext)
        media.typeValue = legacy.typeValue
        media.relativeFilePath = legacy.relativeFilePath
        media.width = legacy.width
        media.height = legacy.height
        media.order = legacy.order
        media.previewData = legacy.previewData

        switch legacy.mediaDirectory {
        case .media:
            media.mediaDirectory = .media
        case .chatMedia:
            media.mediaDirectory = .chatMedia
        case .none:
            DDLogError("ChatData/migrateLegacyQuotedMedia/error [missing-media-dir]")
            media.mediaDirectory = .chatMedia
        }

        media.chatQuoted = quoted
        DDLogInfo("ChatData/migrateLegacyQuotedMedia/finished")
    }

    private func migrateLegacyGroupMember(_ legacy: ChatGroupMember, toGroup group: Group, in managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("ChatData/migrateLegacyGroupMember/new/\(legacy.userId)")
        let member = GroupMember(context: managedObjectContext)
        member.groupID = legacy.groupId
        member.typeValue = legacy.typeValue
        member.userID = legacy.userId
        member.group = group

        if legacy.groupId != group.id {
            DDLogError("ChatData/migrateLegacyGroupMember/\(legacy.userId)/wrong-group-id [legacy: \(legacy.groupId)] [group: \(group.id)]")
        }

        DDLogInfo("ChatData/migrateLegacyGroupMember/finished/\(legacy.userId)")

    }

    private func processUnsupportedItems() {
        performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            guard let self = self else { return }
            let messageFetchRequest: NSFetchRequest<ChatMessage> = ChatMessage.fetchRequest()
            messageFetchRequest.predicate = NSPredicate(format: "incomingStatusValue = %d", ChatMessage.IncomingStatus.unsupported.rawValue)
            do {
                let unsupportedMessages = try managedObjectContext.fetch(messageFetchRequest)
                var messagesMigrated = 0
                for message in unsupportedMessages {
                    guard let rawData = message.rawData else {
                        DDLogError("ChatData/processUnsupportedItems/messages/error [missing data] [\(message.id)]")
                        continue
                    }
                    guard let chatContainer = try? Clients_ChatContainer(serializedData: rawData) else {
                        DDLogError("ChatData/processUnsupportedItems/messages/error [deserialization] [\(message.id)]")
                        continue
                    }
                    let content = chatContainer.chatContent
                    switch content {
                    case .album, .text, .voiceNote:
                        let timestamp = message.timestamp ?? Date()
                        let reinterpretedMessage = XMPPChatMessage(
                            content: chatContainer.chatContent,
                            context: chatContainer.chatContext,
                            timestamp: Int64(timestamp.timeIntervalSince1970),
                            from: message.fromUserId,
                            to: message.toUserId,
                            id: message.id,
                            retryCount: 0, //TODO
                            rerequestCount: Int32(message.resendAttempts))
                        messagesMigrated += 1
                        self.processIncomingChatMessage(.decrypted(reinterpretedMessage))
                    case .unsupported:
                        DDLogInfo("ChatData/processUnsupportedItems/messages/skipping [still-unsupported] [\(message.id)]")
                    }
                }
                DDLogInfo("ChatData/processUnsupportedItems/messages/complete [\(messagesMigrated) / \(unsupportedMessages.count)]")
            } catch {
                DDLogError("ChatData/processUnsupportedItems/messages/error [\(error)]")
            }
        }
    }

    // should be called just once, when user have their contacts synced for the very first time
    func populateThreadsWithInitialRegisteredContacts() {
        MainAppContext.shared.contactStore.performSeriallyOnBackgroundContext { [weak self] contactsManagedObjectContext in
            guard let self = self else { return }

            let contacts = MainAppContext.shared.contactStore.allRegisteredContacts(sorted: true, in: contactsManagedObjectContext)
            DDLogInfo("ChatData/populateThreadsWithInitialRegisteredContacts/num contacts: \(contacts.count)")
            var userIDs = [UserID:String]()
            contacts.forEach {
                guard let userID = $0.userId else { return }
                userIDs[userID] = $0.fullName
            }
            guard !userIDs.isEmpty else { return }

            self.performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
                guard let self = self else { return }
                for (userId, fullName) in userIDs {
                    guard self.chatThread(type: ChatType.oneToOne, id: userId, in: managedObjectContext) == nil else { continue }
                    DDLogInfo("ChatData/populateThreadsWithInitialRegisteredContacts/contact/\(userId)")

                    // these chat threads will have no timestamps and be sorted alphabetically below ones that do
                    let chatThread = ChatThread(context: managedObjectContext)
                    chatThread.title = fullName
                    chatThread.userID = userId
                    chatThread.lastMsgUserId = userId
                    chatThread.lastMsgText = nil
                    chatThread.unreadCount = 0
                    chatThread.isNew = false
                }
                self.save(managedObjectContext)
            }
        }
    }

    // newly discovered users can happen in two ways, both of which ends up with user B being displayed at the top
    // 1. user A already have user B in address book and then user B joins HalloApp
    // 2. user B is already in HalloApp and then user A adds user B to their address book
    func updateThreadsWithDiscoveredUsers(for userIDs: [UserID:String]) {
        guard !userIDs.isEmpty else { return }
        let timestampForNewThreads = Date()
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }

            for (userId, fullName) in userIDs {
                guard self.chatThread(type: ChatType.oneToOne, id: userId, in: managedObjectContext) == nil else { continue }

                DDLogInfo("ChatData/updateThreadsWithDiscoveredUsers/userID/\(userId)")
                let chatThread = ChatThread(context: managedObjectContext)
                chatThread.title = fullName
                chatThread.userID = userId
                chatThread.lastMsgUserId = userId
                chatThread.lastMsgText = nil
                chatThread.lastMsgTimestamp = timestampForNewThreads
                chatThread.unreadCount = 0
            }
            self.save(managedObjectContext)
        }
    }

    // update preview with the celebration emoji since the user is invited
    func updateThreadWithInvitedUserPreview(for userID: UserID) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            if let thread = self.chatThread(type: ChatType.oneToOne, id: userID, in: managedObjectContext) {
                DDLogInfo("ChatData/updateThreadWithInvitedUserPreview/thread already exists, userID: \(userID)")
                guard thread.lastMsgText == nil else { return } // skip if messages have already been exchanged
                thread.isNew = true
            } else {
                DDLogInfo("ChatData/updateThreadWithInvitedUserPreview/new thread, userID: /\(userID)")

                var fullName = ""
                MainAppContext.shared.contactStore.performOnBackgroundContextAndWait { contactsManagedObjectContext in
                    fullName = MainAppContext.shared.contactStore.fullName(for: userID, in: contactsManagedObjectContext)
                }

                let chatThread = ChatThread(context: managedObjectContext)
                chatThread.title = fullName
                chatThread.userID = userID
                chatThread.lastMsgUserId = userID
                chatThread.lastMsgText = nil
                chatThread.lastMsgTimestamp = Date()
                chatThread.unreadCount = 0
                chatThread.isNew = true
            }
            self.save(managedObjectContext)
        }
    }

    // remove empty chat threads of users who are not in the address book
    public func pruneEmptyChatThreads() {
        MainAppContext.shared.contactStore.performSeriallyOnBackgroundContext { [weak self] contactsManagedObjectContext in
            guard let self = self else { return }
            let contacts = MainAppContext.shared.contactStore.allRegisteredContacts(sorted: true, in: contactsManagedObjectContext)

            var userIDs = [UserID:String]()
            contacts.forEach {
                guard let userID = $0.userId else { return }
                userIDs[userID] = $0.fullName
            }
            guard !userIDs.isEmpty else { return }

            self.performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
                guard let self = self else { return }
                let emptyOneToOneChatThreads = self.emptyOneToOneChatThreads(in: managedObjectContext)
                emptyOneToOneChatThreads.forEach({
                    guard let chatWithUserID = $0.userID else { return }
                    guard userIDs[chatWithUserID] == nil else { return }
                    DDLogInfo("ChatData/pruneEmptyChatThreads/emptyOneToOneChatThreads/remove \(chatWithUserID)")
                    self.deleteChat(chatThreadId: chatWithUserID)
                })

                if managedObjectContext.hasChanges {
                    self.save(managedObjectContext)
                }
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

    // TODO: Will unify the download logic for media-items across the entire app.
    // Should be called on the same queue with the coreDataObject since objects are not supposed to be accessed across queues.
    func downloadMedia(in chatMessage: ChatMessage) {
        let contentID = chatMessage.id
        downloadChatMedia(mediaItems: chatMessage.media, contentID: contentID)
    }

    func downloadMedia(in linkPreview: CommonLinkPreview) {
        let contentID = linkPreview.id
        downloadChatMedia(mediaItems: linkPreview.media, contentID: contentID)
    }

    func downloadChatMedia(mediaItems: Set<CommonMedia>?, contentID: String) {
        guard let mediaItems = mediaItems,
              !mediaItems.isEmpty else {
            return
        }
        DDLogInfo("ChatData/downloadChatMedia/contentID: \(contentID)")

        var downloadStarted = false
        let sortedMedia = mediaItems.sorted(by: { $0.order < $1.order })
        for mediaItem in sortedMedia {

            let order = mediaItem.order
            DDLogInfo("ChatData/downloadChatMedia/contentID: \(contentID)/order: \(order)/status: \(mediaItem.status)")
            let mediaDownloadGroup = DispatchGroup()
            var startTime: Date?
            var photosDownloaded = 0
            var videosDownloaded = 0
            var audiosDownloaded = 0
            var totalDownloadSize = 0

            guard mediaItem.url != nil else { continue }
            // Have some max-tries since chat media stays forever.
            // TODO: Should cleanup this logic across the app and unify this.
            guard mediaItem.numTries < self.maxTries else { continue }
            guard [.none, .downloading, .downloadError].contains(mediaItem.status) else { continue }

            let (taskAdded, task) = self.downloadManager.downloadMedia(for: mediaItem)
            if taskAdded {
                switch mediaItem.type {
                case .image: photosDownloaded += 1
                case .video: videosDownloaded += 1
                case .audio: audiosDownloaded += 1
                }
                if startTime == nil {
                    startTime = Date()
                    DDLogInfo("ChatData/downloadChatMedia/contentID: \(contentID)/order: \(order)/starting")
                }
                mediaDownloadGroup.enter()
                var isDownloadInProgress = true
                self.cancellableSet.insert(task.downloadProgress.sink { progress in
                    if isDownloadInProgress && progress == 1 {
                        totalDownloadSize += task.fileSize ?? 0
                        mediaDownloadGroup.leave()
                        isDownloadInProgress = false
                    }
                })
                downloadStarted = true
                task.feedMediaObjectId = mediaItem.objectID
                mediaItem.status = .downloading
                mediaItem.numTries += 1
            }

            mediaDownloadGroup.notify(queue: .main) {
                guard photosDownloaded > 0 || videosDownloaded > 0 || audiosDownloaded > 0 else { return }
                guard let startTime = startTime else {
                    DDLogError("ChatData/downloadChatMedia/contentID: \(contentID)/error start time not set")
                    return
                }
                let duration = Date().timeIntervalSince(startTime)
                DDLogInfo("ChatData/downloadChatMedia/contentID: \(contentID)/finished [photos: \(photosDownloaded)] [videos: \(videosDownloaded)] [audios: \(audiosDownloaded)] [t: \(duration)] [bytes: \(totalDownloadSize)]")
            }
        }

        // Using `downloadStarted` to prevent any recursive saves.
        if downloadStarted,
           let context = mediaItems.first?.managedObjectContext,
           context.hasChanges {
            DDLogInfo("ChatData/downloadChatMedia/contentID: \(contentID)/downloadStarted: \(downloadStarted)")
            self.save(context)
        }
    }

    func processInboundPendingChatMsgMedia() {
        DDLogDebug("ChatData/processInboundPendingChatMsgMedia")
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            guard self.currentlyDownloading.count <= self.maxNumDownloads else { return }

            let pendingMessagesWithMedia = self.pendingIncomingChatMessagesMedia(in: managedObjectContext)
            DDLogDebug("ChatData/processInboundPendingChatMsgMedia/NumPendingMessagesWithMedia: \(pendingMessagesWithMedia.count)")

            for chatMessage in pendingMessagesWithMedia {
                self.downloadMedia(in: chatMessage)
            }
        }
    }

    func processInboundPendingChaLinkPreviewMedia() {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            guard self.currentlyDownloading.count <= self.maxNumDownloads else { return }

            let pendingLinkPreivewsWithMedia = self.pendingIncomingLinkPreviewMedia(in: managedObjectContext)

            for linkPreview in pendingLinkPreivewsWithMedia {
                self.downloadMedia(in: linkPreview)
            }
        }
    }

    // MARK: Core Data Setup
    
    private func performSeriallyOnBackgroundContext(_ block: @escaping (NSManagedObjectContext) -> Void) {
        mainDataStore.performSeriallyOnBackgroundContext(block)
    }

    public func performOnBackgroundContextAndWait(_ block: (NSManagedObjectContext) -> Void) {
        mainDataStore.performOnBackgroundContextAndWait(block)
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
    
    func copyFiles(toChatMedia chatMedia: CommonMedia, fileUrl: URL, encryptedFileUrl: URL?) throws {
        
        var threadId = ""
        var messageId = ""

        if let chatMessage = chatMedia.message {
            threadId = chatMessage.toUserId
            messageId = chatMessage.id
        } else if let chatMessage = chatMedia.linkPreview?.message {
            threadId = chatMessage.toUserId
            messageId = chatMessage.id
        }
        /* else if let chatGroupMessage = chatMedia.groupMessage {
            threadId = chatGroupMessage.groupId
            messageId = chatGroupMessage.id
        } */
        
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
        
        let toUrl = MainAppContext.commonMediaStoreURL
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

        DDLogInfo("ChatData/copyFiles/\(messageId), source: \(fileUrl), destination: \(toUrl)")
        try FileManager.default.copyItem(at: fileUrl, to: toUrl)
        let relativePath = self.relativePath(from: toUrl)
        chatMedia.relativeFilePath = relativePath
        chatMedia.mediaDirectory = .commonMedia

        if let encryptedFileUrl = encryptedFileUrl {
            let encryptedDestinationUrl = toUrl.appendingPathExtension("enc")
            DDLogInfo("ChatData/copyFiles/\(messageId), encryptedSourceUrl: \(encryptedFileUrl), encryptedDestinationUrl: \(encryptedDestinationUrl)")
            try FileManager.default.copyItem(at: encryptedFileUrl, to: encryptedDestinationUrl)
        }
    }
    
    private func relativePath(from fileURL: URL) -> String? {
        let fullPath = fileURL.path
        let mediaDirectoryPath = MainAppContext.commonMediaStoreURL.path
        if let range = fullPath.range(of: mediaDirectoryPath, options: [.anchored]) {
            return String(fullPath.suffix(from: range.upperBound))
        }
        return nil
    }
    
    // TODO(murali@): need to do some sort of migration for the existing media elements in the db.
    func copyMediaToQuotedMedia(fromDir: MediaDirectory, fromPath: String?, to quotedMedia: CommonMedia) throws {
        guard let fromRelativePath = fromPath else {
            return
        }
        let fromURL = fromDir.fileURL(forRelativePath: fromRelativePath)
        DDLogInfo("ChatData/copyMediaToQuotedMedia/fromURL: \(fromURL)")

        // Store references to the quoted media directory and file path.
        quotedMedia.relativeFilePath = fromRelativePath
        quotedMedia.mediaDirectory = fromDir

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

    func sendPlayedReceipt(for chatMessage: ChatMessage) {
        DDLogInfo("ChatData/sendPlayedReceipt \(chatMessage.id)")
        service.sendReceipt(
            itemID: chatMessage.id,
            thread: .none,
            type: .played,
            fromUserID: userData.userId,
            toUserID: chatMessage.fromUserId)
    }

    // MARK: Share Extension Merge Data
    
    func mergeData(from sharedDataStore: SharedDataStore, completion: @escaping (() -> ())) {
        performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            guard let self = self else { return }

            var messages: [SharedChatMessage] = []
            sharedDataStore.performOnBackgroundContextAndWait { sharedManagedObjectContext in
                messages = sharedDataStore.messages(in: sharedManagedObjectContext)
            }

            self.merge(messages: messages, from: sharedDataStore, using: managedObjectContext)
        }

        DDLogInfo("ChatData/mergeData - \(sharedDataStore.source)/begin")
        let sharedMessageIds = sharedDataStore.chatMessageIds()
        DDLogInfo("ChatData/mergeData/sharedMessageIds: \(sharedMessageIds)")

        mainDataStore.saveSeriallyOnBackgroundContext ({ managedObjectContext in
            // TODO: murali@: we dont need the following merge in the future - leaving it in for now.
            self.mergeMediaItems(from: sharedDataStore, using: managedObjectContext)
        }) { [self] result in
            switch result {
            case .success:
                mainDataStore.saveSeriallyOnBackgroundContext { [self] context in
                    // Messages
                    let sharedMessages = chatMessages(with: Set(sharedMessageIds), in: context)
                    var mergedMessages = chatMessagesToProcess(in: context)
                    mergedMessages.append(contentsOf: sharedMessages)
                    let mergedMessageIds = mergedMessages.map { $0.id }

                    updateUnreadChatsThreadCount()
                    mergedMessages.forEach { chatMsg in
                        didGetAChatMsg.send(chatMsg.fromUserId)
                        chatMsg.hasBeenProcessed = true
                    }

                        // send pending chat messages
                        processPendingChatMsgs()
                        // download chat message media
                        processInboundPendingChatMsgMedia()
                        processInboundPendingChaLinkPreviewMedia()
                        DDLogInfo("ChatData/mergeData/chatMessageIds: \(mergedMessageIds)")
                }
                sharedDataStore.clearChatMessageIds()
            case .failure(let error):
                DDLogDebug("ChatData/mergeData/error: \(error)")
            }
            DDLogInfo("ChatData/mergeData - \(sharedDataStore.source)/done")
            completion()
        }
    }

    private func merge(messages: [SharedChatMessage], from sharedDataStore: SharedDataStore, using managedObjectContext: NSManagedObjectContext) {
        var mergedMessages = [(SharedChatMessage, ChatMessage)]()
        for message in messages {
            let messageId: ChatMessageID = message.id
            DDLogInfo("ChatData/mergeSharedData/message/\(messageId)")

            var oldChatMsg: ChatMessage? = nil
            if let existingChatmessage = chatMessage(with: messageId, in: managedObjectContext) {
                if existingChatmessage.incomingStatus == .rerequesting, [.received, .acked].contains(message.status) {
                    DDLogInfo("ChatData/mergeSharedData/already-exists [\(messageId)] override failed decryption.")
                } else {
                    DDLogError("ChatData/mergeSharedData/already-exists [\(messageId)] dont override/status: \(existingChatmessage.incomingStatusValue)")
                    continue
                }
                oldChatMsg = existingChatmessage
            }

            // Dont merge messages with invalid status - these messages were interrupted in between by the user.
            // So, we will discard them completeley and let the user retry it.
            guard message.status != .none else {
                DDLogError("ChatData/mergeSharedData/ignore failed message [\(messageId)], status: \(message.status)")
                continue
            }

            DDLogInfo("ChatData/mergeSharedData/merging message/\(messageId)")

            let chatContent: ChatContent?
            let chatContext: ChatContext?
            if let clientChatMsgPb = message.clientChatMsgPb {
                if let chatContainer = try? Clients_ChatContainer(serializedData: clientChatMsgPb) {
                    chatContent = chatContainer.chatContent
                    chatContext = chatContainer.chatContext
                } else {
                    DDLogError("ChatData/mergeSharedData/failed to extract clientChatMsg: [\(clientChatMsgPb.bytes)]")
                    continue
                }
            } else {
                chatContent = nil
                chatContext = nil
            }

            // Chat message does not have a unique-id constraint.
            // So either update an existing message or create a new one.
            // Dont overwrite timestamp for tombstones.
            let chatMessage: ChatMessage
            if let existingChatmessage = oldChatMsg {
                chatMessage = existingChatmessage
            } else {
                chatMessage = ChatMessage(context: managedObjectContext)
                chatMessage.timestamp = message.timestamp
            }
            chatMessage.id = messageId
            chatMessage.toUserId = message.toUserId
            chatMessage.fromUserId = message.fromUserId
            chatMessage.feedPostId = chatContext?.feedPostID
            chatMessage.feedPostMediaIndex = chatContext?.feedPostMediaIndex ?? 0
            chatMessage.chatReplyMessageID = chatContext?.chatReplyMessageID
            chatMessage.chatReplyMessageSenderID = chatContext?.chatReplyMessageSenderID
            chatMessage.chatReplyMessageMediaIndex = chatContext?.chatReplyMessageMediaIndex ?? 0
            chatMessage.serverTimestamp = message.serverTimestamp
            DDLogDebug("ChatData/mergeSharedData/ChatData/\(messageId)/serialId [\(message.serialID)]")
            chatMessage.serialID = message.serialID

            // message could be incoming or outgoing.
            DDLogInfo("ChatData/mergeSharedData/message/\(messageId), status: \(message.status)")
            switch message.status {
            case .none:
                chatMessage.incomingStatus = .none
                chatMessage.outgoingStatus = .pending
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
            let isIncomingMsg = [.received, .acked].contains(message.status)

            switch chatContent {
            case .album(let text, _):
                chatMessage.rawText = text
            case .text(let text, _):
                // TODO @dini merge linkPreviewData
                chatMessage.rawText = text
            case .voiceNote(_):
                chatMessage.rawText = ""
            case .unsupported(let data):
                chatMessage.rawData = data
                // Overwrite incoming status for unsupported messages
                chatMessage.incomingStatus = .unsupported
            case .none:
                chatMessage.rawText = message.text
            }

            // Process link preview if present
            var linkPreviews = Set<CommonLinkPreview>()
            message.linkPreviews?.forEach { chatLinkPreview in
                DDLogDebug("ChatData/mergeSharedData/message/add-link-preview [\(String(describing: chatLinkPreview.url))]")

            let linkPreview = CommonLinkPreview(context: managedObjectContext)
            linkPreview.id = PacketID.generate()
            linkPreview.url = chatLinkPreview.url
            linkPreview.title = chatLinkPreview.title
            linkPreview.desc = chatLinkPreview.desc
            // Set preview image if present
            chatLinkPreview.media?.forEach { sharedPreviewMedia in
                DDLogInfo("ChatData/mergeSharedData/message/\(messageId)/add-link-preview-media [\(sharedPreviewMedia)], status: \(sharedPreviewMedia.status)")
                let chatMedia = CommonMedia(context: managedObjectContext)
                    // set incoming and outgoing status.
                    switch sharedPreviewMedia.status {
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
                    chatMedia.url = sharedPreviewMedia.url
                    chatMedia.uploadUrl = sharedPreviewMedia.uploadUrl
                    chatMedia.size = sharedPreviewMedia.size
                    chatMedia.key = sharedPreviewMedia.key
                    chatMedia.order = sharedPreviewMedia.order
                    chatMedia.sha256 = sharedPreviewMedia.sha256
                    chatMedia.linkPreview = linkPreview
                    chatMedia.mediaDirectory = .chatMedia
                    linkPreview.message = chatMessage
                    if let relativeFilePath = sharedPreviewMedia.relativeFilePath {
                        do {
                            let sourceUrl = sharedDataStore.legacyFileURL(forRelativeFilePath: relativeFilePath)
                            let encryptedFileUrl = chatMedia.outgoingStatus == .error ? sourceUrl.appendingPathExtension("enc") : nil
                            DDLogInfo("ChatData/mergeSharedData/link-preview-media/\(messageId)/sourceUrl: \(sourceUrl), encryptedFileUrl: \(encryptedFileUrl?.absoluteString ?? "[nil]"), \(sharedPreviewMedia.status)")
                            try copyFiles(toChatMedia: chatMedia, fileUrl: sourceUrl, encryptedFileUrl: encryptedFileUrl)
                        } catch {
                            DDLogError("ChatData/mergeSharedData/link-preview-media/copy-media/error [\(error)]")
                        }
                    }
                }
                linkPreviews.insert(linkPreview)
            }

            var lastMsgMediaType: ChatThread.LastMediaType = .none
            message.media?.forEach { media in
                DDLogInfo("ChatData/mergeSharedData/message/\(messageId)/add-media [\(media)], status: \(media.status)")
                let chatMedia = CommonMedia(context: managedObjectContext)
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
                        DDLogInfo("ChatData/mergeSharedData/media/\(messageId)/sourceUrl: \(sourceUrl), encryptedFileUrl: \(encryptedFileUrl?.absoluteString ?? "[nil]"), \(media.status)")
                        try copyFiles(toChatMedia: chatMedia, fileUrl: sourceUrl, encryptedFileUrl: encryptedFileUrl)
                    } catch {
                        DDLogError("ChatData/mergeSharedData/media/copy-media/error [\(error)]")
                    }
                }
            }

            // Process quoted content.
            if let feedPostId = chatMessage.feedPostId, !feedPostId.isEmpty {
                // Process Quoted Feedpost
                if let quotedFeedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId, in: managedObjectContext) {
                    copyQuoted(to: chatMessage, from: quotedFeedPost, using: managedObjectContext)
                }
            } else if let chatReplyMsgId = chatMessage.chatReplyMessageID, !chatReplyMsgId.isEmpty {
                // Process Quoted Message: these messages could be in the main database or in the shared database.
                // so we first lookup the main database and then our list of mergedMessages.
                // we ensure that messages are fetched in the correct order.
                if let quotedChatMessage = MainAppContext.shared.chatData.chatMessage(with: chatReplyMsgId, in: managedObjectContext) {
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
                chatThread.lastMsgText = chatMessage.rawText
                chatThread.lastMsgMediaType = lastMsgMediaType
                chatThread.lastMsgStatus = .none
                chatThread.lastMsgTimestamp = chatMessage.timestamp
                if isIncomingMsg {
                    chatThread.unreadCount = isCurrentlyChattingWithUser ? 0 : chatThread.unreadCount + 1
                }
            } else {
                let chatThread = NSEntityDescription.insertNewObject(forEntityName: ChatThread.entity().name!, into: managedObjectContext) as! ChatThread
                chatThread.userID = threadId
                chatThread.lastMsgId = chatMessage.id
                chatThread.lastMsgUserId = chatMessage.fromUserId
                chatThread.lastMsgText = chatMessage.rawText
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
                        contentType: .chat)
                    DDLogInfo("ChatData/mergeSharedData/reported decryption result \(sharedMsg.decryptionError ?? "no-error") for msg: \(chatMsg.id)")
                } catch {
                    DDLogError("ChatData/mergeSharedData/Unable to initialize Server_Msg")
                }
            } else {
                DDLogError("ChatData/mergeSharedData/could not report decryption result, messageId: \(chatMsg.id)")
            }
            didGetAChatMsg.send(chatMsg.fromUserId)
        })

        // send pending chat messages
        processPendingChatMsgs()
        // download chat message media
        processInboundPendingChatMsgMedia()
        processInboundPendingChaLinkPreviewMedia()

        DDLogInfo("ChatData/mergeSharedData/finished")

        sharedDataStore.delete(messages: messages) {
        }
    }

    // TODO: duplicate code from ProtoService.swift
    private func reportDecryptionResult(error: DecryptionError?, messageID: String, timestamp: Date, sender: UserAgent?, rerequestCount: Int, contentType: DecryptionReportContentType) {
        AppContext.shared.eventMonitor.count(.decryption(error: error, sender: sender))
        if let sender = sender {
            MainAppContext.shared.cryptoData.update(
                messageID: messageID,
                timestamp: timestamp,
                result: error?.rawValue ?? "success",
                rerequestCount: rerequestCount,
                sender: sender,
                contentType: contentType)
        } else {
            DDLogError("ChatData/reportDecryptionResult/\(messageID)/decrypt/error missing sender user agent")
        }
    }

    private func mergeMediaItems(from sharedDataStore: SharedDataStore, using managedObjectContext: NSManagedObjectContext) {
        let mediaDirectory = sharedDataStore.oldMediaDirectory
        DDLogInfo("ChatData/mergeMediaItems from \(mediaDirectory)/begin")

        let mediaPredicate = NSPredicate(format: "mediaDirectoryValue == \(mediaDirectory.rawValue)")
        let extensionMediaItems = mainDataStore.commonMediaItems(predicate: mediaPredicate, in: managedObjectContext)
        DDLogInfo("ChatData/mergeMediaItems/extensionMediaItems: \(extensionMediaItems.count)")
        extensionMediaItems.forEach { media in
            if media.message != nil || media.chatQuoted != nil || media.linkPreview?.message != nil {
                DDLogDebug("ChatData/mergeMediaItems/media: \(String(describing: media.relativeFilePath))")
                if let relativeFilePath = media.relativeFilePath {
                    do {
                        let sourceUrl = sharedDataStore.fileURL(forRelativeFilePath: relativeFilePath)
                        let encryptedFileUrl = media.outgoingStatus == .error ? sourceUrl.appendingPathExtension("enc") : nil
                        DDLogInfo("ChatData/mergeMediaItems/sourceUrl: \(sourceUrl), encryptedFileUrl: \(encryptedFileUrl?.absoluteString ?? "[nil]"), \(media.status)")
                        try copyFiles(toChatMedia: media, fileUrl: sourceUrl, encryptedFileUrl: encryptedFileUrl)
                    } catch {
                        DDLogError("ChatData/mergeSharedData/link-preview-media/copy-media/error [\(error)]")
                    }
                }
            }
        }
        DDLogInfo("ChatData/mergeMediaItems from \(mediaDirectory)/done")
    }

    // This function can nicely copy references to quoted feed post or quoted message to the new chatMessage.
    private func copyQuoted(to chatMessage: ChatMessage, from chatQuoted: ChatQuotedProtocol, using managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("ChatData/copyQuoted/message/\(chatMessage.id), chatQuotedType: \(chatQuoted.type)")
        let quoted = NSEntityDescription.insertNewObject(forEntityName: ChatQuoted.entity().name!, into: managedObjectContext) as! ChatQuoted
        quoted.type = chatQuoted.type
        quoted.userID = chatQuoted.userId
        quoted.rawText = chatQuoted.quotedText
        quoted.message = chatMessage
        quoted.mentions = chatQuoted.mentions

        // TODO: Why Int16? - other classes have Int32 for the order attribute.
        var mediaIndex: Int16 = 0
        // Ensure Id of the quoted object is not empty - postId/msgId.
        if let feedPostId = chatMessage.feedPostId, !feedPostId.isEmpty {
            mediaIndex = Int16(chatMessage.feedPostMediaIndex)
        } else if let chatReplyMessageID = chatMessage.chatReplyMessageID, !chatReplyMessageID.isEmpty {
            mediaIndex = Int16(chatMessage.chatReplyMessageMediaIndex)
        }
        if let chatQuotedMediaItem = chatQuoted.mediaList.first(where: { $0.order == mediaIndex }) {
            DDLogInfo("ChatData/copyQuoted/message/\(chatMessage.id), chatQuotedMediaIndex: \(chatQuotedMediaItem.order)")
            let quotedMedia = CommonMedia(context: managedObjectContext)
            quotedMedia.type = chatQuotedMediaItem.quotedMediaType
            quotedMedia.order = chatQuotedMediaItem.order
            quotedMedia.width = Float(chatQuotedMediaItem.width)
            quotedMedia.height = Float(chatQuotedMediaItem.height)
            quotedMedia.chatQuoted = quoted
            do {
                try copyMediaToQuotedMedia(fromDir: chatQuotedMediaItem.mediaDirectory, fromPath: chatQuotedMediaItem.relativeFilePath, to: quotedMedia)
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
        guard let homeView = topController.children.first as? UITabBarController else { return false }
        guard homeView.selectedIndex == 2 else { return false }
        guard let navigationController = homeView.selectedViewController as? UINavigationController else { return false }
        guard let chatListViewController = navigationController.topViewController as? ChatListViewController else { return false }

        return chatListViewController.isScrolledFromTop(by: 100)
    }

    // temporary, fixes an issue prior to build 187 and can be removed after some time
    // resets the unread count for sample group welcome posts in which the user deleted the group without clicking into it
    private func resetUnreadForDeletedSampleGroup() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let sharedNUX = MainAppContext.shared.nux
            if let sampleGroupID = sharedNUX.sampleGroupID(), self.chatGroup(groupId: sampleGroupID, in: self.viewContext) == nil {
                sharedNUX.markSampleGroupWelcomePostSeen()
                self.updateUnreadThreadGroupsCount()
            }
        }
    }

}

extension ChatData: FeedDownloadManagerDelegate {
    func feedDownloadManager(_ manager: FeedDownloadManager, didFinishTask task: FeedDownloadManager.Task) {
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            // Update chatMediaItem
            guard let objectID = task.feedMediaObjectId, let chatMediaItem = try? managedObjectContext.existingObject(with: objectID) as? CommonMedia else {
                DDLogError("ChatData/download-task/\(task.id)/error  Missing CommonMedia  taskId=[\(task.id)]  objectId=[\(task.feedMediaObjectId?.uriRepresentation().absoluteString ?? "nil")))]")
                return
            }

            guard chatMediaItem.relativeFilePath == nil else {
                DDLogError("ChatData/download-task/\(task.id)/error File already exists media=[\(chatMediaItem)]")
                chatMediaItem.status = .downloaded
                self.save(managedObjectContext)
                return
            }

            if let error = task.error {
                DDLogError("ChatData/download-task/\(task.id)/error [\(error)]")
                chatMediaItem.status = .downloadError

                // TODO: Do an exponential backoff on the client for 1 day and then show a manual retry button for the user.
                // Mark as permanent failure if we encounter hashMismatch or MACMismatch.
                switch error {
                case .macMismatch, .hashMismatch, .decryptionFailed:
                    DDLogInfo("ChatData/download-task/\(task.id)/error [\(error) - fail permanently]")
                    chatMediaItem.status = .downloadFailure
                    AppContext.shared.errorLogger?.logError(error)
                default:
                    break
                }
            } else {
                DDLogInfo("ChatData/download-task/\(task.id)/complete [\(task.decryptedFilePath!)]")
                chatMediaItem.mediaDirectory = .commonMedia
                chatMediaItem.status = task.isPartialChunkedDownload ? .downloadedPartial : .downloaded
                chatMediaItem.relativeFilePath = task.decryptedFilePath
                if task.isPartialChunkedDownload, let chunkSet = task.downloadedChunkSet {
                    DDLogDebug("ChatData/download-task/\(task.id)/feedDownloadManager chunkSet=[\(chunkSet)]")
                    chatMediaItem.chunkSet = chunkSet.data
                }
            }

            // hack: force a change so frc can pick up the change
            // TODO: murali@: check with team on this.
            if let chatMessage = chatMediaItem.message {
                let fromUserId = chatMessage.fromUserId
                chatMessage.fromUserId = fromUserId
            } else if let linkPreview = chatMediaItem.linkPreview,
                      let chatMessage = linkPreview.message {
                let fromUserId = chatMessage.fromUserId
                chatMessage.fromUserId = fromUserId
            } else {
                return
            }

            self.save(managedObjectContext)

            // Update upload data to avoid duplicate uploads
            if let fileURL = chatMediaItem.mediaURL, let downloadURL = chatMediaItem.url {
                MainAppContext.shared.mediaHashStore.update(url: fileURL,
                                                            blobVersion: chatMediaItem.blobVersion,
                                                            key: chatMediaItem.key,
                                                            sha256: chatMediaItem.sha256,
                                                            downloadURL: downloadURL)
            }
        }
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

    func markPlayedMessage(for id: String) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            guard let message = self.chatMessage(with: id, in: managedObjectContext) else { return }
            guard ![.played, .sentPlayedReceipt].contains(message.incomingStatus) else { return }

            self.sendPlayedReceipt(for: message)
            message.incomingStatus = .played

            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
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

    // trigger update for fetchedcontrollers with a manual (forced) save
    func triggerGroupThreadUpdate(_ groupID: GroupID) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }

            guard let chatThread = self.chatThread(type: .group, id: groupID, in: managedObjectContext) else { return }
            let unreadFeedCount = chatThread.unreadFeedCount
            chatThread.unreadFeedCount = unreadFeedCount

            self.save(managedObjectContext)
        }
    }

    func markThreadAsRead(type: ChatType, for id: String) {
        DDLogInfo("ChatData/markThreadAsRead/type: \(type)/id: \(id)")
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            
            if let chatThread = self.chatThread(type: type, id: id, in: managedObjectContext) {
                if chatThread.unreadCount != 0 {
                    chatThread.unreadCount = 0
                }
            }
            DDLogInfo("ChatData/markThreadAsRead/type: \(type)/id: \(id)/set unreadCount to zero")
            self.markSeenMessages(type: type, for: id, in: managedObjectContext)
            
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    func updateUnreadThreadGroupsCount() {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            let threads = self.commonThreads(predicate: NSPredicate(format: "groupID != nil && unreadCount > 0"), in: managedObjectContext)
            self.unreadThreadGroupsCount = Int(threads.count)
        }
    }

    func updateUnreadChatsThreadCount() {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            let threads = self.commonThreads(predicate: NSPredicate(format: "groupID = nil && unreadCount > 0"), in: managedObjectContext)
            self.unreadThreadCount = Int(threads.count)
        }
    }

    //MARK: Thread Core Data Fetching
    
    private func commonThreads(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext) -> [ChatThread] {
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

    func emptyOneToOneChatThreads(in managedObjectContext: NSManagedObjectContext) -> [ChatThread] {
        return commonThreads(predicate: NSPredicate(format: "groupID == nil AND lastContentID == nil"), in: managedObjectContext)
    }

    func groupThreadsWithExpiredPosts(expiredPostIDs: [FeedPostID], in managedObjectContext: NSManagedObjectContext) -> [ChatThread] {
        return commonThreads(predicate: NSPredicate(format: "groupID != nil && lastContentID IN %@", expiredPostIDs), in: managedObjectContext)
    }

    func groupThreads(in managedObjectContext: NSManagedObjectContext) -> [ChatThread] {
        return commonThreads(predicate: NSPredicate(format: "groupID != nil"), in: managedObjectContext)
    }

    func chatThread(type: ChatType, id: String, in managedObjectContext: NSManagedObjectContext) -> ChatThread? {
        if type == .group {
            return commonThreads(predicate: NSPredicate(format: "groupID == %@", id), in: managedObjectContext).first
        } else {
            return commonThreads(predicate: NSPredicate(format: "userID == %@", id), in: managedObjectContext).first
        }
    }
    
    func chatThreadStatus(type: ChatType, id: String, messageId: String, in managedObjectContext: NSManagedObjectContext) -> ChatThread? {
        if type == .group {
            return commonThreads(predicate: NSPredicate(format: "groupID == %@ AND lastContentID == %@", id, messageId), in: managedObjectContext).first
        } else {
            return commonThreads(predicate: NSPredicate(format: "userID == %@ AND lastContentID == %@", id, messageId), in: managedObjectContext).first
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
            guard let chatThread = self.chatThreadStatus(type: type, id: id, messageId: messageId, in: managedObjectContext) else {
                DDLogError("ChatData/updateChatThreadStatus - missing")
                return
            }
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

    private func processInboundChatRetractInBg(_ chatRetractInfo: ChatRetractInfo, in context: NSManagedObjectContext) {
        backgroundProcessingQueue.async {
            self.retractMsg(chatRetractInfo: chatRetractInfo, in: context)
        }
    }

    private func retractMsg(chatRetractInfo: ChatRetractInfo, in context: NSManagedObjectContext) {
        DDLogInfo("ChatData/retractMsgIfFound/")
 
        switch chatRetractInfo.threadType {
        case .oneToOne:
            processInboundChatMessageRetract(from: chatRetractInfo.from, messageID: chatRetractInfo.messageID)
        default:
            return
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
                     linkPreviewData: LinkPreviewData? = nil,
                     linkPreviewMedia : PendingMedia? = nil,
                     feedPostId: String?,
                     feedPostMediaIndex: Int32,
                     chatReplyMessageID: String? = nil,
                     chatReplyMessageSenderID: UserID? = nil,
                     chatReplyMessageMediaIndex: Int32) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            self.createChatMsg( toUserId: toUserId,
                                text: text,
                                media: media,
                                linkPreviewData: linkPreviewData,
                                linkPreviewMedia : linkPreviewMedia,
                                feedPostId: feedPostId,
                                feedPostMediaIndex: feedPostMediaIndex,
                                chatReplyMessageID: chatReplyMessageID,
                                chatReplyMessageSenderID: chatReplyMessageSenderID,
                                chatReplyMessageMediaIndex: chatReplyMessageMediaIndex,
                                using: managedObjectContext)
        }
        
        addIntent(toUserId: toUserId)
    }

    /// - Returns: A chat message object that should be used on the main thread.
    @discardableResult
    func sendMomentReply(to userID: UserID, postID: FeedPostID, text: String) async -> ChatMessage? {
        await withCheckedContinuation { continuation in
            performSeriallyOnBackgroundContext { context in
                let id = self.createChatMsg(toUserId: userID,
                                                text: text,
                                               media: [],
                                     linkPreviewData: nil,
                                    linkPreviewMedia: nil,
                                          feedPostId: postID,
                                  feedPostMediaIndex: 0,
                                       isMomentReply: true,
                          chatReplyMessageMediaIndex: 0,
                                               using: context)

                let message = self.chatMessage(with: id, in: context)
                continuation.resume(returning: message)
            }
        }
    }

    @discardableResult
    func createChatMsg( toUserId: String,
                        text: String,
                        media: [PendingMedia],
                        linkPreviewData: LinkPreviewData?,
                        linkPreviewMedia : PendingMedia?,
                        feedPostId: String?,
                        feedPostMediaIndex: Int32,
                        isMomentReply: Bool = false,
                        chatReplyMessageID: String? = nil,
                        chatReplyMessageSenderID: UserID? = nil,
                        chatReplyMessageMediaIndex: Int32,
                        using context: NSManagedObjectContext) -> ChatMessageID {
        
        let messageId = PacketID.generate()
        let isMsgToYourself: Bool = toUserId == userData.userId
        
        // Create and save new ChatMessage object.
        DDLogDebug("ChatData/createChatMsg/\(messageId)")
        let chatMessage = ChatMessage(context: context)
        chatMessage.id = messageId
        chatMessage.toUserId = toUserId
        chatMessage.fromUserId = userData.userId
        chatMessage.rawText = text
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
                  
            let chatMedia = CommonMedia(context: context)
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

        if isMomentReply, let _ = feedPostId {
            // quoted moment; feed post has already been deleted at this point
            let quoted = ChatQuoted(context: context)
            quoted.type = .moment
            quoted.userID = toUserId
            quoted.message = chatMessage
        } else if let feedPostId = feedPostId, let feedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId, in: context) {
            // Create and save Quoted FeedPost
            let quoted = ChatQuoted(context: context)
            quoted.type = .feedpost
            quoted.userID = feedPost.userId
            quoted.rawText = feedPost.rawText
            quoted.message = chatMessage
            quoted.mentions = feedPost.mentions

            if let feedPostMedia = feedPost.media?.first(where: { $0.order == feedPostMediaIndex }) {
                let quotedMedia = CommonMedia(context: context)
                quotedMedia.type = feedPostMedia.type
                quotedMedia.order = feedPostMedia.order
                quotedMedia.width = Float(feedPostMedia.size.width)
                quotedMedia.height = Float(feedPostMedia.size.height)
                quotedMedia.chatQuoted = quoted

                do {
                    try copyMediaToQuotedMedia(fromDir: feedPostMedia.mediaDirectory, fromPath: feedPostMedia.relativeFilePath, to: quotedMedia)
                }
                catch {
                    DDLogError("ChatData/createChatMsg/\(messageId)/quoted/copy-media/error [\(error)]")
                }
            }
        }
        // Process link preview if present
        if let linkPreviewData = linkPreviewData {
            // add link preview info to the chatMessage
            generateLinkPreview(
                messageId: messageId,
                chatMessage: chatMessage,
                isMsgToYourself: isMsgToYourself,
                linkPreviewData: linkPreviewData,
                linkPreviewMedia: linkPreviewMedia,
                using: context)
        }

        if let chatReplyMessageID = chatReplyMessageID,
           let chatReplyMessageSenderID = chatReplyMessageSenderID,
           let quotedChatMessage = self.chatMessage(with: chatReplyMessageID, in: context) {
            
            let quoted = ChatQuoted(context: context)
            quoted.type = .message
            quoted.userID = chatReplyMessageSenderID
            quoted.rawText = quotedChatMessage.rawText
            quoted.message = chatMessage

            if let quotedChatMessageMedia = quotedChatMessage.media?.first(where: { $0.order == chatReplyMessageMediaIndex }) {
                let quotedMedia = CommonMedia(context: context)
                quotedMedia.type = quotedChatMessageMedia.type
                quotedMedia.order = quotedChatMessageMedia.order
                quotedMedia.width = Float(quotedChatMessageMedia.size.width)
                quotedMedia.height = Float(quotedChatMessageMedia.size.height)
                quotedMedia.chatQuoted = quoted

                do {
                    try copyMediaToQuotedMedia(fromDir: quotedChatMessageMedia.mediaDirectory, fromPath: quotedChatMessageMedia.relativeFilePath, to: quotedMedia)
                }
                catch {
                    DDLogError("ChatData/createChatMsg/\(messageId)/quoted/copy-media/error [\(error)]")
                }
            }
        }
        
        // Update Chat Thread
        if let chatThread = self.chatThread(type: ChatType.oneToOne, id: chatMessage.toUserId, in: context) {
            DDLogDebug("ChatData/createChatMsg/ update-thread")
            chatThread.lastMsgId = chatMessage.id
            chatThread.lastMsgUserId = chatMessage.fromUserId
            chatThread.lastMsgText = chatMessage.rawText
            chatThread.lastMsgMediaType = lastMsgMediaType
            chatThread.lastMsgStatus = isMsgToYourself ? .seen : .pending
            chatThread.lastMsgTimestamp = chatMessage.timestamp
            chatThread.unreadCount = 0
        } else {
            DDLogDebug("ChatData/createChatMsg/\(messageId)/new-thread")
            let chatThread = ChatThread(context: context)
            chatThread.userID = chatMessage.toUserId
            chatThread.lastMsgId = chatMessage.id
            chatThread.lastMsgUserId = chatMessage.fromUserId
            chatThread.lastMsgText = chatMessage.rawText
            chatThread.lastMsgMediaType = lastMsgMediaType
            chatThread.lastMsgStatus = isMsgToYourself ? .seen : .pending
            chatThread.lastMsgTimestamp = chatMessage.timestamp
            chatThread.unreadCount = 0
        }
        
        save(context)

        if !isMsgToYourself {
            processPendingChatMsgs()
        }

        return messageId
    }

    private func generateLinkPreview(messageId: ChatMessageID, chatMessage: ChatMessage, isMsgToYourself: Bool, linkPreviewData: LinkPreviewProtocol, linkPreviewMedia: PendingMedia?, using context: NSManagedObjectContext) {
        DDLogDebug("ChatData/process-chats/new/generate-link-preview [\(linkPreviewData.url)]")
        let linkPreview = CommonLinkPreview(context: context)
        linkPreview.id = PacketID.generate()
        linkPreview.url = linkPreviewData.url
        linkPreview.title = linkPreviewData.title
        linkPreview.desc = linkPreviewData.description
        linkPreview.message = chatMessage
        // Set preview image if present
        if let linkPreviewMedia = linkPreviewMedia {
            let linkPreviewChatMedia = CommonMedia(context: context)
            if let mediaItemSize = linkPreviewMedia.size, let mediaItemfileURL = linkPreviewMedia.fileURL {
                linkPreviewChatMedia.type = {
                    switch linkPreviewMedia.type {
                    case .image:
                        return .image
                    case .video:
                        return .video
                    case .audio:
                        return .audio
                    }
                }()
                linkPreviewChatMedia.outgoingStatus = isMsgToYourself ? .uploaded : .pending
                linkPreviewChatMedia.url = linkPreviewMedia.url
                linkPreviewChatMedia.uploadUrl = linkPreviewMedia.uploadUrl
                linkPreviewChatMedia.size = mediaItemSize
                linkPreviewChatMedia.key = ""
                linkPreviewChatMedia.sha256 = ""
                linkPreviewChatMedia.order = 0
                linkPreviewChatMedia.linkPreview = linkPreview
                do {
                    try copyFiles(toChatMedia: linkPreviewChatMedia, fileUrl: mediaItemfileURL, encryptedFileUrl: linkPreviewMedia.encryptedFileUrl)
                }
                catch {
                    DDLogError("ChatData/createChatMsg/\(messageId)/copy-media-linkPreview/error [\(error)]")
                }
            } else {
                DDLogDebug("ChatData/createChatMsg/\(messageId)/add-media-linkPreview/skip/missing info")
            }
        }
    }
    
    private func addLinkPreview(chatMessage: ChatMessage, linkPreviewData: [LinkPreviewProtocol], using context: NSManagedObjectContext) {
        linkPreviewData.forEach { linkPreviewData in
            DDLogDebug("ChatData/process-chats/new/add-link-preview [\(linkPreviewData.url)]")
            let linkPreview = CommonLinkPreview(context: context)
            linkPreview.id = PacketID.generate()
            linkPreview.url = linkPreviewData.url
            linkPreview.title = linkPreviewData.title
            linkPreview.desc = linkPreviewData.description
            // Set preview image if present
            linkPreviewData.previewImages.forEach { previewMedia in
                let media = CommonMedia(context: context)
                media.type = {
                    switch previewMedia.type {
                    case .image:
                        return .image
                    case .video:
                        return .video
                    case .audio:
                        return .audio
                    }
                }()
                media.outgoingStatus = .none
                media.incomingStatus = .pending
                media.url = previewMedia.url
                media.size = previewMedia.size
                media.key = previewMedia.key
                media.sha256 = previewMedia.sha256
                media.linkPreview = linkPreview
            }
            linkPreview.message = chatMessage
        }
    }

    private func uploadAllChatMsgMediaAndSend(_ xmppChatMsg: XMPPChatMessage, in managedObjectContext: NSManagedObjectContext) {
        let msgID = xmppChatMsg.id
        
        guard let chatMsg = chatMessage(with: msgID, in: managedObjectContext) else { return }

        MainAppContext.shared.beginBackgroundTask(msgID)
        
        // Either all media has already been uploaded or post does not contain media.
        if let mediaItemsToUpload = chatMsg.media?.filter({ $0.outgoingStatus == .none || $0.outgoingStatus == .pending || $0.outgoingStatus == .error }), !mediaItemsToUpload.isEmpty {
            uploadChatMsgMediaAndSend(msgID: msgID, chatMsg: chatMsg, mediaItemsToUpload: mediaItemsToUpload, mediaType: .chatMedia)
        } else if let mediaItemsToUpload = chatMsg.linkPreviews?.first?.media?.filter({ $0.outgoingStatus == .none || $0.outgoingStatus == .pending || $0.outgoingStatus == .error }), !mediaItemsToUpload.isEmpty{
            uploadChatMsgMediaAndSend(msgID: msgID, chatMsg: chatMsg, mediaItemsToUpload: mediaItemsToUpload, mediaType: .linkPreviewMedia)
        } else {
            send(message: XMPPChatMessage(chatMessage: chatMsg))
            return
        }
    }
 
    private enum ChatMediaType {
        case chatMedia
        case linkPreviewMedia
    }

    private func uploadChatMsgMediaAndSend(msgID: ChatMessageID, chatMsg: ChatMessage, mediaItemsToUpload: Set<CommonMedia>, mediaType: ChatMediaType) {

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
            let outputFileID = "\(msgID)-\(mediaIndex)"

            DDLogDebug("ChatData/process-mediaItem/chatMessage: \(msgID)/\(mediaItem.order), index: \(mediaIndex)")
            if let url = mediaItem.mediaURL, mediaItem.sha256.isEmpty && mediaItem.key.isEmpty {
                DDLogDebug("ChatData/process-mediaItem/chatMessage: \(msgID)/\(mediaIndex)/url: \(url)")
                let output = url.deletingLastPathComponent().appendingPathComponent(outputFileID, isDirectory: false).appendingPathExtension("processed").appendingPathExtension(url.pathExtension)

                let type: CommonMediaType = {
                    switch mediaItem.type {
                    case .image:
                        return .image
                    case .video:
                        return .video
                    case .audio:
                        return .audio
                    }
                } ()

                ImageServer.shared.prepare(type, url: url, for: msgID, index: Int(mediaIndex), shouldStreamVideo: false) { [weak self] in
                    guard let self = self else { return }

                    switch $0 {
                    case .success(let result):
                        result.copy(to: output)
                        if result.url != url {
                            result.clear()
                        }

                        let path = self.relativePath(from: output)
                        DDLogDebug("ChatData/process-mediaItem/success: \(msgID)/\(mediaIndex)")
                        self.updateChatMessage(with: msgID, block: { msg in
                            switch mediaType {
                            case .chatMedia:
                                guard let media = msg.media?.first(where: { $0.order == mediaIndex }) else {
                                    DDLogError("ChatData/process-mediaItem/failed to save/msgId: \(msgID)/\(mediaIndex)")
                                    return
                                }

                                media.size = result.size
                                media.key = result.key
                                media.sha256 = result.sha256
                                media.relativeFilePath = path
                                DDLogDebug("ChatData/updating chat message: \(msgID), relativeFilePath: \(path ?? "nil")")
                            case .linkPreviewMedia:
                                guard let media = msg.linkPreviews?.first?.media?.first(where: { $0.order == mediaIndex }) else {
                                    DDLogError("ChatData/process-linkPreview-mediaItem/failed to save/msgId: \(msgID)/\(mediaIndex)")
                                    return
                                }

                                media.size = result.size
                                media.key = result.key
                                media.sha256 = result.sha256
                                media.relativeFilePath = path
                                DDLogDebug("ChatData/linkPreview updating chat message: \(msgID), relativeFilePath: \(path ?? "nil")")
                            }
                        }) {
                            self.uploadChat(msgID: msgID, mediaIndex: mediaIndex, mediaType: mediaType, completion: uploadCompletion)
                        }
                    case .failure(_):
                        DDLogDebug("ChatData/process-mediaItem/failure: \(msgID)/\(mediaIndex)")
                        numberOfFailedUploads += 1
                        self.updateChatMessage(with: msgID, block: { msg in
                            switch mediaType {
                            case .chatMedia:
                                guard let media = msg.media?.first(where: { $0.order == mediaIndex }) else { return }
                                media.outgoingStatus = .error
                                media.numTries += 1
                            case .linkPreviewMedia:
                                guard let media = msg.linkPreviews?.first?.media?.first(where: { $0.order == mediaIndex }) else { return }
                                media.outgoingStatus = .error
                                media.numTries += 1
                            }
                        }) {
                            uploadGroup.leave()
                        }
                    }
                }
            } else {
                DDLogDebug("ChatData/process-mediaItem/processed already: \(msgID)/\(mediaIndex)")
                uploadChat(msgID: msgID, mediaIndex: mediaIndex, mediaType: mediaType, completion: uploadCompletion)
            }
        }

        uploadGroup.notify(queue: backgroundProcessingQueue) { [weak self] in
            guard let self = self else { return }
            DDLogInfo("ChatData/uploadChatMsgMediaAndSend/finish/\(msgID) failed/total: \(numberOfFailedUploads)/\(totalUploads)")
            ImageServer.shared.clearAllTasks(for: msgID)
            self.mediaUploader.clearTasks(withGroupID: msgID)
            if numberOfFailedUploads > 0 {
                if isMsgStale {
                    self.updateChatMessage(with: msgID) { msg in
                        msg.outgoingStatus = .error
                    }
                }
            } else {
                self.performSeriallyOnBackgroundContext { managedObjectContext in
                    guard let chatMsg = self.chatMessage(with: msgID, in: managedObjectContext) else { return }
                    self.send(message: XMPPChatMessage(chatMessage: chatMsg))
                }
            }

        }
    }

    private func getChatMediaFromMessage(msg: ChatMessage, mediaIndex: Int16, mediaType: ChatMediaType) -> CommonMedia? {
        var chatMedia: CommonMedia?
        switch mediaType {
        case .chatMedia:
            chatMedia = msg.media?.first(where: { $0.order == mediaIndex })
        case .linkPreviewMedia:
            chatMedia = msg.linkPreviews?.first?.media?.first(where: { $0.order == mediaIndex })
        }
        return chatMedia
    }

    private func uploadChat(msgID: String, mediaIndex: Int16, mediaType: ChatMediaType, completion: @escaping (Result<MediaUploader.UploadDetails, Error>) -> Void) {
        performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            guard let self = self else { return }
            guard let msg = self.chatMessage(with: msgID, in: managedObjectContext),
                  let chatMedia = self.getChatMediaFromMessage(msg: msg, mediaIndex: mediaIndex, mediaType: mediaType) else {
                DDLogError("ChatData/uploadChat/fetch msg and media \(msgID)/\(mediaIndex) - missing")
                completion(.failure(RequestError.aborted))
                return
            }

            DDLogDebug("ChatData/uploadChat/media \(msgID)/\(chatMedia.order), index:\(mediaIndex), path: \(chatMedia.relativeFilePath ?? "nil")")
            guard let processed = chatMedia.mediaURL else {
                DDLogError("ChatData/uploadChat/\(msgID)/\(mediaIndex) missing file path")
                return completion(.failure(MediaUploadError.invalidUrls))
            }

            MainAppContext.shared.mediaHashStore.fetch(url: processed, blobVersion: chatMedia.blobVersion) { [weak self] upload in
                guard let self = self else { return }
                self.checkMediaHashAndUploadChat(msgID: msgID, mediaIndex: mediaIndex, mediaType: mediaType, mediaHash: upload, completion: completion)
            }
        }
    }

    private func checkMediaHashAndUploadChat(msgID: String, mediaIndex: Int16, mediaType: ChatMediaType, mediaHash: (url: URL?, key: String?, sha256: String?)?,
                                             completion: @escaping (Result<MediaUploader.UploadDetails, Error>) -> Void) {
        let mediaHashURL = mediaHash?.url
        let mediaHashKey = mediaHash?.key
        let mediaHashSha256 = mediaHash?.sha256
        performSeriallyOnBackgroundContext { context in
            // Lookup object from coredata again instead of passing around the object across threads.
            DDLogInfo("ChatData/uploadChat/fetch upload hash \(msgID)/\(mediaIndex)")
            guard let msg = self.chatMessage(with: msgID, in: context),
                  let media = self.getChatMediaFromMessage(msg: msg, mediaIndex: mediaIndex, mediaType: mediaType) else {
                DDLogError("ChatData/uploadChat/fetch msg and media \(msgID)/\(mediaIndex) - missing")
                completion(.failure(RequestError.aborted))
                return
            }

            guard let mediaURL = media.mediaURL else {
                DDLogError("ChatData/uploadChat/\(msgID)/\(mediaIndex) missing file path")
                return completion(.failure(MediaUploadError.invalidUrls))
            }

            if let url = mediaHashURL {
                DDLogInfo("Media \(mediaURL) has been uploaded before at \(url).")
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
                    guard let media = self.getChatMediaFromMessage(msg: msg, mediaIndex: mediaIndex, mediaType: mediaType) else { return }

                    switch mediaURLs {
                    case .getPut(let getURL, let putURL):
                        media.url = getURL
                        media.uploadUrl = putURL
                    case .patch(let patchURL):
                        media.uploadUrl = patchURL
                        media.url = nil
                    case .download(let downloadURL):
                        media.url = downloadURL
                    }
                }
            }) { (uploadResult) in
                DDLogInfo("ChatData/uploadChatMsgMediaAndSend/\(msgID)/\(mediaIndex)/finished result=[\(uploadResult)]")

                // Save URLs acquired during upload to the database.
                self.updateChatMessage(with: msgID, block: { msg in
                    guard let media = self.getChatMediaFromMessage(msg: msg, mediaIndex: mediaIndex, mediaType: mediaType) else { return }

                    switch uploadResult {
                    case .success(let details):
                        media.url = details.downloadURL
                        media.outgoingStatus = .uploaded

                        if media.url == mediaHashURL, let key = mediaHashKey, let sha256 = mediaHashSha256 {
                            media.key = key
                            media.sha256 = sha256
                        }

                        MainAppContext.shared.mediaHashStore.update(url: mediaURL, blobVersion: media.blobVersion, key: media.key, sha256: media.sha256, downloadURL: media.url!)
                    case .failure(_):
                        media.outgoingStatus = .error
                        media.numTries += 1
                    }
                }) {
                    if media.outgoingStatus == .uploaded {
                        ImageServer.cleanUpUploadData(directoryURL: MainAppContext.commonMediaStoreURL, relativePath: media.relativeFilePath)
                    }
                    completion(uploadResult)
                }
            }
        }
    }

    private func send(message: ChatMessageProtocol) {
        service.sendChatMessage(message) { _ in
            MainAppContext.shared.endBackgroundTask(message.id)
        }
    }

    private func handleRerequest(for messageID: String, from userID: UserID, completion: @escaping ServiceRequestCompletion<Void>) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else {
                completion(.failure(.aborted))
                return
            }
            guard let chatMessage = self.chatMessage(with: messageID, in: managedObjectContext) else {
                DDLogError("ChatData/handleRerequest/\(messageID)/error could not find message")
                self.service.sendContentMissing(id: messageID, type: .chat, to: userID) { result in
                    completion(result)
                }
                return
            }
            guard userID == chatMessage.toUserId else {
                DDLogError("ChatData/handleRerequest/\(messageID)/error user mismatch [original: \(chatMessage.toUserId)] [rerequest: \(userID)]")
                completion(.failure(.aborted))
                return
            }
            guard chatMessage.resendAttempts < 5 else {
                DDLogInfo("ChatData/handleRerequest/\(messageID)/skipping (\(chatMessage.resendAttempts) resend attempts)")
                completion(.failure(.aborted))
                return
            }
            chatMessage.resendAttempts += 1

            let xmppChatMessage = XMPPChatMessage(chatMessage: chatMessage)
            self.backgroundProcessingQueue.async {
                self.send(message: xmppChatMessage)
                completion(.success(()))
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
            var name = ""
            MainAppContext.shared.contactStore.performOnBackgroundContextAndWait { managedObjectContext in
                name = MainAppContext.shared.contactStore.fullName(for: toUserId, in: managedObjectContext)
            }

            let recipient = INSpeakableString(spokenPhrase: name)
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
                                in managedObjectContext: NSManagedObjectContext) -> [ChatMessage] {
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
    
    private func linkPreviews(  predicate: NSPredicate? = nil,
                                limit: Int? = nil,
                                in managedObjectContext: NSManagedObjectContext) -> [CommonLinkPreview] {
        let fetchRequest: NSFetchRequest<CommonLinkPreview> = CommonLinkPreview.fetchRequest()
        fetchRequest.predicate = predicate
        if let fetchLimit = limit { fetchRequest.fetchLimit = fetchLimit }
        fetchRequest.returnsObjectsAsFaults = false

        do {
            let linkPreviews = try managedObjectContext.fetch(fetchRequest)
            return linkPreviews
        }
        catch {
            DDLogError("ChatData/fetch-linkPreviews/error  [\(error)]")
            fatalError("Failed to fetch chat linkPreviews")
        }
    }
    
    func chatMessage(with id: String, in managedObjectContext: NSManagedObjectContext) -> ChatMessage? {
        return self.chatMessages(predicate: NSPredicate(format: "id == %@", id), in: managedObjectContext).first
    }

    func chatMessages(with ids: Set<FeedPostCommentID>, in managedObjectContext: NSManagedObjectContext) -> [ChatMessage] {
        return self.chatMessages(predicate: NSPredicate(format: "id in %@", ids), in: managedObjectContext)
    }

    func chatMessagesToProcess(in managedObjectContext: NSManagedObjectContext) -> [ChatMessage] {
        return self.chatMessages(predicate: NSPredicate(format: "hasBeenProcessed == NO"), in: managedObjectContext)
    }
    
    func chatLinkPreview(with id: String, in managedObjectContext: NSManagedObjectContext) -> CommonLinkPreview? {
        return self.linkPreviews(predicate: NSPredicate(format: "id == %@", id), in: managedObjectContext).first
    }

    // includes seen but not sent messages
    func unseenChatMessages(with fromUserId: String, in managedObjectContext: NSManagedObjectContext) -> [ChatMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.serialID, ascending: true),
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true)
        ]
        return self.chatMessages(predicate: NSPredicate(format: "fromUserID = %@ && toUserID = %@ && (incomingStatusValue = %d OR incomingStatusValue = %d)", fromUserId, userData.userId, ChatMessage.IncomingStatus.none.rawValue, ChatMessage.IncomingStatus.haveSeen.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }
    
    func pendingOutgoingChatMessages(in managedObjectContext: NSManagedObjectContext) -> [ChatMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true)
        ]
        return chatMessages(predicate: NSPredicate(format: "fromUserID = %@ && outgoingStatusValue = %d", userData.userId, ChatMessage.OutgoingStatus.pending.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }
    
    func retractingOutboundChatMsgs(in managedObjectContext: NSManagedObjectContext) -> [ChatMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true)
        ]
        return chatMessages(predicate: NSPredicate(format: "outgoingStatusValue = %d", ChatMessage.OutgoingStatus.retracting.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }
    
    func pendingOutgoingSeenReceipts(in managedObjectContext: NSManagedObjectContext) -> [ChatMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true)
        ]
        return chatMessages(predicate: NSPredicate(format: "fromUserID = %@ && incomingStatusValue = %d", userData.userId, ChatMessage.IncomingStatus.haveSeen.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }

    func pendingOutgoingPlayedReceipts(in managedObjectContext: NSManagedObjectContext) -> [ChatMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true)
        ]
        return chatMessages(predicate: NSPredicate(format: "fromUserID = %@ && incomingStatusValue = %d", userData.userId, ChatMessage.IncomingStatus.played.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }
    
    func pendingIncomingChatMessagesMedia(in managedObjectContext: NSManagedObjectContext) -> [ChatMessage] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \ChatMessage.timestamp, ascending: true)
        ]
        return chatMessages(predicate: NSPredicate(format: "ANY media.statusValue == %d", CommonMedia.Status.downloading.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
    }
    
    func pendingIncomingLinkPreviewMedia(in managedObjectContext: NSManagedObjectContext) -> [CommonLinkPreview] {
        return linkPreviews(predicate: NSPredicate(format: "ANY media.statusValue == %d", CommonMedia.Status.downloading.rawValue), in: managedObjectContext)
    }

    func haveMessagedBefore(userID: UserID, in managedObjectContext: NSManagedObjectContext) -> Bool {
        let predicate = NSPredicate(format: "fromUserID = %@ AND toUserID = %@", userData.userId, userID)
        let fetchLimit = 1
        return (chatMessages(predicate: predicate, limit: fetchLimit, in: managedObjectContext).count > 0) ? true : false
    }

    func haveReceivedMessagesBefore(userID: UserID, in managedObjectContext: NSManagedObjectContext) -> Bool {
        let predicate = NSPredicate(format: "fromUserID = %@ AND toUserID = %@", userID, userData.userId)
        let fetchLimit = 1
        return (chatMessages(predicate: predicate, limit: fetchLimit, in: managedObjectContext).count > 0) ? true : false
    }

    // MARK: 1-1 Core Data Updating

    private func createNewChatMessageIfMissing(from: UserID, messageID: String, status: ChatMessage.IncomingStatus) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self, self.chatMessage(with: messageID, in: managedObjectContext) == nil else {
                return
            }
            DDLogWarn("ChatData/createNewChatMessageIfMissing/from: \(from)/messageID: \(messageID)/status: \(status)/messages might be out of order")
            let timestamp = Date()
            let chatMessage = ChatMessage(context: managedObjectContext)
            chatMessage.id = messageID
            chatMessage.fromUserId = from
            chatMessage.toUserId = self.userData.userId
            chatMessage.incomingStatus = status
            chatMessage.outgoingStatus = .none
            chatMessage.timestamp = timestamp
            chatMessage.serverTimestamp = timestamp
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }

    private func createNewChatThreadIfMissing(from: UserID, messageID: String, status: ChatThread.LastMsgStatus) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self, self.chatThreadStatus(type: .oneToOne, id: from, messageId: messageID, in: managedObjectContext) == nil else {
                return
            }
            DDLogWarn("ChatData/createNewChatThreadIfMissing/from: \(from)/messageID: \(messageID)/status: \(status)/messages might be out of order")
            let timestamp = Date()
            let chatThread = ChatThread(context: managedObjectContext)
            chatThread.lastMsgUserId = from
            chatThread.lastMsgTimestamp = timestamp
            chatThread.lastMsgStatus = status
            chatThread.lastMsgText = nil
            chatThread.lastMsgMediaType = .none
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
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
            DDLogVerbose("ChatData/update-existing-message [\(chatMessageId)]")
            block(chatMessage)
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    private func updateLinkPreview(with linkPreviewId: String, block: @escaping (CommonLinkPreview) -> (), performAfterSave: (() -> ())? = nil) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            defer {
                if let performAfterSave = performAfterSave {
                    performAfterSave()
                }
            }
            guard let self = self else { return }
            guard let chatLinkPreview = self.chatLinkPreview(with: linkPreviewId, in: managedObjectContext) else {
                DDLogError("ChatData/update-link-preview/missing [\(linkPreviewId)]")
                return
            }
            DDLogVerbose("ChatData/update-link-preview [\(linkPreviewId)]")
            block(chatLinkPreview)
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

    // MARK: 1-1 Clean Up Media Upload Data

    // todo: this should be called from somewhere else since this is calling chatData & feedData methods
    func cleanUpOldUploadData() {
        var shouldCleanUp = true
        if let mediaUploadDataLastCleanUpDouble = MainAppContext.shared.userDefaults?.double(forKey: MainAppContext.MediaUploadDataLastCleanUpTime) {
            let mediaUploadDataLastCleanUpDate = Date(timeIntervalSince1970: mediaUploadDataLastCleanUpDouble)

            if let diff = Calendar.current.dateComponents([.day], from: mediaUploadDataLastCleanUpDate, to: Date()).day, diff < 3 {
                shouldCleanUp = false
            }
        }

        guard shouldCleanUp else {
            return
        }
        cleanUpOldUploadData(directoryURL: MainAppContext.chatMediaDirectoryURL)
        cleanUpOldUploadData(directoryURL: MainAppContext.commonMediaStoreURL)
        MainAppContext.shared.feedData.cleanUpOldUploadData(directoryURL: MainAppContext.mediaDirectoryURL)
        MainAppContext.shared.feedData.cleanUpOldUploadData(directoryURL: MainAppContext.commonMediaStoreURL)
        MainAppContext.shared.userDefaults?.setValue(Date().timeIntervalSince1970, forKey: MainAppContext.MediaUploadDataLastCleanUpTime)
    }

    // cleans up old upload data since prior to build 173 we did not do so
    // this will be a redundant clean up after the first run and can be revisited to see if it's needed
    private func cleanUpOldUploadData(directoryURL: URL) {
        DDLogInfo("ChatData/cleanUpOldUploadData")
        guard let enumerator = FileManager.default.enumerator(atPath: directoryURL.path) else { return }
        let encryptedSuffix = "enc"
        let encryptedExtSuffix = ".\(encryptedSuffix)"
        let processedSuffix = "processed"

        enumerator.forEach({ file in
            // check if it's an encrypted file that ends with .enc
            guard let relativeFilePath = file as? String else { return }
            guard relativeFilePath.hasSuffix(encryptedExtSuffix) else { return }

            // get the last part of the path, which is the filename
            var relativeFilePathComponents = relativeFilePath.components(separatedBy: "/")
            guard let fileName = relativeFilePathComponents.last else { return }

            // get the id (with index) of the message from the filename
            var fileNameComponents = fileName.components(separatedBy: ".")
            guard let fileNameWithIndex = fileNameComponents.first else { return }

            // strip out the index part of the id
            var fileNameWithIndexComponents = fileNameWithIndex.components(separatedBy: "-")
            fileNameWithIndexComponents.removeLast()
            let msgID = fileNameWithIndexComponents.joined(separator: "-")

            DDLogInfo("ChatData/cleanUpOldUploadData/file: \(file)/msgID: \(msgID)")
            if let chatMessage = MainAppContext.shared.chatData.chatMessage(with: msgID, in: MainAppContext.shared.chatData.viewContext) {
                // message exists, clean up any upload data in all the media
                chatMessage.media?.forEach { (media) in
                    guard media.outgoingStatus == .uploaded else { return }
                    DDLogInfo("ChatData/cleanUpOldUploadData/clean up existing message upload data: \(media.relativeFilePath ?? "")")
                    ImageServer.cleanUpUploadData(directoryURL: directoryURL, relativePath: media.relativeFilePath)
                }
                chatMessage.linkPreviews?.forEach { linkPreview in
                    linkPreview.media?.forEach { media in
                        guard media.outgoingStatus == .uploaded else { return }
                        DDLogVerbose("ChatData/cleanUpOldUploadData/clean up existing link preview upload data: \(media.relativeFilePath ?? "")")
                        ImageServer.cleanUpUploadData(directoryURL: directoryURL, relativePath: media.relativeFilePath)
                    }
                }
            } else {
                // message does not exist anymore, get the processed relative filepath and clean up
                if fileNameComponents.count == 4, fileNameComponents[3] == encryptedSuffix, fileNameComponents[1] == processedSuffix {
                    // remove .enc
                    fileNameComponents.removeLast()
                    let processedFileName = fileNameComponents.joined(separator: ".")

                    // remove the last part of the path, which is the filename
                    relativeFilePathComponents.removeLast()
                    let relativeFilePathForProcessed = relativeFilePathComponents.joined(separator: "/")

                    // form the processed filename's relative path
                    let processedRelativeFilePath = relativeFilePathForProcessed + "/" + processedFileName

                    DDLogInfo("ChatData/cleanUpOldUploadData/clean up deleted message upload data: \(processedRelativeFilePath)")
                    ImageServer.cleanUpUploadData(directoryURL: directoryURL, relativePath: processedRelativeFilePath)
                }
            }
        })
    }

    // MARK: 1-1 Core Data Deleting

    func deleteChat(chatThreadId: String) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }

            // delete all chat events and chat thread
            if let chatThread = self.chatThread(type: ChatType.oneToOne, id: chatThreadId, in: managedObjectContext) {
                if let chatWithUserId = chatThread.userID {
                    AppContext.shared.coreChatData.deleteChatEvents(userID: chatWithUserId)
                }

                managedObjectContext.delete(chatThread)
            }

            let fetchRequest = NSFetchRequest<ChatMessage>(entityName: ChatMessage.entity().name!)
            // TODO: eventually use a chatId instead of a confusing match
            fetchRequest.predicate = NSPredicate(format: "(fromUserID = %@ AND toUserID = %@) || (toUserID = %@ && fromUserID = %@)", chatThreadId, MainAppContext.shared.userData.userId, chatThreadId, AppContext.shared.userData.userId)

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
                self.updateUnreadChatsThreadCount()
            }
        }

        MainAppContext.shared.mainDataStore.deleteCalls(with: chatThreadId)
    }

    public func deleteChatMessage(with id: ChatMessageID) {
        DDLogDebug("ChatData/deleteChatmessage/message \(id)")

        performSeriallyOnBackgroundContext { [weak self] context in
            guard let self = self, let chatMessage = self.chatMessage(with: id, in: context) else {
                return
            }

            self.deleteMedia(in: chatMessage)
            context.delete(chatMessage)

            if context.hasChanges {
                self.save(context)
            }
        }
    }

    private func deleteChatMessageContent(in chatMessage: ChatMessage) {
        DDLogDebug("ChatData/deleteChatMessageContent/message \(chatMessage.id) ")
        
        chatMessage.rawText = nil
        
        chatMessage.feedPostId = nil
        chatMessage.feedPostMediaIndex = 0
        
        chatMessage.chatReplyMessageID = nil
        chatMessage.chatReplyMessageSenderID = nil
        chatMessage.chatReplyMessageMediaIndex = 0
        
        self.deleteMedia(in: chatMessage)

        // delete link previews.
        chatMessage.linkPreviews?.forEach { linkPreview in
            chatMessage.managedObjectContext?.delete(linkPreview)
        }
        chatMessage.media = nil
        chatMessage.quoted = nil
    }
    
    private func deleteMedia(in chatMessage: ChatMessage) {
        DDLogDebug("ChatData/deleteMedia/message \(chatMessage.id) ")
        chatMessage.media?.forEach { (media) in
            if let fileURL = media.mediaURL {
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

        // Delete link previews in messages.
        chatMessage.linkPreviews?.forEach { linkPreview in
            linkPreview.media?.forEach { (media) in
                if let fileURL = media.mediaURL {
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
        }

        // quoted media item will be deleted - when the main chat message containing that media object is deleted.
        // this message only contains a reference to it - so quoted media should not be deleted.
        if let quoted = chatMessage.quoted {
            DDLogDebug("ChatData/deleteMedia/quoted ")
            if let quotedMedia = quoted.media {
                quotedMedia.forEach { (media) in
                    /* TODO: Restore this if necessary (but it seems like the comment above suggests we shouldn't delete the media?)
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
                     */
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
        if let existingChatMessage = existingChatMessage {
            switch existingChatMessage.incomingStatus {
            case .unsupported, .rerequesting:
                DDLogInfo("ChatData/process/already-exists/updating [\(existingChatMessage.incomingStatus)] [\(xmppChatMessage.id)]")
                break
            case .error, .haveSeen, .none, .retracted, .sentSeenReceipt, .played, .sentPlayedReceipt:
                DDLogError("ChatData/process/already-exists/error [\(existingChatMessage.incomingStatus)] [\(xmppChatMessage.id)]")
                return
            }
        }

        let isCurrentlyChattingWithUser = isCurrentlyChatting(with: xmppChatMessage.fromUserId)
        DDLogDebug("ChatData/processInboundChatMessage [\(xmppChatMessage.id)]")
        let chatMessage: ChatMessage = {
            guard let existingChatMessage = existingChatMessage else {
                DDLogDebug("ChatData/process/new [\(xmppChatMessage.id)]")
                return ChatMessage(context: managedObjectContext)
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
            chatMessage.rawText = text
            for (index, xmppMedia) in media.enumerated() {
                guard let downloadUrl = xmppMedia.url else { continue }

                DDLogDebug("ChatData/process/new/add-media [\(downloadUrl)]")
                let chatMedia = CommonMedia(context: managedObjectContext)

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

            chatMessage.rawText = ""
            lastMsgMediaType = .audio

            let chatMedia = CommonMedia(context: managedObjectContext)
            chatMedia.type = .audio
            chatMedia.incomingStatus = .pending
            chatMedia.outgoingStatus = .none
            chatMedia.url = xmppMedia.url
            chatMedia.size = xmppMedia.size
            chatMedia.key = xmppMedia.key
            chatMedia.order = 0
            chatMedia.sha256 = xmppMedia.sha256
            chatMedia.message = chatMessage
        case .text(let text, let linkPreviewData):
            chatMessage.rawText = text
            addLinkPreview( chatMessage: chatMessage, linkPreviewData: linkPreviewData, using: managedObjectContext)
        case .unsupported(let data):
            chatMessage.rawData = data
            chatMessage.incomingStatus = .unsupported
        }

        // Process quoted content.
        if let feedPostId = xmppChatMessage.context.feedPostID {
            // Process Quoted Feedpost
            if let quotedFeedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId, in: managedObjectContext) {
                copyQuoted(to: chatMessage, from: quotedFeedPost, using: managedObjectContext)
            }
        } else if let chatReplyMsgId = xmppChatMessage.context.chatReplyMessageID {
            // Process Quoted Message
            if let quotedChatMessage = MainAppContext.shared.chatData.chatMessage(with: chatReplyMsgId, in: managedObjectContext) {
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
            chatThread.lastMsgText = chatMessage.rawText
            chatThread.lastMsgMediaType = lastMsgMediaType
            chatThread.lastMsgStatus = .none
            chatThread.lastMsgTimestamp = chatMessage.timestamp
            chatThread.unreadCount = isCurrentlyChattingWithUser ? 0 : chatThread.unreadCount + 1
        } else {
            let chatThread = ChatThread(context: managedObjectContext)
            chatThread.userID = chatMessage.fromUserId
            chatThread.lastMsgId = chatMessage.id
            chatThread.lastMsgUserId = chatMessage.fromUserId
            chatThread.lastMsgText = chatMessage.rawText
            chatThread.lastMsgMediaType = lastMsgMediaType
            chatThread.lastMsgStatus = .none
            chatThread.lastMsgTimestamp = chatMessage.timestamp
            chatThread.unreadCount = isCurrentlyChattingWithUser ? 0 : chatThread.unreadCount + 1
        }

        save(managedObjectContext)

        if isCurrentlyChattingWithUser && isAppActive && (chatMessage.incomingStatus != .unsupported) && (chatMessage.incomingStatus != .rerequesting) {
            self.sendSeenReceipt(for: chatMessage)
            self.updateChatMessage(with: chatMessage.id) { (chatMessage) in
                chatMessage.incomingStatus = .haveSeen
            }
        } else {
            self.updateUnreadChatsThreadCount()
        }

        showOneToOneNotification(for: xmppChatMessage)
        // download media for this chat message.
        downloadMedia(in: chatMessage)
        chatMessage.linkPreviews?.forEach { linkPreview in
            downloadMedia(in: linkPreview)
        }

        // download any other pending chat message media
        processInboundPendingChatMsgMedia()
        processInboundPendingChaLinkPreviewMedia()

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
            guard ![.played, .seen, .retracting, .retracted].contains(chatMessage.outgoingStatus) || receiptType == .played else { return }

            switch receiptType {
            case .delivery:
                chatMessage.outgoingStatus = .delivered
            case .read:
                chatMessage.outgoingStatus = .seen
            case .played:
                chatMessage.outgoingStatus = .played
            }

            self.updateChatThreadStatus(type: .oneToOne, for: chatMessage.toUserId, messageId: chatMessage.id) { (chatThread) in
                switch receiptType {
                case .delivery:
                    chatThread.lastMsgStatus = .delivered
                case .read:
                    chatThread.lastMsgStatus = .seen
                case .played:
                    chatThread.lastMsgStatus = .played
                }
            }
        }
    }
    
    // MARK: 1-1 Process Inbound Retract Message
    
    private func processInboundChatMessageRetract(from: UserID, messageID: String) {
        DDLogInfo("ChatData/processInboundChatMessageRetract")

        createNewChatMessageIfMissing(from: from, messageID: messageID, status: .retracted)

        updateChatMessage(with: messageID) { [weak self] (chatMessage) in
            guard let self = self else { return }

            chatMessage.incomingStatus = .retracted

            self.deleteChatMessageContent(in: chatMessage)

            self.createNewChatThreadIfMissing(from: from, messageID: messageID, status: .retracted)
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
    
    private func checkViewAndSendPresence(type: PresenceType) {
        let isCallViewControllerActive = isCallViewControllerActive()
        if !isCallViewControllerActive {
            MainAppContext.shared.service.sendPresenceIfPossible(type)
        } else {
            // CallViewController is active - so just send away and ignore input presence type.
            MainAppContext.shared.service.sendPresenceIfPossible(.away)
        }
    }

    func isCallViewControllerActive() -> Bool {
        guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }),
              let rootViewController = window.rootViewController else {
            return false
        }

        var topViewController = rootViewController
        while let newTopViewController = topViewController.presentedViewController {
            topViewController = newTopViewController
        }

        return (topViewController as? CallViewController) != nil
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

            pendingOutgoingChatMessages.forEach { pendingMsg in
                let xmppChatMsg = XMPPChatMessage(chatMessage: pendingMsg)
                self.uploadAllChatMsgMediaAndSend(xmppChatMsg, in: managedObjectContext)
            }
        }
    }

    private func processRetractingChatMsgs() {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            let retractingOutboundChatMsgs = self.retractingOutboundChatMsgs(in: managedObjectContext)
            DDLogInfo("ChatData/processRetractingChatMsgs/num: \(retractingOutboundChatMsgs.count)")

            retractingOutboundChatMsgs.forEach {
                guard let chatMsg = self.chatMessage(with: $0.id, in: managedObjectContext) else { return }
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

    private func processPendingPlayedReceipts() {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            let pendingOutgoingPlayedReceipts = self.pendingOutgoingPlayedReceipts(in: managedObjectContext)
            DDLogInfo("ChatData/pendingOutgoingPlayedReceipts/num: \(pendingOutgoingPlayedReceipts.count)")

            pendingOutgoingPlayedReceipts.forEach {
                DDLogInfo("ChatData/pendingOutgoingPlayedReceipts/seenReceipts \($0.id)")
                self.sendPlayedReceipt(for: $0)
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
        DDLogDebug("ChatData/presentOneToOneBanner/checking")
        let userID = xmppChatMessage.fromUserId
        let messageID = xmppChatMessage.id
        
        let name = contactStore.fullName(for: userID, in: contactStore.viewContext)
        
        let title = "\(name)"
        
        let body: String

        switch xmppChatMessage.content {
        case .text(let text, _):
            // TODO Dini present linkPreviewData here?
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
        AppContext.shared.notificationStore.runIfNotificationWasNotPresented(for: messageID) {
            Banner.show(title: title, body: body, userID: userID, using: MainAppContext.shared.avatarStore)
        }
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

                // create invite link now and store it so later UI does not need to show empty link on very first load
                dispatchGroup.enter()
                self.getGroupInviteLink(groupID: groupID) { _ in
                    dispatchGroup.leave() // the group can be created regardless if group link request succeeds or not
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
                    chatGroup.avatarID = avatarID
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

    // TODO: murali@: Why are we syncing after every group event.
    // This is very inefficient: we should not be doing this!
    // We should just follow our own state of groupEvents and do a weekly sync of all our groups.
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
                        self.performSeriallyOnBackgroundContext { context in
                            self.deleteChatGroupMember(groupId: groupId, memberUserId: MainAppContext.shared.userData.userId, in: context)
                        }
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
        performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
            guard let self = self else { return }

            guard let group = self.chatGroup(groupId: groupId, in: managedObjectContext) else { return }
            guard self.chatGroupMember(groupId: groupId, memberUserId: MainAppContext.shared.userData.userId, in: managedObjectContext) != nil else { return }

            if let lastSync = group.lastSync {
                guard let diff = Calendar.current.dateComponents([.hour], from: lastSync, to: Date()).hour, diff > 24 else {
                    return
                }
            }

            MainAppContext.shared.chatData.getAndSyncGroup(groupId: groupId)
        }
    }

    // Sync group crypto state and remove non-members in sender-states and pendingUids string.
    func syncGroup(_ xmppGroup: XMPPGroup) {
        let groupID = xmppGroup.groupId
        DDLogInfo("ChatData/group: \(groupID)/syncGroupInfo")

        let memberUserIDs = xmppGroup.members?.map { $0.userId } ?? []
        updateChatGroup(with: xmppGroup.groupId, block: { [weak self] (chatGroup) in
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
            if chatGroup.avatarID != xmppGroup.avatarID {
                chatGroup.avatarID = xmppGroup.avatarID
                if let avatarID = xmppGroup.avatarID {
                    MainAppContext.shared.avatarStore.updateOrInsertGroupAvatar(for: chatGroup.id, with: avatarID)
                }
            }
            if chatGroup.background != xmppGroup.background {
                chatGroup.background = xmppGroup.background
            }

            // look for users that are not members anymore
            chatGroup.orderedMembers.forEach { currentMember in
                let foundMember = xmppGroup.members?.first(where: { $0.userId == currentMember.userID })

                if foundMember == nil {
                    chatGroup.managedObjectContext!.delete(currentMember)
                }
            }

            var contactNames = [UserID:String]()

            // see if there are new members added or needs to be updated
            xmppGroup.members?.forEach { inboundMember in
                let foundMember = chatGroup.members?.first(where: { $0.userID == inboundMember.userId })

                // member already exists
                if let member = foundMember {
                    if let inboundType = inboundMember.type {
                        if member.type != inboundType {
                            member.type = inboundType
                        }
                    }
                } else {
                    DDLogDebug("ChatData/group: \(groupID)/syncGroupInfo/new/add-member [\(inboundMember.userId)]")
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

        }, performAfterSave: {
            AppContext.shared.messageCrypter.syncGroupSession(in: groupID, members: memberUserIDs)
            DDLogInfo("ChatData/group: \(groupID)/syncGroupInfo/done")
        })
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
            guard path == "/invite/" || path == "/appclip/" else { return nil }
        } else if scheme == "halloapp" {
            guard host == "invite" else { return nil }
            guard path == "/" else { return nil }
        }

        guard let params = components.queryItems else { return nil }
        guard let inviteLink = params.first(where: { $0.name == "g" })?.value else { return nil }

        return inviteLink
    }

    static public func formatGroupInviteLink(_ link: String) -> String {
        var result = "https://halloapp.com/invite/?g="
        result += link
        return result
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
    
    private func chatGroups(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext) -> [Group] {
        let fetchRequest: NSFetchRequest<Group> = Group.fetchRequest()
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
    
    func chatGroup(groupId id: String, in managedObjectContext: NSManagedObjectContext) -> Group? {
        return chatGroups(predicate: NSPredicate(format: "id == %@", id), in: managedObjectContext).first
    }
    
    private func chatGroupMembers(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext) -> [GroupMember] {
        let fetchRequest: NSFetchRequest<GroupMember> = GroupMember.fetchRequest()
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
    
    func chatGroupMember(groupId id: GroupID, memberUserId: UserID, in managedObjectContext: NSManagedObjectContext) -> GroupMember? {
        return chatGroupMembers(predicate: NSPredicate(format: "groupID == %@ && userID == %@", id, memberUserId), in: managedObjectContext).first
    }

    func chatGroupIds(for memberUserId: UserID, in managedObjectContext: NSManagedObjectContext) -> [GroupID] {
        let chatGroupMemberItems = chatGroupMembers(predicate: NSPredicate(format: "userID == %@", memberUserId), in: managedObjectContext)
        return chatGroupMemberItems.map { $0.groupID }
    }
    
    private func chatGroupMessages(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext) -> [ChatGroupMessage] {
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
    
    func chatGroupMessage(with id: String, in managedObjectContext: NSManagedObjectContext) -> ChatGroupMessage? {
        return chatGroupMessages(predicate: NSPredicate(format: "id == %@", id), in: managedObjectContext).first
    }
    
    func groupFeedEvents(with groupID: GroupID, in managedObjectContext: NSManagedObjectContext) -> [GroupEvent] {
        let cutOffDate = Date(timeIntervalSinceNow: -Date.days(31))
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \GroupEvent.timestamp, ascending: true)
        ]

        let fetchRequest = GroupEvent.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "groupID == %@ && timestamp >= %@", groupID, cutOffDate as NSDate)
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false

        do {
            let events = try managedObjectContext.fetch(fetchRequest)
            return events
        }
        catch {
            DDLogError("ChatData/group/fetch-events/error  [\(error)]")
            return []
        }
    }

    private func chatGroupMessageAllInfo(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext) -> [ChatGroupMessageInfo] {
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

    func chatGroupMessageInfo(messageId: String, in managedObjectContext: NSManagedObjectContext) -> ChatGroupMessageInfo? {
        return chatGroupMessageAllInfo(predicate: NSPredicate(format: "chatGroupMessageId == %@", messageId), in: managedObjectContext).first
    }

    func chatGroupMessageInfoForUser(messageId: String, userId: UserID, in managedObjectContext: NSManagedObjectContext) -> ChatGroupMessageInfo? {
        return chatGroupMessageAllInfo(predicate: NSPredicate(format: "chatGroupMessageId == %@ && userId == %@", messageId, userId), in: managedObjectContext).first
    }

    // MARK: Group Core Data Updating

    func updateChatGroup(with groupId: GroupID, block: @escaping (Group) -> (), performAfterSave: (() -> ())? = nil) {
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
        DDLogInfo("ChatData/deleteChatGroup")
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

            let fetchRequest = GroupEvent.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "groupID = %@", groupId)

            do {
                let chatGroupEvents = try managedObjectContext.fetch(fetchRequest)
                DDLogInfo("ChatData/deleteChatGroup/begin count=[\(chatGroupEvents.count)]")
                chatGroupEvents.forEach {
                    managedObjectContext.delete($0)
                }
            }
            catch {
                DDLogError("ChatData/deleteChatGroup/error  [\(error)]")
                return
            }

            // delete feeds
            MainAppContext.shared.feedData.deletePosts(groupId: groupId)

            // delete welcome post
            MainAppContext.shared.nux.deleteWelcomePost(id: groupId)

            self.save(managedObjectContext)
        }
    }

    func deleteChatGroupMember(groupId: GroupID, memberUserId: UserID, in managedObjectContext: NSManagedObjectContext) {
        let fetchRequest = NSFetchRequest<GroupMember>(entityName: GroupMember.entity().name!)
        fetchRequest.predicate = NSPredicate(format: "groupID = %@ && userID = %@", groupId, memberUserId)

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
        guard let groupFeedPost = MainAppContext.shared.feedData.feedPost(with: id, in: managedObjectContext) else { return }
        guard let groupID = groupFeedPost.groupId else { return }

        var groupExist = true

        if isInbound {
            // if group doesn't exist yet, create
            if chatGroup(groupId: groupID, in: managedObjectContext) == nil {
                DDLogDebug("ChatData/group/updateThreadWithGroupFeed/group not exist yet [\(groupID)]")
                groupExist = false
                let chatGroup = Group(context: managedObjectContext)
                chatGroup.id = groupID
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

        var mentionText: NSAttributedString?
        contactStore.performOnBackgroundContextAndWait { contactsManagedObjectContext in
            mentionText = contactStore.textWithMentions(groupFeedPost.rawText, mentions: groupFeedPost.orderedMentions, in: contactsManagedObjectContext)
        }

        // Update Chat Thread
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
        guard let groupFeedPost = MainAppContext.shared.feedData.feedPost(with: id, in: managedObjectContext) else { return }
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

        var contactNames = [UserID:String]()
        // Update push names for member userids on any events received.
        xmppGroup.members?.forEach { inboundMember in
            // add to pushnames
            if let name = inboundMember.name, !name.isEmpty {
                contactNames[inboundMember.userId] = name
            }
        }
        self.contactStore.addPushNames(contactNames)
        // Saving push names early on will help us show push names for events/content from these users.

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
        case .get:
            // Sync group if we get a message from the server.
            syncGroup(xmppGroup)
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
            let groupCreator =  GroupMember(context: managedObjectContext)
            groupCreator.groupID = xmppGroup.groupId
            groupCreator.userID = sender
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
            
            if xmppGroupMember.userId == MainAppContext.shared.userData.userId {
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
        
        var membersAdded: [UserID] = []
        for xmppGroupMember in xmppGroup.members ?? [] {
            guard xmppGroupMember.action == .join else { continue }

            membersAdded.append(xmppGroupMember.userId)
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

        // Update group crypto state.
        if !membersAdded.isEmpty {
            AppContext.shared.messageCrypter.addMembers(userIds: membersAdded, in: xmppGroup.groupId)
        }
        getAndSyncGroup(groupId: xmppGroup.groupId)
    }

    private func processGroupLeaveAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) {
        
        _ = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)

        var membersRemoved: [UserID] = []
        for xmppGroupMember in xmppGroup.members ?? [] {
            DDLogDebug("ChatData/group/process/new/leave-member [\(xmppGroupMember.userId)]")
            guard xmppGroupMember.action == .leave else { continue }
            deleteChatGroupMember(groupId: xmppGroup.groupId, memberUserId: xmppGroupMember.userId, in: managedObjectContext)
            
            recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: xmppGroupMember, in: managedObjectContext)

            membersRemoved.append(xmppGroupMember.userId)
            if xmppGroupMember.userId != MainAppContext.shared.userData.userId {
                getAndSyncGroup(groupId: xmppGroup.groupId)
            }
        }

        // Update group crypto state.
        if !membersRemoved.isEmpty {
            AppContext.shared.messageCrypter.removeMembers(userIds: membersRemoved, in: xmppGroup.groupId)
        }
        // TODO: murali@: should we clear our crypto session here?
        // but what if messages arrive out of order from the server.
    }

    private func processGroupModifyMembersAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) {
        DDLogDebug("ChatData/group/processGroupModifyMembersAction")
        let group = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)

        var membersAdded: [UserID] = []
        var membersRemoved: [UserID] = []
        for xmppGroupMember in xmppGroup.members ?? [] {
            DDLogDebug("ChatData/group/process/modifyMembers [\(xmppGroupMember.userId)]/action: \(String(describing: xmppGroupMember.action))")

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
                membersAdded.append(xmppGroupMember.userId)
                processGroupAddMemberAction(chatGroup: group, xmppGroupMember: xmppGroupMember, in: managedObjectContext)
            case .remove:
                membersRemoved.append(xmppGroupMember.userId)
                deleteChatGroupMember(groupId: xmppGroup.groupId, memberUserId: xmppGroupMember.userId, in: managedObjectContext)
            case .promote:
                if let foundMember = group.members?.first(where: { $0.userID == xmppGroupMember.userId }) {
                    foundMember.type = .admin
                }
            case .demote:
                if let foundMember = group.members?.first(where: { $0.userID == xmppGroupMember.userId }) {
                    foundMember.type = .member
                }
            default:
                break
            }

            recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: xmppGroupMember, in: managedObjectContext)

            if xmppGroupMember.action == .add, xmppGroupMember.userId == MainAppContext.shared.userData.userId {
                showGroupAddNotification(for: xmppGroup)
            }
        }

        // Always add members to group crypto session first and then remove members.
        // This ensures that we clear our outgoing state for sure!
        if !membersAdded.isEmpty {
            AppContext.shared.messageCrypter.addMembers(userIds: membersAdded, in: xmppGroup.groupId)
        }
        if !membersRemoved.isEmpty {
            AppContext.shared.messageCrypter.removeMembers(userIds: membersRemoved, in: xmppGroup.groupId)
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
        let group = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)
        group.desc = xmppGroup.description
        save(managedObjectContext)
        recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: nil, in: managedObjectContext)
        getAndSyncGroup(groupId: xmppGroup.groupId)
    }

    private func processGroupChangeAvatarAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("ChatData/group/processGroupChangeAvatarAction")
        let group = processGroupCreateIfNotExist(xmppGroup: xmppGroup, in: managedObjectContext)
        group.avatarID = xmppGroup.avatarID
        if let avatarID = xmppGroup.avatarID {
            MainAppContext.shared.avatarStore.updateOrInsertGroupAvatar(for: group.id, with: avatarID)
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

    private func processGroupCreateIfNotExist(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) -> Group {
        DDLogDebug("ChatData/group/processGroupCreateIfNotExist/ [\(xmppGroup.groupId)]")
        if let existingChatGroup = chatGroup(groupId: xmppGroup.groupId, in: managedObjectContext) {
            DDLogDebug("ChatData/group/processGroupCreateIfNotExist/groupExist [\(xmppGroup.groupId)]")
            return existingChatGroup
        } else {
            return addGroup(xmppGroup: xmppGroup, in: managedObjectContext)
        }
    }
    
    private func addGroup(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) -> Group {
        DDLogDebug("ChatData/group/addGroup/new [\(xmppGroup.groupId)]")

        // Add Group to database
        let chatGroup = Group(context: managedObjectContext)
        chatGroup.id = xmppGroup.groupId
        chatGroup.name = xmppGroup.name
        
        // Add Chat Thread
        if chatThread(type: .group, id: chatGroup.id, in: managedObjectContext) == nil {
            let chatThread = ChatThread(context: managedObjectContext)
            chatThread.type = ChatType.group
            chatThread.groupId = chatGroup.id
            chatThread.title = chatGroup.name
            chatThread.lastMsgTimestamp = nil
        }
        return chatGroup
    }
    
    private func recordGroupMessageEvent(xmppGroup: XMPPGroup, xmppGroupMember: XMPPGroupMember?, in managedObjectContext: NSManagedObjectContext) {
        DDLogVerbose("ChatData/recordGroupMessageEvent/groupID/\(xmppGroup.groupId)")

        // hack: skip recording the event(s) of an avatar change and/or description change if the changes are done at group creation,
        // since server api require separate requests for them but we want to show only the group creation event
        // rough check by comparing if the last event (also first) was a group creation event and if avatar/description changes happened right after
        let groupFeedEventsList = groupFeedEvents(with: xmppGroup.groupId, in: managedObjectContext)
        if let lastEvent = groupFeedEventsList.last,
           [.create].contains(lastEvent.action),
           lastEvent.memberUserID == xmppGroupMember?.userId,
           [.changeAvatar, .changeDescription].contains(xmppGroup.action),
           let diff = Calendar.current.dateComponents([.second], from: lastEvent.timestamp, to: Date()).second,
           diff < 3 {
            return
        }

        let isCreateEvent = xmppGroup.action == .create
        let sharedNUX = MainAppContext.shared.nux
        let isSampleGroup = sharedNUX.sampleGroupID() == xmppGroup.groupId
        let isSampleGroupCreationEvent = isCreateEvent && isSampleGroup


        let event = GroupEvent(context: managedObjectContext)
        event.senderUserID = xmppGroup.sender
        event.memberUserID = xmppGroupMember?.userId
        event.groupName = xmppGroup.name
        event.groupID = xmppGroup.groupId
        event.timestamp = Date()

        event.action = {
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

        event.memberAction = {
            switch xmppGroupMember?.action {
            case .add: return .add
            case .remove: return .remove
            case .promote: return .promote
            case .demote: return .demote
            case .leave: return .leave
            default: return .none
            }
        }()

        if let chatThread = self.chatThread(type: .group, id: event.groupID, in: managedObjectContext) {

            chatThread.lastFeedUserID = event.senderUserID
            chatThread.lastFeedTimestamp = event.timestamp
            chatThread.lastFeedText = event.text

            if isSampleGroupCreationEvent {
                chatThread.lastFeedText = Localizations.groupFeedWelcomePostTitle
            } else {
                chatThread.lastFeedText = event.text
            }

            // nb: unreadFeedCount is not incremented for group event messages
            // and NUX zero zone unread welcome post count is recorded in NUX userDefaults, not unreadFeedCount
        }

        if isSampleGroupCreationEvent {
            DDLogVerbose("ChatData/recordGroupMessageEvent/groupID/\(xmppGroup.groupId)/isSampleGroupCreationEvent")
            self.updateUnreadThreadGroupsCount() // refresh bottom nav groups badge

            // remove group message and event since this group is created for the user
            managedObjectContext.delete(event)
        }

        save(managedObjectContext)

        didGetAGroupEvent.send(event.groupID)
    }

    private func processGroupAddMemberAction(chatGroup: Group, xmppGroupMember: XMPPGroupMember, in managedObjectContext: NSManagedObjectContext) {
        DDLogDebug("ChatData/group/processGroupAddMemberAction/member [\(xmppGroupMember.userId)]")
        guard let xmppGroupMemberType = xmppGroupMember.type else { return }
        if let existingMember = chatGroupMember(groupId: chatGroup.id, memberUserId: xmppGroupMember.userId, in: managedObjectContext) {
            switch xmppGroupMemberType {
            case .member:
                existingMember.type = .member
            case .admin:
                existingMember.type = .admin
            }
        } else {
            let member = GroupMember(context: managedObjectContext)
            member.groupID = chatGroup.id
            member.userID = xmppGroupMember.userId
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
        DDLogDebug("ChatData/presentGroupAddBanner/id \(xmppGroup.groupId)/checking")
        let groupID = xmppGroup.groupId
        guard let userID = xmppGroup.sender else { return }
        guard let messageID = xmppGroup.messageId else { return }
        let groupName = xmppGroup.name
        let name = contactStore.fullName(for: userID, in: contactStore.viewContext)

        let title = "\(name) @ \(groupName)"
        let body = Localizations.groupsAddNotificationBody

        AppContext.shared.notificationStore.runIfNotificationWasNotPresented(for: messageID) {
            Banner.show(title: title, body: body, groupID: groupID, using: MainAppContext.shared.avatarStore)
        }
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

        handleRerequest(for: messageID, from: userID) { result in
            switch result {
            case .failure(let error):
                DDLogError("ChatData/didRerequestMessage/\(messageID)/error: \(error)/from: \(userID)")
                if error.canAck {
                    ack?()
                }
            case .success:
                DDLogInfo("ChatData/didRerequestMessage/\(messageID)/success/from: \(userID)")
                ack?()
            }
        }
    }

    func halloService(_ halloService: HalloService, didSendMessageReceipt receipt: HalloReceipt) {
        guard receipt.thread == .none else { return }

        updateChatMessage(with: receipt.itemId) { (chatMessage) in
            DDLogDebug("ChatData/oneToOne/didSendMessageReceipt [\(receipt.itemId)]")

            switch receipt.type {
            case .read:
                guard chatMessage.incomingStatus == .haveSeen else { return }
                chatMessage.incomingStatus = .sentSeenReceipt
            case .played:
                guard chatMessage.incomingStatus == .played else { return }
                chatMessage.incomingStatus = .sentPlayedReceipt
            case .delivery:
                break
            }
        }
    }

    func halloService(_ halloService: HalloService, didReceiveGroupMessage group: HalloGroup) {
        processIncomingXMPPGroup(group)
    }

    func halloService(_ halloService: HalloService, didReceiveHistoryResendPayload historyPayload: Clients_GroupHistoryPayload?, withGroupMessage group: HalloGroup) {
        guard let sender = group.sender else {
            DDLogError("ChatData/didReceiveHistoryPayload/invalid group here: \(group)")
            return
        }
        let groupID = group.groupId

        // Check if self is a newly added member to the group
        let memberDetails = historyPayload?.memberDetails
        let ownUserID = userData.userId
        let isSelfANewMember = memberDetails?.contains(where: { $0.uid == Int64(ownUserID) }) ?? false

        // If self is a new member then we can just ignore.
        // Nothing to share with anyone else.
        if isSelfANewMember {
            DDLogInfo("ChatData/didReceiveHistoryPayload/\(groupID)/self is newly added member - ignore historyResend stanza")
            let numExpected = historyPayload?.contentDetails.count ?? 0
            AppContext.shared.cryptoData.resetFeedHistory(groupID: groupID, timestamp: Date(), numExpected: numExpected)
            if let contentDetails = historyPayload?.contentDetails {
                MainAppContext.shared.feedData.createTombstones(for: groupID, with: contentDetails)
            }

        } else if let historyPayload = historyPayload,
                  sender != userData.userId {
            // Members of the group on receiving a historyPayload stanza
            // Must verify keys and hashes and then share the content.
            DDLogInfo("ChatData/didReceiveHistoryPayload/\(groupID)/from: \(sender)/processing")
            processGroupFeedHistoryResend(historyPayload, for: group.groupId, fromUserID: sender)

        } else if sender == userData.userId {
            // For admin who added the members
            // share authored group feed history to all new member uids.
            let newlyAddedMembers = group.members?.filter { $0.action == .add } ?? []
            let newMemberUids = newlyAddedMembers.map{ $0.userId }

            performSeriallyOnBackgroundContext { managedObjectContext in
                let (postsData, commentsData) = MainAppContext.shared.feedData.authoredFeedHistory(for: groupID, in: managedObjectContext)

                DDLogInfo("ChatData/didReceiveHistoryPayload/\(groupID)/from self/processing")
                self.shareGroupFeedItems(posts: postsData, comments: commentsData, in: groupID, to: newMemberUids)
            }
        } else {
            DDLogInfo("ChatData/didReceiveHistoryPayload/\(groupID)/error - unexpected stanza")
        }

    }

    func halloService(_ halloService: HalloService, didReceiveHistoryResendPayload historyPayload: Clients_GroupHistoryPayload, for groupID: GroupID, from fromUserID: UserID) {
        // Members of the group on receiving a historyPayload stanza
        // Must verify keys and hashes and then share the content.
        DDLogInfo("ChatData/didReceiveHistoryPayload/\(groupID)/from: \(fromUserID)/processing")
        processGroupFeedHistoryResend(historyPayload, for: groupID, fromUserID: fromUserID)
    }

    func processGroupFeedHistoryResend(_ historyPayload: Clients_GroupHistoryPayload, for groupID: GroupID, fromUserID: UserID) {
        // Check if sender is in the address book.
        // If yes - then verify the hash of the contents and send them to the new members.
        // Else - log and return

        performSeriallyOnBackgroundContext { managedObjectContext in
            var isContactInAddressBook = false
            self.contactStore.performOnBackgroundContextAndWait { contactsManagedObjectContext in
                isContactInAddressBook = self.contactStore.isContactInAddressBook(userId: fromUserID, in: contactsManagedObjectContext)
            }

            guard isContactInAddressBook else {
                DDLogInfo("ChatData/processGroupFeedHistory/\(groupID)/sendingAdmin is not in address book - ignore historyResend stanza")
                return
            }

            let contentsDetails = historyPayload.contentDetails
            var contentsHashDict = [String: Data]()
            contentsDetails.forEach { contentDetails in
                switch contentDetails.contentID {
                case .postIDContext(let postIdContext):
                    contentsHashDict[postIdContext.feedPostID] = contentDetails.contentHash
                case .commentIDContext(let commentIdContext):
                    contentsHashDict[commentIdContext.commentID] = contentDetails.contentHash
                case .none:
                    break
                }
            }

            let (postsData, commentsData) = MainAppContext.shared.feedData.authoredFeedHistory(for: groupID, in: managedObjectContext)
            var postsToShare: [PostData] = []
            var commentsToShare: [CommentData] = []
            do {
                for post in postsData {
                    let contentData = try post.clientContainer.serializedData()
                    let actualHash = SHA256.hash(data: contentData).data
                    let expectedHash = contentsHashDict[post.id]
                    if let expectedHash = expectedHash,
                       expectedHash == actualHash {
                        postsToShare.append(post)
                    } else {
                        DDLogError("ChatData/processGroupFeedHistory/\(groupID)/post: \(post.id)/hash mismatch/expected: \(String(describing: expectedHash))/actual: \(actualHash)")
                    }
                }
                for comment in commentsData {
                    let contentData = try comment.clientContainer.serializedData()
                    let actualHash = SHA256.hash(data: contentData).data
                    let expectedHash = contentsHashDict[comment.id]
                    if let expectedHash = expectedHash,
                       expectedHash == actualHash {
                        commentsToShare.append(comment)
                    } else {
                        DDLogError("ChatData/processGroupFeedHistory/\(groupID)/comment: \(comment.id)/hash mismatch/expected: \(String(describing: expectedHash))/actual: \(actualHash)")
                    }
                }

                // Fetch identity keys of new members and compare with received keys.
                var numberOfFailedVerifications = 0
                let verifyKeysGroup = DispatchGroup()
                var newMemberUids: [UserID] = []
                let totalNewMemberUids = historyPayload.memberDetails.count
                historyPayload.memberDetails.forEach { memberDetails in
                    verifyKeysGroup.enter()
                    let memberUid = UserID(memberDetails.uid)
                    AppContext.shared.messageCrypter.setupOutbound(for: memberUid) { result in
                        switch result {
                        case .success(let keyBundle):
                            let expected = keyBundle.inboundIdentityPublicEdKey
                            let actual = memberDetails.publicIdentityKey
                            if expected == actual {
                                DDLogInfo("ChatData/processGroupFeedHistory/\(groupID)/verified \(memberUid) successfully")
                                newMemberUids.append(memberUid)
                            } else {
                                DDLogError("ChatData/processGroupFeedHistory/\(groupID)/failed verification of \(memberUid)/expected: \(expected.bytes.prefix(4))/actual: \(actual.bytes.prefix(4))")
                                numberOfFailedVerifications += 1
                            }
                        case .failure(let error):
                            DDLogError("ChatData/processGroupFeedHistory/\(groupID)/failed to verify \(memberUid)/\(error)")
                            numberOfFailedVerifications += 1
                        }
                        verifyKeysGroup.leave()
                    }
                }

                // After verification - share group feed items to the verified new members.
                verifyKeysGroup.notify(queue: .main) { [weak self] in
                    guard let self = self else { return }
                    if numberOfFailedVerifications > 0 {
                        DDLogError("ProtoServiceCore/modifyGroup/\(groupID)/fetchMemberKeysCompletion/error - num: \(numberOfFailedVerifications)/\(totalNewMemberUids)")
                    }

                    // Now encrypt and send the stanza to the verified members.
                    DDLogInfo("ChatData/processGroupFeedHistory/\(groupID)/postsToShare: \(postsToShare.count)/commentsToShare: \(commentsToShare.count)")
                    self.shareGroupFeedItems(posts: postsToShare, comments: commentsToShare, in: groupID, to: newMemberUids)
                }
            } catch {
                DDLogError("ChatData/processGroupFeedHistory/\(groupID)/failed serializing content: \(error)")
            }
        }
    }

    func shareGroupFeedItems(posts: [PostData], comments: [CommentData], in groupID: GroupID, to memberUids: [UserID]) {
        var groupFeedItemsToShare: [Server_GroupFeedItem] = []
        for post in posts {
            if let serverPost = post.serverPost {
                var serverGroupFeedItem = Server_GroupFeedItem()
                switch post.content {
                case .unsupported, .waiting, .moment:
                    // This cannot happen - since we are always sharing our own content.
                    // our own content can never be unsupported or waiting
                    // moments are only for the home feed
                    DDLogError("ChatData/shareGroupFeedItems/\(groupID)/post: \(post.id)/invalid content here: \(post.content)")
                    continue
                case .retracted:
                    serverGroupFeedItem.action = .retract
                case .album, .text, .voiceNote:
                    serverGroupFeedItem.action = .publish
                }
                serverGroupFeedItem.post = serverPost
                serverGroupFeedItem.isResentHistory = true
                groupFeedItemsToShare.append(serverGroupFeedItem)
            } else {
                DDLogError("ChatData/shareGroupFeedItems/\(groupID)/post: \(post.id)/invalid proto")
            }
        }
        for comment in comments {
           if let serverComment = comment.serverComment {
                var serverGroupFeedItem = Server_GroupFeedItem()
               switch comment.content {
               case .unsupported, .waiting:
                   // This cannot happen - since we are always sharing our own content.
                   // our own content can never be unsupported or waiting
                   DDLogError("ChatData/shareGroupFeedItems/\(groupID)/comment: \(comment.id)/invalid content here: \(comment.content)")
                   continue
               case .retracted:
                   serverGroupFeedItem.action = .retract
               case .album, .text, .voiceNote:
                   serverGroupFeedItem.action = .publish
               }
                serverGroupFeedItem.comment = serverComment
               serverGroupFeedItem.isResentHistory = true
                groupFeedItemsToShare.append(serverGroupFeedItem)
            } else {
                DDLogError("ChatData/shareGroupFeedItems/\(groupID)/comment: \(comment.id)/invalid proto")
            }
        }
        DDLogInfo("ChatData/shareGroupFeedItems/\(groupID)/items count: \(groupFeedItemsToShare.count)")
        var groupFeedItemsStanza = Server_GroupFeedItems()
        groupFeedItemsStanza.gid = groupID
        groupFeedItemsStanza.items = groupFeedItemsToShare
        // We need to encrypt this stanza and send it to all the new member uids.
        memberUids.forEach { memberUid in
            service.shareGroupHistory(items: groupFeedItemsStanza, with: memberUid) { result in
                switch result {
                case .success:
                    DDLogInfo("ChatData/shareGroupFeedItems/\(groupID)/sent successfully to \(memberUid)")
                case .failure(let error):
                    DDLogError("ChatData/shareGroupFeedItems/\(groupID)/failed sending to \(memberUid)/error: \(error)")
                }
            }
        }
    }
}
