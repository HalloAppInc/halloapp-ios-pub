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
    static private let barHeight: CGFloat = 59

    @EnvironmentObject var mainViewController: MainViewController

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Spacer () // This spacer will push the bottom bar all the way to the bottom edge in full-screen GeometryReader container
                VStack(spacing: 0) {

                    Divider()

                    HStack(alignment: .top) {
                        // "Home" tab
                        VStack(alignment: .center) {
                            Button(action: {
                                self.mainViewController.selectFeedTab()
                            }) {
                                Image(systemName: "house.fill")
                                    .imageScale(.large)
                                    .foregroundColor(self.mainViewController.currentTab == .feed ? Color.primary : Color.gray)
                                    .padding(EdgeInsets(top: 20, leading: 25, bottom: 20, trailing: 25))
                            }
                        }
                        .frame(width: 75)

                        Spacer()

                        // "Messages" tab
                        VStack(alignment: .center) {
                            Button(action: {
                                self.mainViewController.selectMessagesTab()
                            }) {
                                Image(systemName: "envelope.fill")
                                    .imageScale(.large)
                                    .foregroundColor(self.mainViewController.currentTab == .messages ? Color.primary : Color.gray)
                                    .padding(EdgeInsets(top: 20, leading: 25, bottom: 20, trailing: 25))
                            }
                        }
                        .frame(width: 75)

                        Spacer()

                        // "Profile" tab
                        VStack(alignment: .center) {
                            Button(action: {
                                self.mainViewController.selectProfileTab()
                            }) {
                                Image(systemName: "person.fill")
                                    .imageScale(.large)
                                    .foregroundColor(self.mainViewController.currentTab == .profile ? Color.primary : Color.gray)
                                    .padding(EdgeInsets(top: 20, leading: 25, bottom: 20, trailing: 25))
                            }
                        }
                        .frame(width: 75)
                    }
                        // 30 instead of 40 on sides cause it looks better on older phones
                        .padding(EdgeInsets(top: 0, leading: 30, bottom: 0, trailing: 30))
                        .frame(height: BottomBarView.barHeight)

                    // Safe area inset padding on devices without home button.
                    // Note that we intentionally make padding smaller than the bottom inset
                    // to let bar buttons actually use some of that space vs keeping the space unused.
                    Spacer()
                        .frame(height: 0.5*geometry.safeAreaInsets.bottom)
                }
                .background(BlurView(style: .systemChromeMaterial))
                .padding(.zero)
            }
        }
    }

    static func currentBarHeight() -> CGFloat {
        let keyWindow = UIApplication.shared.connectedScenes
                .filter({$0.activationState == .foregroundActive})
                .map({$0 as? UIWindowScene})
                .compactMap({$0})
                .first?.windows
                .filter({$0.isKeyWindow}).first
        guard keyWindow != nil else {
            return barHeight
        }
        let bottomSafeAreaInset = keyWindow!.safeAreaInsets.bottom
        // Scroll view's insets are automatically adjusted by the amount of bottom safe area inset.
        // Increase inset by visible height of the bottom bar and subtract value applied automatically: barHeight + 0.5*bottomInset - bottomInset
        return barHeight - 0.5*bottomSafeAreaInset
    }
}

struct BottomBarView_Previews: PreviewProvider {
    static var previews: some View {
        BottomBarView()
    }
}
