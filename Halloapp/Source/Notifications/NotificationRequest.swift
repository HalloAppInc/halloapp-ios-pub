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
import CoreData

final class NotificationRequest {

    public static func createAndShow(from metadata: NotificationMetadata, with completionHandler: ((Error?) -> Void)? = nil) {

        AppContext.shared.notificationStore.runIfNotificationWasNotPresented(for: metadata.contentId) {
            DDLogInfo("NotificationRequest/createAndShow/contentId: \(metadata.contentId)")
            let notificationContent = UNMutableNotificationContent()
            // populate only fills the fallback text for chat messages: so we need to explicitly fill chat body as well.
            // TODO(murali@): need to clean this call further.
            notificationContent.populate(from: metadata, contactStore: MainAppContext.shared.contactStore)
            switch metadata.contentType {
            case .chatMessage:
                guard let clientChatContainer = metadata.protoContainer?.chatContainer else {
                    DDLogError("NotificationRequest/createAndShow/clientChatContainer is empty")
                    break
                }
                notificationContent.populateChatBody(from: clientChatContainer.chatContent, using: metadata, contactStore: MainAppContext.shared.contactStore)
            case .groupFeedPost:
                guard let postData = metadata.postData() else {
                    DDLogError("NotificationRequest/createAndShow/postData is empty")
                    break
                }
                notificationContent.populateFeedPostBody(from: postData, using: metadata, contactStore: MainAppContext.shared.contactStore)
            case .groupFeedComment:
                guard let commentData = metadata.commentData() else {
                    DDLogError("NotificationRequest/createAndShow/commentData is empty")
                    break
                }
                notificationContent.populateFeedCommentBody(from: commentData, using: metadata, contactStore: MainAppContext.shared.contactStore)
            default:
                break
            }
            notificationContent.sound = .default
            let request = UNNotificationRequest(identifier: metadata.contentId, content: notificationContent, trigger: nil)
            let notificationCenter = UNUserNotificationCenter.current()
            notificationCenter.add(request, withCompletionHandler: completionHandler)
            AppContext.shared.notificationStore.save(id: metadata.contentId, type: metadata.contentType.rawValue)
        }
    }

}
