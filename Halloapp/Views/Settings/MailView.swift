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

struct MailView: UIViewControllerRepresentable {

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

    func makeUIViewController(context: UIViewControllerRepresentableContext<MailView>) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
    
        let formatter = DateFormatter()
        formatter.dateFormat = "MMdd_HHmm"
        let time = formatter.string(from: Date())
        
        let logfileName = "logs-\(time)"
            
        vc.setSubject("iOS Logs \(time)")

        vc.setToRecipients(["iphone-support@halloapp.com"])

        vc.setMessageBody("short description of issue (if needed): \n", isHTML:false)

        let logFilePaths = MainAppContext.shared.fileLogger.logFileManager.sortedLogFilePaths.compactMap{ URL(fileURLWithPath: $0) }
        do {
            let zipFilePath = try Zip.quickZipFiles(logFilePaths, fileName: "\(logfileName)") // Zip
            if let fileData = try? Data(contentsOf: zipFilePath) {
                vc.addAttachmentData(fileData, mimeType: "application/zip", fileName: "logs.zip")
            }
            do {
                try FileManager.default.removeItem(at: zipFilePath)
            } catch let error as NSError {
                DDLogError("Error: \(error.domain)")
            }
        }
        catch {
          DDLogError("can't zip log files: \(error)")
        }
        
        vc.mailComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController,
                                context: UIViewControllerRepresentableContext<MailView>) {

    }
}
