//
//  HomeController.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/25/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct HomeInit: View {
    @ObservedObject var xmpp: XMPP
    
    var body: some View {
        VStack {
            if (xmpp.userData.isLoggedIn) {
                MainView(contacts: Contacts(xmpp: xmpp), feedData: FeedData(xmpp: xmpp))
                .environmentObject(xmpp)
                .environmentObject(MainViewController())
            } else {
                ActivityIndicator()
                    .frame(width: 50, height: 50)
                
            }
        }
    }
}
