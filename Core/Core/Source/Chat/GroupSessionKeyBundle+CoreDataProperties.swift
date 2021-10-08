//
//  GroupSessionKeyBundle+CoreDataProperties.swift
//  Core
//
//  Created by Murali Balusu on 10/1/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//
//

import Foundation
import CoreData


extension GroupSessionKeyBundle {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<GroupSessionKeyBundle> {
        return NSFetchRequest<GroupSessionKeyBundle>(entityName: "GroupSessionKeyBundle")
    }

    @NSManaged public var audienceHash: Data?
    @NSManaged public var groupId: String
    @NSManaged public var pendingUserIdsString: String
    @NSManaged public var privateSignatureKey: Data?
    @NSManaged public var stateValue: Int16
    @NSManaged public var senderStates: Set<SenderStateBundle>?

    public var state: GroupSessionState {
        get {
            return GroupSessionState(rawValue: self.stateValue) ?? GroupSessionState.awaitingSetup
        }
        set {
            self.stateValue = newValue.rawValue
        }
    }

    public var pendingUserIds: [UserID] {
        get {
            pendingUserIdsString.split(separator: ",") as? [UserID] ?? []
        }
        set {
            pendingUserIdsString = newValue.joined(separator: ",")
        }
    }

}

// MARK: Generated accessors for senderStates
extension GroupSessionKeyBundle {

    @objc(addSenderStatesObject:)
    @NSManaged public func addToSenderStates(_ value: SenderStateBundle)

    @objc(removeSenderStatesObject:)
    @NSManaged public func removeFromSenderStates(_ value: SenderStateBundle)

    @objc(addSenderStates:)
    @NSManaged public func addToSenderStates(_ values: NSSet)

    @objc(removeSenderStates:)
    @NSManaged public func removeFromSenderStates(_ values: NSSet)

}

extension GroupSessionKeyBundle : Identifiable {

}
