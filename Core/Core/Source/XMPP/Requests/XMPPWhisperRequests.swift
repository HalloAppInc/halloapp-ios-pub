//
//  HalloApp
//
//  Created by Tony Jiang on 7/8/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation
import XMPPFramework

public typealias WhisperKeyBundle = XMPPWhisperKey

public enum WhisperMessage {
    case normal(keyCount: Int32)
    case update(userID: UserID)

    public init?(_ item: DDXMLElement) {
        guard let whisperType = item.attributeStringValue(forName: "type") else { return nil }
        if let uid = item.attributeStringValue(forName: "uid"), whisperType == "update" {
            self = .update(userID: uid)
        } else if let otpKeyCount = item.element(forName: "otp_key_count"), whisperType == "normal" {
            self = .normal(keyCount: otpKeyCount.stringValueAsInt())
        } else {
            return nil
        }
    }

    public init?(_ pbKeys: PBwhisper_keys) {
        switch pbKeys.action {
        case .normal:
            self = .normal(keyCount: pbKeys.otpKeyCount)
        case .update:
            self = .update(userID: UserID(pbKeys.uid))
        default:
            return nil
        }
    }
}

class XMPPWhisperUploadRequest : XMPPRequest {
    typealias XMPPWhisperRequestCompletion = (Error?) -> Void
    let completion: XMPPWhisperRequestCompletion

    init(keyBundle: XMPPWhisperKey, completion: @escaping XMPPWhisperRequestCompletion) {
        self.completion = completion
        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: "s.halloapp.net"))
        iq.addChild(keyBundle.xmppElement)
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        self.completion(nil)
    }

    override func didFail(with error: Error) {
        self.completion(error)
    }
}

class XMPPWhisperAddOneTimeKeysRequest : XMPPRequest {
    typealias XMPPWhisperRequestCompletion = (Error?) -> Void
    let completion: XMPPWhisperRequestCompletion

    init(whisperKeyBundle: XMPPWhisperKey, completion: @escaping XMPPWhisperRequestCompletion) {
        self.completion = completion
        let iq = XMPPIQ(iqType: .set, to: XMPPJID(string: "s.halloapp.net"))
        iq.addChild(whisperKeyBundle.xmppElement)
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        print("whisper uploader response: \(response)")
        self.completion(nil)
    }

    override func didFail(with error: Error) {
        self.completion(error)
    }
}

class XMPPWhisperGetBundleRequest : XMPPRequest {
    typealias XMPPWhisperRequestCompletion = (XMPPIQ?, Error?) -> Void
    let completion: XMPPWhisperRequestCompletion

    init(targetUserId: String, completion: @escaping XMPPWhisperRequestCompletion) {
        print("XMPPWhisperGetBundleRequest")
        self.completion = completion
        let iq = XMPPIQ(iqType: .get, to: XMPPJID(string: "s.halloapp.net"))
        iq.addAttribute(withName: "from", stringValue: "\(AppContext.shared.userData.userId)@s.halloapp.net")
        iq.addChild({
            let whisperKeys = XMPPElement(name: "whisper_keys", xmlns: "halloapp:whisper:keys")
            whisperKeys.addAttribute(withName: "type", stringValue: "get")
            whisperKeys.addAttribute(withName: "uid", stringValue: targetUserId)
            return whisperKeys
        }())
        super.init(iq: iq)
    }

    override func didFinish(with response: XMPPIQ) {
        print("XMPPWhisperGetBundleRequest success")
        self.completion(response, nil)
    }

    override func didFail(with error: Error) {
        print("XMPPWhisperGetBundleRequest error \(error)")
        self.completion(nil, error)
    }
}


class XMPPWhisperGetCountOfOneTimeKeysRequest : XMPPRequest {
    typealias XMPPWhisperRequestCompletion = (XMPPIQ?, Error?) -> Void
    let completion: XMPPWhisperRequestCompletion

    init(completion: @escaping XMPPWhisperRequestCompletion) {
        self.completion = completion
        let iq = XMPPIQ(iqType: .get, to: XMPPJID(string: "s.halloapp.net"))
        iq.addAttribute(withName: "from", stringValue: "\(AppContext.shared.userData.userId)@s.halloapp.net")
        iq.addChild({
            let whisperKeys = XMPPElement(name: "whisper_keys", xmlns: "halloapp:whisper:keys")
            whisperKeys.addAttribute(withName: "type", stringValue: "count")
            return whisperKeys
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
