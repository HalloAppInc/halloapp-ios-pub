//
//  HelpViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 10/28/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import MessageUI
import SafariServices
import UIKit

private extension Localizations {

    static var faq: String {
        NSLocalizedString("profile.help.faq", value: "FAQ", comment: "Item in Profile > Help screen.")
    }

    static var termsOfService: String {
        NSLocalizedString("profile.help.tos", value: "Terms of Service", comment: "Item in Profile > Help screen.")
    }

    static var privacyPolicy: String {
        NSLocalizedString("profile.help.pp", value: "Privacy Policy", comment: "Item in Profile > Help screen.")
    }

    static var feedback: String {
        NSLocalizedString("profile.help.feedback", value: "Share Feedback & Logs", comment: "Item in Profile > Help screen.")
    }

    static var shareLogs: String {
        NSLocalizedString("profile.help.share.logs", value: "Share Logs", comment: "Item in Profile > Help screen.")
    }
}

class HelpViewController: UITableViewController {

    // MARK: Table View Data Source and Rows

    private enum Section {
        case one
        case two
    }

    private enum Row {
        case faq
        case termsOfService
        case privacyPolicy
        case feedback
        case shareLogs
        case calls
    }

    private class HelpTableViewDataSource: UITableViewDiffableDataSource<Section, Row> {

        override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
            let section = snapshot().sectionIdentifiers[section]
            if section == .two {
                let formatString = NSLocalizedString("settings.app.version", value: "HalloApp Version %@", comment: "App version text in Profile > Help.")
                return String(format: formatString, MainAppContext.appVersionForDisplay)
            }
            return nil
        }
    }

    private var dataSource: HelpTableViewDataSource!
    private let cellFAQ = SettingsTableViewCell(text: Localizations.faq)
    private let cellTOS = SettingsTableViewCell(text: Localizations.termsOfService)
    private let cellPP = SettingsTableViewCell(text: Localizations.privacyPolicy)
    private let cellFeedback = SettingsTableViewCell(text: Localizations.feedback)
    private let cellShareLogs = SettingsTableViewCell(text: Localizations.shareLogs)
    private let cellCalls = SettingsTableViewCell(text: "Calls")


    // MARK: View Controller

    init(title: String) {
        super.init(style: .grouped)
        self.title = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.backgroundColor = .feedBackground
        tableView.delegate = self

        dataSource = HelpTableViewDataSource(tableView: tableView, cellProvider: { [weak self] (_, _, row) -> UITableViewCell? in
            guard let self = self else { return nil }
            switch row {
            case .faq: return self.cellFAQ
            case .termsOfService: return self.cellTOS
            case .privacyPolicy: return self.cellPP
            case .feedback: return self.cellFeedback
            case .shareLogs: return self.cellShareLogs
            case .calls: return self.cellCalls
            }
        })
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections([ .one, .two ])
        snapshot.appendItems([ .faq, .termsOfService, .privacyPolicy ], toSection: .one)
        // Send Logs/Feedback via email composer.
        if MFMailComposeViewController.canSendMail() {
            snapshot.appendItems([ .feedback ], toSection: .two)
        }
        // Share Logs: Internal users or Mail unavailable.
        if ServerProperties.isInternalUser || !MFMailComposeViewController.canSendMail() {
            snapshot.appendItems([ .shareLogs ], toSection: .two)
            snapshot.appendItems([ .calls ], toSection: .two)
        }
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: Menu Items

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let row = dataSource.itemIdentifier(for: indexPath) else { return }
        switch row {
        case .faq:
            openFAQ()
        case .termsOfService:
            openTermsOfService()
        case .privacyPolicy:
            openPrivacyPolicy()
        case .feedback:
            sendLogs()
        case .shareLogs:
            shareLogs()
        case .calls:
            openCalls()
        }
    }

    private func openFAQ() {
        let viewController = SFSafariViewController(url: URL(string: "https://www.halloapp.com/help")!)
        present(viewController, animated: true)
    }

    private func openTermsOfService() {
        let viewController = SFSafariViewController(url: URL(string: "https://www.halloapp.com/terms")!)
        present(viewController, animated: true)
    }

    private func openPrivacyPolicy() {
        let viewController = SFSafariViewController(url: URL(string: "https://www.halloapp.com/privacy")!)
        present(viewController, animated: true)
    }

    private func sendLogs() {
        DDLogInfo("HelpViewController/sendLogs")
        let viewController = MFMailComposeViewController.makeEmailLogsViewController(delegate: self)
        present(viewController, animated: true) {
            if let indexPath = self.dataSource.indexPath(for: .feedback) {
                self.tableView.deselectRow(at: indexPath, animated: true)
            }
        }
    }

    private func shareLogs() {
        DDLogInfo("HelpViewController/shareLogs")
        let viewController = UIActivityViewController.makeShareLogsViewController()
        present(viewController, animated: true) {
            if let indexPath = self.dataSource.indexPath(for: .shareLogs) {
                self.tableView.deselectRow(at: indexPath, animated: true)
            }
        }
    }

    private func openCalls() {
        DDLogInfo("HelpViewController/openCalls")
        if MainAppContext.shared.callManager.activeCall != nil,
           let peerUserID = MainAppContext.shared.callManager.peerUserID,
           let isOutgoing = MainAppContext.shared.callManager.isOutgoing {
            DDLogInfo("HelpViewController/opening call screen")
            let viewController = CallViewController(peerUserID: peerUserID, isOutgoing: isOutgoing)
            viewController.hidesBottomBarWhenPushed = true
            navigationController?.pushViewController(viewController, animated: true)
        } else {
            let alert = self.getNoCallsAlertController()
            self.present(alert, animated: true)
        }
        if let indexPath = self.dataSource.indexPath(for: .calls) {
            self.tableView.deselectRow(at: indexPath, animated: true)
        }
    }

    private func getNoCallsAlertController() -> UIAlertController {
        let alert = UIAlertController(
            title: Localizations.noCallsTitle,
            message: Localizations.noCallsNoticeText,
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonOk, style: .default, handler: { action in
            self.dismiss(animated: true, completion: nil)
        }))
        return alert
    }
}

