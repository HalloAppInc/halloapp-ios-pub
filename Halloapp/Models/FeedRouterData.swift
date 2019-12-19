//
//  FeedRouter.swift
//  Halloapp
//
//  Created by Tony Jiang on 12/16/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//


import Foundation
import SwiftUI
import Combine
import CoreData

final class FeedRouterData: ObservableObject {

    @Published var currentPage = "feed"

    func gotoPage(page: String) {
        self.currentPage = page
    }
    

}
