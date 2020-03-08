//
//  Home.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/25/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

enum MainViewModal {
    case none, camera, photoLibrary, postComposer
}

enum MainViewTab {
    case feed, messages, profile
}

final class MainViewController: ObservableObject {
    //
    // Modal view presentation
    //
    @Published var presentedModalView : MainViewModal = .none

    func presentModally(_ view: MainViewModal) {
        self.presentedModalView = view
    }

    func dismissModalView() {
        self.presentedModalView = .none
    }

    func presentCamera() {
        presentModally(.camera)
    }

    func presentPhotoPicker() {
        presentModally(.photoLibrary)
    }

    func presentPostComposer() {
        presentModally(.postComposer)
    }

    //
    // Tab Bar
    //
    @Published var currentTab : MainViewTab = .feed ///TODO: make restorable
    func selectTab(_ tab: MainViewTab) {
        currentTab = tab
    }

    func selectFeedTab() {
        selectTab(.feed)
    }

    func selectMessagesTab() {
        selectTab(.messages)
    }

    func selectProfileTab() {
        selectTab(.profile)
    }

    //
    // Other navigation
    //
    func messageAuthor(of post: FeedDataItem) {
        
    }
}

struct MainView: View {
    @EnvironmentObject var mainViewController: MainViewController

    @State private var mediaToPost: [FeedMedia] = []

    var body: some View {
        ZStack {
            //
            // Currently selected content view
            //
            VStack {
                if mainViewController.currentTab == .feed {
                    NavigationView {
                        FeedView()
                    }
                } else if mainViewController.currentTab == .messages {
                    NavigationView {
                        MessagesView()
                    }
                } else if mainViewController.currentTab == .profile {
                    NavigationView {
                        ProfileView()
                    }
                }
            }

            //
            // Possible full-screen modal views
            //
            // Camera
            if (mainViewController.presentedModalView == .camera) {
                CameraPickerView(capturedMedia: self.$mediaToPost,
                                 didFinishWithMedia: {
                                    Utils().requestMultipleUploadUrl(xmppStream: AppContext.shared.xmpp.xmppController.xmppStream, num: self.mediaToPost.count)
                                    self.mainViewController.presentPostComposer() },
                                 didCancel: { self.mainViewController.dismissModalView() })
                    .transition(.move(edge: .bottom))
                    .animation(.easeInOut)
            }

            // Photo Library picker
            if (mainViewController.presentedModalView == .photoLibrary) {
                PickerWrapper(selectedMedia: self.$mediaToPost,
                              didFinishWithMedia: {
                                Utils().requestMultipleUploadUrl(xmppStream: AppContext.shared.xmpp.xmppController.xmppStream, num: self.mediaToPost.count)
                                self.mainViewController.presentPostComposer() },
                              didCancel: { self.mainViewController.dismissModalView() })
                    .transition(.move(edge: .bottom))
                    .animation(.easeInOut)
            }

            // Post Composer
            if (mainViewController.presentedModalView == .postComposer) {
                PostComposerView(mediaItemsToPost: mediaToPost,
                                 didFinish: {
                                    self.mediaToPost.removeAll()
                                    self.mainViewController.dismissModalView() })
                    .transition(.move(edge: .bottom))
                    .animation(.easeInOut)
            }
        }
        .environmentObject(mainViewController)
    }
}
