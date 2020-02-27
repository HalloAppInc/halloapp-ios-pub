//
//  Notifications.swift
//  Halloapp
//
//  Created by Tony Jiang on 11/17/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct Notifications: View {
    var onDismiss: () -> ()
    
    var body: some View {
        VStack() {
            HStack() {
                Spacer()
                Button(action: {
                    self.onDismiss()
                    
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.primary)
                        .padding()
                }
            }
            Spacer()
            Text("Notifications coming soon")
            Spacer()

        }
    }
}


//struct Notifications_Previews: PreviewProvider {
//    static var previews: some View {
//        Notifications()
//    }
//}

