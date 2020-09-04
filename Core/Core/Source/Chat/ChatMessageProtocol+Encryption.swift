//
//  XMPPChatMessage+Encryption.swift
//  Core
//
//  Created by Garrett on 8/21/20.
//  Copyright © 2020 Hallo App, Inc. All rights reserved.
//

import Foundation
import XMPPFramework

extension ChatMessageProtocol {
    func encryptXMPPElement(_ encrypt: EncryptOperation, completion: @escaping (XMPPElement) -> Void) {
        let element = self.xmppElement
        guard let chat = element.element(forName: "chat") else { return }

        guard let s1 = chat.element(forName: "s1") else { return }
        guard let encStringValue = s1.stringValue else { return }

        guard let unencryptedData = Data(base64Encoded: encStringValue, options: .ignoreUnknownCharacters) else { return }

        encrypt(unencryptedData) { encryptedData in
            if let data = encryptedData.data {
                chat.addChild({
                    let enc = XMPPElement(name: "enc", stringValue: data.base64EncodedString())
                    if let identityKey = encryptedData.identityKey {
                        enc.addAttribute(withName: "identity_key", stringValue: identityKey.base64EncodedString())
                        if encryptedData.oneTimeKeyId >= 0 {
                            enc.addAttribute(withName: "one_time_pre_key_id", stringValue: String(encryptedData.oneTimeKeyId))
                        }
                    }
                    return enc
                    }())
            }
            completion(element)
        }
    }
}
