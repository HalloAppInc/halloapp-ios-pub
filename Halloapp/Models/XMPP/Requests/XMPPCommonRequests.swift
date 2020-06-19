//
//  XMPPCommonRequests.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 3/13/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import Foundation
import XMPPFramework

class XMPPPushTokenRequest: XMPPRequest {
    var completion: XMPPRequestCompletion

    init(token: String, completion: @escaping XMPPRequestCompletion) {
        self.completion = completion
        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: XMPPIQDefaultTo))
        iq.addChild({
            let pushRegister = XMLElement(name: "push_register", xmlns: "halloapp:push:notifications")
            pushRegister.addChild({
                let pushToken = XMPPElement(name: "push_token", stringValue: token)
                #if DEBUG
                pushToken.addAttribute(withName: "os", stringValue: "ios_dev")
                #else
                pushToken.addAttribute(withName: "os", stringValue: "ios")
                #endif
                return pushToken
            }())
            return pushRegister
        }())
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        self.completion(nil)
    }

    override func didFail(with error: Error) {
        self.completion(error)
    }
}

class XMPPSendNameRequest: XMPPRequest {
    var completion: XMPPRequestCompletion

    init(name: String, completion: @escaping XMPPRequestCompletion) {
        self.completion = completion
        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: XMPPIQDefaultTo))
        iq.addChild({
            let nameElement = XMLElement(name: "name", xmlns: "halloapp:users:name")
            nameElement.stringValue = name
            return nameElement
            }())
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        self.completion(nil)
    }

    override func didFail(with error: Error) {
        self.completion(error)
    }
}

class XMPPUploadAvatarRequest: XMPPRequest {
    typealias XMPPUploadAvatarRequestCompletion = (Error?, String?) -> Void
    
    var completion: XMPPUploadAvatarRequestCompletion
    
    init(data: Data, completion: @escaping XMPPUploadAvatarRequestCompletion) {
        self.completion = completion
        
        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: XMPPIQDefaultTo))
        
        iq.addChild({
            let avatarElement = XMLElement(name: "avatar", xmlns: "halloapp:user:avatar")
            
            avatarElement.addAttribute(withName: "bytes", intValue: Int32(data.count))
            avatarElement.addAttribute(withName: "width", intValue: Int32(AvatarStore.avatarSize))
            avatarElement.addAttribute(withName: "height", intValue: Int32(AvatarStore.avatarSize))
            
            avatarElement.stringValue = data.base64EncodedString()
            
            return avatarElement
        }())
        
        super.init(iq: iq)
    }
    
    override func didFinish(with response: XMPPIQ) {
        let avatarId = response.element(forName: "avatar")?.attributeStringValue(forName: "id")
        self.completion(nil, avatarId)
    }

    override func didFail(with error: Error) {
        self.completion(error, nil)
    }
}
