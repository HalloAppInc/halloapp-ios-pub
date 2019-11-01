//
//  Landing.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/25/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct Landing: View {
    
    @EnvironmentObject var authRouteData: AuthRouteData
    @EnvironmentObject var userData: UserData

    
    var body: some View {
        VStack {
            if (authRouteData.isLoggedIn) {
                HomeInit(xmpp: XMPP(user: self.userData.userJIDString, password: self.userData.password))
            } else {
                AuthRouter()
            }
        }
    }
}

struct Landing_Previews: PreviewProvider {
    static var previews: some View {
        Landing()
            .environmentObject(AuthRouteData())
            .environmentObject(UserData())
           
    }
}
