//
//  FeedPostInfo+CoreDataProperties.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/5/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//
//

import Core
import CoreCommon
import CoreData
import Foundation
import SwiftProtobuf

extension FeedPostInfo {

    @nonobjc class func fetchRequest() -> NSFetchRequest<FeedPostInfo> {
        return NSFetchRequest<FeedPostInfo>(entityName: "FeedPostInfo")
    }

    @NSManaged private var receiptInfo: Any?
    @NSManaged private var post: FeedPost?
    @NSManaged private var privacyListTypeValue: String?

    var receipts: [UserID : Receipt]? {
        get { receiptInfo as? [ UserID : Receipt ] }
        set { receiptInfo = newValue }
    }
    
    // TODO(murali@): rename coredata attribute name - else it is confusing!
    var audienceType: AudienceType? {
        get { AudienceType(rawValue: privacyListTypeValue ?? "") }
        set { privacyListTypeValue = newValue?.rawValue }
    }

}

class FeedPostReceiptInfoTransformer: ValueTransformer {

    override class func transformedValueClass() -> AnyClass {
        return NSData.self
    }

    override class func allowsReverseTransformation() -> Bool {
        return true
    }

    override func transformedValue(_ value: Any?) -> Any? {
        guard let receipts = value as? [UserID: Receipt] else { return nil }
        guard !receipts.isEmpty else { return nil }
        var pbReceipts = Proto_Receipts()
        pbReceipts.receipts = receipts.map { (userId, receipt) -> Proto_Receipts.Receipt in
            var pbReceipt = Proto_Receipts.Receipt()
            pbReceipt.userID = userId
            if let date = receipt.deliveredDate {
                pbReceipt.timestampDelivered = Google_Protobuf_Timestamp(seconds: Int64(date.timeIntervalSince1970))
            }
            if let date = receipt.seenDate {
                pbReceipt.timestampSeen = Google_Protobuf_Timestamp(seconds: Int64(date.timeIntervalSince1970))
            }
            return pbReceipt
        }
        return try? pbReceipts.serializedData()
    }

    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard value != nil else { return nil }
        guard let data = value as? Data else { return nil }
        do {
            let pbReceipts = try Proto_Receipts(serializedData: data)
            let receiptsMap: [UserID : Receipt] = pbReceipts.receipts.reduce(into: [:]) { (receiptsMap, pbReceipt) in
                if !pbReceipt.userID.isEmpty {
                    let deliveredDate = pbReceipt.hasTimestampDelivered ? Date(timeIntervalSince1970: TimeInterval(pbReceipt.timestampDelivered.seconds)) : nil
                    let seenDate = pbReceipt.hasTimestampSeen ? Date(timeIntervalSince1970: TimeInterval(pbReceipt.timestampSeen.seconds)) : nil
                    receiptsMap[pbReceipt.userID] = Receipt(deliveredDate: deliveredDate, seenDate: seenDate)
                }
            }
            return receiptsMap
        }
        catch {
            return nil
        }
    }

}

extension NSValueTransformerName {
    static let feedPostReceiptInfoTransformer = NSValueTransformerName(rawValue: "FeedPostReceiptInfoTransformer")
}
