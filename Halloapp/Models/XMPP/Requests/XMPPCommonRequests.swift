//
//  XMPPCommonRequests.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 3/13/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import XMPPFramework

class XMPPPushTokenRequest: XMPPRequest {
    var completion: XMPPRequestCompletion

    init(token: String, completion: @escaping XMPPRequestCompletion) {
        self.completion = completion
        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: XMPPIQDefaultTo), elementID: UUID().uuidString)
        iq.addChild({
            let pushRegister = XMLElement(name: "push_register", xmlns: "halloapp:push:notifications")
            pushRegister.addChild({
                let pushToken = XMPPElement(name: "push_token", stringValue: token)
                pushToken.addAttribute(withName: "os", stringValue: "ios")
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
