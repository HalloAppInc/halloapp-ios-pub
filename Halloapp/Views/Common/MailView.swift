//
//  MailView.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/11/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI
import UIKit
import MessageUI

import Zip

struct MailView: UIViewControllerRepresentable {

    @Environment(\.presentationMode) var presentation
    @Binding var result: Result<MFMailComposeResult, Error>?
    
    var logs: String

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

    
    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }

    
    func makeUIViewController(context: UIViewControllerRepresentableContext<MailView>) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
    
        let formatter = DateFormatter()
        formatter.dateFormat = "MMdd_HHmm"
        let time = formatter.string(from: Date())
        
        let logfileName = "logs-\(time)"
            
        vc.setSubject("iOS Logs \(time)")

        vc.setToRecipients(["tony@halloapp.com"])

        vc.setMessageBody("short description of issue (if needed): \n", isHTML:false)
        
        let filename = getDocumentsDirectory().appendingPathComponent("\(logfileName).txt")
        let filenameZip = getDocumentsDirectory().appendingPathComponent("\(logfileName).zip")
        
        do {
            try self.logs.write(to: filename, atomically: true, encoding: String.Encoding.utf8)
        } catch {
            print("can't write logs file")
        }

        do {
            let zipFilePath = try Zip.quickZipFiles([filename], fileName: "\(logfileName)") // Zip
            if let fileData = try? Data(contentsOf: zipFilePath) {
                vc.addAttachmentData(fileData, mimeType: "application/zip", fileName: "\(logfileName).zip")
            }
        }
        catch {
          print("can't zip log files")
        }
        
        do {
            try FileManager.default.removeItem(at: filename)
            try FileManager.default.removeItem(at: filenameZip)
        } catch let error as NSError {
            print("Error: \(error.domain)")
        }
        
        /* list dir to make sure files are deleted */
//        let documentsUrl =  FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
//        do {
//            let directoryContents = try FileManager.default.contentsOfDirectory(at: documentsUrl, includingPropertiesForKeys: nil)
//            print(directoryContents)
//        } catch {
//            print(error)
//        }
        
        vc.mailComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController,
                                context: UIViewControllerRepresentableContext<MailView>) {

    }
}
