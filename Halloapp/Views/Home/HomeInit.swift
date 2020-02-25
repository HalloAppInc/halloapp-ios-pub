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
                HomeRouter(
                    xmpp: xmpp,
                    contacts: Contacts(xmpp: xmpp),
                    feedData: FeedData(xmpp: xmpp)
                )
                    
            } else {
                ActivityIndicator()
                    .frame(width: 50, height: 50)
                
            }
        }
    }
}

//struct HomeInit_Previews: PreviewProvider {
//    static var previews: some View {
//        HomeInit(xmpp: XMPP(userData: UserData(), metaData: MetaData()))
//        
//    }
//}
