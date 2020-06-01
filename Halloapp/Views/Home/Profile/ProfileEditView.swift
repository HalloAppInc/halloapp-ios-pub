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
    
    @ObservedObject var name = TextWithLengthLimit(limit: 25, text: AppContext.shared.userData.name)
    
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
                            TextField("Enter your name", text: $name.text)
                            
                            Text("\(name.text.count)/25")
                                .foregroundColor(.gray)
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
                            .foregroundColor(Color("Tint"))
                    }
                }, trailing:
                HStack {
                    Button(action: {
                        if (self.name.text != AppContext.shared.userData.name) {
                            AppContext.shared.userData.name = self.name.text
                            AppContext.shared.userData.save()
                            
                            AppContext.shared.xmppController.sendCurrentUserNameIfPossible()
                        }
                        
                        if self.dismiss != nil {
                            self.dismiss!()
                        }
                    }) {
                        Text("Done")
                            .fontWeight(.medium)
                            .foregroundColor(name.text == "" ? .gray : Color("Tint"))
                    }.disabled(name.text == "")
                    
                }
            )
        }
    }
}

class TextWithLengthLimit: ObservableObject {
    let limit: Int
    
    @Published var text: String {
        didSet {
            if text.count > limit {
                text = oldValue
            }
        }
    }
    
    init(limit: Int, text: String) {
        self.limit = limit
        self.text = text
    }
}

struct ProfileEditView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileEditView()
    }
}
