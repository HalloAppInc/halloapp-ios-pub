//
//  Auth.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/25/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct AuthRouter: View {
    
    @EnvironmentObject var authRouteData: AuthRouteData
    @EnvironmentObject var userData: UserData
    
    var body: some View {
        
        VStack {
            if !userData.isRegistered {
                Login()
            } else if (userData.isRegistered) {
                Verify()
            }
        }
        
    }
}

struct AuthRouter_Previews: PreviewProvider {
    static var previews: some View {
        AuthRouter()
            .environmentObject(AuthRouteData())
            .environmentObject(UserData())
            
    }
}