extension HelpViewController: MFMailComposeViewControllerDelegate {

    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }
}

private extension MFMailComposeViewController {

    class func makeEmailLogsViewController(delegate: MFMailComposeViewControllerDelegate) -> MFMailComposeViewController {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMdd_HHmm"
        let timeStr = formatter.string(from: Date())
        let version = MainAppContext.appVersionForService
        let model = "\(UIDevice.current.getModelName()) (iOS \(UIDevice.current.systemVersion))"
        let userID = MainAppContext.shared.userData.userId

        let vc = MFMailComposeViewController()
        vc.setSubject("iOS Logs \(timeStr) [\(version)]")
        vc.setToRecipients(["iphone-support@halloapp.com"])
        
        let formatString = NSLocalizedString("help.send.logs.email.body", value: "\n\n\nPlease leave feedback or a description of the issue in the space above. \n\nVersion %1@ - %2@\n%3@", comment: "Text shown in the email body when sending logs from the help screen")
        let localizedEmailStr = String(format: formatString, version, userID, model)
        
        vc.setMessageBody(localizedEmailStr, isHTML:false)
        
        vc.mailComposeDelegate = delegate

        do {
            let tempDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let archiveURL = tempDirectoryURL.appendingPathComponent("logs-\(timeStr).zip")
            try MainAppContext.shared.archiveLogs(to: archiveURL)
            if let archiveData = try? Data(contentsOf: archiveURL) {
                vc.addAttachmentData(archiveData, mimeType: "application/zip", fileName: "logs.zip")
            }
        }
        catch {
            DDLogError("Failed to archive log files: \(error)")
        }

        return vc
    }
}

private extension UIActivityViewController {

    class func makeShareLogsViewController() -> UIActivityViewController {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMdd_HHmmss"
        let timeStr = formatter.string(from: Date())
        return UIActivityViewController(activityItems: [ LogsArchive(filenameSuffix: timeStr) ], applicationActivities: nil)
    }
}

private class LogsArchive: UIActivityItemProvider {

    private var archiveURL: URL
    private var archiveCreated = false

    init(filenameSuffix: String) {
        let tempDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        self.archiveURL = tempDirectoryURL.appendingPathComponent("logs-\(filenameSuffix).zip")
        super.init(placeholderItem: archiveURL)
    }

    override var item: Any {
        if !archiveCreated {
            try? MainAppContext.shared.archiveLogs(to: archiveURL)
            archiveCreated = true
        }
        return archiveURL
    }
}

extension Localizations {

    static var noCallsTitle: String {
        NSLocalizedString("home.calls.notice.title", value: "No Active Calls", comment: "Title of call screen alert.")
    }

    static var noCallsNoticeText: String {
        NSLocalizedString("home.calls.notice.text", value: "You dont have an active call at the moment.", comment: "Text shown to users trying to open the call screen.")
    }

    static var buttonOk: String {
        NSLocalizedString("home.calls.button.exit", value: "OK", comment: "Button to dismiss the alert.")
    }

    static var failedCallTitle: String {
        NSLocalizedString("home.calls.fail.title", value: "Failed placing a call.", comment: "Title of failed call screen alert.")
    }

    static var failedCallNoticeText: String {
        NSLocalizedString("home.calls.fail.text", value: "Sorry, please try again later.", comment: "Text shown to users on call failure.")
    }
}
