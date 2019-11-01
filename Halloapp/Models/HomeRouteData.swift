//
//  HomeRouter.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/25/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Foundation
import SwiftUI
import Combine

final class HomeRouteData: ObservableObject {

    @Published var homePage = "feed"
    
    func gotoPage(page: String) {
        self.homePage = page
    }
    
}
