//
//  viewRouter.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/25/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Foundation
import SwiftUI
import Combine

final class AuthRouteData: ObservableObject {

//    @Published var isLoggedIn = false
//    @Published var currentPage = "login"
    
    @Published var isLoggedIn = true
    @Published var currentPage = "feed"
    

    func gotoPage(page: String) {
        self.currentPage = page
    }
    
    func setIsLoggedIn(value: Bool) {
        self.isLoggedIn = value
    }
}
