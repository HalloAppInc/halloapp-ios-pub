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
    
    var body: some View {
        
        VStack {
            if authRouteData.currentPage == "login" {
                Login()
            } else if authRouteData.currentPage == "verify" {
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
