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
    private let completion: XMPPRequestCompletion

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
        self.completion(.success(()))
    }

    override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}

class XMPPSendNameRequest: XMPPRequest {
    private let completion: XMPPRequestCompletion

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
        self.completion(.success(()))
    }

    override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}

class XMPPUploadAvatarRequest: XMPPRequest {
    typealias XMPPUploadAvatarRequestCompletion = (Result<String?, Error>) -> Void
    
    private let completion: XMPPUploadAvatarRequestCompletion
    
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
        self.completion(.success(avatarId))
    }

    override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}

class XMPPRemoveAvatarRequest: XMPPRequest {
    private let completion: XMPPRequestCompletion
    
    init(completion: @escaping XMPPRequestCompletion) {
        self.completion = completion
        
        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: XMPPIQDefaultTo))
        iq.addChild({
            let avatarElement = XMLElement(name: "avatar", xmlns: "halloapp:user:avatar")
            avatarElement.addAttribute(withName: "id", stringValue: "")
            return avatarElement
        }())
        
        super.init(iq: iq)
    }
    
    override func didFinish(with response: XMPPIQ) {
        self.completion(.success(()))
    }

    override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
}

class XMPPQueryAvatarRequest: XMPPRequest {
    typealias XMPPQueryAvatarRequestCompletion = (Result<String?, Error>) -> Void
    
    private let completion: XMPPQueryAvatarRequestCompletion
    
    init(userId: UserID, completion: @escaping XMPPQueryAvatarRequestCompletion) {
        self.completion = completion
        
        let iq = XMPPIQ(iqType: .get, to: XMPPJID(string: XMPPIQDefaultTo))
        
        iq.addChild({
            let avatarElement = XMLElement(name: "avatar", xmlns: "halloapp:user:avatar")
            
            avatarElement.addAttribute(withName: "userid", stringValue: userId)
            
            return avatarElement
        }())
        
        super.init(iq: iq)
    }
    
    override func didFail(with error: Error) {
        self.completion(.failure(error))
    }
    
    override func didFinish(with response: XMPPIQ) {
        let avatarId = response.element(forName: "avatar")?.attributeStringValue(forName: "id")
        self.completion(.success(avatarId))
    }
}

class XMPPClientVersionRequest : XMPPRequest {
    typealias RequestCompletion = (XMPPIQ?, Error?) -> Void
    let completion: RequestCompletion

    init(completion: @escaping RequestCompletion) {
        self.completion = completion
        let iq = XMPPIQ(iqType: .get, to: XMPPJID(string: "s.halloapp.net"))
        iq.addChild({
            let clientVersion = XMLElement(name: "client_version", xmlns: "halloapp:client:version")
            clientVersion.addChild({
                let appVersion = AppContext.appVersionForXMPP
                let userAgent = NSString(string: "HalloApp/iOS\(appVersion)")
                let version = XMPPElement(name: "version", stringValue: String(userAgent))
                return version
            }())
            return clientVersion
        }())
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        self.completion(response, nil)
    }

    override func didFail(with error: Error) {
        self.completion(nil, error)
    }
}
