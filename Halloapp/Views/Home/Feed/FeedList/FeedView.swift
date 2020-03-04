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
    @EnvironmentObject var feedData: FeedData
    @EnvironmentObject var contacts: Contacts

    @State private var notificationsModal = false
    @State private var showShareSheet = false
    @State private var showNetworkAlert = false

    var body: some View {
        VStack {
            FeedCollectionView(
                isOnProfilePage: false,
                items: self.feedData.feedDataItems,
                getItemMedia: { itemId in
                    self.feedData.getItemMedia(itemId)
                },
                setItemCellHeight: { itemId, cellHeight in
                    self.feedData.setItemCellHeight(itemId, cellHeight) })
            }
            .overlay(
                BottomBarView(),
                alignment: .bottom
            )

            .edgesIgnoringSafeArea(.all)

            .navigationBarTitle(Text("Home"))

            .navigationBarItems(trailing:
                HStack {
                    Button(action: {
                        self.showNotifications()
                    }) {
                        Image(systemName: "bell")
                            .font(Font.title.weight(.regular))
                            .foregroundColor(Color.primary)
                    }
                    .padding(.trailing, 8)

                    Button(action: {
                        if (self.feedData.isConnecting) {
                            self.showNetworkAlert = true
                        } else {
                            self.showShareSheet = true
                        }
                    }) {
                        Image(systemName: "plus")
                            .font(Font.title.weight(.regular))
                            .foregroundColor(Color.primary)
                    }
            })

            // Notifications modal
            .sheet(isPresented: self.$notificationsModal,
                   content: {
                    Notifications(showModal: self.$notificationsModal)
            })

            // Share Sheet
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

            // "Not Connected" alert
            ///TODO: allow to open photo picker and camera even when not connected
            .alert(isPresented: $showNetworkAlert) {
                Alert(title: Text("Couldn't connect to Halloapp"),
                      message: Text("We'll keep trying, but there may be a problem with your connection"),
                      dismissButton: .default(Text("OK")))
        }
    }

    private func showNotifications () {
        notificationsModal = true
    }
}
