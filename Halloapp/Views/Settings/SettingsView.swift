//
//  SettingsView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import MessageUI
import SwiftUI

struct SettingsView: View {
    @State private var isShowingMailView = false
    @State private var mailViewResult: Result<MFMailComposeResult, Error>? = nil

    var body: some View {
        Form {

            Section(header: Text("ABOUT")) {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("\(UIApplication.shared.version)")
                }
            }

            Section {
                Button(action: {
                    if MFMailComposeViewController.canSendMail() {
                        self.isShowingMailView = true
                    }
                }) {
                    Text("Send Logs").foregroundColor(.lavaOrange)
                }
                .sheet(isPresented: self.$isShowingMailView) {
                    MailView(result: self.$mailViewResult)
                }
            }
        }
        .navigationBarTitle("Settings", displayMode: .inline)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
