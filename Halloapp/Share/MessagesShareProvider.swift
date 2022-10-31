//
//  MessagesShareProvider.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 10/11/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import CoreCommon
import MessageUI

class MessagesShareProvider: DestinationShareProvider {

    static var analyticsShareDestination: String {
        return "sms"
    }

    static var title: String {
        return NSLocalizedString("shareprovider.messages.title", value: "Messages", comment: "Name of system messages app")
    }

    static var canShare: Bool {
        return MFMessageComposeViewController.canSendText()
    }

    static func share(destination: ABContact.NormalizedPhoneNumber?, text: String?, image: UIImage?, completion: ((ShareProviderResult) -> Void)?) {
        guard let currentViewController = UIViewController.currentViewController else {
            DDLogError("MessagesShareProvider/unable to find view controller to present on")
            completion?(.failed)
            return
        }

        let messageComposeViewController = MessageShareProviderMessageComposeViewController()
        messageComposeViewController.completion = completion
        messageComposeViewController.messageComposeDelegate = messageComposeViewController

        if let destination = destination {
            messageComposeViewController.recipients = [destination]
        }

        if let text = text {
            messageComposeViewController.body = text
        }

        if MFMessageComposeViewController.canSendAttachments(), let image = image {
            if let pngData = image.pngData() {
                messageComposeViewController.addAttachmentData(pngData, typeIdentifier: "public.png", filename: "image.png")
            } else {
                DDLogError("MessagesShareProvider/Unable to convert image to png, skipping")
            }
        }

        currentViewController.present(messageComposeViewController, animated: true, completion: nil)
    }
}

private class MessageShareProviderMessageComposeViewController: MFMessageComposeViewController, MFMessageComposeViewControllerDelegate {

    var completion: ((ShareProviderResult) -> Void)?

    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        let shareProviderResult: ShareProviderResult
        switch result {
        case .failed:
            shareProviderResult = .failed
        case .cancelled:
            shareProviderResult = .cancelled
        case .sent:
            shareProviderResult = .success
        @unknown default:
            shareProviderResult = .unknown
        }
        dismiss(animated: true) { [weak self] in
            self?.completion?(shareProviderResult)
        }
    }
}
