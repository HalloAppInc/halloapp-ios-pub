//
//  ChatViewControllerNew.swift
//  HalloApp
//
//  Created by Nandini Shetty on 5/2/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import CocoaLumberjackSwift
import UIKit

class ChatViewControllerNew: UIViewController {

    weak var delegate: ChatViewControllerDelegate?

    init(for fromUserId: String, with feedPostId: FeedPostID? = nil, at feedPostMediaIndex: Int32 = 0) {
        DDLogDebug("ChatViewControllerNew/init/\(fromUserId) [\(MainAppContext.shared.contactStore.fullName(for: fromUserId))]")
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }
}
