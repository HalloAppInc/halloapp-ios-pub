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
    private var item: FeedDataItem

    init(item: FeedDataItem) {
        self.item = item
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> CommentsViewController {
        return CommentsViewController(item: context.coordinator.parent.item)
    }

    func updateUIViewController(_ viewController: CommentsViewController, context: Context) {
    }

    class Coordinator: NSObject {
        var parent: CommentsView

        init(_ commentsView: CommentsView) {
            self.parent = commentsView
        }
    }
}
