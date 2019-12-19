//
//  Test.swift
//  Halloapp
//
//  Created by Tony Jiang on 12/17/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct Test: View {
    var body: some View {
        TabView {
            Content()
                .tabItem {
                    Image(systemName: "list.dash")
                    Text("Menu")
                }

            GroupChat()
                .tabItem {
                    Image(systemName: "square.and.pencil")
                    Text("Order")
                }
        }
    }
}

struct Test_Previews: PreviewProvider {
    static var previews: some View {
        Test()
    }
}
