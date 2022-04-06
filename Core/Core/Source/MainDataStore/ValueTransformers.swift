//
//  ValueTransformers.swift
//  Core
//
//  Created by Garrett on 3/18/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import Foundation

public extension NSValueTransformerName {
    static let mentionValueTransformer = NSValueTransformerName(rawValue: "MentionValueTransformer")
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
