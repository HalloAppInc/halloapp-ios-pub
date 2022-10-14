//
//  HalloApp
//
//  Created by Tony Jiang on 7/15/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
import CocoaLumberjackSwift
import Combine
import CoreCommon
import CoreData
import Foundation

extension KeyStore {

    public func groupSessionKeyBundle(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext) -> GroupSessionKeyBundle? {
        let fetchRequest: NSFetchRequest<GroupSessionKeyBundle> = GroupSessionKeyBundle.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false

        do {
            let keyBundles = try managedObjectContext.fetch(fetchRequest)
            if keyBundles.count > 1 {
                DDLogError("KeyStore/groupKeyBundle/error multiple-bundles-for-group [\(keyBundles.count)]")
                keyBundles[1...].forEach { managedObjectContext.delete($0) }
            }
            self.save(managedObjectContext)
            return keyBundles.first
        }
        catch {
            DDLogError("KeyStore/fetch-groupKeyBundles/error  [\(error)]")
            fatalError("Failed to fetch key bundle")
        }
    }

    public func groupSessionKeyBundle(for groupID: GroupID, in managedObjectContext: NSManagedObjectContext) -> GroupSessionKeyBundle? {
        let groupPredicate = NSPredicate(format: "groupId == %@", groupID)
        return groupSessionKeyBundle(predicate: groupPredicate, in: managedObjectContext)
    }

    public func homeSessionKeyBundle(predicate: NSPredicate? = nil, sortDescriptors: [NSSortDescriptor]? = nil, in managedObjectContext: NSManagedObjectContext) -> HomeSessionKeyBundle? {
        let fetchRequest: NSFetchRequest<HomeSessionKeyBundle> = HomeSessionKeyBundle.fetchRequest()
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = sortDescriptors
        fetchRequest.returnsObjectsAsFaults = false

        do {
            let keyBundles = try managedObjectContext.fetch(fetchRequest)
            if keyBundles.count > 1 {
                DDLogError("KeyStore/homeSessionKeyBundle/error multiple-bundles-for-group [\(keyBundles.count)]")
                keyBundles[1...].forEach { managedObjectContext.delete($0) }
            }
            self.save(managedObjectContext)
            return keyBundles.first
        }
        catch {
            DDLogError("KeyStore/fetch-homeSessionKeyBundles/error  [\(error)]")
            fatalError("Failed to fetch key bundle")
        }
    }

    public func homeSessionKeyBundle(for type: HomeSessionType, in managedObjectContext: NSManagedObjectContext) -> HomeSessionKeyBundle? {
        let homePredicate = NSPredicate(format: "typeValue == \(type.rawValue)")
        return homeSessionKeyBundle(predicate: homePredicate, in: managedObjectContext)
    }

    public func commentKey(for postID: FeedPostID, in managedObjectContext: NSManagedObjectContext) -> CommentKey? {
        let fetchRequest: NSFetchRequest<FeedPostCommentKey> = FeedPostCommentKey.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "postID == %@", postID)
        fetchRequest.returnsObjectsAsFaults = false

        do {
            let keyBundles = try managedObjectContext.fetch(fetchRequest)
            if keyBundles.count > 1 {
                DDLogError("KeyStore/commentKey/error multiple-bundles-for-post [\(keyBundles.count)]/postID: \(postID)")
                keyBundles[1...].forEach { managedObjectContext.delete($0) }
            }
            self.save(managedObjectContext)
            if let feedPostCommentKey = keyBundles.first {
                return CommentKey(data: feedPostCommentKey.commentKey)
            } else {
                return nil
            }
        }
        catch {
            DDLogError("KeyStore/fetch-commentKey/error  [\(error)]")
            fatalError("Failed to fetch key bundle")
        }
    }
}

extension KeyStore {

    // MARK: Saving
    public func saveMessageKeys(_ keys: MessageKeyMap, for userID: UserID) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            guard let messageKeyBundle = self.messageKeyBundle(for: userID, in: managedObjectContext) else {
                DDLogError("KeyStore/saveMessageKeys/\(userID)/error bundle not found")
                return
            }

            var keysToAdd = keys
            var keysDeleted = 0

            for oldKey in messageKeyBundle.messageKeys ?? [] {
                if let newData = keysToAdd[oldKey.locator], newData == oldKey.key {
                    keysToAdd[oldKey.locator] = nil
                } else {
                    managedObjectContext.delete(oldKey)
                    keysDeleted += 1
                }
            }

