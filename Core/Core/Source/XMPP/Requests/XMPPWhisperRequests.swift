//
//  HalloApp
//
//  Created by Tony Jiang on 7/8/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation

public typealias WhisperKeyBundle = XMPPWhisperKey

public enum WhisperMessage {
    case normal(keyCount: Int32)
    case update(userID: UserID)

    public init?(_ pbKeys: Server_WhisperKeys) {
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
