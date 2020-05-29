//
//  ProfileEditView.swift
//  HalloApp
//
//  Created by Alan Luo on 5/28/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct ProfileEditView: View {
    
    var dismiss: (() -> ())?
    
    @State private var name: String = AppContext.shared.userData.name
    
    var body: some View {
        NavigationView {
            VStack {
                List {
                    Section(header: Text("Your Photo")) {
                        Image(systemName: "person.crop.circle")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 50, height: 50)
                            .foregroundColor(.gray)
                        
                    }
                    
                    Section(header: Text("Your Name")) {
                        HStack {
                            TextField("Enter your name", text: $name)
                        }
                    }
                    
                    Section(header: Text("Your Phone Number")) {
                        HStack {
                            Text(AppContext.shared.userData.formattedPhoneNumber)
                                .foregroundColor(.gray)
                        }
                    }
                }.listStyle(GroupedListStyle())
            }.navigationBarTitle("Edit Profile", displayMode: .inline)
            .navigationBarItems(leading:
                HStack {
                    Button(action: {
                        if self.dismiss != nil {
                            self.dismiss!()
                        }
                    }) {
                        Text("Cancel")
                            .foregroundColor(Color.red)
                    }
                }, trailing:
                HStack {
                    Button(action: {
                        if (self.name != AppContext.shared.userData.name) {
                            AppContext.shared.userData.name = self.name
                            AppContext.shared.userData.save()
                            
                            AppContext.shared.xmppController.sendCurrentUserNameIfPossible()
                        }
                        
                        if self.dismiss != nil {
                            self.dismiss!()
                        }
                    }) {
                        Text("Done")
                            .foregroundColor(Color("Tint"))
                    }
                }
            )
        }
    }
}

struct ProfileEditView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileEditView()
    }
}
