//
//  HalloApp
//
//  Created by Tony Jiang on 7/8/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Foundation

public enum WhisperMessage {
    case count(Int32)
    case update(userID: UserID, identityKey: Data)

    public init?(_ pbKeys: Server_WhisperKeys) {
        switch pbKeys.action {
        case .normal, .count:
            // NB: Server has been setting action to `.normal` for OTP key count but we want to transition to `.count`
            self = .count(pbKeys.otpKeyCount)
        case .update:
            self = .update(userID: UserID(pbKeys.uid), identityKey: pbKeys.identityKey)
        default:
            return nil
        }
    }
}
