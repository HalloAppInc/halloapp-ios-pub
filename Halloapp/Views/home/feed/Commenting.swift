//
//  Commenting.swift
//  Halloapp
//
//  Created by Tony Jiang on 11/18/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct Commenting: View {
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
            Text("Not available yet")
            Spacer()

        }
    }
}

//struct Commenting_Previews: PreviewProvider {
//    static var previews: some View {
//        Commenting()
//    }
//}
