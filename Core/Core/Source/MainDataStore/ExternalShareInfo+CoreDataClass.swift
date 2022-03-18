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

fileprivate let shareURLPrefix = "https://share.halloapp.com/"

@objc(ExternalShareInfo)
public class ExternalShareInfo: NSManagedObject {

    public var externalShareURL: URL? {
        guard let blobID = blobID, let key = key else {
            return nil
        }
        return URL(string: "\(shareURLPrefix)\(blobID)#k\(key.base64urlEncodedString())")
    }
}
