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

typealias AckInfo = (id: String, timestamp: Date?)

typealias ChatPresenceInfo = (userID: UserID, presence: PresenceType?, lastSeen: Date?)

typealias ChatStateInfo = (from: UserID, threadType: ChatType, threadID: String, type: ChatState, timestamp: Date?)
typealias ChatRetractInfo = (from: UserID, threadType: ChatType, threadID: String, messageID: String)

public enum UserPresenceType: Int16 {
    case none = 0
    case available = 1
    case away = 2
}

class ChatData: NSObject, ObservableObject {

    public var currentPage: Int = 0

    let didGetCurrentChatPresence = PassthroughSubject<(UserID, UserPresenceType, Date?), Never>()
    let didGetChatStateInfo = PassthroughSubject<ChatStateInfo?, Never>()
    
    let didGetMediaUploadProgress = PassthroughSubject<(String, Float), Never>()
    
    let didGetAGroupFeed = PassthroughSubject<GroupID, Never>()
    let didGetAGroupEvent = PassthroughSubject<GroupID, Never>()
    let didResetGroupInviteLink = PassthroughSubject<GroupID, Never>()
    let didUserPresenceChange = PassthroughSubject<PresenceType, Never>()
    
    private let backgroundProcessingQueue = DispatchQueue(label: "com.halloapp.chat")
    private let currentSubscribersQueue = DispatchQueue(label: "com.halloapp.chat.currentsubscribers", qos: .userInitiated)
    private lazy var downloadManager: FeedDownloadManager = {
        let downloadManager = FeedDownloadManager(mediaDirectoryURL: MainAppContext.commonMediaStoreURL)
        downloadManager.delegate = self
        return downloadManager
    }()

