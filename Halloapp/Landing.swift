//
//  Landing.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/25/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

fileprivate struct DebugInfoView: View {
    @ObservedObject var xmppController = MainAppContext.shared.xmppController

    var body: some View {
        VStack {
            Text("Connection Status: \(String(describing:xmppController.connectionState))")
                .font(.footnote)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.5))
    }
}

struct Landing: View {
    @ObservedObject var userData = MainAppContext.shared.userData

    var body: some View {
        ZStack {
            if (self.userData.isLoggedIn) {
                #if DEBUG
                HomeView()
                    .edgesIgnoringSafeArea(.all)
                    .overlay(DebugInfoView().allowsHitTesting(false), alignment: .top)
                #else
                HomeView()
                    .edgesIgnoringSafeArea(.all)
                #endif
            } else {
                VerificationView()
                    .edgesIgnoringSafeArea(.all)
            }
        }
    }
}
