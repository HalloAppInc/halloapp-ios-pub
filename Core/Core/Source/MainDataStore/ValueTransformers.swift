//
//  ValueTransformers.swift
//  Core
//
//  Created by Garrett on 3/18/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import Foundation
import SwiftProtobuf
import CoreCommon

public extension NSValueTransformerName {
    static let mentionValueTransformer = NSValueTransformerName(rawValue: "MentionValueTransformer")
    static let linksValueTransformer = NSValueTransformerName(rawValue: "LinksValueTransformer")
}

@objc(MentionValueTransformer)
public final class MentionValueTransformer: ValueTransformer {
    public override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else {
            return nil
        }
        guard let mentions: [MentionData] = try? PropertyListDecoder().decode([MentionData].self, from: data) else
        {
            return nil
        }
        return mentions
    }

    public override func transformedValue(_ value: Any?) -> Any? {
        guard let mentions = value as? [MentionData] else {
            return nil
        }
        guard let data = try? PropertyListEncoder().encode(mentions) else {
            return nil
        }
        return data
    }
}


@objc(FeedPostReceiptInfoTransformer)
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
            if let date = receipt.screenshotDate {
                pbReceipt.timestampScreenshot = Google_Protobuf_Timestamp(seconds: Int64(date.timeIntervalSince1970))
            }
            if let date = receipt.savedDate {
                pbReceipt.timestampSaved = Google_Protobuf_Timestamp(seconds: Int64(date.timeIntervalSince1970))
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
                    let screenshotDate = pbReceipt.hasTimestampScreenshot ? Date(timeIntervalSince1970: TimeInterval(pbReceipt.timestampScreenshot.seconds)) : nil
                    let savedDate = pbReceipt.hasTimestampSaved ? Date(timeIntervalSince1970: TimeInterval(pbReceipt.timestampSaved.seconds)) : nil
                    receiptsMap[pbReceipt.userID] = Receipt(deliveredDate: deliveredDate, seenDate: seenDate, screenshotDate: screenshotDate, savedDate: savedDate)
                }
            }
            return receiptsMap
        }
        catch {
            return nil
        }
    }

}

@objc(ProfileLinksValueTransformer)
public final class ProfileLinksValueTransformer: ValueTransformer {
    
    public override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data,
              let links = try? PropertyListDecoder().decode([ProfileLink].self, from: data) else {
            return nil
        }

        return links
    }

    public override func transformedValue(_ value: Any?) -> Any? {
        guard let links = value as? [ProfileLink],
              let data = try? PropertyListEncoder().encode(links) else {
            return nil
        }

        return data
    }
}

extension NSValueTransformerName {
    static let feedPostReceiptInfoTransformer = NSValueTransformerName(rawValue: "FeedPostReceiptInfoTransformer")
}
