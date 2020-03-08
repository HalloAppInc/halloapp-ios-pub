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

    @ObservedObject var userData = AppContext.shared.userData
    
    @State var isButtonClicked = false
    
    var body: some View {
        VStack() {
            Divider()
                .frame(height: 80)
                .hidden()
            
            Text("Hallo")
                .font(.gothamMedium(80))
                .fontWeight(.heavy)
                .multilineTextAlignment(.center)
                .foregroundColor(Color.primary)
                
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "plus")
                        .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .foregroundColor(Color(UIColor.systemGray))
                    
                    /* Country Code */
                    TextField("", text: self.$userData.countryCode, onEditingChanged: { (changed) in
                    }) {
                        // pressing enter should go to the phone number input box, if it's empty
                    }
                    .font(.gothamBody)
                    .frame(minWidth: 0, maxWidth: 60, minHeight: 20, maxHeight: 20)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .padding(EdgeInsets(top: 15, leading: 10, bottom: 15, trailing: 10))
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(self.userData.highlight ? Color(UIColor.systemRed) : Color.clear, lineWidth: 2)
                    )
                
                    /* Phone Number */
                    TextField("phone number", text: self.$userData.phoneInput, onEditingChanged: { (changed) in
                    }) {
                        // pressing enter
                        if self.userData.validate() {
                             self.authRouteData.gotoPage(page: "verify")
                         }
                    }
                    .font(.gothamBody)
                    .frame(height: 20)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .padding(EdgeInsets(top: 15, leading: 10, bottom: 15, trailing: 10))
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(self.userData.highlight ? Color(UIColor.systemRed) : Color.clear, lineWidth: 2)
                    )
                }
                
                /* error messages */
                    Text(self.userData.status)
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color(UIColor.systemOrange))
                        .frame(height: 50)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 0)

            Button(action: {
                self.isButtonClicked = true
                
                if self.userData.validate() {
                    self.authRouteData.gotoPage(page: "verify")
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    self.isButtonClicked = false
                }
            }) {
                Text("Sign In")
                    .font(Font.gothamBody)
                    .padding(15)
                    .background(self.isButtonClicked ? Color(UIColor.systemGray5) : Color(UIColor.systemBlue))
                    .foregroundColor(self.isButtonClicked ? .gray : .white)
                    .cornerRadius(40)
                    .shadow(radius: 5)
            }
            .disabled(self.isButtonClicked)
            
            Spacer()
        }
        .padding(.horizontal, 0)
    }
}
