//
//  MailView.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/11/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import MessageUI
import SwiftUI
import UIKit
import Zip

struct EmailLogsView: UIViewControllerRepresentable {

    @Environment(\.presentationMode) var presentation
    @Binding var result: Result<MFMailComposeResult, Error>?

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {

        @Binding var presentation: PresentationMode
        @Binding var result: Result<MFMailComposeResult, Error>?

        init(presentation: Binding<PresentationMode>,
             result: Binding<Result<MFMailComposeResult, Error>?>) {
            _presentation = presentation
            _result = result
        }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            defer {
                $presentation.wrappedValue.dismiss()
            }
            guard error == nil else {
                self.result = .failure(error!)
                return
            }
            self.result = .success(result)
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(presentation: presentation,
                           result: $result)
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<EmailLogsView>) -> MFMailComposeViewController {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMdd_HHmm"
        let timeStr = formatter.string(from: Date())

        let vc = MFMailComposeViewController()
        vc.setSubject("iOS Logs \(timeStr)")
        vc.setToRecipients(["iphone-support@halloapp.com"])
        vc.setMessageBody("short description of issue (if needed): \n", isHTML:false)
        vc.mailComposeDelegate = context.coordinator

        do {
            let logFilePaths = MainAppContext.shared.fileLogger.logFileManager.sortedLogFilePaths.compactMap { URL(fileURLWithPath: $0) }
            let tempDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let archiveURL = tempDirectoryURL.appendingPathComponent("logs-\(timeStr).zip")
            try Zip.zipFiles(paths: logFilePaths, zipFilePath: archiveURL, password: nil, progress: nil)
            if let archiveData = try? Data(contentsOf: archiveURL) {
                vc.addAttachmentData(archiveData, mimeType: "application/zip", fileName: "logs.zip")
            }
        }
        catch {
            DDLogError("Failed to archive log files: \(error)")
        }
        
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: UIViewControllerRepresentableContext<EmailLogsView>) {

    }
}

struct ShareLogsView: UIViewControllerRepresentable {

    typealias UIViewControllerType = UIActivityViewController

    private let activityItems: [Any]

    init() {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMdd_HHmmss"
        let timeStr = formatter.string(from: Date())
        activityItems = [ LogsArchive(filenameSuffix: timeStr) ]
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<ShareLogsView>) -> UIViewControllerType {
        let activityViewController = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        return activityViewController
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: UIViewControllerRepresentableContext<ShareLogsView>) {

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
            let logFilePaths = MainAppContext.shared.fileLogger.logFileManager.sortedLogFilePaths.compactMap { URL(fileURLWithPath: $0) }
            try? Zip.zipFiles(paths: logFilePaths, zipFilePath: archiveURL, password: nil, progress: nil)
            archiveCreated = true
        }
        return archiveURL
    }

}