            for (locator, keyData) in keysToAdd {
                let messageKey = NSEntityDescription.insertNewObject(forEntityName: MessageKey.entity().name!, into: managedObjectContext) as! MessageKey
                messageKey.ephemeralKeyId = locator.ephemeralKeyID
                messageKey.chainIndex = locator.chainIndex
                messageKey.key = keyData
                messageKey.messageKeyBundle = messageKeyBundle
            }

            DDLogInfo("KeyStore/saveMessageKeys/\(userID)/complete [\(keysToAdd.count) added] [\(keysDeleted) deleted]")

            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
}

extension KeyStore {

    // MARK: GroupKeys Saving
    public func checkAndSaveGroupSessionKeyBundle(groupID: GroupID, state: GroupSessionState, groupKeyBundle: GroupKeyBundle) {
        AppContext.shared.mainDataStore.performSeriallyOnBackgroundContext { context in
            let groupMemberUserIds = AppContext.shared.coreChatData.chatGroupMemberUserIds(for: groupID, in: context)
            self.saveGroupSessionKeyBundle(groupID: groupID, members: groupMemberUserIds, state: state, groupKeyBundle: groupKeyBundle)
        }
    }

    private func saveGroupSessionKeyBundle(groupID: GroupID, members: [UserID], state: GroupSessionState, groupKeyBundle: GroupKeyBundle) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            // TODO: murali@: cleanup these logs.
            DDLogInfo("KeyStore/saveGroupSessionKeyBundle/groupID: \(groupID)/state:\(state)/\(groupKeyBundle)/starting")
            let groupSessionKeyBundle: GroupSessionKeyBundle = self.groupSessionKeyBundle(for: groupID, in: managedObjectContext) ?? NSEntityDescription.insertNewObject(forEntityName: GroupSessionKeyBundle.entity().name!, into: managedObjectContext) as! GroupSessionKeyBundle
            DDLogInfo("KeyStore/saveGroupSessionKeyBundle/groupID: \(groupID)/\(groupSessionKeyBundle)/begin")
            var senderStates = Set<SenderStateBundle>()
            if groupSessionKeyBundle.senderStates != nil {
                senderStates = groupSessionKeyBundle.senderStates!
            }

            let memberUserIds1 = groupSessionKeyBundle.senderStates?.map{ $0.userId } ?? []
            let memberUserIds2 = groupKeyBundle.incomingSession?.senderStates.map{ $0.key } ?? []
            let ownUserId = AppContext.shared.userData.userId
            let memberUserIds = Array(Set(memberUserIds1 + memberUserIds2)).filter{ $0 != ownUserId }
            for memberUserId in memberUserIds {
                if let incomingSenderState = groupKeyBundle.incomingSession?.senderStates.first(where: { $0.key == memberUserId })?.value {
                    let memberSenderState = groupSessionKeyBundle.senderStates?.first(where: { $0.userId == memberUserId }) ?? SenderStateBundle(context: managedObjectContext)
                    // overwrite current state only if chainIndex is larger or if signKey changed.
                    if (memberSenderState.publicSignatureKey != incomingSenderState.senderKey.publicSignatureKey ||
                        memberSenderState.currentChainIndex < incomingSenderState.currentChainIndex) {
                        memberSenderState.messageKeys?.forEach{ messageKey in managedObjectContext.delete(messageKey) }
                        memberSenderState.userId = memberUserId
                        memberSenderState.chainKey = incomingSenderState.senderKey.chainKey
                        memberSenderState.publicSignatureKey = incomingSenderState.senderKey.publicSignatureKey
                        memberSenderState.currentChainIndex = Int32(incomingSenderState.currentChainIndex)
                        var messageKeys = Set<GroupMessageKey>()
                        for (chainIndex, messageKey) in incomingSenderState.unusedMessageKeys {
                            let groupMessageKey = GroupMessageKey(context: managedObjectContext)
                            groupMessageKey.messageKey = messageKey
                            groupMessageKey.chainIndex = chainIndex
                            groupMessageKey.senderStateBundle = memberSenderState
                            messageKeys.insert(groupMessageKey)
                        }
                        memberSenderState.messageKeys = messageKeys.isEmpty ? nil : messageKeys
                        memberSenderState.groupSessionKeyBundle = groupSessionKeyBundle
                        senderStates.insert(memberSenderState)
                    }
                } else {
                    if let senderState = groupSessionKeyBundle.senderStates?.first(where: { $0.userId == memberUserId }) {
                        managedObjectContext.delete(senderState)
                    }
                }
            }

