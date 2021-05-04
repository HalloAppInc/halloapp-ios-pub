//
//  NotificationRequest.swift
//  HalloApp
//
//  Created by Murali Balusu on 4/18/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Foundation
import CocoaLumberjack
import Core
import CoreData

final class NotificationRequest {

    public static func createAndShow(from metadata: NotificationMetadata, with completionHandler: ((Error?) -> Void)? = nil) {
        DDLogInfo("NotificationRequest/createAndShow/contentId: \(metadata.contentId)")
        let notificationContent = UNMutableNotificationContent()
        // populate only fills the fallback text for chat messages: so we need to explicitly fill chat body as well.
        // TODO(murali@): need to clean this call further.
        notificationContent.populate(from: metadata, contactStore: MainAppContext.shared.contactStore)
        switch metadata.contentType {
        case .chatMessage:
            guard let clientChatMessage = metadata.protoContainer?.chatMessage else {
                return
            }
            notificationContent.populateChatBody(from: clientChatMessage, using: metadata, contactStore: MainAppContext.shared.contactStore)
        default:
            break
        }
        notificationContent.sound = .default
        let request = UNNotificationRequest(identifier: metadata.contentId, content: notificationContent, trigger: nil)
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.add(request, withCompletionHandler: completionHandler)
    }

}
