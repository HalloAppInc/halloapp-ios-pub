//
//  FeedView.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 2/28/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Combine
import SwiftUI

struct FeedView: View {
    @EnvironmentObject var mainViewController: MainViewController

    @State private var showNotifications = false
    @State private var showShareSheet = false
    @State private var showNetworkAlert = false

    var body: some View {
        VStack {
            FeedTableView(isOnProfilePage: false)
        }
        .overlay(BottomBarView())

        .edgesIgnoringSafeArea(.all)

        .navigationBarTitle(Text("Home"))

        .navigationBarItems(trailing:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button(action: {
                    self.showNotifications = true
                }) {
                    Image(systemName: "bell")
                        .padding(8)
                }
                .sheet(isPresented: self.$showNotifications) {
                    Notifications(isViewPresented: self.$showNotifications)
                }

                Button(action: {
                    if (AppContext.shared.xmppController.xmppStream.isConnected) {
                        self.showShareSheet = true
                    } else {
                        self.showNetworkAlert = true
                    }
                }) {
                    Image(systemName: "plus")
                        .padding(8)
                }
                .actionSheet(isPresented: self.$showShareSheet) {
                    ActionSheet(
                        title: Text("Post something"),
                        buttons: [
                            .default(Text("Photo Library"), action: {
                                self.mainViewController.presentPhotoPicker()
                            }),
                            .default(Text("Camera"), action: {
                                self.mainViewController.presentCamera()
                            }),
                            .default(Text("Text"), action: {
                                self.mainViewController.presentPostComposer()
                            }),
                            .destructive(Text("Cancel"), action: {
                                self.showShareSheet = false
                            })
                        ]
                    )}
            }
            .foregroundColor(Color.primary)
            .font(Font.system(size: 20))
        )

        // "Not Connected" alert
        ///TODO: allow to open photo picker and camera even when not connected
        .alert(isPresented: $showNetworkAlert) {
            Alert(title: Text("Couldn't connect to Halloapp"),
                  message: Text("We'll keep trying, but there may be a problem with your connection"),
                  dismissButton: .default(Text("OK")))
        }
    }
}
