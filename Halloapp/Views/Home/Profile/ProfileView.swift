//
//  ProfileView.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/9/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var userData: UserData
    @EnvironmentObject var mainViewController: MainViewController
    @EnvironmentObject var feedData: FeedData
    @EnvironmentObject var contacts: Contacts

    @State var showSheet = false
    @State var showSettings = false

    var body: some View {
        FeedCollectionView(
            isOnProfilePage: true,
            items: self.feedData.feedDataItems,
            getItemMedia: { itemId in
                self.feedData.getItemMedia(itemId)
            },
            setItemCellHeight: { itemId, cellHeight in
                self.feedData.setItemCellHeight(itemId, cellHeight)
            })

            .overlay(
                BottomBarView(),
                alignment: .bottom
            )
            
            .edgesIgnoringSafeArea(.all)

            .navigationBarTitle(Text("Profile"))

            .navigationBarItems(trailing:
                HStack {
                    Button(action: {
                        self.showSettings = true
                        self.showSheet = true
                    }) {
                        Image(systemName: "person.crop.square.fill")
                            .font(Font.title.weight(.regular))
                            .foregroundColor(Color.primary)
                    }
                    .padding(.trailing, 8)

                    Button(action: {
                        self.showSettings = true
                        self.showSheet = true
                    }) {
                        Image(systemName: "gear")
                            .font(Font.title.weight(.regular))
                            .foregroundColor(Color.primary)
                    }
            })

            .sheet(isPresented: self.$showSheet, content: {
                if (self.showSettings) {
                    Settings(onDismiss: {
                        self.showSheet = false
                    })
                        .environmentObject(self.userData)
                        .environmentObject(self.mainViewController)
                } else if (self.showSheet) {

                }
            })
    }
}
