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
        notificationContent.populate(from: metadata, contactStore: MainAppContext.shared.contactStore)
        notificationContent.sound = .default
        let request = UNNotificationRequest(identifier: metadata.contentId, content: notificationContent, trigger: nil)
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.add(request, withCompletionHandler: completionHandler)
    }

}
