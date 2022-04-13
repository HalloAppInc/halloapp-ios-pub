//
//  ExternalShareInfo+CoreDataClass.swift
//  
//
//  Created by Chris Leonavicius on 3/18/22.
//
//

import Foundation
import CoreCommon
import CoreData

@objc(ExternalShareInfo)
public class ExternalShareInfo: NSManagedObject {

    private static let shareURLHost = "share.halloapp.com"
    private static let shareURLTestHost = "share-test.halloapp.com"

    public class var externalShareHost: String {
        ServerProperties.isInternalUser ? shareURLTestHost : shareURLHost
    }

    public var externalShareURL: URL? {
        guard let blobID = blobID, let key = key else {
            return nil
        }
        return URL(string: "https://\(Self.externalShareHost)/\(blobID)#k\(key.base64urlEncodedString())")
    }
}
