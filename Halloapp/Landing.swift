//
//  Landing.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/25/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct Landing: View {
    @ObservedObject var userData = AppContext.shared.userData

    var body: some View {
        VStack {
            if (self.userData.isLoggedIn) {
                HomeInit()
            } else {
                AuthRouter()
            }
        }
    }
}
