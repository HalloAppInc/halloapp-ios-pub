//
//  SharedChatMessageMigrationPolicy.swift
//  Core
//
//  Created by Murali Balusu on 12/2/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import Foundation

import Foundation
import CoreData
import CocoaLumberjackSwift

class SharedChatMessageMigrationPolicy: NSEntityMigrationPolicy {

    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {

        guard let sourceMsgId = sInstance.value(forKey: "id") as? String else {
            return
        }
        DDLogInfo("SharedChatMessageMigrationPolicy, sourceId: \(sourceMsgId), sourceInstance: \(sInstance)")
        let request = NSFetchRequest<NSManagedObject>(entityName: "SharedChatMessage")
        request.predicate = NSPredicate(format: "id == %@", sourceMsgId)
        let destSharedChatMessage = try manager.destinationContext.fetch(request)
        let sharedChatMessage: NSManagedObject
        if destSharedChatMessage == [] {
            sharedChatMessage = NSEntityDescription.insertNewObject(forEntityName: mapping.destinationEntityName!, into: manager.destinationContext)

            sharedChatMessage.setValue(sInstance.value(forKey: "clientChatMsgPb"), forKey: "clientChatMsgPb")
            sharedChatMessage.setValue(sInstance.value(forKey: "decryptionError"), forKey: "decryptionError")
            sharedChatMessage.setValue(sInstance.value(forKey: "ephemeralKey"), forKey: "ephemeralKey")
            sharedChatMessage.setValue(sInstance.value(forKey: "fromUserId"), forKey: "fromUserId")
            sharedChatMessage.setValue(sInstance.value(forKey: "id"), forKey: "id")
            sharedChatMessage.setValue(sInstance.value(forKey: "senderClientVersion"), forKey: "senderClientVersion")
            sharedChatMessage.setValue(sInstance.value(forKey: "serialID"), forKey: "serialID")
            sharedChatMessage.setValue(sInstance.value(forKey: "serverMsgPb"), forKey: "serverMsgPb")
            sharedChatMessage.setValue(sInstance.value(forKey: "serverTimestamp"), forKey: "serverTimestamp")
            sharedChatMessage.setValue(sInstance.value(forKey: "statusValue"), forKey: "statusValue")
            sharedChatMessage.setValue(sInstance.value(forKey: "text"), forKey: "text")
            sharedChatMessage.setValue(sInstance.value(forKey: "timestamp"), forKey: "timestamp")
            sharedChatMessage.setValue(sInstance.value(forKey: "toUserId"), forKey: "toUserId")
        } else {
            return
        }
        DDLogInfo("SharedChatMessageMigrationPolicy/associate sourceId: \(sourceMsgId), sourceInstance: \(sInstance)")
        manager.associate(sourceInstance: sInstance, withDestinationInstance: sharedChatMessage, for: mapping)
        return
    }
}