            let outgoingSession = groupKeyBundle.outgoingSession
            // Try and insert own senderState if available.
            if outgoingSession != nil,
               let chainKey = outgoingSession?.senderKey.chainKey,
               let signKey = outgoingSession?.senderKey.publicSignatureKey,
               let chainIndex = outgoingSession?.currentChainIndex {

                let memberSenderState = groupSessionKeyBundle.senderStates?.first(where: { $0.userId == ownUserId }) ?? SenderStateBundle(context: managedObjectContext)
                if memberSenderState.publicSignatureKey != signKey || memberSenderState.currentChainIndex < chainIndex {
                    memberSenderState.userId = AppContext.shared.userData.userId
                    memberSenderState.chainKey = chainKey
                    memberSenderState.publicSignatureKey = signKey
                    memberSenderState.currentChainIndex = Int32(chainIndex)
                    memberSenderState.messageKeys = nil
                    memberSenderState.groupSessionKeyBundle = groupSessionKeyBundle
                    senderStates.insert(memberSenderState)
                }
            } else {
                if let senderState = groupSessionKeyBundle.senderStates?.first(where: { $0.userId == ownUserId }) {
                    managedObjectContext.delete(senderState)
                }
            }

            // Update pendingUserIds by taking union of both sets of pending uids: in-store vs in-memory.
            // Make sure all pendingUids are members of the group.
            let newPendingUids = groupKeyBundle.pendingUids
            let oldPendingUids = groupSessionKeyBundle.pendingUserIds
            groupSessionKeyBundle.pendingUserIds = Array(Set(members).intersection(Set(oldPendingUids + newPendingUids))).filter{ $0 != ownUserId }

            groupSessionKeyBundle.groupId = groupID
            groupSessionKeyBundle.state = state
            groupSessionKeyBundle.audienceHash = outgoingSession?.audienceHash
            groupSessionKeyBundle.privateSignatureKey = outgoingSession?.privateSigningKey
            groupSessionKeyBundle.senderStates = senderStates.isEmpty ? nil : senderStates
            DDLogInfo("KeyStore/saveGroupSessionKeyBundle/groupID: \(groupID)/\(groupSessionKeyBundle)/done")

            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
}

extension KeyStore {