    lazy var unreadGroupThreadCountController: CountController<CommonThread> = {
        let fetchRequest = CommonThread.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "groupID != nil && typeValue = %d && unreadCount > 0", GroupType.groupFeed.rawValue)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "groupID", ascending: true)]
        return CountController(fetchRequest: fetchRequest, managedObjectContext: mainDataStore.viewContext)
    }()

    private lazy var friendResultsController: NSFetchedResultsController<UserProfile> = {
        let request = UserProfile.fetchRequest()
        request.propertiesToFetch = ["id", "name"]
        request.predicate = NSPredicate(format: "friendshipStatusValue == %d", UserProfile.FriendshipStatus.friends.rawValue)
        request.sortDescriptors = []
        return .init(fetchRequest: request, managedObjectContext: mainDataStore.viewContext, sectionNameKeyPath: nil, cacheName: nil)
    }()

    private let userData: UserData
    private let mainDataStore: MainDataStore
    private let contactStore: ContactStoreMain
    private var service: HalloService
    private let coreChatData: CoreChatData
    private let userProfileData: UserProfileData
    private let mediaUploader: MediaUploader

    private var currentlySubscribedUsers: [UserID] = []
    private var recentUsersPresenceInfo = [UserID: (UserPresenceType, Date?)]()
    
    private var chatStateInfoList: [ChatStateInfo] = []
    private var chatStateDebounceTimer: Timer? = nil

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
    
    init(service: HalloService, contactStore: ContactStoreMain, mainDataStore: MainDataStore, userData: UserData, coreChatData: CoreChatData, userProfileData: UserProfileData) {
        self.service = service
        self.contactStore = contactStore
        self.userData = userData
        self.mainDataStore = mainDataStore
        self.coreChatData = coreChatData
        self.userProfileData = userProfileData
        self.mediaUploader = MediaUploader(service: service)

        super.init()
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
            service.didGetAck.sink { [weak self] chatAck in
                guard let self = self else { return }
                DDLogInfo("ChatData/didGetAck \(chatAck.id)")
                self.processPotentialChatAck(chatAck)
            }
        )

        cancellableSet.insert(
            service.didGetNewChatMessage.sink { [weak self] incomingMessage in
                self?.processIncomingChatMessage(incomingMessage)
            }
        )

        cancellableSet.insert(
            service.didGetNewGroupChatMessage.sink { [weak self] incomingMessage in
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
                                self.setThreadUnreadFeedCount(type: .groupFeed, for: groupID, num: Int32(numNew))
                            case .seenPosts(_):
                                self.updateChatThread(type: .groupFeed, for: groupID, block: { thread in
                                    guard thread.unreadFeedCount > 0 else { return }
                                    thread.unreadFeedCount = 0
                                })
                            }

                            groupThreadIDs.removeAll(where: { $0 == groupID })
                        })

                        // leftover groupThreadIDs not found in groupFeedStates mean those groups do not have
                        // any posts in feed and should reset its unread counter to 0
                        groupThreadIDs.forEach({
                            self.updateChatThread(type: .groupFeed, for: $0, block: { thread in
                                guard thread.unreadFeedCount > 0 else { return }
                                thread.unreadFeedCount = 0
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
                        let timestamp = call.timestamp

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
                                if !coreChatData.isCurrentlyChatting(with: peerUserID) {
                                    $0.unreadCount += 1
                                }
                            }
                            $0.lastMsgId = callID
                            $0.lastMsgTimestamp = timestamp
                            $0.lastMsgStatus = .none
                        }, performAfterSave: nil)
                    }
                }
            )
        }

        cancellableSet.insert(
            service.didDisconnect.sink { [weak self] in
                guard let self = self else { return }
                DDLogInfo("ChatData/didDisconnect")
                self.clearAllUserSubscriptions()
            }
        )

        cancellableSet.insert(
            service.didConnect.sink { [weak self] in
                guard let self = self else { return }
                DDLogInfo("ChatData/didConnect")
                self.clearAllUserSubscriptions()
                // include inactive as app is still in foreground (one case found is when app is freshly installed and the scene is in transition)
                if ([.active, .inactive].contains(UIApplication.shared.applicationState)) {
                    DDLogInfo("ChatData/didConnect/sendPresence \(UIApplication.shared.applicationState.rawValue)")
                    self.checkViewAndSendPresence(type: .available)

                    if let currentUser = coreChatData.getCurrentlyChattingWithUserId() {
                        self.subscribeToPresence(to: currentUser)
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
                if let currentlyChattingWithUserId = coreChatData.getCurrentlyChattingWithUserId() {
                    self.performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
                        guard let self = self else { return }
                        self.coreChatData.markSeenMessages(type: .oneToOne, for: currentlyChattingWithUserId, in: managedObjectContext)
                        UNUserNotificationCenter.current().removeDeliveredChatNotifications(fromUserId: currentlyChattingWithUserId)
                    }
                }

                // clear the typing indicators
                self.chatStateInfoList.removeAll()
                self.didGetChatStateInfo.send(nil)
            }
        )

        cancellableSet.insert(
            NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification).sink { [weak self] notification in
                guard let self = self else { return }
                self.checkViewAndSendPresence(type: .away)
            }
        )

        userProfileData.completedInitialFriendSyncPublisher
            .sink { [weak self] in
                DDLogInfo("ChatData/completedInitialFriendSync")
                self?.populateThreadsWithFriends()
            }
            .store(in: &cancellableSet)

        cancellableSet.insert(
            userData.didLogIn.sink {
                DDLogInfo("ChatData/didLogIn")
                shouldGetGroupsList = true
            }
        )

        do {
            friendResultsController.delegate = self
            try friendResultsController.performFetch()
        } catch {
            DDLogError("ChatData/init/friendResultsController fetch failed \(String(describing: error))")
        }

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
                DDLogInfo("CoreChatData/saveChatMessage/ creating new thread type: \(legacy.type) userID: \(userID)")
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
        case .groupFeed, .groupChat:
            guard let groupID = legacy.groupId else {
                DDLogError("ChatData/migrateLegacyThread/group/aborting [missing groupID]")
                return
            }
            if let existingThread = chatThread(type: legacy.type, id: groupID, in: managedObjectContext) {
                DDLogInfo("ChatData/migrateLegacyThread/group/existing/\(groupID)")
                thread = existingThread
            } else {
                DDLogInfo("CoreChatData/saveChatMessage/ creating new thread type: \(legacy.type) groupId: \(groupID)")
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
        group.expirationType = .expiresInSeconds
        group.expirationTime = .thirtyDays
        group.lastUpdate = Date()

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

    public func migrateGroupExpiry() {
        do {
            try mainDataStore.saveSeriallyOnBackgroundContextAndWait { context in
                chatGroups(in: context).forEach { group in
                    group.expirationTime = .thirtyDays
                    group.expirationType = .expiresInSeconds

                }
            }
        } catch {
            DDLogError("Failed to migrate chat group expirations")
        }
    }

    // MARK: Friendship migration

    func migrateMessagesToProfiles() throws {
        try mainDataStore.saveSeriallyOnBackgroundContextAndWait { context in
            DDLogInfo("ChatData/migrateMessagesToProfiles/begin")
            connectMessagesToProfiles(context)
            DDLogInfo("ChatData/migrateMessagesToProfiles/finished")
        }
    }

    private func connectMessagesToProfiles(_ context: NSManagedObjectContext) {
        let predicate = NSPredicate(format: "user == nil")
        let messages = chatMessages(predicate: predicate, in: context)

        messages.forEach { $0.user = UserProfile.findOrCreate(with: $0.fromUserID, in: context) }
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
        media.id = "\(message?.id ?? linkPreview?.id ?? UUID().uuidString)-\(legacy.order)"
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
        media.id = "\(quoted.message?.id ?? UUID().uuidString)-quoted-\(legacy.order)"
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

    func migrateChatGroupLastUpdated() {
        DDLogInfo("ChatData/migrateChatGroupLastUpdated/start")
        do {
            try mainDataStore.saveSeriallyOnBackgroundContextAndWait { context in
                for group in chatGroups(predicate: NSPredicate(format: "typeValue = %d", GroupType.groupFeed.rawValue), in: context) {
                    let fetchRequest: NSFetchRequest<FeedPost> = FeedPost.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "groupID == %@", group.id)
                    fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: false)]
                    fetchRequest.returnsObjectsAsFaults = false
                    fetchRequest.fetchLimit = 1

                    do {
                        if let timestamp = try context.fetch(fetchRequest).first?.timestamp {
                            group.lastUpdate = timestamp
                            DDLogInfo("ChatData/migrateChatGroupLastUpdated/updated \(group.id)")
                        }
                    } catch {
                        DDLogError("ChatData/migrateChatGroupLastUpdated/ failed to fetch latest post for \(group.id): \(error)")
                    }
                }
            }
        } catch {
            DDLogError("ChatData/migrateChatGroupLastUpdated error: \(error)")
        }

        DDLogInfo("ChatData/migrateChatGroupLastUpdated/end")
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
                    case .album, .text, .voiceNote, .location, .files:
                        let timestamp = message.timestamp ?? Date()
                        let reinterpretedMessage = XMPPChatMessage(
                            content: chatContainer.chatContent,
                            context: chatContainer.chatContext,
                            timestamp: Int64(timestamp.timeIntervalSince1970),
                            from: message.fromUserId,
                            chatMessageRecipient: message.chatMessageRecipient,
                            id: message.id,
                            retryCount: 0, //TODO
                            rerequestCount: Int32(message.resendAttempts))
                        messagesMigrated += 1
                        self.processIncomingChatMessage(.decrypted(reinterpretedMessage))
                    case .reaction:
                        DDLogInfo("ChatData/processUnsupportedItems/messages/reaction [deleting tombstone] [\(message.id)]")
                        let timestamp = message.timestamp ?? Date()
                        let reinterpretedMessage = XMPPReaction(
                            content: chatContainer.chatContent,
                            context: chatContainer.chatContext,
                            timestamp: Int64(timestamp.timeIntervalSince1970),
                            from: message.fromUserId,
                            chatMessageRecipient: message.chatMessageRecipient,
                            id: message.id,
                            retryCount: 0, //TODO
                            rerequestCount: Int32(message.resendAttempts))
                            messagesMigrated += 1
                            self.processIncomingChatMessage(.decrypted(reinterpretedMessage))
                        self.deleteChatMessage(with: message.id)
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
    func populateThreadsWithFriends() {
        mainDataStore.saveSeriallyOnBackgroundContext { context in
            let friends = UserProfile.find(predicate: .init(format: "friendshipStatusValue == %d", UserProfile.FriendshipStatus.friends.rawValue), in: context)
            let names = friends.reduce(into: [:]) { $0[$1.id] = $1.name }
            DDLogInfo("ChatData/populateThreadsWithFriends [\(friends.count)] friends")

            if friends.isEmpty {
                return
            }

            for (userID, name) in names {
                guard self.chatThread(type: .oneToOne, id: userID, in: context) == nil else {
                    continue
                }

                DDLogInfo("ChatData/populateThreadsWithFriends/creating thread for [\(userID)]")
                let thread = ChatThread(context: context)
                thread.title = name
                thread.userID = userID
                thread.lastMsgUserId = userID
                thread.lastMsgText = nil
                thread.unreadCount = 0
                thread.isNew = false
                thread.type = .oneToOne
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
                chatThread.type = .oneToOne
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
                let fullName = UserProfile.find(with: userID, in: managedObjectContext)?.name ?? ""

                let chatThread = ChatThread(context: managedObjectContext)
                chatThread.title = fullName
                chatThread.userID = userID
                chatThread.lastMsgUserId = userID
                chatThread.lastMsgText = nil
                chatThread.lastMsgTimestamp = Date()
                chatThread.unreadCount = 0
                chatThread.isNew = true
                chatThread.type = .oneToOne
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
        let chatMessageObjectID = chatMessage.objectID
        performSeriallyOnBackgroundContext { [weak self] context in
            guard let self, let chatMessage = try? context.existingObject(with: chatMessageObjectID) as? ChatMessage else {
                DDLogError("ChatData/downloadMedia/could not find chatMessage")
                return
            }
            let contentID = chatMessage.id
            self.downloadChatMedia(mediaItems: chatMessage.media, contentID: contentID)
        }
    }

    func downloadMedia(in linkPreview: CommonLinkPreview) {
        let linkPreviewObjectID = linkPreview.objectID
        performSeriallyOnBackgroundContext { [weak self] context in
            guard let self, let linkPreview = try? context.existingObject(with: linkPreviewObjectID) as? CommonLinkPreview else {
                DDLogError("ChatData/downloadMedia/could not find linkPreview")
                return
            }
            let contentID = linkPreview.id
            self.downloadChatMedia(mediaItems: linkPreview.media, contentID: contentID)
        }
    }

    private func downloadChatMedia(mediaItems: Set<CommonMedia>?, contentID: String) {
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
            var docsDownloaded = 0
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
                case .document: docsDownloaded += 1
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
                guard photosDownloaded > 0 || videosDownloaded > 0 || audiosDownloaded > 0 || docsDownloaded > 0 else { return }
                guard let startTime = startTime else {
                    DDLogError("ChatData/downloadChatMedia/contentID: \(contentID)/error start time not set")
                    return
                }
                let duration = Date().timeIntervalSince(startTime)
                DDLogInfo("ChatData/downloadChatMedia/contentID: \(contentID)/finished [photos: \(photosDownloaded)] [videos: \(videosDownloaded)] [audios: \(audiosDownloaded)] [docs: \(docsDownloaded)] [t: \(duration)] [bytes: \(totalDownloadSize)]")
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
    
    private func processPotentialChatAck(_ chatAck: AckInfo) {
        let messageID = chatAck.id
        
        // search for pending 1-1 message
        updateChatMessageByStatus(for: messageID, status: .pending) { [weak self] (chatMessage) in
            guard let self = self else { return }
            DDLogDebug("ChatData/processPotentialChatAck/updatePendingChatMessage/ [\(messageID)]")

            chatMessage.outgoingStatus = .sentOut
            self.updateChatThreadStatus(chatMessageRecipient: chatMessage.chatMessageRecipient, messageId: chatMessage.id) { (chatThread) in
                chatThread.lastMsgStatus = .sentOut
            }

            // only change timestamp the first time message is ack'ed,
            // rerequests should not, with the assumption resendAttempts are only used for rerequests
            guard chatMessage.resendAttempts == 0 else { return }
            guard let serverTimestamp = chatAck.timestamp else { return }
            chatMessage.serverTimestamp = serverTimestamp

            self.processPendingChatMsgs()
        }
        
        // search for pending 1-1 reaction
        updateReactionByStatus(for: messageID, status: .pending) { [weak self] (reaction) in
            guard let self = self else { return }
            DDLogDebug("ChatData/processPotentialChatAck/updatePendingReaction/ [\(messageID)]")

            reaction.outgoingStatus = .sentOut

            // only change timestamp the first time message is ack'ed,
            // rerequests should not, with the assumption resendAttempts are only used for rerequests
            guard reaction.resendAttempts == 0 else { return }
            guard let serverTimestamp = chatAck.timestamp else { return }
            reaction.serverTimestamp = serverTimestamp

            self.processPendingReactions()
        }

        // search for retracting 1-1 message
        updateRetractingChatMessage(for: messageID) { (chatMessage) in
            DDLogDebug("ChatData/processPotentialChatAck/updateRetractingChatMessage/ [\(messageID)]")
            chatMessage.outgoingStatus = .retracted
            self.updateChatThreadStatus(chatMessageRecipient: chatMessage.chatMessageRecipient, messageId: chatMessage.id) { (chatThread) in
                chatThread.lastMsgStatus = .retracted
            }
        }
        
        // search for retracting 1-1 reactions
        updateRetractingReaction(for: messageID) { (reaction) in
            DDLogDebug("ChatData/processPotentialChatAck/updateRetractingReaction/ [\(messageID)]")
            reaction.outgoingStatus = .retracted
        }

    }
    
    func copyFiles(toChatMedia chatMedia: CommonMedia, fileUrl: URL, encryptedFileUrl: URL?) throws {
        
        var threadId = ""
        var messageId = ""

        if let chatMessage = chatMedia.message, let toUserId = chatMessage.toUserId {
            threadId = toUserId
            messageId = chatMessage.id
        } else if let chatMessage = chatMedia.message, let toGroupId = chatMessage.toGroupId {
            threadId = toGroupId
            messageId = chatMessage.id
        } else if let chatMessage = chatMedia.linkPreview?.message, let toUserId = chatMessage.toUserId {
            threadId = toUserId
            messageId = chatMessage.id
        }

        let filename: String = {
            if let filename = chatMedia.name, !filename.isEmpty {
                return filename
            } else {
                return "\(messageId)-\(chatMedia.order).\(CommonMedia.fileExtension(forMediaType: chatMedia.type))"
            }
        }()
        
        let toUrl = MainAppContext.commonMediaStoreURL
            .appendingPathComponent(threadId, isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
        
        // create intermediate directories
        if !FileManager.default.fileExists(atPath: toUrl.path) {
            do {
                try FileManager.default.createDirectory(at: toUrl.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            } catch {
                DDLogError("\(error.localizedDescription)")
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

    // MARK: Share Extension Merge Data
    
    func mergeData(from sharedDataStore: SharedDataStore, completion: @escaping (() -> ())) {
        DDLogInfo("ChatData/mergeData - \(sharedDataStore.source)/begin")
        let sharedMessageIds = sharedDataStore.chatMessageIds()
        DDLogInfo("ChatData/mergeData/sharedMessageIds: \(sharedMessageIds)")

        sharedDataStore.performSeriallyOnBackgroundContext { [self] sharedManagedObjectContext in
            let messages = sharedDataStore.messages(in: sharedManagedObjectContext)

            performSeriallyOnBackgroundContext { [self] context in
                merge(messages: messages, from: sharedDataStore, using: context)
            }

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

                        mergedMessages.forEach { chatMsg in
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
            chatMessage.forwardCount = chatContext?.forwardCount ?? 0
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

            var lastMsgTextFallback: String?
            switch chatContent {
            case .album(let mentionText, _):
                chatMessage.rawText = mentionText.collapsedText
                chatMessage.mentions = mentionText.mentions.map { (index, user) in
                    return MentionData(index: index, userID: user.userID, name: contactStore.pushNames[user.userID] ?? user.pushName ?? "")
                }
            case .text(let mentionText, _):
                chatMessage.rawText = mentionText.collapsedText
                chatMessage.mentions = mentionText.mentions.map { (index, user) in
                    return MentionData(index: index, userID: user.userID, name: contactStore.pushNames[user.userID] ?? user.pushName ?? "")
                }
            case .voiceNote(_):
                chatMessage.rawText = ""
            case .reaction(let emoji):
                chatMessage.rawText = emoji
            case .location(let chatLocation):
                chatMessage.location = CommonLocation(chatLocation: chatLocation, context: managedObjectContext)
            case .files(let files):
                chatMessage.rawText = ""
                lastMsgTextFallback = files.first?.name
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
                chatMedia.id = "\(linkPreview.id)-\(sharedPreviewMedia.order)"
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
                    chatMedia.name = sharedPreviewMedia.name
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
                chatMedia.id = "\(chatMessage.id)-\(media.order)"
                chatMedia.type = media.type
                if lastMsgMediaType == .none {
                    lastMsgMediaType = CommonThread.lastMediaType(for: media.type)
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
                chatMedia.name = media.name
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

            if chatMessage.location != nil {
                lastMsgMediaType = .location
            }
            
            // Process quoted content.
            if let feedPostId = chatMessage.feedPostId, !feedPostId.isEmpty {
                // Process Quoted Feedpost
                if let quotedFeedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId, in: managedObjectContext) {
                    CoreChatData.copyQuoted(to: chatMessage, from: quotedFeedPost, using: managedObjectContext)
                }
            } else if let chatReplyMsgId = chatMessage.chatReplyMessageID, !chatReplyMsgId.isEmpty {
                // Process Quoted Message: these messages could be in the main database or in the shared database.
                // so we first lookup the main database and then our list of mergedMessages.
                // we ensure that messages are fetched in the correct order.
                if let quotedChatMessage = MainAppContext.shared.chatData.chatMessage(with: chatReplyMsgId, in: managedObjectContext) {
                    CoreChatData.copyQuoted(to: chatMessage, from: quotedChatMessage, using: managedObjectContext)
                } else if let quotedChatMessage = mergedMessages.first(where: { $0.1.id == chatReplyMsgId })?.1 {
                    CoreChatData.copyQuoted(to: chatMessage, from: quotedChatMessage, using: managedObjectContext)
                }
            }

            let isMsgToYourself = chatMessage.chatMessageRecipient.toUserId == userData.userId
            coreChatData.updateChatThreadOnMessageCreate(
                chatMessageRecipient: chatMessage.chatMessageRecipient,
                chatMessage: chatMessage,
                isMsgToYourself: isMsgToYourself,
                lastMsgMediaType: lastMsgMediaType,
                lastMsgText: (chatMessage.rawText ?? "").isEmpty ? lastMsgTextFallback : chatMessage.rawText,
                mentions: chatMessage.mentions,
                using: managedObjectContext)
            mergedMessages.append((message, chatMessage))
        }
        save(managedObjectContext)

        mergedMessages.forEach({ (sharedMsg, chatMsg) in
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

    private func incrementApplicationIconBadgeNumber() {
        DispatchQueue.main.async {
            let badgeNum = MainAppContext.shared.applicationIconBadgeNumber
            MainAppContext.shared.applicationIconBadgeNumber = badgeNum == -1 ? 1 : badgeNum + 1
        }
    }

    // MARK: Helpers
    
    private func isAtChatListViewTop() -> Bool {
        guard
            let keyWindow = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: { $0.isKeyWindow }),
            let tabController = keyWindow.rootViewController?.children.first as? UITabBarController,
            tabController.selectedIndex == HomeViewController.TabBarSelection.chat.index,
            let chatNavigationController = tabController.selectedViewController as? UINavigationController,
            let chatListViewController = chatNavigationController.topViewController as? ChatListViewController
        else {
            return false
        }

        return chatListViewController.isScrolledFromTop(by: 100)
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
                chatMediaItem.fileSize = Int64(task.fileSize ?? 0)
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
        DDLogInfo("ChatData/markThreadAsRead/type: \(type)/id: \(id)")
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            
            if let chatThread = self.chatThread(type: type, id: id, in: managedObjectContext) {
                if chatThread.unreadCount != 0 {
                    chatThread.unreadCount = 0
                }
            }
            DDLogInfo("ChatData/markThreadAsRead/type: \(type)/id: \(id)/set unreadCount to zero")
            self.coreChatData.markSeenMessages(type: type, for: id, in: managedObjectContext)
            
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }

    func markSeenMessages(type: ChatType, for id: String) {
        DDLogInfo("ChatData/markSeenMessages/type: \(type)/id: \(id)")
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            DDLogInfo("ChatData/markSeenMessages/type: \(type)/id: \(id)/without setting unreadCount to zero")
            self.coreChatData.markSeenMessages(type: type, for: id, in: managedObjectContext)
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
        switch type {
        case .oneToOne:
            return commonThreads(predicate: NSPredicate(format: "userID == %@", id), in: managedObjectContext).first
        case .groupFeed, .groupChat:
            return commonThreads(predicate: NSPredicate(format: "groupID == %@", id), in: managedObjectContext).first
        }
    }
    
    func chatThreadStatus(type: ChatType, id: String, messageId: String, in managedObjectContext: NSManagedObjectContext) -> ChatThread? {
        switch type {
        case .oneToOne:
            return commonThreads(predicate: NSPredicate(format: "userID == %@ AND lastContentID == %@", id, messageId), in: managedObjectContext).first
        case .groupFeed, .groupChat:
            return commonThreads(predicate: NSPredicate(format: "groupID == %@ AND lastContentID == %@", id, messageId), in: managedObjectContext).first
        }
    }
    
    // MARK: Thread Core Data Updating
    
    private func updateChatThread(type: ChatType, for id: String, block: @escaping (ChatThread) -> Void, performAfterSave: (() -> ())? = nil) {
        coreChatData.updateChatThread(type: type, for: id, block: block, performAfterSave: performAfterSave)
    }

    private func updateChatThreadStatus(chatMessageRecipient: ChatMessageRecipient, messageId: String, block: @escaping (ChatThread) -> Void) {
        guard let recipientId = chatMessageRecipient.recipientId else {
            DDLogError("ChatData/updateChatThreadStatus/ unable to update chat thread chatMessageId: \(messageId)")
            return
        }
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            guard let chatThread = self.chatThreadStatus(type: chatMessageRecipient.chatType, id: recipientId, messageId: messageId, in: managedObjectContext) else {
                DDLogError("ChatData/updateChatThreadStatus - missing")
                return
            }
            DDLogVerbose("ChatData/updateChatThreadStatus found lastMsgID: [\(messageId)] in threadID: [\(recipientId)]")
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

    public func getTypingIndicatorString(type: ChatType, id: String?, fromUserID: UserID?) -> String? {
        guard let id = id else { return nil }
        
        var typingStr = ""
        var chatStateList: [ChatStateInfo] = []
        
        switch type {
        case .oneToOne:
            chatStateList = chatStateInfoList.filter { $0.threadType == .oneToOne && $0.threadID == id }
            typingStr = Localizations.chatTyping
        case .groupFeed:
            chatStateList = chatStateInfoList.filter { $0.threadType == .groupFeed && $0.threadID == id }
        case .groupChat:
            chatStateList = chatStateInfoList.filter { $0.threadType == .groupChat && $0.threadID == id && $0.from == fromUserID}
            if let fromUserID = fromUserID {
                let name = UserProfile.find(with: fromUserID, in: MainAppContext.shared.mainDataStore.viewContext)?.displayName ?? ""
                typingStr = Localizations.userChatTyping(name: name)
            }
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
                if chatStateInfo.type == .typing {
                    // subscribe to presence for the user when typing indicator is received, we do this so
                    // we can clear typing indicators when we receive offline presence.
                    subscribeToPresence(to: chatStateInfo.from)
                }
            }
        }

        didGetChatStateInfo.send(chatStateInfo)

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
        case .oneToOne, .groupChat:
            performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
                guard let self = self else { return }

                if self.commonReaction(with: chatRetractInfo.messageID, in: managedObjectContext) != nil {
                    self.processInboundReactionRetract(chatRetractInfo: chatRetractInfo)
                } else {
                    self.processInboundChatMessageRetract(chatRetractInfo: chatRetractInfo)
                }
            }
        default:
            return
        }
    }
}

// MARK: 1-1
extension ChatData {
    
    func setCurrentlyChattingWithUserId(for chatWithUserId: String?) {
        coreChatData.setCurrentlyChattingWithUserId(for: chatWithUserId)
    }

    func clearAllUserSubscriptions() {
        currentSubscribersQueue.sync {
            self.currentlySubscribedUsers = []
            self.recentUsersPresenceInfo.removeAll()
        }
    }

    func setCurrentlyChattingInGroup(in groupId: GroupID?) {
        coreChatData.setCurrentlyChattingInGroup(in: groupId)
    }

    func isSubscribedToUser(userId: UserID) -> Bool {
        currentSubscribersQueue.sync {
            return currentlySubscribedUsers.contains(userId)
        }
    }

    func presenceInfoOfUser(_ userID: UserID) -> (UserPresenceType, Date?)? {
        currentSubscribersQueue.sync {
            return recentUsersPresenceInfo[userID]
        }
    }
            
    // MARK: 1-1 Sending Messages
    
    func sendMessage(chatMessageRecipient: ChatMessageRecipient,
                     mentionText: MentionText,
                     media: [PendingMedia],
                     files: [FileSharingData],
                     linkPreviewData: LinkPreviewData? = nil,
                     linkPreviewMedia : PendingMedia? = nil,
                     location: ChatLocationProtocol? = nil,
                     feedPostId: String?,
                     feedPostMediaIndex: Int32,
                     chatReplyMessageID: String? = nil,
                     chatReplyMessageSenderID: UserID? = nil,
                     chatReplyMessageMediaIndex: Int32) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            if let toUserId = chatMessageRecipient.toUserId {
                DDLogInfo("ChatData/sendMessage/createChatMsg/toUserId: \(toUserId)")
                self.coreChatData.addIntent(toUserId: toUserId)
            } else if let toGroupId = chatMessageRecipient.toGroupId {
                DDLogInfo("ChatData/sendMessage/createChatMsg/toGroupId: \(toGroupId)")
                AppContext.shared.coreFeedData.addIntent(groupId: toGroupId)
            }

            self.createChatMsg(chatMessageRecipient: chatMessageRecipient,
                                mentionText: mentionText,
                                media: media,
                                files: files,
                                linkPreviewData: linkPreviewData,
                                linkPreviewMedia : linkPreviewMedia,
                                location: location,
                                feedPostId: feedPostId,
                                feedPostMediaIndex: feedPostMediaIndex,
                                chatReplyMessageID: chatReplyMessageID,
                                chatReplyMessageSenderID: chatReplyMessageSenderID,
                                chatReplyMessageMediaIndex: chatReplyMessageMediaIndex,
                                using: managedObjectContext)
        }
    }

    func forwardChatMessages(toUserIds: [String], toChatGroupIDs: [GroupID], chatMessage: ChatMessage) {
        // Prepare chat message
        var media: [PendingMedia] = []
        var files: [FileSharingData] = []
        var linkPreviewData: LinkPreviewData? = nil
        var linkPreviewMedia: PendingMedia? = nil
        var chatLocation: ChatLocation? = nil
        if let chatMedia = chatMessage.media {
            for mediaItem in chatMedia {
                guard let url = mediaItem.mediaURL else {
                    continue
                }
                switch mediaItem.type {
                case .image, .audio, .video:
                    let pendingMedia = PendingMedia(type: mediaItem.type)
                    pendingMedia.size = mediaItem.size
                    pendingMedia.fileURL = url
                    DDLogInfo("forwardChatMessages \(mediaItem.order) : \(Int(mediaItem.order))")
                    pendingMedia.order = Int(mediaItem.order)
                    if mediaItem.type == .video {
                        pendingMedia.originalVideoURL = url
                    }
                    media.append(pendingMedia)
                case .document:
                    DDLogInfo("forwardChatMessages \(mediaItem.order) [document]")
                    let fileData = FileSharingData(
                        name: mediaItem.name ?? "file",
                        size: Int(mediaItem.fileSize),
                        localURL: url)
                    files.append(fileData)
                }
            }
        }
        if let linkPreviews = chatMessage.linkPreviews {
            for sourceLinkPreview in linkPreviews {
                linkPreviewData = LinkPreviewData(id: nil, url: sourceLinkPreview.url, title: sourceLinkPreview.title ?? "", description: sourceLinkPreview.description , previewImages: [])
                if let mediaItem = sourceLinkPreview.media?.first, let url = mediaItem.mediaURL {
                    let pendingMedia = PendingMedia(type: mediaItem.type)
                    pendingMedia.size = mediaItem.size
                    switch mediaItem.type {
                    case .image:
                        pendingMedia.fileURL = url
                        linkPreviewMedia = pendingMedia
                    default:
                        break
                    }
                }
            }
        }

        if let location = chatMessage.location {
            chatLocation = ChatLocation(latitude: location.latitude, longitude: location.longitude, name: location.name ?? "", formattedAddressLines: [location.addressString ?? ""])
        }

        let mentionText = MentionText(collapsedText: chatMessage.rawText ?? "", mentionArray: chatMessage.mentions)

        // Create chat message
        // Increment forward count if current user is not the author of the message.
        let forwardCount = (chatMessage.fromUserID == userData.userId) ? chatMessage.forwardCount : chatMessage.forwardCount + 1
        for toUserId in toUserIds {
            DDLogInfo("ChatData/forwardChatMessages/createChatMsg/chatMessageId: \(chatMessage.id) toUserId: \(toUserId)")
            performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
                guard let self = self else { return }
                self.createChatMsg( chatMessageRecipient: ChatMessageRecipient.oneToOneChat(toUserId: toUserId, fromUserId: self.userData.userId),
                                    mentionText: mentionText,
                                    media: media,
                                    files: files,
                                    linkPreviewData: linkPreviewData,
                                    linkPreviewMedia : linkPreviewMedia,
                                    location: chatLocation,
                                    feedPostId: nil,
                                    feedPostMediaIndex: 0,
                                    chatReplyMessageID: nil,
                                    chatReplyMessageSenderID: nil,
                                    chatReplyMessageMediaIndex: 0,
                                    forwardCount: forwardCount,
                                    using: managedObjectContext)
            }
        }
        for groupID in toChatGroupIDs {
            DDLogInfo("ChatData/forwardChatMessages/createChatMsg/chatMessageId: \(chatMessage.id) toGroupID: \(groupID)")
            performSeriallyOnBackgroundContext { [weak self] managedObjectContext in
                guard let self = self else {
                    return
                }
                guard self.chatGroup(groupId: groupID, in: managedObjectContext)?.type == .groupChat else {
                    DDLogError("ChatData/forwardChatMessages/createChatMsg/invalid chat group id: \(groupID)")
                    return
                }
                self.createChatMsg(chatMessageRecipient: .groupChat(toGroupId: groupID, fromUserId: self.userData.userId),
                                   mentionText: mentionText,
                                   media: media,
                                   files: files,
                                   linkPreviewData: linkPreviewData,
                                   linkPreviewMedia: linkPreviewMedia,
                                   location: chatLocation,
                                   feedPostId: nil,
                                   feedPostMediaIndex: 0,
                                   chatReplyMessageID: nil,
                                   chatReplyMessageSenderID: nil,
                                   chatReplyMessageMediaIndex: 0,
                                   forwardCount: forwardCount,
                                   using: managedObjectContext)
            }
        }
    }

    /// - Returns: A chat message object that should be used on the main thread.
    @discardableResult
    func sendMomentReply(chatMessageRecipient: ChatMessageRecipient, postID: FeedPostID, text: String, media: [PendingMedia], files: [FileSharingData]) async -> ChatMessage? {
        await withCheckedContinuation { continuation in
            performSeriallyOnBackgroundContext { context in
                DDLogInfo("ChatData/sendMomentReply/createChatMsg/toUserId: \(String(describing: chatMessageRecipient.toUserId))")
                let id = self.createChatMsg(chatMessageRecipient: chatMessageRecipient,
                               mentionText: MentionText(collapsedText: text, mentionArray: []),
                               media: media,
                               files: files,
                     linkPreviewData: nil,
                    linkPreviewMedia: nil,
                            location: nil,
                          feedPostId: postID,
                  feedPostMediaIndex: 0,
                       isMomentReply: true,
          chatReplyMessageMediaIndex: 0,
                               using: context)

                DispatchQueue.main.async {
                    let message = self.chatMessage(with: id, in: self.viewContext)
                    continuation.resume(returning: message)
                }
            }
        }
    }

    @discardableResult
    func createChatMsg(chatMessageRecipient: ChatMessageRecipient,
                       mentionText: MentionText,
                        media: [PendingMedia],
                        files: [FileSharingData],
                        linkPreviewData: LinkPreviewData?,
                        linkPreviewMedia : PendingMedia?,
                        location: ChatLocationProtocol?,
                        feedPostId: String?,
                        feedPostMediaIndex: Int32,
                        isMomentReply: Bool = false,
                        chatReplyMessageID: String? = nil,
                        chatReplyMessageSenderID: UserID? = nil,
                        chatReplyMessageMediaIndex: Int32,
                        forwardCount: Int32 = 0,
                        using context: NSManagedObjectContext) -> ChatMessageID {
        coreChatData.createChatMsg(chatMessageRecipient: chatMessageRecipient,
                                          mentionText: mentionText,
                                          media: media,
                                          files: files,
                                          linkPreviewData: linkPreviewData,
                                          linkPreviewMedia: linkPreviewMedia,
                                          location: location,
                                          feedPostId: feedPostId,
                                          feedPostMediaIndex: feedPostMediaIndex,
                                          isMomentReply: isMomentReply,
                                          chatReplyMessageID: chatReplyMessageID,
                                          chatReplyMessageSenderID: chatReplyMessageSenderID,
                                          chatReplyMessageMediaIndex: chatReplyMessageMediaIndex,
                                          forwardCount: forwardCount,
                                          using: context)
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
            linkPreviewData.previewImages.enumerated().forEach { (index, previewMedia) in
                let media = CommonMedia(context: context)
                media.id = "\(linkPreview.id)-\(index)"
                media.type = previewMedia.type
                media.outgoingStatus = .none
                media.incomingStatus = .pending
                media.url = previewMedia.url
                media.size = previewMedia.size
                media.key = previewMedia.key
                media.sha256 = previewMedia.sha256
                media.linkPreview = linkPreview
                media.order = Int16(index)
                media.name = previewMedia.name
            }
            linkPreview.message = chatMessage
        }
    }
 
    private enum ChatMediaType {
        case chatMedia1
        case linkPreviewMedia1
    }

    private func send(message: ChatMessageProtocol) {
        service.sendChatMessage(message) { _ in
            MainAppContext.shared.endBackgroundTask(message.id)
        }
    }

    func retractChatMessage(chatMessage: ChatMessage, messageToRetractID: String) {
        let messageID = PacketID.generate()

        updateChatMessage(with: messageToRetractID) { [weak self] (chatMessage) in
            guard let self = self else { return }
            guard [.sentOut, .delivered, .seen, .retracting].contains(chatMessage.outgoingStatus) else { return }

            chatMessage.retractID = messageID
            chatMessage.outgoingStatus = .retracting
            
            self.deleteChatMessageContent(in: chatMessage)
            self.updateChatThreadStatus(chatMessageRecipient: chatMessage.chatMessageRecipient, messageId: chatMessage.id) { (chatThread) in
                chatThread.lastMsgStatus = .retracting
                chatThread.lastMsgText = nil
                chatThread.lastMsgMediaType = .none
            }
        }
        if let toUserId = chatMessage.toUserId {
            self.service.retractChatMessage(messageID: messageID, toUserID: toUserId, messageToRetractID: messageToRetractID) { result in
                switch result {
                case .failure(let error):
                    DDLogError("ChatData/retractChatMessage: \(messageToRetractID)/failed: \(error)")
                case .success:
                    DDLogInfo("ChatData/retractChatMessage: \(messageToRetractID)/success")
                }
            }
        } else if let toGroupId = chatMessage.toGroupId {
            self.service.retractGroupChatMessage(messageID: messageID, groupID: toGroupId, messageToRetractID: messageToRetractID) { result in
                switch result {
                case .failure(let error):
                    DDLogError("ChatData/retractGroupChatMessage: \(messageToRetractID)/failed: \(error)")
                case .success:
                    DDLogInfo("ChatData/retractGroupChatMessage: \(messageToRetractID)/success")
                }
            }
        } else {
            DDLogError("ChatData/retractChatMessage: \(messageToRetractID)/failed: recipient Id not set")
        }
    }
    
    // MARK: 1-1 Reaction
    func sendReaction(chatMessageRecipient: ChatMessageRecipient,
                      reaction: String,
                      chatMessageID: ChatMessageID) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            DDLogInfo("ChatData/sendReaction/createReaction/recipientId: \(String(describing: chatMessageRecipient.recipientId)) type: \(chatMessageRecipient.chatType)")
            self.createReaction(chatMessageRecipient: chatMessageRecipient,
                                reaction: reaction,
                                chatMessageID: chatMessageID,
                                using: managedObjectContext)
        }
        if let toUserId = chatMessageRecipient.toUserId {
            DDLogInfo("ChatData/sendReaction/toUserId: \(toUserId)")
            self.coreChatData.addIntent(toUserId: toUserId)
        } else if let toGroupId = chatMessageRecipient.toGroupId {
            DDLogInfo("ChatData/sendReaction/toGroupId: \(toGroupId)")
            AppContext.shared.coreFeedData.addIntent(groupId: toGroupId)
        }
    }

    @discardableResult
    func createReaction(chatMessageRecipient: ChatMessageRecipient,
                        reaction: String,
                        chatMessageID: ChatMessageID,
                        using context: NSManagedObjectContext) -> CommonReactionID {
        let reactionId = PacketID.generate()
        let isMsgToYourself: Bool = chatMessageRecipient.toUserId == userData.userId

        // Create and save new ChatMessage object.
        DDLogDebug("ChatData/createReaction/\(reactionId)/recipientId: \(String(describing: chatMessageRecipient.recipientId)) type: \(chatMessageRecipient.chatType)")
        let commonReaction = CommonReaction(context: context)
        commonReaction.id = reactionId
        commonReaction.chatMessageRecipient = chatMessageRecipient
        commonReaction.fromUserID = userData.userId
        commonReaction.emoji = reaction
        commonReaction.incomingStatus = .none
        commonReaction.outgoingStatus = isMsgToYourself ? .seen : .pending
        commonReaction.timestamp = Date()
        
        var reactionText = String(format: Localizations.chatListYouReactedMessage, commonReaction.emoji)
        if let message = MainAppContext.shared.chatData.chatMessage(with: chatMessageID, in: context) {
            commonReaction.message = message
            if let media = message.media, media.count == 1 {
                let mediaType = media.first?.type
                switch mediaType {
                case .video:
                    reactionText = String(format: Localizations.chatListYouReactedVideo, commonReaction.emoji)
                case .audio:
                    reactionText = String(format: Localizations.chatListYouReactedAudio, commonReaction.emoji)
                case .image:
                    reactionText = String(format: Localizations.chatListYouReactedImage, commonReaction.emoji)
                case .document:
                    reactionText = String(format: Localizations.chatListYouReactedMessage, commonReaction.emoji)
                case .none:
                    break
                }
            } else if let text = message.rawText, !text.isEmpty {
                reactionText = String(format: Localizations.chatListYouReactedText, commonReaction.emoji, "\"\(text)\"")
            }
        }
        save(context)

        // Update Chat Thread
        let lastMsgStatus = isMsgToYourself ? ChatThread.LastMsgStatus.seen : ChatThread.LastMsgStatus.pending
        switch chatMessageRecipient {
        case .oneToOneChat(let toUserId, _):
            updateChatThread(chatType: .oneToOne, with: commonReaction,
                             recipientId: toUserId,
                             reactionText: reactionText,
                             in: context,
                             lastMsgStatus: lastMsgStatus,
                             updateUnreadCount: false)
        case .groupChat(let groupId, _):
            updateChatThread(chatType: .groupChat, with: commonReaction,
                             recipientId: groupId,
                             reactionText: reactionText,
                             in: context,
                             lastMsgStatus: lastMsgStatus,
                             updateUnreadCount: false)
        }
        save(context)

        if !isMsgToYourself {
            processPendingReactions()
        }

        return reactionId
    }

    func retractReaction(commonReaction: CommonReaction, reactionToRetractID: String) {
        let retractID = PacketID.generate()

        updateReaction(with: reactionToRetractID) { [weak self] (commonReaction) in
            guard let self = self, let chatMessageRecipient = commonReaction.chatMessageRecipient else { return }

            commonReaction.retractID = retractID
            commonReaction.outgoingStatus = .retracting
            
            var reactionText = String(format: Localizations.chatListYouDeletedReactionMessage, commonReaction.emoji)
            if let message = commonReaction.message {
                if let media = message.media, media.count == 1 {
                    let mediaType = media.first?.type
                    switch mediaType {
                    case .video:
                        reactionText = String(format: Localizations.chatListYouDeletedReactionVideo, commonReaction.emoji)
                    case .audio:
                        reactionText = String(format: Localizations.chatListYouDeletedReactionAudio, commonReaction.emoji)
                    case .image:
                        reactionText = String(format: Localizations.chatListYouDeletedReactionImage, commonReaction.emoji)
                    case .document:
                        reactionText = String(format: Localizations.chatListYouDeletedReactionMessage, commonReaction.emoji)
                    case .none:
                        break
                    }
                } else if let text = message.rawText, !text.isEmpty {
                    reactionText = String(format: Localizations.chatListYouDeletedReactionText, commonReaction.emoji, "\"\(text)\"")
                }
            }
            
            self.deleteReaction(commonReaction: commonReaction)
            self.updateChatThreadStatus(chatMessageRecipient: chatMessageRecipient, messageId: commonReaction.id) { (chatThread) in
                chatThread.lastMsgStatus = .retracting
                chatThread.lastMsgText = reactionText
                chatThread.lastMsgMediaType = .none
            }
        }

        if let toUserID = commonReaction.toUserID {
            self.service.retractChatMessage(messageID: retractID, toUserID: toUserID, messageToRetractID: reactionToRetractID) { result in
                switch result {
                case .failure(let error):
                    DDLogError("ChatData/retractChatReaction: \(reactionToRetractID)/failed: \(error)")
                case .success:
                    DDLogInfo("ChatData/retractChatReaction: \(reactionToRetractID)/success")
                }
            }
        } else if let toGroupID = commonReaction.toGroupID {
            self.service.retractGroupChatMessage(messageID: retractID, groupID: toGroupID, messageToRetractID: reactionToRetractID) { result in
                switch result {
                case .failure(let error):
                    DDLogError("ChatData/retractGroupChatReaction: \(reactionToRetractID)/failed: \(error)")
                case .success:
                    DDLogInfo("ChatData/retractGroupChatReaction: \(reactionToRetractID)/success")
                }
            }
        } else {
            DDLogInfo("ChatData/retractGroupChatReaction: \(reactionToRetractID)/error - recipientID not set")
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
    
    private func commonReactions(predicate: NSPredicate? = nil,
                                sortDescriptors: [NSSortDescriptor]? = nil,
                                limit: Int? = nil,
                                in managedObjectContext: NSManagedObjectContext) -> [CommonReaction] {
        let fetchRequest: NSFetchRequest<CommonReaction> = CommonReaction.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        if let fetchLimit = limit { fetchRequest.fetchLimit = fetchLimit }
        fetchRequest.returnsObjectsAsFaults = false

        do {
            let reactions = try managedObjectContext.fetch(fetchRequest)
            return reactions
        }
        catch {
            DDLogError("ChatData/fetch-reactions/error  [\(error)]")
            fatalError("Failed to fetch reactions")
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
    
    func commonReaction(with id: String, in managedObjectContext: NSManagedObjectContext) -> CommonReaction? {
        return self.commonReactions(predicate: NSPredicate(format: "id == %@", id), in: managedObjectContext).first
    }
    
    func chatLinkPreview(with id: String, in managedObjectContext: NSManagedObjectContext) -> CommonLinkPreview? {
        return self.linkPreviews(predicate: NSPredicate(format: "id == %@", id), in: managedObjectContext).first
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
    
    func pendingOutgoingReactions(in managedObjectContext: NSManagedObjectContext) -> [CommonReaction] {
        let sortDescriptors = [
            NSSortDescriptor(keyPath: \CommonReaction.timestamp, ascending: true)
        ]
        return commonReactions(predicate: NSPredicate(format: "fromUserID = %@ && outgoingStatusValue = %d && message != nil", userData.userId, CommonReaction.OutgoingStatus.pending.rawValue), sortDescriptors: sortDescriptors, in: managedObjectContext)
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

    private func createNewChatMessageIfMissing(chatRetractInfo: ChatRetractInfo, status: ChatMessage.IncomingStatus) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self, self.chatMessage(with: chatRetractInfo.messageID, in: managedObjectContext) == nil else {
                return
            }
            DDLogWarn("ChatData/createNewChatMessageIfMissing/from: \(chatRetractInfo.from)/messageID: \(chatRetractInfo.messageID)/status: \(status)/messages might be out of order")
            let timestamp = Date()
            let chatMessage = ChatMessage(context: managedObjectContext)
            chatMessage.id = chatRetractInfo.messageID
            chatMessage.fromUserId = chatRetractInfo.from
            switch chatRetractInfo.threadType {
            case .oneToOne:
                chatMessage.toUserId = self.userData.userId
            case .groupChat:
                chatMessage.toGroupId = chatRetractInfo.threadID
            case .groupFeed:
                break
            }

            chatMessage.incomingStatus = status
            chatMessage.outgoingStatus = .none
            chatMessage.timestamp = timestamp
            chatMessage.serverTimestamp = timestamp
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }

    private func createNewChatThreadIfMissing(chatRetractInfo: ChatRetractInfo, status: ChatThread.LastMsgStatus) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            // TODO NOTE this was previously self.chatThreadStatus WHY?
            guard let self = self, self.chatThread(type: chatRetractInfo.threadType, id: chatRetractInfo.threadID, in: managedObjectContext) == nil else {
                return
            }
            DDLogWarn("ChatData/createNewChatThreadIfMissing/from: \(chatRetractInfo.from)/messageID: \(chatRetractInfo.messageID)/status: \(status)/messages might be out of order")
            let timestamp = Date()
            let chatThread = ChatThread(context: managedObjectContext)
            switch chatRetractInfo.threadType {
            case .oneToOne:
                chatThread.userID = chatRetractInfo.threadID
            case .groupChat:
                chatThread.groupId = chatRetractInfo.threadID
            default:
                break
            }
            chatThread.lastMsgUserId = chatRetractInfo.from
            chatThread.lastMsgTimestamp = timestamp
            chatThread.lastMsgStatus = status
            chatThread.lastMsgText = nil
            chatThread.lastMsgMediaType = .none
            chatThread.type = chatRetractInfo.threadType
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    private func updateChatThread(chatType: ChatType,
                                  with commonReaction: CommonReaction,
                                  recipientId: String,
                                  reactionText: String,
                                  in context: NSManagedObjectContext,
                                  lastMsgStatus: CommonThread.LastMsgStatus,
                                  updateUnreadCount: Bool) {
        let isCurrentlyChattingWithUser = coreChatData.isCurrentlyChatting(with: commonReaction.fromUserID)
        if let chatThread = self.chatThread(type: chatType, id: recipientId, in: context) {
            DDLogDebug("ChatData/updateChatThread/with-reaction/update-thread")
            chatThread.lastMsgId = commonReaction.id
            chatThread.lastMsgUserId = commonReaction.fromUserID
            chatThread.lastMsgText = reactionText
            chatThread.lastMsgMediaType = .none
            chatThread.lastMsgStatus = lastMsgStatus
            chatThread.lastMsgTimestamp = commonReaction.timestamp
            if updateUnreadCount {
                chatThread.unreadCount = chatThread.unreadCount + 1
            }
        } else {
            DDLogDebug("ChatData/updateChatThread/with-reaction/new-thread")
            let chatThread = ChatThread(context: context)
            switch chatType {
            case .oneToOne:
                chatThread.userID = recipientId
                chatThread.groupId = nil
                chatThread.type = chatType
            case .groupChat, .groupFeed:
                chatThread.userID = nil
                chatThread.groupId = recipientId
                chatThread.type = chatType
            }

            chatThread.lastMsgId = commonReaction.id
            chatThread.lastMsgUserId = commonReaction.fromUserID
            chatThread.lastMsgText = reactionText
            chatThread.lastMsgMediaType = .none
            chatThread.lastMsgStatus = lastMsgStatus
            chatThread.lastMsgTimestamp = commonReaction.timestamp
            if updateUnreadCount {
                chatThread.unreadCount = isCurrentlyChattingWithUser ? 0 : chatThread.unreadCount + 1
            }
        }
        save(context)
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
    
    private func updateReaction(with reactionId: String, block: @escaping (CommonReaction) -> (), performAfterSave: (() -> ())? = nil) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            defer {
                if let performAfterSave = performAfterSave {
                    performAfterSave()
                }
            }
            guard let self = self else { return }
            guard let commonReaction = self.commonReaction(with: reactionId, in: managedObjectContext) else {
                DDLogError("ChatData/update-reaction/missing [\(reactionId)]")
                return
            }
            DDLogVerbose("ChatData/update-existing-reaction [\(reactionId)]")
            block(commonReaction)
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
    
    private func updateReactionByStatus(for id: String, status: CommonReaction.OutgoingStatus, block: @escaping (CommonReaction) -> ()) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            let sortDescriptors = [
                NSSortDescriptor(keyPath: \CommonReaction.timestamp, ascending: true)
            ]
            guard let reaction = self.commonReactions(predicate: NSPredicate(format: "outgoingStatusValue = %d && id == %@", status.rawValue, id), sortDescriptors: sortDescriptors, in: managedObjectContext).first else {
                return
            }
            
            DDLogVerbose("ChatData/updateReactionByStatus [\(id)]")
            block(reaction)
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
    
    private func updateRetractingReaction(for id: String, block: @escaping (CommonReaction) -> ()) {

        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            let sortDescriptors = [
                NSSortDescriptor(keyPath: \CommonReaction.timestamp, ascending: true)
            ]
            guard let reaction = self.commonReactions(predicate: NSPredicate(format: "outgoingStatusValue = %d && retractID == %@", CommonReaction.OutgoingStatus.retracting.rawValue, id), sortDescriptors: sortDescriptors, in: managedObjectContext).first else {
                return
            }
            
            DDLogVerbose("ChatData/updateRetractingCommonReaction [\(id)]")
            block(reaction)
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

        // Delete temporary files
        DispatchQueue.global(qos: .background).async {
            let cutoffDate = Date().addingTimeInterval(-3 * 24 * 60 * 60) // 3 days ago
            let tmpDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            FileManager.default.enumerator(at: tmpDirectory, includingPropertiesForKeys: [.contentModificationDateKey])?.forEach { fileURL in
                guard let fileURL = fileURL as? URL,
                      let modificationDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                      modificationDate <= cutoffDate else {
                    return
                }
                DDLogInfo("ChatData/cleanUpOldUploadData/deleting temp file: \(fileURL)")
                do {
                    try FileManager.default.removeItem(at: fileURL)
                } catch {
                    DDLogError("ChatData/cleanUpOldUploadData/failed to delete temp file: \(fileURL)")
                }
            }
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
        // Create our own context so we don't block the main queue, this can be a lengthy operation
        let context = mainDataStore.persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.perform {
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
                if let media = MainAppContext.shared.mainDataStore.commonMediaItem(id: fileNameWithIndex, in: context) {
                    guard media.status == .uploaded else {
                        return
                    }
                    DDLogInfo("ChatData/cleanUpOldUploadData/clean up existing media upload data: \(media.relativeFilePath ?? "")")
                    ImageServer.cleanUpUploadData(directoryURL: directoryURL, relativePath: media.relativeFilePath)
                } else if let chatMessage = MainAppContext.shared.chatData.chatMessage(with: msgID, in: context) {
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
    }

    // MARK: 1-1 Core Data Deleting

    func deleteChat(chatThreadId: String) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }

            // delete all chat events and chat thread
            if let chatThread = self.chatThread(type: ChatType.oneToOne, id: chatThreadId, in: managedObjectContext) {
                if let chatWithUserId = chatThread.userID {
                    self.coreChatData.deleteChatEvents(userID: chatWithUserId)
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
        }

        MainAppContext.shared.mainDataStore.deleteCalls(with: chatThreadId)
    }

    public func deleteChatMessage(with id: ChatMessageID) {
        DDLogDebug("ChatData/deleteChatmessage/message \(id)")

        performSeriallyOnBackgroundContext { [weak self] context in
            guard let self = self, let chatMessage = self.chatMessage(with: id, in: context) else {
                return
            }
            // Clear out the last message info from the chat thread.
            self.updateChatThreadStatus(chatMessageRecipient: chatMessage.chatMessageRecipient, messageId: chatMessage.id) { (chatThread) in
                chatThread.lastMsgStatus = .none
                chatThread.lastMsgText = nil
                chatThread.lastMsgMediaType = .none
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
        chatMessage.forwardCount = 0
        
        self.deleteMedia(in: chatMessage)

        // delete link previews.
        chatMessage.linkPreviews?.forEach { linkPreview in
            chatMessage.managedObjectContext?.delete(linkPreview)
        }
        chatMessage.media = nil
        chatMessage.quoted = nil
    }
    
    private func deleteReaction(commonReaction: CommonReaction) {
        DDLogDebug("ChatData/deleteReaction/reaction \(commonReaction.id) ")
        guard let parentMessage = commonReaction.message else {
            DDLogError("ChatData/deleteReaction/no parent message")
            return
        }
        if let reactionToDelete = parentMessage.sortedReactionsList.filter({ $0.id == commonReaction.id }).last {
                parentMessage.managedObjectContext?.delete(reactionToDelete)
        }
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

// MARK: - ChatData + NSFetchedResultsControllerDelegate

extension ChatData: NSFetchedResultsControllerDelegate {

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch (controller, type) {
        case (friendResultsController, .insert):
            guard let profile = anObject as? UserProfile else {
                break
            }
            DDLogInfo("ChatData/controllerDidChangeContent/new friend [\(profile.id)]")
            self.updateThreadsWithDiscoveredUsers(for: [profile.id: profile.name])

        default:
            break
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
                    switch chatMessage.content {
                    case .reaction(_):
                        self.processInboundReaction(xmppReaction: chatMessage, using: managedObjectContext, isAppActive: isAppActive)
                    case .album, .text, .voiceNote, .location, .files, .unsupported:
                        self.processInboundChatMessage(xmppChatMessage: chatMessage, using: managedObjectContext, isAppActive: isAppActive)
                    }
                case .notDecrypted(let tombstone):
                    DDLogInfo("ChatData/processIncomingChatMessage/tombstone \(tombstone.id)")
                    self.processInboundTombstone(tombstone, using: managedObjectContext)
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
        chatMessage.chatMessageRecipient = tombstone.chatMessageRecipient
        chatMessage.timestamp = tombstone.timestamp
        let serialID = MainAppContext.shared.getchatMsgSerialId()
        DDLogDebug("ChatData/processInboundTombstone/\(tombstone.id)/serialId [\(serialID)]")
        chatMessage.serialID = serialID
        chatMessage.incomingStatus = .rerequesting
        chatMessage.outgoingStatus = .none

        save(managedObjectContext)
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
        chatMessage.chatMessageRecipient = xmppChatMessage.chatMessageRecipient
        chatMessage.fromUserId = xmppChatMessage.fromUserId
        chatMessage.user = UserProfile.findOrCreate(with: xmppChatMessage.fromUserId, in: managedObjectContext)
        chatMessage.feedPostId = xmppChatMessage.context.feedPostID
        chatMessage.feedPostMediaIndex = xmppChatMessage.context.feedPostMediaIndex
        
        chatMessage.chatReplyMessageID = xmppChatMessage.context.chatReplyMessageID
        chatMessage.chatReplyMessageSenderID = xmppChatMessage.context.chatReplyMessageSenderID
        chatMessage.chatReplyMessageMediaIndex = xmppChatMessage.context.chatReplyMessageMediaIndex
        chatMessage.forwardCount = xmppChatMessage.context.forwardCount
        
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

        var lastMsgTextFallback: String?
        var lastMsgMediaType: ChatThread.LastMediaType = .none // going with the first media found
        
        // Process chat content
        switch xmppChatMessage.content {
        case .album(let mentionText, let media):
            chatMessage.rawText = mentionText.collapsedText
            chatMessage.mentions = mentionText.mentionsArray
            for (index, xmppMedia) in media.enumerated() {
                guard let downloadUrl = xmppMedia.url else { continue }

                DDLogDebug("ChatData/process/new/add-media [\(downloadUrl)]")
                let chatMedia = CommonMedia(context: managedObjectContext)
                chatMedia.id = "\(chatMessage.id)-\(index)"
                chatMedia.type = xmppMedia.mediaType
                if lastMsgMediaType == .none {
                    lastMsgMediaType = CommonThread.lastMediaType(for: xmppMedia.mediaType)
                }
                chatMedia.incomingStatus = .pending
                chatMedia.outgoingStatus = .none
                chatMedia.url = xmppMedia.url
                chatMedia.size = xmppMedia.size
                chatMedia.key = xmppMedia.key
                chatMedia.order = Int16(index)
                chatMedia.sha256 = xmppMedia.sha256
                chatMedia.message = chatMessage
                chatMedia.name = xmppMedia.name
            }
        case .voiceNote(let xmppMedia):
            guard let downloadUrl = xmppMedia.url else { break }

            DDLogDebug("ChatData/process/new/add-media [\(downloadUrl)]")

            chatMessage.rawText = ""
            lastMsgMediaType = .audio

            let chatMedia = CommonMedia(context: managedObjectContext)
            chatMedia.id = "\(chatMessage.id)-0"
            chatMedia.type = .audio
            chatMedia.incomingStatus = .pending
            chatMedia.outgoingStatus = .none
            chatMedia.url = xmppMedia.url
            chatMedia.size = xmppMedia.size
            chatMedia.key = xmppMedia.key
            chatMedia.order = 0
            chatMedia.sha256 = xmppMedia.sha256
            chatMedia.message = chatMessage
            chatMedia.name = xmppMedia.name
        case .files(let files):
            for (index, xmppMedia) in files.enumerated() {
                guard let downloadUrl = xmppMedia.url else { break }

                DDLogDebug("ChatData/process/new/add-media [\(downloadUrl)]")

                chatMessage.rawText = ""
                lastMsgMediaType = .document
                lastMsgTextFallback = xmppMedia.name

                let chatMedia = CommonMedia(context: managedObjectContext)
                chatMedia.id = "\(chatMessage.id)-\(index)"
                chatMedia.type = .document
                chatMedia.incomingStatus = .pending
                chatMedia.outgoingStatus = .none
                chatMedia.url = xmppMedia.url
                chatMedia.size = xmppMedia.size
                chatMedia.key = xmppMedia.key
                chatMedia.order = 0
                chatMedia.sha256 = xmppMedia.sha256
                chatMedia.message = chatMessage
                chatMedia.name = xmppMedia.name
            }
        case .text(let mentionText, let linkPreviewData):
            chatMessage.rawText = mentionText.collapsedText
            chatMessage.mentions = mentionText.mentionsArray
            addLinkPreview( chatMessage: chatMessage, linkPreviewData: linkPreviewData, using: managedObjectContext)
        case .reaction(let emoji):
            DDLogDebug("ChatData/processInboundChatMessage/processing reaction as message")
            chatMessage.rawText = emoji
        case .location(let chatLocation):
            chatMessage.location = CommonLocation(chatLocation: chatLocation, context: managedObjectContext)
            lastMsgMediaType = .location
        case .unsupported(let data):
            chatMessage.rawData = data
            chatMessage.incomingStatus = .unsupported
        }

        // Process quoted content.
        if let feedPostId = xmppChatMessage.context.feedPostID {
            // Process Quoted Feedpost
            if let quotedFeedPost = MainAppContext.shared.feedData.feedPost(with: feedPostId, in: managedObjectContext) {
                if quotedFeedPost.isMoment {
                    CoreChatData.copyQuotedMoment(to: chatMessage,
                                                  from: quotedFeedPost,
                                                  selfieLeading: quotedFeedPost.isMomentSelfieLeading,
                                                  using: managedObjectContext)
                } else {
                    CoreChatData.copyQuoted(to: chatMessage, from: quotedFeedPost, using: managedObjectContext)
                }
            }
        } else if let chatReplyMsgId = xmppChatMessage.context.chatReplyMessageID {
            // Process Quoted Message
            if let quotedChatMessage = MainAppContext.shared.chatData.chatMessage(with: chatReplyMsgId, in: managedObjectContext) {
                CoreChatData.copyQuoted(to: chatMessage, from: quotedChatMessage, using: managedObjectContext)
            }
        }

        save(managedObjectContext) // extra save

        let lastMsgText = (chatMessage.rawText ?? "").isEmpty ? lastMsgTextFallback : chatMessage.rawText

        // Update Chat Thread
        coreChatData.updateChatThreadOnMessageCreate(chatMessageRecipient: xmppChatMessage.chatMessageRecipient, chatMessage: chatMessage, isMsgToYourself: false, lastMsgMediaType: lastMsgMediaType, lastMsgText: lastMsgText, mentions: chatMessage.mentions, using: managedObjectContext)

        save(managedObjectContext)

        var isCurrentlyChattingWithUser = false
        switch chatMessage.chatMessageRecipient {
        case .oneToOneChat(_, let fromUserId):
            isCurrentlyChattingWithUser = coreChatData.isCurrentlyChatting(with: fromUserId)
        case .groupChat(let groupId, _):
            isCurrentlyChattingWithUser = coreChatData.isCurrentlyChatting(in: groupId)
        }
        
        if isCurrentlyChattingWithUser && isAppActive && (chatMessage.incomingStatus != .unsupported) && (chatMessage.incomingStatus != .rerequesting) {
            self.coreChatData.sendReceipt(for: chatMessage, type: .read)
            self.updateChatMessage(with: chatMessage.id) { (chatMessage) in
                chatMessage.incomingStatus = .haveSeen
            }
        }

        showChatNotification(for: xmppChatMessage)
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

    // MARK: 1-1 Process Inbound Reactions
    private func processInboundReaction(xmppReaction: ChatMessageProtocol, using managedObjectContext: NSManagedObjectContext, isAppActive: Bool) {
        let existingReaction = commonReaction(with: xmppReaction.id, in: managedObjectContext)
        if let existingReaction = existingReaction {
            switch existingReaction.incomingStatus {
            case .unsupported, .none, .rerequesting:
                DDLogInfo("ChatData/process/already-exists/updating [\(existingReaction.incomingStatus)] [\(xmppReaction.id)]")
                break
            case .error, .incoming, .retracted:
                DDLogError("ChatData/process/already-exists/error [\(existingReaction.incomingStatus)] [\(xmppReaction.id)]")
                return
            }
        }
        DDLogDebug("ChatData/processInboundReaction [\(xmppReaction.id)]")
        let commonReaction: CommonReaction = {
            guard let existingReaction = existingReaction else {
                let existingTombstone = self.chatMessage(with: xmppReaction.id, in: managedObjectContext)
                if let existingTombstone = existingTombstone, existingTombstone.incomingStatus == .rerequesting {
                    //Delete tombstone
                    DDLogInfo("ChatData/processInboundReaction/deleteTombstone [\(existingTombstone.id)]")
                    managedObjectContext.delete(existingTombstone)
                }
                DDLogDebug("ChatData/process/new [\(xmppReaction.id)]")
                return CommonReaction(context: managedObjectContext)
            }
            DDLogDebug("ChatData/process/updating rerequested reaction [\(xmppReaction.id)]")
            return existingReaction
        }()

        commonReaction.id = xmppReaction.id
        commonReaction.chatMessageRecipient = xmppReaction.chatMessageRecipient
        commonReaction.fromUserID = xmppReaction.fromUserId
        switch xmppReaction.content {
        case .reaction(let emoji):
            commonReaction.emoji = emoji
        case .album, .text, .voiceNote, .location, .files, .unsupported:
            DDLogError("ChatData/processInboundReaction content not reaction type")
        }
        if let chatReplyMsgId = xmppReaction.context.chatReplyMessageID {
            // Remove reaction from the same author on the same content if any.
            if let duplicateReaction = self.coreChatData.commonReaction(from: xmppReaction.fromUserId, on: chatReplyMsgId, in: managedObjectContext) {
                managedObjectContext.delete(duplicateReaction)
                DDLogInfo("ChatData/processInboundReaction/remove-old-reaction/reactionID [\(duplicateReaction.id)]")
            }
            // Process Quoted Message
            if let message = MainAppContext.shared.chatData.chatMessage(with: chatReplyMsgId, in: managedObjectContext) {
                commonReaction.message = message
            }
        }

        commonReaction.incomingStatus = .incoming
        commonReaction.outgoingStatus = .none

        if let ts = xmppReaction.timeIntervalSince1970 {
            commonReaction.timestamp = Date(timeIntervalSince1970: ts)
        } else {
            commonReaction.timestamp = Date()
        }

        let fromUserID = commonReaction.fromUserID
        let fromUserName = UserProfile.find(with: fromUserID, in: managedObjectContext)?.displayName ?? ""
        var reactionText = String(format: Localizations.chatListUserReactedMessage, fromUserName, commonReaction.emoji)
        if let message = commonReaction.message {
            if let media = message.media, media.count == 1 {
                let mediaType = media.first?.type
                switch mediaType {
                case .video:
                    reactionText = String(format: Localizations.chatListUserReactedVideo, fromUserName, commonReaction.emoji)
                case .audio:
                    reactionText = String(format: Localizations.chatListUserReactedAudio, fromUserName, commonReaction.emoji)
                case .image:
                    reactionText = String(format: Localizations.chatListUserReactedImage, fromUserName, commonReaction.emoji)
                case .document:
                    reactionText = String(format: Localizations.chatListUserReactedMessage, fromUserName, commonReaction.emoji)
                case .none:
                    break
                }
            } else if let text = message.rawText, !text.isEmpty {
                reactionText = String(format: Localizations.chatListUserReactedText, fromUserName, commonReaction.emoji, "\"\(text)\"")
            }
        }
        // Update Chat Thread
        switch xmppReaction.chatMessageRecipient {
        case .oneToOneChat(_, let fromUserId):
            updateChatThread(chatType: .oneToOne, with: commonReaction,
                             recipientId: fromUserId,
                             reactionText: reactionText,
                             in: managedObjectContext,
                             lastMsgStatus: .none,
                             updateUnreadCount: true)
        case .groupChat(let groupId, _):
            updateChatThread(chatType: .groupChat, with: commonReaction,
                             recipientId: groupId,
                             reactionText: reactionText,
                             in: managedObjectContext,
                             lastMsgStatus: .none,
                             updateUnreadCount: true)
        }
        

        save(managedObjectContext)

        showChatNotification(for: xmppReaction)

        // remove user from typing state
        removeFromChatStateList(from: xmppReaction.fromUserId, threadType: .oneToOne, threadID: xmppReaction.fromUserId, type: .available)
    }
    
    // MARK: 1-1 Process Inbound Receipts
    
    private func processInboundMessageReceipt(with receipt: XMPPReceipt, chatMessage: ChatMessage) {
        DDLogInfo("ChatData/processInboundMessageReceipt")
        switch chatMessage.chatMessageRecipient.chatType {
        case .oneToOne:
            self.processInboundOneToOneMessageReceipt(with: receipt)
        case .groupChat:
            self.processInboundGroupMessageReceipt(with: receipt, chatMessage: chatMessage)
        case .groupFeed:
            DDLogError("ChatData/processInboundMessageReceipt/ invalid receipt type received")
        }
    }
    private func processInboundOneToOneMessageReceipt(with receipt: XMPPReceipt) {
        let messageId = receipt.itemId
        updateChatMessage(with: messageId) { [weak self] (chatMessage) in
            guard let self = self else { return }
            DDLogInfo("ChatData/processInboundOneToOneMessageReceipt")
            let receiptType = receipt.type
            guard ![.played, .seen, .retracting, .retracted].contains(chatMessage.outgoingStatus) || receiptType == .played else { return }
            switch receiptType {
            case .delivery:
                chatMessage.outgoingStatus = .delivered
            case .read:
                chatMessage.outgoingStatus = .seen
            case .played:
                chatMessage.outgoingStatus = .played
            case .screenshot, .saved:
                DDLogError("ChatData/processInboundOneToOneMessageReceipt/processing invalid \(receiptType) receipt")
                break
            }
            self.updateChatThreadStatus(chatMessageRecipient: chatMessage.chatMessageRecipient, messageId: chatMessage.id) { (chatThread) in
                switch receiptType {
                case .delivery:
                    chatThread.lastMsgStatus = .delivered
                case .read:
                    chatThread.lastMsgStatus = .seen
                case .played:
                    chatThread.lastMsgStatus = .played
                case .screenshot, .saved:
                    break
                }
            }
        }
    }

    private func processInboundGroupMessageReceipt(with receipt: XMPPReceipt, chatMessage: ChatMessage) {
        DDLogInfo("ChatData/processInboundGroupMessageReceipt")
        let receiptType = receipt.type
        let messageId = receipt.itemId
        // Group chat message has already been updated to its final state, no further updates needed
        guard ![.played, .seen, .retracting, .retracted].contains(chatMessage.outgoingStatus) || receiptType == .played else { return }
        switch receiptType {
        case .delivery:
            updateChatReceiptInfo(with: messageId, userId: receipt.userId) { [weak self] (chatReceiptInfo) in
                guard let self = self else { return }
                if chatReceiptInfo.outgoingStatus == .none {
                    chatReceiptInfo.outgoingStatus = .delivered
                    chatReceiptInfo.timestamp = Date()
                }

                let groupMessage = chatReceiptInfo.chatMessage
                guard groupMessage.outgoingStatus != .seen && groupMessage.outgoingStatus != .played && groupMessage.outgoingStatus != .delivered else {
                    return
                }
                let orderedInfo = groupMessage.orderedInfo
                let delivered = orderedInfo.filter {
                    $0.outgoingStatus == .delivered || $0.outgoingStatus == .seen
                }

                if delivered.count == orderedInfo.count {
                    groupMessage.outgoingStatus = .delivered

                    self.updateChatThreadStatus(chatMessageRecipient: groupMessage.chatMessageRecipient, messageId: groupMessage.id) { (chatThread) in
                        chatThread.lastMsgStatus = .delivered
                    }
                }
            }
        case .read:
            updateChatReceiptInfo(with: messageId, userId: receipt.userId) { [weak self] (chatReceiptInfo) in
                guard let self = self else { return }
                if (chatReceiptInfo.outgoingStatus == .none || chatReceiptInfo.outgoingStatus == .delivered) {
                    chatReceiptInfo.outgoingStatus = .seen
                    chatReceiptInfo.timestamp = Date()
                }

                let groupMessage = chatReceiptInfo.chatMessage
                guard groupMessage.outgoingStatus != .seen && groupMessage.outgoingStatus != .played else { return }
                let orderedInfo = groupMessage.orderedInfo
                let seen = orderedInfo.filter {
                    $0.outgoingStatus == .seen
                }

                if seen.count == orderedInfo.count {
                    groupMessage.outgoingStatus = .seen

                    self.updateChatThreadStatus(chatMessageRecipient: groupMessage.chatMessageRecipient, messageId: groupMessage.id) { (chatThread) in
                        chatThread.lastMsgStatus = .seen
                    }
                }
            }
        case .played:
            updateChatReceiptInfo(with: messageId, userId: receipt.userId) { [weak self] (chatReceiptInfo) in
                guard let self = self else { return }
                if (chatReceiptInfo.outgoingStatus == .none || chatReceiptInfo.outgoingStatus == .delivered || chatReceiptInfo.outgoingStatus == .seen) {
                    chatReceiptInfo.outgoingStatus = .played
                    chatReceiptInfo.timestamp = Date()
                }

                let groupMessage = chatReceiptInfo.chatMessage
                guard groupMessage.outgoingStatus != .played else { return }
                let orderedInfo = groupMessage.orderedInfo
                let played = orderedInfo.filter {
                    $0.outgoingStatus == .played
                }

                if played.count == orderedInfo.count {
                    groupMessage.outgoingStatus = .played

                    self.updateChatThreadStatus(chatMessageRecipient: groupMessage.chatMessageRecipient, messageId: groupMessage.id) { (chatThread) in
                        chatThread.lastMsgStatus = .played
                    }
                }
            }
        case .screenshot, .saved:
            DDLogError("ChatData/processInboundGroupMessageReceipt/processing invalid \(receiptType) receipt")
            break
        }
    }

    func updateChatReceiptInfo(with chatMessageId: String, userId: UserID, block: @escaping (ChatReceiptInfo) -> Void) {
        performSeriallyOnBackgroundContext { (managedObjectContext) in
            guard let chatReceiptInfo = self.chatReceiptInfoForUser(messageId: chatMessageId, userId: userId, in: managedObjectContext) else {
                DDLogError("ChatData/updateChatReceiptInfo/ missing message id: [\(chatMessageId)]")
                return
            }
            DDLogVerbose("ChatData/updateChatReceiptInfo/update-messageInfo")
            block(chatReceiptInfo)
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
    
    private func processInboundOneToOneReactionReceipt(with receipt: XMPPReceipt) {
        DDLogInfo("ChatData/processInboundOneToOneReactionReceipt")
        let messageId = receipt.itemId
        let receiptType = receipt.type
        
        updateReaction(with: messageId) { [weak self] (reaction) in
            guard self != nil else { return }
            guard ![.seen, .retracting, .retracted].contains(reaction.outgoingStatus) else { return }

            switch receiptType {
            case .delivery:
                reaction.outgoingStatus = .delivered
            case .read:
                reaction.outgoingStatus = .seen
            case .played, .screenshot, .saved:
                DDLogError("ChatData/processInboundOneToOneReactionReceipt/processing incompatible \(receiptType) receipt")
                break
            }
        }
    }
    
    // MARK: 1-1 Process Inbound Retract Message
    
    private func processInboundChatMessageRetract(chatRetractInfo: ChatRetractInfo) {
        DDLogInfo("ChatData/processInboundChatMessageRetract")

        createNewChatMessageIfMissing(chatRetractInfo: chatRetractInfo, status: .retracted)

        updateChatMessage(with: chatRetractInfo.messageID) { [weak self] (chatMessage) in
            guard let self = self else { return }

            chatMessage.incomingStatus = .retracted

            self.deleteChatMessageContent(in: chatMessage)

            self.createNewChatThreadIfMissing(chatRetractInfo: chatRetractInfo, status: .retracted)
            self.updateChatThreadStatus(chatMessageRecipient: chatMessage.chatMessageRecipient, messageId: chatMessage.id) { (chatThread) in
                chatThread.lastMsgStatus = .retracted

                chatThread.lastMsgText = nil
                chatThread.lastMsgMediaType = .none
            }
        }
    }
    
    private func processInboundReactionRetract(chatRetractInfo: ChatRetractInfo) {
        DDLogInfo("ChatData/processInboundReactionRetract")

        updateReaction(with: chatRetractInfo.messageID) { [weak self] (commonReaction) in
            guard let self = self, let chatMessageRecipient = commonReaction.chatMessageRecipient else { return }

            commonReaction.incomingStatus = .retracted

            self.deleteReaction(commonReaction: commonReaction)

            let fromUserID = commonReaction.fromUserID
            var fromUserName = ""
            if let context = commonReaction.managedObjectContext {
                fromUserName = UserProfile.find(with: fromUserID, in: context)?.name ?? ""
            }
            var reactionText = String(format: Localizations.chatListUserDeletedReactionMessage, fromUserName, commonReaction.emoji)
            if let message = commonReaction.message {
                if let media = message.media, media.count == 1 {
                    let mediaType = media.first?.type
                    switch mediaType {
                    case .video:
                        reactionText = String(format: Localizations.chatListUserDeletedReactionVideo, fromUserName, commonReaction.emoji)
                    case .audio:
                        reactionText = String(format: Localizations.chatListUserDeletedReactionAudio, fromUserName, commonReaction.emoji)
                    case .image:
                        reactionText = String(format: Localizations.chatListUserDeletedReactionImage, fromUserName, commonReaction.emoji)
                    case .document:
                        reactionText = String(format: Localizations.chatListUserDeletedReactionMessage, fromUserName, commonReaction.emoji)
                    case .none:
                        break
                    }
                } else if let text = message.rawText, !text.isEmpty {
                    reactionText = String(format: Localizations.chatListUserDeletedReactionText, fromUserName, commonReaction.emoji, "\"\(text)\"")
                }
            }
            self.createNewChatThreadIfMissing(chatRetractInfo: chatRetractInfo, status: .retracted)
            self.updateChatThreadStatus(chatMessageRecipient: chatMessageRecipient, messageId: commonReaction.id) { (chatThread) in
                chatThread.lastMsgStatus = .retracted
                chatThread.lastMsgText = reactionText
                chatThread.lastMsgMediaType = .none
            }
        }
    }
}
    
extension ChatData {

    // MARK: 1-1 Presence
    
    func subscribeToPresence(to chatWithUserId: String) {
        guard isSubscribedToUser(userId: chatWithUserId) == false else { return }
        if service.subscribeToPresenceIfPossible(to: chatWithUserId) {
            currentSubscribersQueue.sync {
                currentlySubscribedUsers.append(chatWithUserId)
            }
        }
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
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: { $0.isKeyWindow }),
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

        currentSubscribersQueue.async {
            self.recentUsersPresenceInfo[presenceInfo.userID] = (presenceStatus, presenceLastSeen)
        }
                
        // notify chatViewController
        if let currentlyChattingWithUserId = coreChatData.getCurrentlyChattingWithUserId() {
            guard currentlyChattingWithUserId == presenceInfo.userID else { return }
            didGetCurrentChatPresence.send((presenceInfo.userID, presenceStatus, presenceLastSeen))
            // remove user from typing state
            if presenceInfo.presence == .away {
                removeFromChatStateList(from: currentlyChattingWithUserId, threadType: .oneToOne, threadID: currentlyChattingWithUserId, type: .available)
            }
        } else if let currentlyChattingInGroup = coreChatData.getCurrentlyChattingInGroup() {
            guard (MainAppContext.shared.chatData.chatGroupMember(groupId: currentlyChattingInGroup, memberUserId: presenceInfo.userID, in: viewContext) != nil) else { return }
            // process user presence for group chat to clear typing indicators.
            didGetCurrentChatPresence.send((presenceInfo.userID, presenceStatus, presenceLastSeen))
            // remove user from typing state
            if presenceInfo.presence == .away {
                removeFromChatStateList(from: currentlyChattingInGroup, threadType: .groupChat, threadID: currentlyChattingInGroup, type: .available)
            }
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

            pendingOutgoingChatMessages.forEach { self.coreChatData.beginMediaUploadAndSend(chatMessage: $0) }
        }
    }

    private func processPendingReactions() {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            let pendingOutgoingReactions = self.pendingOutgoingReactions(in: managedObjectContext)
            DDLogInfo("ChatData/processPendingReactions/num: \(pendingOutgoingReactions.count)")

            pendingOutgoingReactions.forEach { pendingReaction in
                if let xmppReaction = XMPPReaction(chatReaction: pendingReaction) {
                    self.send(message: xmppReaction)
                } else {
                    DDLogError("ChatData/processPendingReactions/could not send reaction with id \(pendingReaction.id)")
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
                guard let chatMsg = self.chatMessage(with: $0.id, in: managedObjectContext) else { return }
                guard chatMsg.retractID != nil else { return }
                DDLogInfo("ChatData/processRetractingChatMsgs \($0.id)")
                let msgToRetractID = chatMsg.id

                self.retractChatMessage(chatMessage: chatMsg, messageToRetractID: msgToRetractID)
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
                self.coreChatData.sendReceipt(for: $0, type: .read)
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
                self.coreChatData.sendReceipt(for: $0, type: .played)
            }
        }
    }
}

// MARK: 1-1 Local Notifications
extension ChatData {
    
    private func showChatNotification(for xmppChatMessage: ChatMessageProtocol) {
        DDLogVerbose("ChatData/showChatNotification")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            switch UIApplication.shared.applicationState {
            case .background, .inactive:
                self.presentLocalOneToOneNotifications(for: xmppChatMessage)
            case .active:
                guard !self.isAtChatListViewTop() else {
                    DDLogVerbose("ChatData/showChatNotification/isAtChatListViewTop/skip")
                    return
                }
                guard self.coreChatData.getCurrentlyChattingWithUserId() != xmppChatMessage.fromUserId else {
                    DDLogVerbose("ChatData/showChatNotification/currentlyChattingWithUserId/skip")
                    return
                }
                if let groupId = xmppChatMessage.chatMessageRecipient.toGroupId, self.coreChatData.isCurrentlyChatting(in: groupId) {
                    DDLogVerbose("ChatData/showChateNotification/currentlyChattingInGroup/skip")
                    return
                }
                if let groupId = xmppChatMessage.chatMessageRecipient.toGroupId, self.coreChatData.isCurrentlyChatting(in: groupId) {
                    DDLogVerbose("ChatData/showChateNotification/currentlyChattingInGroup/skip")
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
        
        let name = UserProfile.find(with: userID, in: MainAppContext.shared.mainDataStore.viewContext)?.displayName
        var groupName: String? = nil
        if let groupId = xmppChatMessage.chatMessageRecipient.toGroupId {
            groupName = chatGroup(groupId: groupId, in: viewContext)?.name
        }
        let title = [name, groupName].compactMap({ $0 }).joined(separator: " @ ")

        let attributedBody = NSMutableAttributedString(string: "", attributes: [ .font: UIFont.TextStyle.subheadline ])
        switch xmppChatMessage.content {
        case .text(let mentionText, _):
            if let body = UserProfile.text(with: mentionText.orderedMentions,
                                           collapsedText: mentionText.collapsedText,
                                           in: MainAppContext.shared.mainDataStore.viewContext) {
                attributedBody.append(body)
            }
            
        case .album(let mentionText, let media):
            let mediaStr: String? = {
                guard let firstMedia = media.first else { return nil }
                switch firstMedia.mediaType {
                case .image: return "📷"
                case .video: return "📹"
                case .audio: return "🎤"
                case .document: return "📄"
                }
            }()
            if let mediaStr = mediaStr {
                attributedBody.append(NSAttributedString(string: mediaStr))
            }
            if let body = UserProfile.text(with: mentionText.orderedMentions,
                                           collapsedText: mentionText.collapsedText,
                                           in: MainAppContext.shared.mainDataStore.viewContext) {
                attributedBody.append(body)
            }
        case .voiceNote(_):
            attributedBody.append(NSAttributedString(string: "🎤"))
        case .location(_):
            attributedBody.append(NSAttributedString(string: "📍"))
        case .reaction(let emoji):
            attributedBody.append(NSAttributedString(string: String(format: Localizations.chatUserReactedMessage, emoji)))
        case .files(let files):
            let filenames = files.compactMap { $0.name }
            var bodyComponents: [String?] = ["📄", filenames.first]
            if filenames.count > 1 {
                bodyComponents.append("...")
            }
            let body = bodyComponents.compactMap { $0 }.joined(separator: " ")
            attributedBody.append(NSAttributedString(string: body))
        case .unsupported(_):
            break
        }
        AppContext.shared.notificationStore.runIfNotificationWasNotPresented(for: messageID) {
            Banner.show(title: title, body: nil, attributedBody: attributedBody, userID: userID, groupID: xmppChatMessage.chatMessageRecipient.toGroupId, type: xmppChatMessage.chatMessageRecipient.chatType, using: MainAppContext.shared.avatarStore)
        }
    }
    
    private func presentLocalOneToOneNotifications(for xmppChatMessage: ChatMessageProtocol) {
        DDLogDebug("ChatData/presentLocalOneToOneNotifications")
        let userID = xmppChatMessage.fromUserId
        
        guard let ts = xmppChatMessage.timeIntervalSince1970 else { return }
        let timestamp = Date(timeIntervalSinceReferenceDate: ts)
        let protoContainer = xmppChatMessage.protoContainer
        let protobufData = try? protoContainer?.serializedData()
        var groupName: String? = nil
        if let groupId = xmppChatMessage.chatMessageRecipient.toGroupId, let group = chatGroup(groupId: groupId, in: viewContext) {
            groupName = group.name
        }
        let metadata = NotificationMetadata(contentId: xmppChatMessage.id,
                                            contentType: xmppChatMessage.chatMessageRecipient.chatType == .groupChat ? .groupChatMessage : .chatMessage,
                                            fromId: userID,
                                            groupId: xmppChatMessage.chatMessageRecipient.toGroupId,
                                            groupType: xmppChatMessage.chatMessageRecipient.chatType,
                                            groupName: groupName,
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

    public func createGroup(name: String,
                            description: String,
                            groupType: GroupType,
                            members: [UserID],
                            avatarData: Data?,
                            expirationType: Group.ExpirationType,
                            expirationTime: Int64,
                            completion: @escaping ServiceRequestCompletion<String>) {
        MainAppContext.shared.service.createGroup(name: name, expiryType: expirationType.serverExpiryType, expiryTime: expirationTime, groupType: groupType, members: members) { [weak self] result in
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

                if let avatarData = avatarData {
                    dispatchGroup.enter()
                    self.changeGroupAvatar(groupID: groupID, data: avatarData) { result in
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
    
    private func updateGroupName(for groupID: GroupID, groupType: GroupType, with name: String, completion: @escaping () -> ()) {
        let group = DispatchGroup()
            
        group.enter()
        updateChatGroup(with: groupID, block: { (chatGroup) in
            guard chatGroup.name != name else { return }
            chatGroup.name = name
        }, performAfterSave: {
            group.leave()
        })

        group.enter()
        updateChatThread(type: groupType, for: groupID, block: { (chatThread) in
            guard chatThread.title != name else { return }
            chatThread.title = name
        }, performAfterSave: {
            group.leave()
        })
        
        group.notify(queue: backgroundProcessingQueue) {
            completion()
        }
    }
    
    public func changeGroupName(groupID: GroupID, type: GroupType, name: String, completion: @escaping ServiceRequestCompletion<Void>) {
        MainAppContext.shared.service.changeGroupName(groupID: groupID, name: name) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.updateGroupName(for: groupID, groupType: type, with: name) {
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
        coreChatData.syncGroup(xmppGroup)
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

    func chatGroupMemberUserIDs(groupID: GroupID, in context: NSManagedObjectContext) -> [UserID] {
        return coreChatData.chatGroupMemberUserIDs(groupID: groupID, in: context)
    }

    func chatGroupMember(groupId id: GroupID, memberUserId: UserID, in managedObjectContext: NSManagedObjectContext) -> GroupMember? {
        return coreChatData.chatGroupMember(groupId: id, memberUserId: memberUserId, in: managedObjectContext)
    }

    func chatGroupIds(for memberUserId: UserID, in managedObjectContext: NSManagedObjectContext) -> [GroupID] {
        let chatGroupMemberItems = coreChatData.chatGroupMembers(predicate: NSPredicate(format: "userID == %@", memberUserId), in: managedObjectContext)
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

    func markGroupEventAsRead(groupEvent: GroupEvent) {
        let objectID = groupEvent.objectID
        mainDataStore.saveSeriallyOnBackgroundContext { context in
            guard let groupEvent = context.object(with: objectID) as? GroupEvent else {
                DDLogError("ChatData/markGroupEventAsRead/could not find groupevent")
                return
            }
            groupEvent.read = true
        }
    }

    func markAllGroupEventsAsRead() {
        mainDataStore.saveSeriallyOnBackgroundContext { context in
            let fetchRequest = GroupEvent.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "read == NO")
            do {
                let events = try context.fetch(fetchRequest)
                events.forEach { $0.read = true }
            } catch {
                DDLogError("ChatData/group/fetch-events/error  [\(error)]")
            }
        }
    }

    private func chatReceiptInfoAll(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext) -> [ChatReceiptInfo] {
        let fetchRequest: NSFetchRequest<ChatReceiptInfo> = ChatReceiptInfo.fetchRequest()
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

    func chatReceiptInfo(messageId: String, in managedObjectContext: NSManagedObjectContext) -> ChatReceiptInfo? {
        return chatReceiptInfoAll(predicate: NSPredicate(format: "chatMessageId == %@", messageId), in: managedObjectContext).first
    }

    func chatReceiptInfoForUser(messageId: String, userId: UserID, in managedObjectContext: NSManagedObjectContext) -> ChatReceiptInfo? {
        return chatReceiptInfoAll(predicate: NSPredicate(format: "chatMessageId == %@ && userId == %@", messageId, userId), in: managedObjectContext).first
    }

    // MARK: Group Core Data Updating

    func updateChatGroup(with groupId: GroupID, block: @escaping (Group) -> (), performAfterSave: (() -> ())? = nil) {
        coreChatData.updateChatGroup(with: groupId, block: block, performAfterSave: performAfterSave)
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
    func deleteChatGroup(groupId: GroupID, type: GroupType) {
        DDLogInfo("ChatData/deleteChatGroup")
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            var groupType: GroupType = .groupFeed
            // delete group
            if let chatGroup = self.chatGroup(groupId: groupId, in: managedObjectContext) {
                groupType = chatGroup.type
                if let members = chatGroup.members {
                    members.forEach {
                        managedObjectContext.delete($0)
                    }
                }

                managedObjectContext.delete(chatGroup)
            }

            // delete thread
            if let chatThread = self.chatThread(type: type, id: groupId, in: managedObjectContext) {
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

            switch groupType {
            case .groupFeed:
                // delete feeds
                MainAppContext.shared.feedData.deletePosts(groupId: groupId)

                // delete welcome post
                MainAppContext.shared.nux.deleteWelcomePost(id: groupId)
            case .groupChat:
                let fetchRequest = ChatMessage.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "toGroupID = %@", groupId)
                do {
                    let chatMessages = try managedObjectContext.fetch(fetchRequest)
                    DDLogInfo("ChatData/deleteChatGroup/delete-messages/begin count=[\(chatMessages.count)]")
                    chatMessages.forEach {
                        self.deleteMedia(in: $0)
                        managedObjectContext.delete($0)
                    }
                    DDLogInfo("ChatData/deleteChatGroup/delete-messages/finished")
                }
                catch {
                    DDLogError("ChatData/deleteChatGroup/delete-messages/error  [\(error)]")
                    return
                }
            case .oneToOne:
                DDLogError("ChatData/deleteChatGroup/delete-messages/wrong group type")
                return

            }
            

            self.save(managedObjectContext)
        }
    }

    func deleteChatGroupMember(groupId: GroupID, memberUserId: UserID, in managedObjectContext: NSManagedObjectContext) {
        coreChatData.deleteChatGroupMember(groupId: groupId, memberUserId: memberUserId, in: managedObjectContext)
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

    // Updates group feed thread when post is incoming as well as retracted.
    private func updateThreadWithGroupFeed(_ id: FeedPostID, isInbound: Bool, using managedObjectContext: NSManagedObjectContext) {
        coreChatData.updateThreadWithGroupFeed(id, isInbound: isInbound, using: managedObjectContext)
    }

    private func updateThreadWithGroupFeedRetract(_ id: FeedPostID, using managedObjectContext: NSManagedObjectContext) {
        coreChatData.updateThreadWithGroupFeedRetract(id, using: managedObjectContext)
    }
    
}

extension ChatData {

    // MARK: Group Process Inbound Actions/Events

    private func processGroupsList(_ groups: XMPPGroups) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }

            groups.groups?.forEach({
                if self.chatGroup(groupId: $0.groupId, in: managedObjectContext) == nil {
                    _ = self.coreChatData.addGroup(xmppGroup: $0, in: managedObjectContext)
                    self.getAndSyncGroup(groupId: $0.groupId)
                }
            })
            self.save(managedObjectContext)
        }
    }

    private func processIncomingXMPPGroup(_ group: XMPPGroup) {
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            self.processIncomingGroup(xmppGroup: group, using: managedObjectContext)
        }
    }

    private func processIncomingGroup(xmppGroup: XMPPGroup, using managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("ChatData/processIncomingGroup groupId: \(xmppGroup.groupId) groupType: \(xmppGroup.groupType)")

        var contactNames = [UserID:String]()
        // Update push names for member userids on any events received.
        xmppGroup.members?.forEach { inboundMember in
            // add to pushnames
            if let name = inboundMember.name, !name.isEmpty {
                contactNames[inboundMember.userId] = name
            }
        }
        UserProfile.updateNames(with: contactNames)
        // Saving push names early on will help us show push names for events/content from these users.

        switch xmppGroup.action {
        case .create:
            processGroupCreateAction(xmppGroup: xmppGroup, in: managedObjectContext)
        case .join:
            processGroupJoinAction(xmppGroup: xmppGroup, in: managedObjectContext)
        case .leave:
            processGroupLeaveAction(xmppGroup: xmppGroup, in: managedObjectContext)
        case .modifyMembers, .modifyAdmins, .autoPromoteAdmins:
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
        case .changeExpiry:
            processGroupChangeExpiryAction(xmppGroup: xmppGroup, in: managedObjectContext)

        default: break
        }

        save(managedObjectContext)
    }

    private func processGroupCreateAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) {
        coreChatData.processGroupCreateAction(xmppGroup: xmppGroup, in: managedObjectContext, recordEvent: false)
        recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: nil, in: managedObjectContext)
    }

    private func processGroupJoinAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("ChatData/group/processGroupJoinAction")
        coreChatData.processGroupJoinAction(xmppGroup: xmppGroup, in: managedObjectContext, recordEvent: false)
        for xmppGroupMember in xmppGroup.members ?? [] {
            guard xmppGroupMember.action == .join else { continue }
            recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: xmppGroupMember, in: managedObjectContext)
        }
    }

    private func processGroupLeaveAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) {
        coreChatData.processGroupLeaveAction(xmppGroup: xmppGroup, in: managedObjectContext, recordEvent: false)
        for xmppGroupMember in xmppGroup.members ?? [] {
            DDLogDebug("ChatData/group/process/new/leave-member [\(xmppGroupMember.userId)]")
            guard xmppGroupMember.action == .leave else { continue }
            recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: xmppGroupMember, in: managedObjectContext)
        }
    }

    private func processGroupModifyMembersAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) {
        DDLogDebug("ChatData/group/processGroupModifyMembersAction")
        coreChatData.processGroupModifyMembersAction(xmppGroup: xmppGroup, in: managedObjectContext, recordEvent: false)
        for xmppGroupMember in xmppGroup.members ?? [] {
            DDLogDebug("ChatData/group/process/modifyMembers [\(xmppGroupMember.userId)]/action: \(String(describing: xmppGroupMember.action))")
            recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: xmppGroupMember, in: managedObjectContext)
            if xmppGroupMember.action == .add, xmppGroupMember.userId == MainAppContext.shared.userData.userId {
                showGroupAddNotification(for: xmppGroup)
            }
        }
    }

    private func processGroupChangeNameAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("ChatData/group/processGroupChangeNameAction")
        coreChatData.processGroupChangeNameAction(xmppGroup: xmppGroup, in: managedObjectContext, recordEvent: false)
        recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: nil, in: managedObjectContext)
    }

    private func processGroupChangeDescriptionAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("ChatData/group/processGroupChangeDescriptionAction")
        coreChatData.processGroupChangeDescriptionAction(xmppGroup: xmppGroup, in: managedObjectContext, recordEvent: false)
        recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: nil, in: managedObjectContext)
    }

    private func processGroupChangeAvatarAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("ChatData/group/processGroupChangeAvatarAction")
        coreChatData.processGroupChangeAvatarAction(xmppGroup: xmppGroup, in: managedObjectContext, recordEvent: false)
        recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: nil, in: managedObjectContext)
    }

    private func processGroupSetBackgroundAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("ChatData/group/processGroupSetBackgroundAction")
        coreChatData.processGroupSetBackgroundAction(xmppGroup: xmppGroup, in: managedObjectContext, recordEvent: false)
        recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: nil, in: managedObjectContext)
    }

    private func processGroupChangeExpiryAction(xmppGroup: XMPPGroup, in managedObjectContext: NSManagedObjectContext) {
        DDLogInfo("ChatData/group/processGroupChangeExpiry")
        coreChatData.processGroupChangeExpiryAction(xmppGroup: xmppGroup, in: managedObjectContext, recordEvent: false)
        recordGroupMessageEvent(xmppGroup: xmppGroup, xmppGroupMember: nil, in: managedObjectContext)
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

        if let expirationType = xmppGroup.expirationType {
            event.groupExpirationType = expirationType
            event.groupExpirationTime = xmppGroup.expirationTime ?? 0
        }

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
            case .changeExpiry: return .changeExpiry
            case .autoPromoteAdmins: return .autoPromoteAdmins
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

        if let chatThread = self.chatThread(type: xmppGroup.groupType, id: event.groupID, in: managedObjectContext) {
            switch xmppGroup.groupType {
            case .groupFeed:
                chatThread.lastFeedUserID = event.senderUserID
                chatThread.lastFeedTimestamp = event.timestamp
                chatThread.lastFeedText = event.text

                if isSampleGroupCreationEvent {
                    chatThread.lastFeedText = Localizations.groupFeedWelcomePostTitle
                } else {
                    chatThread.lastFeedText = event.text
                }
            case .groupChat:
                chatThread.lastMsgUserId = nil
                chatThread.lastMsgTimestamp = event.timestamp
                chatThread.lastMsgText = event.text
            case .oneToOne:
                break
            }
            // nb: unreadFeedCount is not incremented for group event messages
            // and NUX zero zone unread welcome post count is recorded in NUX userDefaults, not unreadFeedCount
        } else {
            DDLogError("ChatData/recordGroupMessageEvent/ missing chat thread for groupId: \(event.groupID) groupType: \(xmppGroup.groupType)")
        }

        if isSampleGroupCreationEvent {
            DDLogVerbose("ChatData/recordGroupMessageEvent/groupID/\(xmppGroup.groupId)/isSampleGroupCreationEvent")
            unreadGroupThreadCountController.updateCount() // refresh bottom nav groups badge

            // remove group message and event since this group is created for the user
            managedObjectContext.delete(event)
        }

        save(managedObjectContext)

        let shouldNotififyForGroupEvent: Bool = {
            if event.senderUserID != MainAppContext.shared.userData.userId {
                if [.changeExpiry, .changeName, .changeDescription].contains(event.action) { // create is handled via `showGroupAddNotification`
                    return true
                } else if event.memberUserID == MainAppContext.shared.userData.userId {
                    if event.action == .modifyMembers, [.remove].contains(event.memberAction) { // add is handled via `showGroupAddNotification`
                        return true
                    } else if event.action == .modifyAdmins, [.promote, .demote].contains(event.memberAction) {
                        return true
                    }
                }
            }
            return false
        }()

        if shouldNotififyForGroupEvent {
            let groupEventObjectID = event.objectID
            let messageID = xmppGroup.messageId
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let event = self.viewContext.object(with: groupEventObjectID) as? GroupEvent, let messageID = messageID else {
                    return
                }
                self.showNotification(for: event, messageID: messageID)
            }
        }

        didGetAGroupEvent.send(event.groupID)
    }

    private func processGroupAddMemberAction(chatGroup: Group, xmppGroupMember: XMPPGroupMember, in managedObjectContext: NSManagedObjectContext) {
        coreChatData.processGroupAddMemberAction(chatGroup: chatGroup, xmppGroupMember: xmppGroupMember, in: managedObjectContext)
    }
}

// MARK: Group Notifications
extension ChatData {

    private func showNotification(for groupEvent: GroupEvent, messageID: String) {
        // Only display these notifications when the app is not active
        guard UIApplication.shared.applicationState == .active else {
            return
        }

        AppContext.shared.notificationStore.runIfNotificationWasNotPresented(for: messageID) {
            Banner.show(attributedBody: groupEvent.formattedNotificationText, groupID: groupEvent.groupID, type: .groupFeed, using: MainAppContext.shared.avatarStore)
        }
    }

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
        let name = UserProfile.find(with: userID, in: MainAppContext.shared.mainDataStore.viewContext)?.displayName ?? ""

        let title = "\(name) @ \(groupName)"
        let body = Localizations.groupsAddNotificationBody

        AppContext.shared.notificationStore.runIfNotificationWasNotPresented(for: messageID) {
            Banner.show(title: title, body: body, groupID: groupID, type: xmppGroup.groupType, using: MainAppContext.shared.avatarStore)
        }
    }

    private func presentLocalGroupAddNotifications(for xmppGroup: XMPPGroup) {
        DDLogDebug("ChatData/presentLocalGroupAddNotifications/groupID \(xmppGroup.groupId)")
        guard let messageID = xmppGroup.messageId else { return }
        guard let userID = xmppGroup.sender else { return }

        let metadata = NotificationMetadata(contentId: messageID,
                                            contentType: .groupAdd,
                                            fromId: userID,
                                            groupId: xmppGroup.groupId,
                                            groupType: xmppGroup.groupType,
                                            groupName: xmppGroup.name,
                                            timestamp: nil,
                                            data: nil,
                                            messageId: messageID)
        metadata.groupId = xmppGroup.groupId
        // create and add a notification to the notification center.
        NotificationRequest.createAndShow(from: metadata)
    }

}

extension ChatData: HalloChatDelegate {

    // MARK: XMPP Chat Delegates

    func halloService(_ halloService: HalloService, didReceiveMessageReceipt receipt: HalloReceipt, ack: (() -> Void)?) {
        DDLogDebug("ChatData/didReceiveMessageReceipt [\(receipt.itemId)] \(receipt)")
        guard receipt.thread != .feed else {
            DDLogError("ChatData/didReceiveMessageReceipt/error [unexpected-thread] [\(receipt.thread)]")
            ack?()
            return
        }
        guard receipt.userId != userData.userId else {
            // skip processing own receipts for group chat
            return
        }
        performSeriallyOnBackgroundContext { [weak self] (managedObjectContext) in
            guard let self = self else { return }
            if let chatMessage = self.chatMessage(with: receipt.itemId, in: managedObjectContext) {
                self.processInboundMessageReceipt(with: receipt, chatMessage: chatMessage)
            } else {
                self.processInboundOneToOneReactionReceipt(with: receipt)
            }
        }
        ack?()
    }

    func halloService(_ halloService: HalloService, didRerequestGroupChatMessage contentID: String, contentType: GroupFeedRerequestContentType, groupID: GroupID, from userID: UserID, ack: (() -> Void)?) {
        DDLogDebug("FeedData/didRerequestGroupChatMessage [\(contentID)] - [\(contentType)] - from: \(userID) - in: \(groupID)")
        switch contentType {
        case .message:
            coreChatData.handleRerequest(for: contentID, in: groupID, from: userID, ack: ack)
        case .messageReaction:
            coreChatData.handleReactionRerequest(for: contentID, in: groupID, from: userID, ack: ack)
        case .post, .postReaction, .comment, .commentReaction, .unknown, .UNRECOGNIZED, .historyResend:
            // These cases are handled separately in feedData.
            break
        }
    }

    func halloService(_ halloService: HalloService, didRerequestMessage messageID: String, from userID: UserID, ack: (() -> Void)?) {
        DDLogDebug("ChatData/didRerequestMessage [\(messageID)]")
        coreChatData.handleRerequest(for: messageID, from: userID, ack: ack)
    }

    func halloService(_ halloService: HalloService, didRerequestReaction reactionID: String, from userID: UserID, ack: (() -> Void)?) {
        DDLogDebug("ChatData/didRerequestReaction [\(reactionID)]")
        coreChatData.handleReactionRerequest(for: reactionID, from: userID, ack: ack)
    }

    func halloService(_ halloService: HalloService, didReceiveGroupMessage group: HalloGroup) {
        processIncomingXMPPGroup(group)
    }

    func halloService(_ halloService: HalloService, didReceiveHistoryResendPayload historyPayload: Clients_GroupHistoryPayload?, withGroupMessage group: HalloGroup) {
        DDLogInfo("ChatData/didReceiveHistoryPayload/\(group.groupId)/withGroupMessage/processing")
        coreChatData.processGroupHistoryPayload(historyPayload: historyPayload, withGroupMessage: group)
    }

    func halloService(_ halloService: HalloService, didReceiveHistoryResendPayload historyPayload: Clients_GroupHistoryPayload, for groupID: GroupID, from fromUserID: UserID) {
        // Members of the group on receiving a historyPayload stanza
        // Must verify keys and hashes and then share the content.
        DDLogInfo("ChatData/didReceiveHistoryPayload/\(groupID)/from: \(fromUserID)/processing")
        coreChatData.processGroupFeedHistoryResend(historyPayload, for: groupID, fromUserID: fromUserID)
    }
}

extension Localizations {
    static var chatListYouReactedMessage: String {
        NSLocalizedString("chat.list.you.reacted.message",
                          value: "You reacted %@ to a message",
                          comment: "Text shown when you reacted to a message")
    }
    
    static var chatListYouReactedAudio: String {
        NSLocalizedString("chat.list.you.reacted.audio",
                          value: "You reacted %1@ to an audio message",
                          comment: "Text shown when you reacted to an audio")
    }
    
    static var chatListYouReactedVideo: String {
        NSLocalizedString("chat.list.you.reacted.video",
                          value: "You reacted %1@ to a video",
                          comment: "Text shown when you reacted to a video")
    }
    
    static var chatListYouReactedImage: String {
        NSLocalizedString("chat.list.you.reacted.image",
                          value: "You reacted %1@ to an image",
                          comment: "Text shown when you reacted to an image")
    }
    
    static var chatListYouReactedText: String {
        NSLocalizedString("chat.list.you.reacted.text",
                          value: "You reacted %1@ to %2@",
                          comment: "Text shown when you reacted to a text message")
    }
    
    static var chatListUserReactedMessage: String {
        NSLocalizedString("chat.list.user.reacted.message",
                          value: "%1@ reacted %2@ to a message",
                          comment: "Text shown when user reacted to a message")
    }
    
    static var chatListUserReactedAudio: String {
        NSLocalizedString("chat.list.user.reacted.audio",
                          value: "%1@ reacted %2@ to an audio message",
                          comment: "Text shown when user reacted to an audio")
    }
    
    static var chatListUserReactedVideo: String {
        NSLocalizedString("chat.list.user.reacted.video",
                          value: "%1@ reacted %2@ to a video",
                          comment: "Text shown when user reacted to a video")
    }
    
    static var chatListUserReactedImage: String {
        NSLocalizedString("chat.list.user.reacted.image",
                          value: "%1@ reacted %2@ to an image",
                          comment: "Text shown when user reacted to an image")
    }
    
    static var chatListUserReactedText: String {
        NSLocalizedString("chat.list.user.reacted.text",
                          value: "%1@ reacted %2@ to %3@",
                          comment: "Text shown when user reacted to a text message")
    }
    
    static var chatListYouDeletedReactionMessage: String {
        NSLocalizedString("chat.list.you.deleted.reaction.message",
                          value: "You removed %@ from a message",
                          comment: "Text shown when you removed a reaction from a message")
    }
    
    static var chatListYouDeletedReactionAudio: String {
        NSLocalizedString("chat.list.you.deleted.reaction.audio",
                          value: "You removed %1@ from an audio",
                          comment: "Text shown when you removed a reaction from an audio")
    }

    static var chatListYouDeletedReactionVideo: String {
        NSLocalizedString("chat.list.you.deleted.reaction.video",
                          value: "You removed %1@ from a video",
                          comment: "Text shown when you removed a reaction from a video")
    }
    
    static var chatListYouDeletedReactionImage: String {
        NSLocalizedString("chat.list.you.deleted.reaction.image",
                          value: "You removed %1@ from an image",
                          comment: "Text shown when you removed a reaction from an image")
    }

    static var chatListYouDeletedReactionText: String {
        NSLocalizedString("chat.list.you.deleted.reaction.text",
                          value: "You removed %1@ from %2@",
                          comment: "Text shown when you removed a reaction from a text message")
    }
    
    static var chatListUserDeletedReactionMessage: String {
        NSLocalizedString("chat.list.user.deleted.reaction.message",
                          value: "%1@ removed %2@ from a message",
                          comment: "Text shown when user removed a reaction from a message")
    }
    
    static var chatListUserDeletedReactionAudio: String {
        NSLocalizedString("chat.list.user.deleted.reaction.audio",
                          value: "%1@ removed %2@ from an audio",
                          comment: "Text shown when user removed a reaction from an audio")
    }

    static var chatListUserDeletedReactionVideo: String {
        NSLocalizedString("chat.list.user.deleted.reaction.video",
                          value: "%1@ removed %2@ from a video",
                          comment: "Text shown when user removed a reaction from a video")
    }
    
    static var chatListUserDeletedReactionImage: String {
        NSLocalizedString("chat.list.user.deleted.reaction.image",
                          value: "%1@ removed %2@ from an image",
                          comment: "Text shown when user removed a reaction from an image")
    }

    static var chatListUserDeletedReactionText: String {
        NSLocalizedString("chat.list.user.deleted.reaction.text",
                          value: "%1@ removed %2@ from %3@",
                          comment: "Text shown when user removed a reaction from a text message")
    }

    static var chatUserReactedMessage: String {
        NSLocalizedString("chat.user.reacted.message",
                          value: "reacted %2@ to a message",
                          comment: "Text shown in a notification when user reacted to a message. The user's name is shown above this message in the notification.")
    }
}
