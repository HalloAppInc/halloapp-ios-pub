//
//  HelpViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 10/28/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
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

    static var calls: String {
        NSLocalizedString("profile.help.calls", value: "Calls", comment: "Item in Profile > Calls screen.")
    }
    
    static var appVersionDisplay: String {
        NSLocalizedString("settings.app.version", value: "HalloApp Version %@", comment: "App version text in Profile > Help.")
    }
}

class HelpViewController: UIViewController, UICollectionViewDelegate {
    typealias Section = InsetCollectionView.Section
    typealias Item = InsetCollectionView.Item
    
    private lazy var collectionView: InsetCollectionView = {
        let collectionView = InsetCollectionView()
        let layout = InsetCollectionView.defaultLayout()
        let config = InsetCollectionView.defaultLayoutConfiguration()
        
        config.boundarySupplementaryItems = [
            NSCollectionLayoutBoundarySupplementaryItem(layoutSize: .init(widthDimension: .fractionalWidth(1.0),
                                                                         heightDimension: .estimated(44)),
                                                       elementKind: UICollectionView.elementKindSectionFooter,
                                                         alignment: .bottom),
        ]
        
        layout.configuration = config
        collectionView.collectionViewLayout = layout
        return collectionView
    }()
    
    private lazy var activityIndicator: ActivityIndicator = {
        let activityIndicator = ActivityIndicator(frame: view.frame)
        return activityIndicator
    }()

    init() {
        super.init(nibName: nil, bundle: nil)
        title = Localizations.help
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .primaryBg
        collectionView.backgroundColor = nil
        collectionView.delegate = self
        
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        
        NSLayoutConstraint.activate([
            
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        
        collectionView.register(AppVersionFooterView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
                                       withReuseIdentifier: AppVersionFooterView.reuseIdentifier)

        collectionView.data.supplementaryViewProvider = { collectionView, _, indexPath in
            return collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionFooter,
                                                      withReuseIdentifier: AppVersionFooterView.reuseIdentifier,
                                                                      for: indexPath)
        }
        
        buildCollection()
    }
    
    private func buildCollection() {
        collectionView.apply(InsetCollectionView.Collection {
            Section {
                Item(title: Localizations.faq, action: { [weak self] in self?.openFAQ() })
                Item(title: Localizations.termsOfService, action : { [weak self] in self?.openTermsOfService() })
                Item(title: Localizations.privacyPolicy, action: { [weak self] in self?.openPrivacyPolicy() })
            }
            
            Section {
                if MFMailComposeViewController.canSendMail() {
                    // send Logs/Feedback via email composer.
                    Item(title: Localizations.feedback, action: { [weak self] in self?.sendLogs() })
                }
                
                if ServerProperties.isInternalUser || !MFMailComposeViewController.canSendMail() {
                    // share Logs: internal users or Mail unavailable.
                    Item(title: Localizations.shareLogs, action: { [weak self] in self?.shareLogs() })
                }
            }
        }
        .separators()
        .disclosure())
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = self.collectionView.data.itemIdentifier(for: indexPath) as? Item else {
            return
        }
        
        collectionView.deselectItem(at: indexPath, animated: true)
        item.action?()
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
        view.addSubview(activityIndicator)
        activityIndicator.show()
        
        let viewController = MFMailComposeViewController.makeEmailLogsViewController(delegate: self)
        present(viewController, animated: true)
        activityIndicator.hide()
    }

    private func shareLogs() {
        DDLogInfo("HelpViewController/shareLogs")
        view.addSubview(activityIndicator)
        activityIndicator.show()
        
        let viewController = UIActivityViewController.makeShareLogsViewController()
        present(viewController, animated: true)
        activityIndicator.hide()
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

fileprivate class ActivityIndicator: UIView {
    private lazy var dimmerView: BlurView = {
        let dimmerView = BlurView(effect: UIBlurEffect(style: .systemThickMaterial), intensity: 0.3)
        dimmerView.isUserInteractionEnabled = false
        return dimmerView
    }()
    
    private lazy var flutterIndicator: UIActivityIndicatorView = {
        let flutterIndicator = UIActivityIndicatorView(style: .large)
        flutterIndicator.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
        return flutterIndicator
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        dimmerView.frame = frame
        dimmerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimmerView.contentView.addSubview(flutterIndicator)
        flutterIndicator.center = dimmerView.center
        addSubview(dimmerView)

    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    func show() {
        flutterIndicator.startAnimating()
        self.isHidden = false
    }
    
    func hide() {
        flutterIndicator.stopAnimating()
        self.isHidden = true
    }
}

// MARK: - AppVersionFooterView implementation

fileprivate class AppVersionFooterView: UICollectionReusableView {
    static let reuseIdentifier = "appVersionFooter"
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        let label = UILabel()
        label.text = String(format: Localizations.appVersionDisplay, MainAppContext.appVersionForDisplay)
        label.font = .systemFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 15),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("AppVersionFooterView coder init not implemented...")
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

    static var noCallsNoticeText: String {
        NSLocalizedString("home.calls.notice.text", value: "You dont have an active call at the moment.", comment: "Text shown to users trying to open the call screen.")
    }

    static var failedCallTitle: String {
        NSLocalizedString("home.calls.fail.title", value: "Couldn't place call.", comment: "Title of failed call screen alert.")
    }

    static var failedCallNoticeText: String {
        NSLocalizedString("home.calls.fail.text", value: "Make sure your phone has an internet connection and try again.", comment: "Text shown to users on call failure.")
    }

    static var failedActionDuringCallTitle: String {
        NSLocalizedString("home.calls.fail.audio.title", value: "Cannot record audio during a HalloApp call.", comment: "Title of failed audio capture alert during a call.")
    }

    static var failedActionDuringCallNoticeText: String {
        NSLocalizedString("home.calls.fail.audio.text", value: "Please try again later.", comment: "Text shown to users on failed audio capture alert during a call.")
    }

    static var unsupportedVideoCallTitle: String {
        NSLocalizedString("home.video.calls.fail.title", value: "Video calls are not supported at the moment.", comment: "Title of failed video call screen alert.")
    }

    static var unsupportedVideoCallNoticeText: String {
        NSLocalizedString("home.video.calls.fail.text", value: "Coming soon...", comment: "Text shown to users on video call failure.")
    }
}