    // MARK: HomeKeys Saving
    // TODO: check pending userIds are valid and part of the audience.
    public func saveHomeSessionKeyBundle(type: HomeSessionType, state: HomeSessionState, homeKeyBundle: HomeKeyBundle) {
        self.performSeriallyOnBackgroundContext { (managedObjectContext) in
            // TODO: murali@: cleanup these logs.
            DDLogInfo("KeyStore/saveHomeSessionKeyBundle/type: \(type)/state:\(state)/\(homeKeyBundle)/starting")
            let homeSessionKeyBundle: HomeSessionKeyBundle = self.homeSessionKeyBundle(for: type, in: managedObjectContext) ?? HomeSessionKeyBundle(context: managedObjectContext)
            DDLogInfo("KeyStore/saveHomeSessionKeyBundle/type: \(type)/\(homeSessionKeyBundle)/begin")
            var senderStates = homeSessionKeyBundle.senderStates ?? Set()

            let memberUserIds1 = homeSessionKeyBundle.senderStates?.map{ $0.userId } ?? []
            let memberUserIds2 = homeKeyBundle.incomingSession?.senderStates.map{ $0.key } ?? []
            let ownUserId = AppContext.shared.userData.userId
            let memberUserIds = Array(Set(memberUserIds1 + memberUserIds2)).filter{ $0 != ownUserId }
            for memberUserId in memberUserIds {
                if let incomingSenderState = homeKeyBundle.incomingSession?.senderStates.first(where: { $0.key == memberUserId })?.value {
                    let memberSenderState = homeSessionKeyBundle.senderStates?.first(where: { $0.userId == memberUserId }) ?? SenderStateBundle(context: managedObjectContext)
                    // overwrite current state only if chainIndex is larger or if signKey changed.
                    if (memberSenderState.publicSignatureKey != incomingSenderState.senderKey.publicSignatureKey ||
                        memberSenderState.currentChainIndex < incomingSenderState.currentChainIndex) {
                        memberSenderState.messageKeys?.forEach{ messageKey in managedObjectContext.delete(messageKey) }
                        memberSenderState.userId = memberUserId
                        memberSenderState.chainKey = incomingSenderState.senderKey.chainKey
                        memberSenderState.publicSignatureKey = incomingSenderState.senderKey.publicSignatureKey
                        memberSenderState.currentChainIndex = Int32(incomingSenderState.currentChainIndex)
                        var messageKeys = Set<GroupMessageKey>()
                        for (chainIndex, messageKey) in incomingSenderState.unusedMessageKeys {
                            let groupMessageKey = GroupMessageKey(context: managedObjectContext)
                            groupMessageKey.messageKey = messageKey
                            groupMessageKey.chainIndex = chainIndex
                            groupMessageKey.senderStateBundle = memberSenderState
                            messageKeys.insert(groupMessageKey)
                        }
                        memberSenderState.messageKeys = messageKeys.isEmpty ? nil : messageKeys
                        memberSenderState.homeSessionKeyBundle = homeSessionKeyBundle
                        senderStates.insert(memberSenderState)
                    }
                } else {
                    if let senderState = homeSessionKeyBundle.senderStates?.first(where: { $0.userId == memberUserId }) {
                        managedObjectContext.delete(senderState)
                    }
                }
            }

            let outgoingSession = homeKeyBundle.outgoingSession
            // Try and insert own senderState if available.
            if outgoingSession != nil,
               let chainKey = outgoingSession?.senderKey.chainKey,
               let signKey = outgoingSession?.senderKey.publicSignatureKey,
               let chainIndex = outgoingSession?.currentChainIndex {

                let memberSenderState = homeSessionKeyBundle.senderStates?.first(where: { $0.userId == ownUserId }) ?? SenderStateBundle(context: managedObjectContext)
                if memberSenderState.publicSignatureKey != signKey || memberSenderState.currentChainIndex < chainIndex {
                    memberSenderState.userId = AppContext.shared.userData.userId
                    memberSenderState.chainKey = chainKey
                    memberSenderState.publicSignatureKey = signKey
                    memberSenderState.currentChainIndex = Int32(chainIndex)
                    memberSenderState.messageKeys = nil
                    memberSenderState.homeSessionKeyBundle = homeSessionKeyBundle
                    senderStates.insert(memberSenderState)
                }
            } else {
                if let senderState = homeSessionKeyBundle.senderStates?.first(where: { $0.userId == ownUserId }) {
                    managedObjectContext.delete(senderState)
                }
            }

            /// Update pendingUserIds by taking union of both sets of pending uids: in-store vs in-memory.
            /// Make sure all pendingUids are members of the audience?? check TODO: murali
            /// Just overwrite new pendingUids for now.
            let newPendingUids = homeKeyBundle.pendingUids
            /// let oldPendingUids = homeSessionKeyBundle.pendingUserIDs
            homeSessionKeyBundle.pendingUserIDs = Array(Set(newPendingUids)).filter{ $0 != ownUserId }

            homeSessionKeyBundle.audienceUserIDs = homeKeyBundle.audienceUids

            homeSessionKeyBundle.type = type
            homeSessionKeyBundle.state = state
            homeSessionKeyBundle.privateSignatureKey = outgoingSession?.privateSigningKey ?? Data()
            homeSessionKeyBundle.senderStates = senderStates.isEmpty ? nil : senderStates
            DDLogInfo("KeyStore/saveHomeSessionKeyBundle/groupID: \(type)/\(homeSessionKeyBundle)/done")

            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }

    func saveCommentKey(postID: FeedPostID, commentKeyData: Data) {
        self.performSeriallyOnBackgroundContext { managedObjectContext in
            let feedPostCommentKey = FeedPostCommentKey(context: managedObjectContext)
            feedPostCommentKey.postID = postID
            feedPostCommentKey.commentKey = commentKeyData
            DDLogInfo("KeyStore/saveCommentKey/postID: \(postID)/\(commentKeyData)/done")
            if managedObjectContext.hasChanges {
                self.save(managedObjectContext)
            }
        }
    }
}
