//
//  Settings.swift
//  Halloapp
//
//  Created by Tony Jiang on 11/20/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct Settings: View {
    
    @EnvironmentObject var userData: UserData
    @EnvironmentObject var homeRouteData: HomeRouteData
    
    var onDismiss: () -> ()
    
    @State private var isButtonVisible = true
    
    var body: some View {
        VStack() {
//            WUICollectionView()
//                .background(Color.red)
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
            
            Text("1.0.7")
            Button(action: {
                self.userData.logout()
                self.homeRouteData.gotoPage(page: "feed")
                
            }) {
                Text("Log out")
                    .padding(10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(20)
                    .shadow(radius: 2)
            }
            .padding(.top, 100)
            
            
            Spacer()

        }
    }
}

//struct Settings_Previews: PreviewProvider {
//    static var previews: some View {
//        Settings()
//    }
//}
