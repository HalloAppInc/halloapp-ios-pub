//
//  Call+CoreDataProperties.swift
//  Core
//
//  Created by Murali Balusu on 12/13/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//
//

import Foundation
import CoreData


extension Call {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Call> {
        return NSFetchRequest<Call>(entityName: "Call")
    }

    @NSManaged public var callID: String
    @NSManaged public var peerUserID: String
    @NSManaged public var directionValue: String
    @NSManaged public var typeValue: String
    @NSManaged public var durationMs: Double
    @NSManaged public var answered: Bool
    @NSManaged public var timestamp: Date
    @NSManaged public var endReasonValue: Int16
    public var endReason: EndCallReason {
        get {
            return EndCallReason(rawValue: self.endReasonValue)!
        }
        set {
            self.endReasonValue = newValue.rawValue
        }
    }

    public var direction: CallDirection {
        get {
            return CallDirection(rawValue: directionValue)!
        }
        set {
            directionValue = newValue.rawValue
        }
    }

    public var type: CallType {
        get {
            return CallType(rawValue: typeValue)!
        }
        set {
            typeValue = newValue.rawValue
        }
    }

}

extension Call : Identifiable {

}

extension Call {
    var isMissedCall: Bool {
        return direction == .incoming && answered != true
    }

    var isOutgoing: Bool {
        return direction == .outgoing
    }

    var isIncoming: Bool {
        return direction == .incoming
    }
}
