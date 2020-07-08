//
//  MFMessageComposeView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 7/7/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import MessageUI
import SwiftUI

struct MFMessageComposeView: UIViewControllerRepresentable {

    typealias UIViewControllerType = MFMessageComposeViewController

    @Binding var isPresented: Bool
    private let recipients: [String]
    private let messageText: String

    class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        @Binding var isPresented: Bool

        init(isPresented: Binding<Bool>) {
            _isPresented = isPresented
        }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            if result != .cancelled {
                // Delay dismissing composer so that user can see their message going out.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.isPresented = false
                }
            } else {
                self.isPresented = false
            }
        }
    }

    init(isPresented: Binding<Bool>, recipients: [String], messageText: String) {
        _isPresented = isPresented
        self.recipients = recipients
        self.messageText = messageText
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(isPresented: $isPresented)
    }

    func makeUIViewController(context: Context) -> UIViewControllerType {
        let viewController = MFMessageComposeViewController()
        viewController.messageComposeDelegate = context.coordinator
        viewController.recipients = recipients
        viewController.body = messageText
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {

    }
}
