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
import CoreData

final class AuthRouteData: ObservableObject {

    @Published var currentPage = "login"

    func gotoPage(page: String) {
        self.currentPage = page
    }
    

}
