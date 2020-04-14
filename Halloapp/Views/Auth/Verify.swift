//
//  Verify.swift
//  Halloapp
//
//  Created by Tony Jiang on 9/25/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct Verify: View {
    @EnvironmentObject var verification: Verification

    @ObservedObject var userData = AppContext.shared.userData
    
    var body: some View {
        
        VStack {
            
            HStack() {
                Button(action: {
                    self.userData.isRegistered = false
                }) {
                    Text("Back")
                        .padding(15)
                        .background(Color.white)
                        .foregroundColor(.blue)
                }
                Spacer()
            }
            
            Divider()
                .frame(height: 20)
                .hidden()
            
            Text("Please enter the verification code")
            
            VStack(spacing: 0) {
                                    
                TextField("Verification Code", text: self.$verification.code) {
                        // pressing enter
                        self.verification.verify(userData: self.userData)
                    }
                    .textContentType(.oneTimeCode) // note: SMS needs to have the word "code" in it
                    .keyboardType(.numberPad)
                    
                    .multilineTextAlignment(.center)
                    .padding(.all)
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(10)
                    .frame(width: 200, height: nil)
                    .font(Font.system(size: 22, design: .default))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(self.verification.highlight ? Color.red : Color.blue, lineWidth: 2)
                    )

                

                Text(self.verification.status)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.orange)
                    .frame(height: 50)
            }
            .padding(EdgeInsets(top: 40, leading: 50, bottom: 10, trailing: 50))
            
            Button(action: {
                self.verification.verify(userData: self.userData)
            }) {
                Text("CONTINUE")

                    .padding(15)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(40)
                    .shadow(radius: 5)
            }
            
            Spacer()
        }
    }
}

