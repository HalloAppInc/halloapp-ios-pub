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
        
        Background {
            VStack() {
                Divider()
                    .frame(height: 80)
                    .hidden()
                
                Text("Hallo")
                    .font(.custom("Gotham", size: 80))
                    .fontWeight(.heavy)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.black)
                    
                VStack(spacing: 0) {
                    


                    HStack {
                        
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .regular))
                            .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .foregroundColor(Color.gray)
                        
                        /* Country Code */
                        TextField("", text: self.$userData.countryCode, onEditingChanged: { (changed) in
                        }) {

                            // pressing enter should go to the phone number input box, if it's empty
                            
                        }
                        .font(.system(size: 20, weight: .regular))
                        .frame(minWidth: 0, maxWidth: 60, minHeight: 20, maxHeight: 20)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .padding(EdgeInsets(top: 15, leading: 10, bottom: 15, trailing: 10))
                        .background(Color(red: 239.0/255.0, green: 243.0/255.0, blue: 244.0/255.0, opacity: 1.0))

                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(self.userData.highlight ? Color.red : Color.clear, lineWidth: 2)
                        )
                    
                        /* Phone Number */
                        TextField("phone number", text: self.$userData.phoneInput, onEditingChanged: { (changed) in
                        }) {
                            // pressing enter
                            if self.userData.validate() {
                                 self.authRouteData.gotoPage(page: "verify")
                             } else {
                                 
                             }
                        }
                        .font(.system(size: 20, weight: .regular))
                        .frame(height: 20)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .padding(EdgeInsets(top: 15, leading: 10, bottom: 15, trailing: 10))
                        .background(Color(red: 239.0/255.0, green: 243.0/255.0, blue: 244.0/255.0, opacity: 1.0))

                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(self.userData.highlight ? Color.red : Color.clear, lineWidth: 2)
                        )
                    }
                    
                    

                    /* error messages */
                    Text(self.userData.status)
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color.orange)
                            .frame(height: 50)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 0)
                    
                
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

                    Spacer()
            }
            .padding(.horizontal, 0)

        }
        .onTapGesture {
            let keyWindow = UIApplication.shared.connectedScenes
                    .filter({$0.activationState == .foregroundActive})
                    .map({$0 as? UIWindowScene})
                    .compactMap({$0})
                    .first?.windows
                    .filter({$0.isKeyWindow}).first
            keyWindow?.endEditing(true)
        }
    }


}


//struct Login_Previews: PreviewProvider {
//    static var previews: some View {
//        Login()
//            .environmentObject(AuthRouteData())
//            .environmentObject(UserData())
//    }
//}
