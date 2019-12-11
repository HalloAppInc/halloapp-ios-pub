//
//  Verify.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/25/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct Verify: View {

    @EnvironmentObject var authRouteData: AuthRouteData
    @EnvironmentObject var userData: UserData
    @EnvironmentObject var verification: Verification
    
    var body: some View {
        
        VStack {
            Text("Please enter the verification code")
            
            VStack {
                TextField("Verification Code", text: $verification.code)
                    .multilineTextAlignment(.center)
                    .padding(.all)
                    .background(Color(red: 239.0/255.0, green: 243.0/255.0, blue: 244.0/255.0, opacity: 1.0))

                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(verification.highlight ? Color.red : Color.blue, lineWidth: 2)
                    )
                    .frame(width: 200, height: nil)
                    .font(Font.system(size: 22, design: .default))

                TextField("", text: $verification.status)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.orange)
            }
            .padding(50)
            
            Button(action: {
                if self.verification.validate() {
                    self.userData.setIsLoggedIn(value: true)
                    self.authRouteData.gotoPage(page: "feed")
                } else {
                    
                }
            }) {
                Text("CONTINUE")

                    .padding(15)
                    .background(LinearGradient(gradient: Gradient(colors: [Color.green, Color.green]), startPoint: .leading, endPoint: .trailing))
                    .foregroundColor(.white)
                    .cornerRadius(40)
                    .shadow(radius: 5)
            }
        }

        
        
    }
}

struct Verify_Previews: PreviewProvider {
    static var previews: some View {
        Verify()
            .environmentObject(AuthRouteData())
            .environmentObject(Verification())
    }
}
