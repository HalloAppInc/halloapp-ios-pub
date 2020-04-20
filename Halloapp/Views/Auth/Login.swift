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
                .frame(height: 20)
                .hidden()
            
            Text("Hallo")
                .font(.system(size: 80, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundColor(Color.primary)
                
            VStack(spacing: 0) {
                HStack {
                    /* Name */
                    TextField("name", text: self.$userData.name) {
                        // pressing enter
                        if self.userData.validate() {
                             self.authRouteData.gotoPage(page: "verify")
                         }
                    }
                    .font(.body)
                    .keyboardType(.namePhonePad)
                    .autocapitalization(.words)
                    .textContentType(.name)
                    .multilineTextAlignment(.center)
                    .padding(EdgeInsets(top: 15, leading: 10, bottom: 15, trailing: 10))
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(self.userData.highlight ? Color(UIColor.systemRed) : Color.clear, lineWidth: 2)
                    )
                }
                .padding(.bottom, 20)
                
                HStack {
                    Image(systemName: "plus")
                        .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .foregroundColor(Color(UIColor.systemGray))
                    
                    /* Country Code */
                    TextField("", text: self.$userData.countryCode) {
                        // TODO: pressing enter should go to the phone number input box, if it's empty
                    }
                    .frame(width: 60)
                    .multilineTextAlignment(.center)
                    .padding(EdgeInsets(top: 15, leading: 10, bottom: 15, trailing: 10))
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(self.userData.highlight ? Color(UIColor.systemRed) : Color.clear, lineWidth: 2)
                    )
                
                    /* Phone Number */
                    TextField("phone number", text: self.$userData.phoneInput) {
                        // pressing enter
                        if self.userData.validate() {
                             self.authRouteData.gotoPage(page: "verify")
                         }
                    }
                    .multilineTextAlignment(.leading)
                    .padding(EdgeInsets(top: 15, leading: 10, bottom: 15, trailing: 10))
                    .background(Color(UIColor.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(self.userData.highlight ? Color(UIColor.systemRed) : Color.clear, lineWidth: 2)
                    )
                }
                .font(.body)
                .keyboardType(.numberPad)

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
                    .font(.system(.body, weight: .medium))
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
