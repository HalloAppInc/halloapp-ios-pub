//
//  Settings.swift
//  Halloapp
//
//  Created by Tony Jiang on 11/20/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI
import MessageUI

struct SettingsView: View {
    @EnvironmentObject var mainViewController: MainViewController
    @Binding var isViewPresented: Bool

    private let userData = AppContext.shared.userData

    @State var result: Result<MFMailComposeResult, Error>? = nil
    @State var isShowingMailView = false

    var body: some View {
        VStack {
            HStack {
                Spacer()

                Button(action: {
                    self.isViewPresented = false
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.primary)
                        .padding()
                }
            }

            Spacer()

            VStack {
                Image("Logo")
                    .resizable()
                    .frame(width: 240, height: 240, alignment: .center)
                    .cornerRadius(40)
                    .padding(.bottom, 16)

                Text("Version \(Utils().appVersion())")
                .font(Font.headline)
                .foregroundColor(Color.primary)
            }

            Spacer()

            VStack(alignment: .center, spacing: 32) {
                Button(action: {
                    self.userData.logout()
                    self.mainViewController.selectFeedTab()
                    self.isViewPresented = false
                }) {
                    Text("Log out")
                        .padding(.horizontal, 15)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(24)
                }

                Button(action: {
                    self.isViewPresented = false
                }) {
                    Text("Send Logs")
                        .padding(.horizontal, 15)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(24)
                }
            }
            .padding(.bottom, 32)
        }
        
        .sheet(isPresented: self.$isShowingMailView) {
            MailView(result: self.$result)
        }
    }
}

struct Settings_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(isViewPresented: .constant(false))
    }
}
