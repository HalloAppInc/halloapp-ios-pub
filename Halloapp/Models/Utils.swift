//
//  Utils.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/18/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Foundation
import SwiftDate
import XMPPFramework

extension Data {
    var hexString: String {
        let hexString = map { String(format: "%02.2hhx", $0) }.joined()
        return hexString
    }
}

extension Date {
    func timeAgoDisplay() -> String {

        let calendar = Calendar.current
        let minuteAgo = calendar.date(byAdding: .minute, value: -1, to: Date())!
        let hourAgo = calendar.date(byAdding: .hour, value: -1, to: Date())!
        let dayAgo = calendar.date(byAdding: .day, value: -1, to: Date())!
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!

        if minuteAgo < self {
            let diff = Calendar.current.dateComponents([.second], from: self, to: Date()).second ?? 0
            return "\(diff) sec ago"
        } else if hourAgo < self {
            let diff = Calendar.current.dateComponents([.minute], from: self, to: Date()).minute ?? 0
            return "\(diff) min ago"
        } else if dayAgo < self {
            let diff = Calendar.current.dateComponents([.hour], from: self, to: Date()).hour ?? 0
            return "\(diff) hrs ago"
        } else if weekAgo < self {
            let diff = Calendar.current.dateComponents([.day], from: self, to: Date()).day ?? 0
            return "\(diff) days ago"
        }
        let diff = Calendar.current.dateComponents([.weekOfYear], from: self, to: Date()).weekOfYear ?? 0
        return "\(diff) weeks ago"
    }
}

class Utils {

