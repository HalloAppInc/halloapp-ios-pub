//
//  ProfileView.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/9/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var mainViewController: MainViewController

    @State var showSettings = false
    @State var showDeveloperMenu = false

    var body: some View {
        VStack {
            FeedTableView(isOnProfilePage: true)
        }
        .overlay(BottomBarView())
            
        .edgesIgnoringSafeArea(.all)

        .navigationBarTitle(Text("Profile"))

        .navigationBarItems(trailing:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button(action: {
                    self.showDeveloperMenu = true
                }) {
                    Image(systemName: "hammer")
                        .padding(8)
                }
                .sheet(isPresented: self.$showDeveloperMenu) {
                    DeveloperMenuView(isViewPresented: self.$showDeveloperMenu)
                }

                Button(action: {
                    self.showSettings = true
                }) {
                    Image(systemName: "gear")
                        .padding(8)
                }
                .sheet(isPresented: self.$showSettings) {
                    SettingsView(isViewPresented: self.$showSettings)
                        .environmentObject(self.mainViewController)
                }
            }
            .foregroundColor(Color.primary)
            .font(Font.system(size: 20))
        )
    }
}
