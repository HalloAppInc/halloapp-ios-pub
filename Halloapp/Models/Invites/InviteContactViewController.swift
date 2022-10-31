//
//  InviteContactViewController.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 3/7/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import MessageUI
import UIKit

protocol InviteContactViewController: UIViewController {

    var inviteManager: InviteManager { get }
    func showLoadIndicator(_ isLoading: Bool)
    func didInviteContact(_ contact: InviteContact, with action: InviteActionType)
}

extension InviteContactViewController {

    var isWhatsAppAvailable: Bool {
        guard let url = URL(string: "whatsapp://app") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    var isIMessageAvailable: Bool {
        return MFMessageComposeViewController.canSendText()
    }

    func showInviteContactActionSheet(for contact: InviteContact) {
        // at least one must be available to proceed
        guard isIMessageAvailable || isWhatsAppAvailable else { return }

        let actionSheet = UIAlertController(title: Localizations.inviteActionSheetTitle(contact.fullName),
                                            message: nil,
                                            preferredStyle: .actionSheet)
        actionSheet.view.tintColor = UIColor.systemBlue

        if isIMessageAvailable {
            actionSheet.addAction(UIAlertAction(title: Localizations.appNameSMS, style: .default) { [weak self] _ in
                self?.inviteAction(.sms, contact: contact)
            })
        }

        if isWhatsAppAvailable {
            actionSheet.addAction(UIAlertAction(title: Localizations.appNameWhatsApp, style: .default) { [weak self] _ in
                self?.inviteAction(.whatsApp, contact: contact)
            })
        }

        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .destructive))
        present(actionSheet, animated: true)
    }

    func inviteAction(_ action: InviteActionType, contact: InviteContact) {
        guard proceedIfConnected() else { return }
        switch action {
        case .sms:
            smsAction(contact: contact)
        case .whatsApp:
            whatsAppAction(contact: contact)
        }

        didInviteContact(contact, with: action)
    }

    private func redeemInvite(for contact: InviteContact, completion: ((InviteResult) -> Void)?) {
        showLoadIndicator(true)
        DDLogInfo("InviteViewController/redeem/\(contact.normalizedPhoneNumber)/start")
        inviteManager.redeemInviteForPhoneNumber(contact.normalizedPhoneNumber) { [weak self] result in
            DDLogInfo("InviteViewController/redeem/\(contact.normalizedPhoneNumber)/result [\(result)]")
            self?.showLoadIndicator(false)
            completion?(result)
        }
    }

    private func smsAction(contact: InviteContact) {
        DDLogInfo("InviteViewController/sms/\(contact.normalizedPhoneNumber)")
        redeemInvite(for: contact) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success, .failure(.existingUser):
                #if targetEnvironment(simulator)
                let vc = UIAlertController(
                    title: "Not available on Simulator",
                    message: "Please use a physical device to test SMS",
                    preferredStyle: .alert)
                vc.addAction(.init(title: "OK", style: .default, handler: nil))
                self.present(vc, animated: true, completion: nil)
                #else
                let vc = InviteContactMessageComposerViewController()
                vc.body = Localizations.inviteText(name: contact.givenName ?? contact.fullName, number: contact.formattedPhoneNumber)
                vc.recipients = [contact.formattedPhoneNumber]
                self.present(vc, animated: true, completion: nil)
                #endif
            case .failure(let reason):
                self.presentFailureAlert(for: reason)
            }
        }
    }

    private func whatsAppAction(contact: InviteContact) {
        DDLogInfo("InviteViewController/WhatsApp/\(contact.normalizedPhoneNumber)")
        redeemInvite(for: contact) { [weak self] result in
            switch result {
            case .success, .failure(.existingUser):
                var allowedCharacters = CharacterSet.urlHostAllowed
                allowedCharacters.remove("+")
                guard let urlEncodedInviteText = Localizations
                        .inviteText(name: contact.givenName ?? contact.fullName, number: contact.formattedPhoneNumber)
                        .addingPercentEncoding(withAllowedCharacters: allowedCharacters),
                      let whatsAppURL = URL(string: "https://wa.me/\(contact.normalizedPhoneNumber)/?text=\(urlEncodedInviteText)") else
                {
                    return
                }
                Analytics.log(event: .sendInvite, properties: [.service: "whatsapp"])
                UIApplication.shared.open(whatsAppURL, options: [:], completionHandler: nil)
            case .failure(let reason):
                self?.presentFailureAlert(for: reason)
            }
        }
    }

    private func presentFailureAlert(for reason: InviteResult.FailureReason) {
        switch reason {
        case .existingUser:
            DDLogInfo("InviteViewController/presentFailureAlert/skipping [existingUser]")
        case .noInvitesLeft:
            DDLogInfo("InviteViewController/presentFailureAlert/out of invites")
            let vc = UIAlertController(
                title: Localizations.inviteErrorTitle,
                message: Localizations.outOfInvitesWith(date: inviteManager.nextRefreshDate ?? Date()),
                preferredStyle: .alert)
            vc.addAction(.init(title: Localizations.buttonOK, style: .default, handler: nil))
            present(vc, animated: true, completion: nil)
        case .invalidNumber, .unknown:
            let vc = UIAlertController(
                title: Localizations.inviteErrorTitle,
                message: Localizations.inviteErrorMessage,
                preferredStyle: .alert)
            vc.addAction(.init(title: Localizations.buttonOK, style: .default, handler: nil))
            present(vc, animated: true, completion: nil)
        }
    }
}

private class InviteContactMessageComposerViewController: MFMessageComposeViewController, MFMessageComposeViewControllerDelegate {

    init() {
        super.init(nibName: nil, bundle: nil)
        messageComposeDelegate = self
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        let type: Server_InviteRequestResult.TypeEnum
        switch result {
        case .sent:
            type = .sent
        case .cancelled:
            type = .cancelled
        case .failed:
            type = .failed
        @unknown default:
            type = .unknown
        }
        controller.recipients?.forEach { recipient in
            MainAppContext.shared.eventMonitor.observe(.inviteResult(phoneNumber: recipient, type: type))
        }

        if result == .sent {
            controller.recipients?.forEach { _ in Analytics.log(event: .sendInvite, properties: [.service: "sms"]) }
        }

        guard result == .cancelled else { return }
        // NB: We should really be calling this on the presenting view controller (see: https://developer.apple.com/documentation/uikit/uiviewcontroller/1621505-dismiss)
        // Unfortunately, that isn't working correctly (Apple bug?) so we have to call it on the presented controller instead
        controller.dismiss(animated: true, completion: nil)
    }
}
