//
//  Utils.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/18/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Foundation
import XMPPFramework

extension Data {
    var hexString: String {
        let hexString = map { String(format: "%02.2hhx", $0) }.joined()
        return hexString
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
