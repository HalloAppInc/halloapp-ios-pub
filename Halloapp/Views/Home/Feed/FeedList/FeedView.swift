//
//  FeedView.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 2/28/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct FeedTableView: UIViewControllerRepresentable {
    typealias UIViewControllerType = FeedTableViewController
    private var isOnProfilePage: Bool

    init(isOnProfilePage: Bool) {
        self.isOnProfilePage = isOnProfilePage
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIViewControllerType {
        return FeedTableViewController(isOnProfilePage: context.coordinator.parent.isOnProfilePage)
    }

    func updateUIViewController(_ viewController: UIViewControllerType, context: Context) {
        guard let tableView = viewController.view as? UITableView else { return }
        let bottomInset = BottomBarView.currentBarHeight()
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        tableView.scrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
    }

    static func dismantleUIViewController(_ uiViewController: Self.UIViewControllerType, coordinator: Self.Coordinator) {
        uiViewController.dismantle()
    }

    class Coordinator: NSObject {
        var parent: FeedTableView

        init(_ feedTableView: FeedTableView) {
            self.parent = feedTableView
        }
    }
}


struct FeedView: View {
    @EnvironmentObject var mainViewController: MainViewController
    @ObservedObject var feedData = AppContext.shared.feedData
    @ObservedObject var contactStore = AppContext.shared.contactStore

    @State private var showNotifications = false
    @State private var showShareSheet = false
    @State private var showNetworkAlert = false

    var body: some View {
        VStack {
            if feedData.isFeedEmpty {
                Spacer()

                if contactStore.isContactsReady {
                    Button(action: {
                        self.feedData.refetchEverything()
                    }) {
                        Text("Refresh")
                            .padding(.horizontal, 15)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(24)
                    }
                } else {
                    Text("Loading...").font(.title)
                }

                Spacer()
            } else {
                FeedTableView(isOnProfilePage: false)
            }

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
                    NotificationsView(isViewPresented: self.$showNotifications)
                        .environment(\.managedObjectContext, AppContext.shared.feedData.viewContext)
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
