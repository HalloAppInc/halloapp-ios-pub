//
//  Utils.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/18/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Foundation
import XMPPFramework

class Utils {
    func parseFeedItem(_ value: XMPPMessage) -> String {
        
        var result = ""
        
        let event = value.element(forName: "event")
        let items = event?.elements(forName: "items")
        print("items: \(items)")

        for item in items ?? [] {
            let et = item.element(forName: "item")
            let entry = et?.element(forName: "entry")
            print("entry: \(entry)")
            if let summary = entry?.element(forName: "summary") {
                print("hit: \(summary.stringValue ?? "x")")
                
                if let summaryValue = summary.stringValue {
                    result = summaryValue
                }
             
            }
          
        }
        return result
    }
}
