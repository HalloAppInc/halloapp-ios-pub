//
//  Utils.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/18/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Foundation
import XMPPFramework

import SwiftDate

class Utils {
    
    func timeForm(dateStr: String) -> String {

        let origDateDouble = Double(dateStr)
        
        var result = ""
        
        var diff = 0
        
        if let origDateDouble = origDateDouble {
            let origDate = Int(origDateDouble)
            
            let current = Int(Date().timeIntervalSince1970)
            
            diff = current - origDate
            if (diff <= 3) {
                result = "now"
            } else if (diff <= 59) {
                result = "\(String(diff))s"
            } else if diff <= 3600 {
                let diff2 = diff/60
                result = "\(String(diff2))m\(diff2 > 1 ? "" : "")"
            } else if diff <= 86400 {
                let diff2 = diff/(60*60)
                result = "\(String(diff2))h\(diff2 > 1 ? "" : "")"
            } else if diff <= 86400*7 {
                let diff2 = diff/(86400)
                if (diff2 == 1) {
                    result = "Yesterday"
                } else {
                    result = "\(String(diff2))d\(diff2 > 1 ? "" : "")"
                }
            } else if diff <= 86400*7*4 {
                let diff2 = diff/(86400*7)
                result = "\(String(diff2))w\(diff2 > 1 ? "" : "")"
            } else {
                
                let dateformatter = DateFormatter()
                 
                dateformatter.dateStyle = .long
                 
                result = dateformatter.string(from: Date(timeIntervalSince1970: origDateDouble))
                
//                let rome = Region(tz: TimeZoneName.europeRome, cal: CalendarName.gregorian, loc: LocaleName.italian)
//
//                // Parse a string which a custom format
//                let date1 = try! DateInRegion(string: dateStr, format: .iso8601(options: .withInternetDateTime), fromRegion: rome)
//                if let date1 = date1 {
//                    result = date1.string(dateStyle: .long, timeStyle: .none)
//                }
            }
            
        }
        

        
        return result
    }
        
        
    func userAlreadyExists(_ value: XMPPIQ) -> Bool {
        
        var result = false

        if (value.isErrorIQ) {

            let error = value.element(forName: "error")
            
            if (error!.attributeStringValue(forName: "code")! == "409") {
                                
                if let text = error?.element(forName: "text") {
                    
                    if let value = text.stringValue {
                        if value == "User already exists" {
                            result = true
                        }
                    }
                 
                }
                
            }
                            
        }
        
        return result
    }
    
    
    func accountsCreatedTooQuickly(_ value: XMPPIQ) -> Bool {
        
        var result = false

        if (value.isErrorIQ) {

            let error = value.element(forName: "error")
            
            if (error!.attributeStringValue(forName: "code")! == "500") {
                                
                if let text = error?.element(forName: "text") {
                    
                    if let value = text.stringValue {
                        if value == "Users are not allowed to register accounts so quickly" {
                            result = true
                        }
                    }
                 
                }
                
            }
                            
        }
        
        return result
    }
    
    /* unused for now */
    func contactNotConnected(_ value: XMPPIQ) -> String? {
        
        var result: String? = nil
        var phone = ""

        if (value.fromStr! == "pubsub.s.halloapp.net" && value.isErrorIQ) {
            let pubsub = value.element(forName: "pubsub")
            
            if let subscribe = pubsub?.element(forName: "subscribe"),
                let node = subscribe.attributeStringValue(forName: "node") {
                let nodeParts = node.components(separatedBy: "-")
                
                if (nodeParts[0] == "contacts") {
                    phone = nodeParts[1]
                    
                    let error = value.element(forName: "error")
                    
                    if (error!.attributeStringValue(forName: "code")! == "404") {
                        result = phone
                    }
                    
                    
                }
            }
            
        }
        
        return result
    }
    
    
    func parseFeedItem(_ value: XMPPMessage) -> FeedDataItem{
        
        let feedDataItem = FeedDataItem()
        
        let event = value.element(forName: "event")
        let items = event?.element(forName: "items")
 

        let itemList = items?.elements(forName: "item")
        
        for item in itemList ?? [] {
            
            let entry = item.element(forName: "entry")
        
            let itemId = item.attributeStringValue(forName: "id")
            feedDataItem.itemId = itemId!
            
            if let text = entry?.element(forName: "text") {
                if let textValue = text.stringValue {
                    feedDataItem.text = textValue
                }
            }
            
            if let username = entry?.element(forName: "username") {
                if let usernameValue = username.stringValue {
                    feedDataItem.username = usernameValue
                }
            }
            
            if let userImageUrl = entry?.element(forName: "userImageUrl") {
                if let userImageUrlValue = userImageUrl.stringValue {
                    feedDataItem.userImageUrl = userImageUrlValue
                }
            }

            if let imageUrl = entry?.element(forName: "imageUrl") {
                if let imageUrlValue = imageUrl.stringValue {
                    feedDataItem.imageUrl = imageUrlValue
                }
            }
            
            if let timestamp = entry?.element(forName: "timestamp") {
                if let timestampValue = timestamp.stringValue {
                    
                    if let convertedTimestampValue = Double(timestampValue) {
                        feedDataItem.timestamp = convertedTimestampValue
                    }
                    
                }
            }
            
        }
        
        return feedDataItem
    }
    
    
    func parseAffList(_ value: XMPPIQ) -> [String] {
       
        var result: [String] = []
       
        let pubsub = value.element(forName: "pubsub")
        let affiliations = pubsub?.element(forName: "affiliations")
        
        let affList = affiliations?.elements(forName: "affiliation")


        for aff in affList ?? [] {
            
            let node = aff.attributeStringValue(forName: "node")
            let status = aff.attributeStringValue(forName: "affiliation")
            
            if (status == "member" || status == "publisher") {

                if node != nil {
                    
                    let nodeParts = node!.components(separatedBy: "-")
                    
                    if (nodeParts[0] == "contacts") {
                        result.append(nodeParts[1])
                    }
                    
                }
                
            }
            

           
        }
       
       
        return result
    }
    
