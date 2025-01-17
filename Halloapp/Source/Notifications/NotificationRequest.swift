//
//  NotificationRequest.swift
//  HalloApp
//
//  Created by Murali Balusu on 4/18/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation
import CocoaLumberjackSwift
import Core
import CoreCommon
import CoreData

final class NotificationRequest {

    public static func createAndShow(from metadata: NotificationMetadata, shouldRecord: Bool = true, with completionHandler: ((Error?) -> Void)? = nil) {

        AppContext.shared.notificationStore.runIfNotificationWasNotPresented(for: metadata.identifier) {
            DDLogInfo("NotificationRequest/createAndShow/identifier: \(metadata.identifier)")
            let notificationContent = UNMutableNotificationContent()
            // populate only fills the fallback text for chat messages: so we need to explicitly fill chat body as well.
            // TODO(murali@): need to clean this call further.
            notificationContent.populate(from: metadata, in: MainAppContext.shared.mainDataStore.viewContext)
            switch metadata.contentType {
            case .chatMessage:
                guard let clientChatContainer = metadata.protoContainer?.chatContainer else {
                    DDLogError("NotificationRequest/createAndShow/clientChatContainer is empty")
                    break
                }
                notificationContent.populateChatBody(from: clientChatContainer.chatContent, using: metadata, in: MainAppContext.shared.mainDataStore.viewContext)
            case .groupFeedPost:
                guard let postData = metadata.postData() else {
                    DDLogError("NotificationRequest/createAndShow/postData is empty")
                    break
                }
                guard NotificationSettings.current.isPostsEnabled else {
                    DDLogInfo("NotificationRequest/createAndShow/postData - skip due to userPreferences")
                    return
                }
                notificationContent.populateFeedPostBody(from: postData, using: metadata, in: MainAppContext.shared.mainDataStore.viewContext)
            case .groupFeedComment:
                guard let commentData = metadata.commentData() else {
                    DDLogError("NotificationRequest/createAndShow/commentData is empty")
                    break
                }
                guard NotificationSettings.current.isCommentsEnabled else {
                    DDLogInfo("NotificationRequest/createAndShow/commentData - skip due to userPreferences")
                    return
                }
                notificationContent.populateFeedCommentBody(from: commentData, using: metadata, in: MainAppContext.shared.mainDataStore.viewContext)
            case .feedPost:
                guard NotificationSettings.current.isPostsEnabled else {
                    DDLogInfo("NotificationRequest/createAndShow/postData - skip due to userPreferences")
                    return
                }
            case .feedComment:
                guard NotificationSettings.current.isCommentsEnabled else {
                    DDLogInfo("NotificationRequest/createAndShow/commentData - skip due to userPreferences")
                    return
                }
            case .groupChatMessage:
                guard let clientChatContainer = metadata.protoContainer?.chatContainer else {
                    DDLogError("NotificationRequest/createAndShow/clientChatContainer is empty")
                    break
                }
                notificationContent.populateChatBody(from: clientChatContainer.chatContent, using: metadata, in: MainAppContext.shared.mainDataStore.viewContext)
            default:
                break
            }
            notificationContent.sound = .default
            let request = UNNotificationRequest(identifier: metadata.identifier, content: notificationContent, trigger: nil)
            let notificationCenter = UNUserNotificationCenter.current()
            notificationCenter.add(request, withCompletionHandler: completionHandler)

            if shouldRecord {
                AppContext.shared.notificationStore.save(id: metadata.identifier, type: metadata.contentType.rawValue)
            }
        }
    }

    public static func updateMomentNotifications() {
        DDLogInfo("NotificationRequest/updateMomentNotifications")
        guard NotificationSettings.current.isMomentsEnabled else {
            DDLogInfo("NotificationRequest/updateMomentNotifications - skip due to userPreferences")
            return
        }
        AppContext.shared.mainDataStore.performSeriallyOnBackgroundContext { managedObjectContext in
            let predicate = NSPredicate(format: "isMoment = YES && (statusValue = %d || statusValue = %d)", FeedPost.Status.incoming.rawValue, FeedPost.Status.rerequesting.rawValue)
            let moments = AppContext.shared.coreFeedData.feedPosts(predicate: predicate,
                                                                   sortDescriptors: [NSSortDescriptor(keyPath: \FeedPost.timestamp, ascending: true)],
                                                                   in: managedObjectContext)

            var unlockedMoments = [FeedPost]()
            var normalMoments = [FeedPost]()

            for moment in moments {
                if moment.unlockedMomentUserID != nil {
                    unlockedMoments.append(moment)
                } else {
                    normalMoments.append(moment)
                }
            }

            DDLogInfo("NotificationRequest/updateMomentNotifications/count: normal: \(normalMoments.count) unlocked: \(unlockedMoments.count)")
            batchMomentNotifications(for: .normal, moments: normalMoments, in: managedObjectContext)
            batchMomentNotifications(for: .unlock, moments: unlockedMoments, in: managedObjectContext)
        }
    }

    private static func batchMomentNotifications(for momentType: NotificationMetadata.MomentType, moments: [FeedPost], in context: NSManagedObjectContext) {
        guard
            let firstMoment = moments.first,
            let lastMoment = moments.last
        else {
            return
        }

        do {
            // We use the oldest notification identifier to replace that notification.
            // But the metadata in the notification refers to the last moment - so that tapping takes us to the latest moment.
            let notificationIdentifier = firstMoment.id
            let metadata = NotificationMetadata(contentId: lastMoment.id,
                                                contentType: .feedPost,
                                                fromId: lastMoment.userId,
                                                groupId: nil,
                                                groupType: nil,
                                                groupName: nil,
                                                timestamp: lastMoment.timestamp,
                                                data: try lastMoment.postData.clientContainer.serializedData(),
                                                messageId: nil,
                                                pushName: nil)
            metadata.momentContext = momentType
            let momentsPostData = moments.map { $0.postData }
            let content = NotificationMetadata.extractMomentNotification(for: metadata, using: momentsPostData, in: context)
            metadata.momentNotificationText = content.body
            let sound = moments.count < 2 ? UNNotificationSound.default : nil

            // Dont update the notification if nothing changed about moments.
            let notificationCenter = UNUserNotificationCenter.current()
            notificationCenter.getMomentNotification(for: momentType) { oldMetadata in
                // Check count and from userId for moments.
                if oldMetadata?.momentNotificationText == metadata.momentNotificationText,
                   oldMetadata?.fromId == metadata.fromId {
                    DDLogInfo("NotificationRequest/updateMomentNotifications/skip - since nothing changed")
                    return
                }

                DDLogInfo("NotificationRequest/updateMomentNotifications/\(metadata.identifier)")
                let notificationContent = UNMutableNotificationContent()
                notificationContent.title = content.title
                notificationContent.subtitle = content.subtitle
                notificationContent.body = content.body
                notificationContent.userInfo = content.userInfo
                notificationContent.sound = sound
                notificationContent.badge = AppContext.shared.applicationIconBadgeNumber as NSNumber?

                notificationCenter.add(UNNotificationRequest(identifier: notificationIdentifier,
                                                             content: notificationContent,
                                                             trigger: nil))
            }
        } catch {
            DDLogError("ProtoService/updateMomentNotifications/error: \(error)")
        }
    }
}
