//
//  MessageUser.swift
//  Halloapp
//
//  Created by Tony Jiang on 11/18/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct MessageUser: View {
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
                        .foregroundColor(Color.black)
                        .padding()
                }
            }
            Spacer()
            Text("coming very soon")
//            WUICollectionView()
//                .background(Color.red)
            Spacer()

        }
    }
}

//struct MessageUser_Previews: PreviewProvider {
//    static var previews: some View {
//        MessageUser()
//    }
//}