    func parseListItems(_ value: XMPPIQ) -> [FeedDataItem] {
       
        var feedList: [FeedDataItem] = []
       
        let pubsub = value.element(forName: "pubsub")
        let items = pubsub?.element(forName: "items")
        
        let itemList = items?.elements(forName: "item")


        for item in itemList ?? [] {
            
            let feedItem = FeedDataItem()

            let entry = item.element(forName: "entry")
       
            let itemId = item.attributeStringValue(forName: "id")
            feedItem.itemId = itemId!
            
            if let text = entry?.element(forName: "text") {
               if let textValue = text.stringValue {
                   feedItem.text = textValue
               }
            }
           
            if let username = entry?.element(forName: "username") {
               if let usernameValue = username.stringValue {
                   feedItem.username = usernameValue
               }
            }
           
            if let userImageUrl = entry?.element(forName: "userImageUrl") {
               if let userImageUrlValue = userImageUrl.stringValue {
                   feedItem.userImageUrl = userImageUrlValue
               }
            }

            if let imageUrl = entry?.element(forName: "imageUrl") {
                if let imageUrlValue = imageUrl.stringValue {
                   feedItem.imageUrl = imageUrlValue
                }
            }
           
            if let timestamp = entry?.element(forName: "timestamp") {
               if let timestampValue = timestamp.stringValue {
                   
                   if let convertedTimestampValue = Double(timestampValue) {
                       feedItem.timestamp = convertedTimestampValue
                   }
                   
               }
            }
            
            feedList.append(feedItem)
           
         
        }
       
       
        return feedList
    }
   
    /*
     role: [owner|member|none]
     */
    func sendAffBatch(xmppStream: XMPPStream, node: String, from: String, users: [BatchId], role: String, id: String) {
//        print("sendAff")
        
        let affiliations = XMLElement(name: "affiliations")
        affiliations.addAttribute(withName: "node", stringValue: node)
        
        for user in users {
            let item = XMLElement(name: "affiliation")
            item.addAttribute(withName: "jid", stringValue: "\(user.phone)@s.halloapp.net")
            item.addAttribute(withName: "affiliation", stringValue: role)
            affiliations.addChild(item)
        }

        let pubsub = XMLElement(name: "pubsub")
        pubsub.addAttribute(withName: "xmlns", stringValue: "http://jabber.org/protocol/pubsub#owner")
        pubsub.addChild(affiliations)

        let iq = XMLElement(name: "iq")
        iq.addAttribute(withName: "type", stringValue: "set")
        iq.addAttribute(withName: "from", stringValue: "\(from)@s.halloapp.net/iphone")
        iq.addAttribute(withName: "to", stringValue: "pubsub.s.halloapp.net")
        iq.addAttribute(withName: "id", stringValue: id)
        iq.addChild(pubsub)
        
        xmppStream.send(iq)
    }
    
    /*
     role: [owner|member|none]
     */
    func sendAff(xmppStream: XMPPStream, node: String, from: String, user: String, role: String) {
//        print("sendAff")
        
        let item = XMLElement(name: "affiliation")
        item.addAttribute(withName: "jid", stringValue: "\(user)@s.halloapp.net")
        item.addAttribute(withName: "affiliation", stringValue: role)
        
        let affiliations = XMLElement(name: "affiliations")
        affiliations.addAttribute(withName: "node", stringValue: node)
        affiliations.addChild(item)

        let pubsub = XMLElement(name: "pubsub")
        pubsub.addAttribute(withName: "xmlns", stringValue: "http://jabber.org/protocol/pubsub#owner")
        pubsub.addChild(affiliations)

        let iq = XMLElement(name: "iq")
        iq.addAttribute(withName: "type", stringValue: "set")
        iq.addAttribute(withName: "from", stringValue: "\(from)@s.halloapp.net/iphone")
        iq.addAttribute(withName: "to", stringValue: "pubsub.s.halloapp.net")
        iq.addAttribute(withName: "id", stringValue: "aff: \(user)")
        iq.addChild(pubsub)
        
        xmppStream.send(iq)
    }
    
}
