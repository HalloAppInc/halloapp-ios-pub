//
//  BottomBarView.swift
//  Halloapp
//
//  Created by Igor Solomennikov on 3/2/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI
import UIKit

struct BottomBarView: View {
    @EnvironmentObject var mainViewController: MainViewController

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(alignment: .top) {
                VStack {
                    Button(action: {
                        self.mainViewController.selectFeedTab()
                    }) {
                        Image(systemName: "house.fill")
                            .imageScale(.large)
                            .foregroundColor(self.mainViewController.currentTab == .feed ? Color.primary : Color.gray)
                            .padding(EdgeInsets(top: 20, leading: 25, bottom: 20, trailing: 25))
                    }

//                    Image(systemName: "circle")
//                        .font(.system(size: 7, weight: .heavy))
//                        .foregroundColor((mainViewController.currentTab == .feed /* || homeRouteData.homePage == "back-to-feed"*/) ? Color(red:  40/255, green:  40/255, blue:  40/255) : Color.clear)
//                        .padding(0)
//                        .hidden()
                }

                Spacer()

                VStack {
                    Button(action: {
                        self.mainViewController.selectMessagesTab()
                    }) {
                        Image(systemName: "envelope.fill")
                            .imageScale(.large)
                            .foregroundColor(self.mainViewController.currentTab == .messages ? Color.primary : Color.gray)
                            .padding(EdgeInsets(top: 20, leading: 25, bottom: 20, trailing: 25))
                    }

//                    Image(systemName: "circle")
//                        .font(.system(size: 7, weight: .heavy))
//                        .foregroundColor(mainViewController.currentTab == .messages ? Color(red: 40/255, green: 40/255, blue: 40/255) : Color.clear)
//                        .padding(0)
//                        .hidden()
                }

                Spacer()

                VStack {
                    Button(action: {
                        self.mainViewController.selectProfileTab()
                    }) {
                        Image(systemName: "person.fill")
                            .imageScale(.large)
                            .foregroundColor(self.mainViewController.currentTab == .profile ? Color.primary : Color.gray)
                            .padding(EdgeInsets(top: 20, leading: 25, bottom: 20, trailing: 25))
                    }

//                    Image(systemName: "circle")
//                        .font(.system(size: 7, weight: .heavy))
//                        .foregroundColor(mainViewController.currentTab == .profile ? Color(red:  40/255, green:  40/255, blue:  40/255) : Color.clear)
//                        .padding(0)
//                        .hidden()
                }
            }
                // 30 instead of 40 on sides cause it looks better on older phones
                .padding(EdgeInsets(top: 0, leading: 30, bottom: 0, trailing: 30))

            Spacer()
        }
        .frame(height: BottomBarView.barHeight())
        .background(BlurView(style: .systemChromeMaterial))
        .padding(.zero)
    }

    static func barHeight() -> CGFloat {
        let window = UIApplication.shared.keyWindow
        let bottomPadding = window!.safeAreaInsets.bottom
        return (bottomPadding > 0.0) ? 72 : 59
    }
}

struct BottomBarView_Previews: PreviewProvider {
    static var previews: some View {
        BottomBarView()
    }
}
