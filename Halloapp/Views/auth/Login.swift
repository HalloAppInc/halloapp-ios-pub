//
//  Login.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/19/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct Login: View {
    
    @EnvironmentObject var authRouteData: AuthRouteData
    @EnvironmentObject var userData: UserData
    
    var body: some View {
            VStack {
                Text("Halloapp")
                    .font(.custom("BanglaSangamMN-Bold", size: 80))
                    .fontWeight(.heavy)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.green)
                
                VStack {
                    TextField("Please enter your phone number", text: $userData.phone)
                        .multilineTextAlignment(.center)
                        .padding(.all)
                        .background(Color(red: 239.0/255.0, green: 243.0/255.0, blue: 244.0/255.0, opacity: 1.0))

                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(userData.highlight ? Color.red : Color.clear, lineWidth: 2)
                        )

                    TextField("", text: $userData.status)
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color.orange)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 80)
                
                Button(action: {
                    if self.userData.validate() {
                        self.authRouteData.gotoPage(page: "verify")
                    } else {
                        
                    }
                }) {
                    Text("JOIN US")

                        .padding(15)
                        .background(LinearGradient(gradient: Gradient(colors: [Color.blue, Color.green]), startPoint: .leading, endPoint: .trailing))
                        .foregroundColor(.white)
                        .cornerRadius(40)
                        .shadow(radius: 5)
                }
            }
            .padding(.horizontal, 15)
    }
}

struct Login_Previews: PreviewProvider {
    static var previews: some View {
        Login()
            .environmentObject(AuthRouteData())
            .environmentObject(UserData())
    }
}
