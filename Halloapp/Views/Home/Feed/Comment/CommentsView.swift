//
//  CommentsView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 3/23/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI
import UIKit

struct CommentsView: UIViewControllerRepresentable {
    typealias UIViewControllerType = CommentsViewController
    private var feedItemId: String

    init(itemId: String) {
        self.feedItemId = itemId
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIViewControllerType {
        return CommentsViewController(feedItemId: context.coordinator.parent.feedItemId)
    }

    func updateUIViewController(_ viewController: UIViewControllerType, context: Context) {
    }

    static func dismantleUIViewController(_ uiViewController: Self.UIViewControllerType, coordinator: Self.Coordinator) {
        uiViewController.dismantle()
    }

    class Coordinator: NSObject {
        var parent: CommentsView

        init(_ commentsView: CommentsView) {
            self.parent = commentsView
        }
    }
}
