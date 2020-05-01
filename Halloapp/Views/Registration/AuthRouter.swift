//
//  Auth.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/25/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

final class AuthRouteData: ObservableObject {
    @Published var currentPage = "login"

    func gotoPage(page: String) {
        self.currentPage = page
    }
}

struct AuthRouter: View {
    @ObservedObject var userData = AppContext.shared.userData
    
    var body: some View {
        VStack {
            if self.userData.isRegistered {
                Verify()
            } else {
                Login()
            }
        }
    }
}
