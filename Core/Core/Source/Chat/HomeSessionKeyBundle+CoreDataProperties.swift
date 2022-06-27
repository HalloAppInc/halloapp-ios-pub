//
//  HomeSessionKeyBundle+CoreDataProperties.swift
//  Core
//
//  Created by Murali Balusu on 6/19/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//
//

import Foundation
import CoreData
import CoreCommon


extension HomeSessionKeyBundle {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<HomeSessionKeyBundle> {
        return NSFetchRequest<HomeSessionKeyBundle>(entityName: "HomeSessionKeyBundle")
    }

    @NSManaged public var typeValue: Int16
    @NSManaged public var stateValue: Int16
    @NSManaged public var privateSignatureKey: Data
    @NSManaged public var pendingUserIDsString: String
    @NSManaged public var audienceUserIDsString: String
    @NSManaged public var senderStates: Set<SenderStateBundle>?

    public var type: HomeSessionType {
        get {
            return HomeSessionType(rawValue: self.typeValue) ?? HomeSessionType.all
        }
        set {
            self.stateValue = newValue.rawValue
        }
    }

    public var state: HomeSessionState {
        get {
            return HomeSessionState(rawValue: self.stateValue) ?? HomeSessionState.awaitingSetup
        }
        set {
            self.stateValue = newValue.rawValue
        }
    }

    public var pendingUserIDs: [UserID] {
        get {
            pendingUserIDsString.split(separator: ",").map{ UserID($0) }
        }
        set {
            pendingUserIDsString = newValue.joined(separator: ",")
        }
    }

    public var audienceUserIDs: [UserID] {
        get {
            audienceUserIDsString.split(separator: ",").map{ UserID($0) }
        }
        set {
            audienceUserIDsString = newValue.joined(separator: ",")
        }
    }

}

// MARK: Generated accessors for senderStates
extension HomeSessionKeyBundle {

    @objc(addSenderStatesObject:)
    @NSManaged public func addToSenderStates(_ value: SenderStateBundle)

    @objc(removeSenderStatesObject:)
    @NSManaged public func removeFromSenderStates(_ value: SenderStateBundle)

    @objc(addSenderStates:)
    @NSManaged public func addToSenderStates(_ values: NSSet)

    @objc(removeSenderStates:)
    @NSManaged public func removeFromSenderStates(_ values: NSSet)

}

extension HomeSessionKeyBundle : Identifiable {

}