    func appVersion() -> String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return ""
        }
        guard let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String else {
            return "\(version)"
        }
        return "\(version) (\(buildNumber))"
    }
    
    func timeForm_2(dateStr: String) -> String {

        let origDateDouble = Double(dateStr)

        var result = ""
        
        if let origDateDouble = origDateDouble {
        let now = Date(timeIntervalSince1970: origDateDouble)
        result = now.timeAgoDisplay()
        }
        
        return result

    }
    
    func timeForm(dateStr: String) -> String {

        let origDateDouble = Double(dateStr)
        
        var result = ""
        
        var diff = 0
        
        if let origDateDouble = origDateDouble {
            var origDate = Int(origDateDouble)
            
            let current = Int(Date().timeIntervalSince1970)
            
            let calendar = Calendar.current
            
            diff = current - origDate
            
            /* one-off": account for if time was in milliseconds */
            if diff < 0 {
                origDate = origDate/1000
                diff = current - origDate
            }
            
            
            if (diff <= 3) {
                result = "now"
            } else if (diff <= 59) {
                result = "\(String(diff))s"
            } else if diff <= 3600 {
                let diff2 = diff/60
                result = "\(String(diff2))m\(diff2 > 1 ? "" : "")"
            } else if calendar.isDateInYesterday(Date(timeIntervalSince1970: origDateDouble)) {
                result = "Yesterday"
            } else if diff <= 86400 {
                let diff2 = diff/(60*60)
                result = "\(String(diff2))h\(diff2 > 1 ? "" : "")"
            } else if diff <= 86400*7 {
 
                let diff2 = diff/(86400) + 1

                result = "\(String(diff2))d\(diff2 > 1 ? "" : "")"

               
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
    
    func parseSubsForExtras(_ value: XMPPIQ) -> [String] {
       
        var result: [String] = []
       
        let pubsub = value.element(forName: "pubsub")
        let subscriptions = pubsub?.element(forName: "subscriptions")
        
        let subList = subscriptions?.elements(forName: "subscription")
        
        for sub in subList ?? [] {
            
            let status = sub.attributeStringValue(forName: "subscription")
            let node = sub.attributeStringValue(forName: "node")
            
            if (status == "subscribed") {

                if node != nil {
                    
                    let nodeParts = node!.components(separatedBy: "-")

                    if (nodeParts[0] != "feed") {
                        continue
                    }

                    if (nodeParts.count > 1) {
                        result.append(nodeParts[1])
                    }
                    
                    
                }
                
            }
            
           
        }
       
       
        return result
    }

    func parseFeedItems(_ value: XMLElement?) -> ([FeedDataItem], [FeedComment]) {
        var feedList: [FeedDataItem] = []
        var commentList: [FeedComment] = []
       
        let items = value?.element(forName: "items")
        let itemList = items?.elements(forName: "item")

        for item in itemList ?? [] {
            let entry = item.element(forName: "entry")
            let itemId = item.attributeStringValue(forName: "id")
            let jid = item.attributeStringValue(forName: "publisher")
            let serverTimestamp = item.attributeStringValue(forName: "timestamp")
            
            // Parse feed posts.
            if let post = entry?.element(forName: "feedpost") {
                
                let feedItem = FeedDataItem()
                feedItem.itemId = itemId!
                
                if let text = post.element(forName: "text") {
                    if let textValue = text.stringValue {
                        feedItem.text = textValue
                    }
                }
                
                if jid != nil {
                    if let jidParts = jid?.components(separatedBy: "@") {
                        feedItem.username = jidParts[0]
                    }
                } else if let username = post.element(forName: "username") {
                    if let usernameValue = username.stringValue {
                        feedItem.username = usernameValue
                    }
                }
                
                let media = post.element(forName: "media")
                let urls = media?.elements(forName: "url")
                
                var medArr: [FeedMedia] = []
                
                var order = 1
                
                for url in urls ?? [] {
                    
                    let med: FeedMedia = FeedMedia()
                    
                    med.feedItemId = feedItem.itemId
                    med.order = order
                    order += 1
                    
                    if let medType = url.attributeStringValue(forName: "type") {
                        med.type = medType
                    }
                    
                    if let medWidth = url.attributeStringValue(forName: "width") {
                        med.width = Int(medWidth) ?? 0
                    }
                    
                    if let medHeight = url.attributeStringValue(forName: "height") {
                        med.height = Int(medHeight) ?? 0
                    }
                    
                    if let key = url.attributeStringValue(forName: "key") {
                        med.key = key
                    }
                    
                    if let sha256hash = url.attributeStringValue(forName: "sha256hash") {
                        med.sha256hash = sha256hash
                    }
 
                    if let medUrl = url.stringValue {
                        med.url = medUrl
                        
                        if med.url != "" {
                            medArr.append(med)
                        }
                    }
                    
                }
            
                feedItem.media = medArr
                
                if serverTimestamp != nil {
                    if let convertedServerTimestamp = Double(serverTimestamp!) {
                        feedItem.timestamp = convertedServerTimestamp
                    }
                } else {
                    if let timestamp = post.element(forName: "timestamp") {
                        if let timestampValue = timestamp.stringValue {
                            if let convertedTimestampValue = Double(timestampValue) {
                                feedItem.timestamp = convertedTimestampValue
                            }
                        }
                    }
                }
                
                feedList.append(feedItem)
//                print ("feed data item: \(feedItem.media.count)")
                
            } else if let post = entry?.element(forName: "comment") {
                
                var commentItem = FeedComment(id: itemId!)
                
                if let text = post.element(forName: "parentCommentId") {
                  if let textValue = text.stringValue {
                        commentItem.parentCommentId = textValue
                    }
                }
                
                if let text = post.element(forName: "text") {
                  if let textValue = text.stringValue {
                        commentItem.text = textValue
                    }
                }
              
                if jid != nil {
                    
                    if let jidParts = jid?.components(separatedBy: "@") {
                        commentItem.username = jidParts[0]
                    }
                    
                } else if let username = post.element(forName: "username") {
                    if let usernameValue = username.stringValue {
                        commentItem.username = usernameValue
                    }
                }
                
                if let feedItemId = post.element(forName: "feedItemId") {
                    if let feedItemId = feedItemId.stringValue {
                        commentItem.feedItemId = feedItemId
                    }
                }
                
                if serverTimestamp != nil {
                    if let convertedServerTimestamp = Double(serverTimestamp!) {
                        commentItem.timestamp = convertedServerTimestamp
                    }
                } else {
                    if let timestamp = post.element(forName: "timestamp") {
                        if let timestampValue = timestamp.stringValue {
                            if let convertedTimestampValue = Double(timestampValue) {
                                commentItem.timestamp = convertedTimestampValue
                            }
                        }
                    }
                }
                
                commentList.append(commentItem)
//                print ("comment item: \(commentItem.username) - \(commentItem.text)")
                
            }
        }
        return (feedList, commentList)
    }

    func getCountryCallingCode(countryRegionCode:String) -> [String] {
        
        let prefix: [String: [String]] = self.getCountryList()
        
        let countryDialingCode = prefix[countryRegionCode]
        return countryDialingCode!
    }
    
    func getCountryFromCode(countryCode:String) -> [String: [String]] {
        
        let result = ["Unknown": ["Unknown", "Unknown"]]
        
//        let prefix: [String: [String]] = self.getCountryList()
//
//        let idx = prefix.firstIndex(where: {$0.1[1] == countryCode})
//
//        if (idx != nil) {
//
//                print(idx)
////            countryDialingCode = prefix[idx] {
////            return countryDialingCode!
//
//        }
        
        return result
    }
    
    func getCountryList() -> [String: [String]] {
        let prefix =  ["AF": ["Afghanistan","93"],
                       "AX": ["Aland Islands","358"],
                       "AL": ["Albania","355"],
                       "DZ": ["Algeria","213"],
                       "AS": ["American Samoa","1"],
                       "AD": ["Andorra","376"],
                       "AO": ["Angola","244"],
                       "AI": ["Anguilla","1"],
                       "AQ": ["Antarctica","672"],
                       "AG": ["Antigua and Barbuda","1"],
                       "AR": ["Argentina","54"],
                       "AM": ["Armenia","374"],
                       "AW": ["Aruba","297"],
                       "AU": ["Australia","61"],
                       "AT": ["Austria","43"],
                       "AZ": ["Azerbaijan","994"],
                       "BS": ["Bahamas","1"],
                       "BH": ["Bahrain","973"],
                       "BD": ["Bangladesh","880"],
                       "BB": ["Barbados","1"],
                       "BY": ["Belarus","375"],
                       "BE": ["Belgium","32"],
                       "BZ": ["Belize","501"],
                       "BJ": ["Benin","229"],
                       "BM": ["Bermuda","1"],
                       "BT": ["Bhutan","975"],
                       "BO": ["Bolivia","591"],
                       "BA": ["Bosnia and Herzegovina","387"],
                       "BW": ["Botswana","267"],
                       "BV": ["Bouvet Island","47"],
                       "BQ": ["BQ","599"],
                       "BR": ["Brazil","55"],
                       "IO": ["British Indian Ocean Territory","246"],
                       "VG": ["British Virgin Islands","1"],
                       "BN": ["Brunei Darussalam","673"],
                       "BG": ["Bulgaria","359"],
                       "BF": ["Burkina Faso","226"],
                       "BI": ["Burundi","257"],
                       "KH": ["Cambodia","855"],
                       "CM": ["Cameroon","237"],
                       "CA": ["Canada","1"],
                       "CV": ["Cape Verde","238"],
                       "KY": ["Cayman Islands","345"],
                       "CF": ["Central African Republic","236"],
                       "TD": ["Chad","235"],
                       "CL": ["Chile","56"],
                       "CN": ["China","86"],
                       "CX": ["Christmas Island","61"],
                       "CC": ["Cocos (Keeling) Islands","61"],
                       "CO": ["Colombia","57"],
                       "KM": ["Comoros","269"],
                       "CG": ["Congo (Brazzaville)","242"],
                       "CD": ["Congo, Democratic Republic of the","243"],
                       "CK": ["Cook Islands","682"],
                       "CR": ["Costa Rica","506"],
                       "CI": ["Côte d'Ivoire","225"],
                       "HR": ["Croatia","385"],
                       "CU": ["Cuba","53"],
                       "CW": ["Curacao","599"],
                       "CY": ["Cyprus","537"],
                       "CZ": ["Czech Republic","420"],
                       "DK": ["Denmark","45"],
                       "DJ": ["Djibouti","253"],
                       "DM": ["Dominica","1"],
                       "DO": ["Dominican Republic","1"],
                       "EC": ["Ecuador","593"],
                       "EG": ["Egypt","20"],
                       "SV": ["El Salvador","503"],
                       "GQ": ["Equatorial Guinea","240"],
                       "ER": ["Eritrea","291"],
                       "EE": ["Estonia","372"],
                       "ET": ["Ethiopia","251"],
                       "FK": ["Falkland Islands (Malvinas)","500"],
                       "FO": ["Faroe Islands","298"],
                       "FJ": ["Fiji","679"],
                       "FI": ["Finland","358"],
                       "FR": ["France","33"],
                       "GF": ["French Guiana","594"],
                       "PF": ["French Polynesia","689"],
                       "TF": ["French Southern Territories","689"],
                       "GA": ["Gabon","241"],
                       "GM": ["Gambia","220"],
                       "GE": ["Georgia","995"],
                       "DE": ["Germany","49"],
                       "GH": ["Ghana","233"],
                       "GI": ["Gibraltar","350"],
                       "GR": ["Greece","30"],
                       "GL": ["Greenland","299"],
                       "GD": ["Grenada","1"],
                       "GP": ["Guadeloupe","590"],
                       "GU": ["Guam","1"],
                       "GT": ["Guatemala","502"],
                       "GG": ["Guernsey","44"],
                       "GN": ["Guinea","224"],
                       "GW": ["Guinea-Bissau","245"],
                       "GY": ["Guyana","595"],
                       "HT": ["Haiti","509"],
                       "VA": ["Holy See (Vatican City State)","379"],
                       "HN": ["Honduras","504"],
                       "HK": ["Hong Kong, Special Administrative Region of China","852"],
                       "HU": ["Hungary","36"],
                       "IS": ["Iceland","354"],
                       "IN": ["India","91"],
                       "ID": ["Indonesia","62"],
                       "IR": ["Iran, Islamic Republic of","98"],
                       "IQ": ["Iraq","964"],
                       "IE": ["Ireland","353"],
                       "IM": ["Isle of Man","44"],
                       "IL": ["Israel","972"],
                       "IT": ["Italy","39"],
                       "JM": ["Jamaica","1"],
                       "JP": ["Japan","81"],
                       "JE": ["Jersey","44"],
                       "JO": ["Jordan","962"],
                       "KZ": ["Kazakhstan","77"],
                       "KE": ["Kenya","254"],
                       "KI": ["Kiribati","686"],
                       "KP": ["Korea, Democratic People's Republic of","850"],
                       "KR": ["Korea, Republic of","82"],
                       "KW": ["Kuwait","965"],
                       "KG": ["Kyrgyzstan","996"],
                       "LA": ["Lao PDR","856"],
                       "LV": ["Latvia","371"],
                       "LB": ["Lebanon","961"],
                       "LS": ["Lesotho","266"],
                       "LR": ["Liberia","231"],
                       "LY": ["Libya","218"],
                       "LI": ["Liechtenstein","423"],
                       "LT": ["Lithuania","370"],
                       "LU": ["Luxembourg","352"],
                       "MO": ["Macao, Special Administrative Region of China","853"],
                       "MK": ["Macedonia, Republic of","389"],
                       "MG": ["Madagascar","261"],
                       "MW": ["Malawi","265"],
                       "MY": ["Malaysia","60"],
                       "MV": ["Maldives","960"],
                       "ML": ["Mali","223"],
                       "MT": ["Malta","356"],
                       "MH": ["Marshall Islands","692"],
                       "MQ": ["Martinique","596"],
                       "MR": ["Mauritania","222"],
                       "MU": ["Mauritius","230"],
                       "YT": ["Mayotte","262"],
                       "MX": ["Mexico","52"],
                       "FM": ["Micronesia, Federated States of","691"],
                       "MD": ["Moldova","373"],
                       "MC": ["Monaco","377"],
                       "MN": ["Mongolia","976"],
                       "ME": ["Montenegro","382"],
                       "MS": ["Montserrat","1"],
                       "MA": ["Morocco","212"],
                       "MZ": ["Mozambique","258"],
                       "MM": ["Myanmar","95"],
                       "NA": ["Namibia","264"],
                       "NR": ["Nauru","674"],
                       "NP": ["Nepal","977"],
                       "NL": ["Netherlands","31"],
                       "AN": ["Netherlands Antilles","599"],
                       "NC": ["New Caledonia","687"],
                       "NZ": ["New Zealand","64"],
                       "NI": ["Nicaragua","505"],
                       "NE": ["Niger","227"],
                       "NG": ["Nigeria","234"],
                       "NU": ["Niue","683"],
                       "NF": ["Norfolk Island","672"],
                       "MP": ["Northern Mariana Islands","1"],
                       "NO": ["Norway","47"],
                       "OM": ["Oman","968"],
                       "PK": ["Pakistan","92"],
                       "PW": ["Palau","680"],
                       "PS": ["Palestinian Territory, Occupied","970"],
                       "PA": ["Panama","507"],
                       "PG": ["Papua New Guinea","675"],
                       "PY": ["Paraguay","595"],
                       "PE": ["Peru","51"],
                       "PH": ["Philippines","63"],
                       "PN": ["Pitcairn","872"],
                       "PL": ["Poland","48"],
                       "PT": ["Portugal","351"],
                       "PR": ["Puerto Rico","1"],
                       "QA": ["Qatar","974"],
                       "RE": ["Réunion","262"],
                       "RO": ["Romania","40"],
                       "RU": ["Russian Federation","7"],
                       "RW": ["Rwanda","250"],
                       "SH": ["Saint Helena","290"],
                       "KN": ["Saint Kitts and Nevis","1"],
                       "LC": ["Saint Lucia","1"],
                       "PM": ["Saint Pierre and Miquelon","508"],
                       "VC": ["Saint Vincent and Grenadines","1"],
                       "BL": ["Saint-Barthélemy","590"],
                       "MF": ["Saint-Martin (French part)","590"],
                       "WS": ["Samoa","685"],
                       "SM": ["San Marino","378"],
                       "ST": ["Sao Tome and Principe","239"],
                       "SA": ["Saudi Arabia","966"],
                       "SN": ["Senegal","221"],
                       "RS": ["Serbia","381"],
                       "SC": ["Seychelles","248"],
                       "SL": ["Sierra Leone","232"],
                       "SG": ["Singapore","65"],
                       "SX": ["Sint Maarten","1"],
                       "SK": ["Slovakia","421"],
                       "SI": ["Slovenia","386"],
                       "SB": ["Solomon Islands","677"],
                       "SO": ["Somalia","252"],
                       "ZA": ["South Africa","27"],
                       "GS": ["South Georgia and the South Sandwich Islands","500"],
                       "SS​": ["South Sudan","211"],
                       "ES": ["Spain","34"],
                       "LK": ["Sri Lanka","94"],
                       "SD": ["Sudan","249"],
                       "SR": ["Suriname","597"],
                       "SJ": ["Svalbard and Jan Mayen Islands","47"],
                       "SZ": ["Swaziland","268"],
                       "SE": ["Sweden","46"],
                       "CH": ["Switzerland","41"],
                       "SY": ["Syrian Arab Republic (Syria)","963"],
                       "TW": ["Taiwan, Republic of China","886"],
                       "TJ": ["Tajikistan","992"],
                       "TZ": ["Tanzania, United Republic of","255"],
                       "TH": ["Thailand","66"],
                       "TL": ["Timor-Leste","670"],
                       "TG": ["Togo","228"],
                       "TK": ["Tokelau","690"],
                       "TO": ["Tonga","676"],
                       "TT": ["Trinidad and Tobago","1"],
                       "TN": ["Tunisia","216"],
                       "TR": ["Turkey","90"],
                       "TM": ["Turkmenistan","993"],
                       "TC": ["Turks and Caicos Islands","1"],
                       "TV": ["Tuvalu","688"],
                       "UG": ["Uganda","256"],
                       "UA": ["Ukraine","380"],
                       "AE": ["United Arab Emirates","971"],
                       "GB": ["United Kingdom","44"],
                       "US": ["United States of America","1"],
                       "UY": ["Uruguay","598"],
                       "UZ": ["Uzbekistan","998"],
                       "VU": ["Vanuatu","678"],
                       "VE": ["Venezuela (Bolivarian Republic of)","58"],
                       "VN": ["Viet Nam","84"],
                       "VI": ["Virgin Islands, US","1"],
                       "WF": ["Wallis and Futuna Islands","681"],
                       "EH": ["Western Sahara","212"],
                       "YE": ["Yemen","967"],
                       "ZM": ["Zambia","260"],
                       "ZW": ["Zimbabwe","263"]]

        return prefix
    }
        
    func sendAck(xmppStream: XMPPStream, id: String, from: String) {
    
        let ack = XMLElement(name: "ack")
        ack.addAttribute(withName: "from", stringValue: "\(from)@s.halloapp.net/iphone")
        ack.addAttribute(withName: "to", stringValue: "pubsub.s.halloapp.net")
        ack.addAttribute(withName: "id", stringValue: id)
        
//        print("\(ack)")
        xmppStream.send(ack)
    }
}
