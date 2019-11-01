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
            if (xmpp.isReady) {
                
                HomeRouter(xmpp: xmpp, contacts: Contacts(xmpp: xmpp), feedData: FeedData(xmpp: xmpp))
                    
            } else {
                
            }
        }
    }
}

struct HomeInit_Previews: PreviewProvider {
    static var previews: some View {
        HomeInit(xmpp: XMPP(user: "jid", password: "pass"))
        
    }
}
