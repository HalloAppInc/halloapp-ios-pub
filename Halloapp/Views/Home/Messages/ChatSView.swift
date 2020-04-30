//
//  HalloApp
//
//  Created by Tony Jiang on 4/10/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI
import UIKit

struct ChatSView: UIViewControllerRepresentable {
    typealias UIViewControllerType = ChatViewController
    private var fromUserId: String = ""

    init(fromUserId: String) {
        self.fromUserId = fromUserId
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIViewControllerType {
        return ChatViewController(fromUserId: context.coordinator.parent.fromUserId)
    }

    func updateUIViewController(_ viewController: UIViewControllerType, context: Context) {
    }

    static func dismantleUIViewController(_ uiViewController: Self.UIViewControllerType, coordinator: Self.Coordinator) {
        uiViewController.dismantle()
    }

    class Coordinator: NSObject {
        var parent: ChatSView

        init(_ chatSView: ChatSView) {
            self.parent = chatSView
        }
    }
}
