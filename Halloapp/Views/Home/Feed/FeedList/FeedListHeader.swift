//
//  FeedListHeader.swift
//  Halloapp
//
//  Created by Tony Jiang on 2/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import SwiftUI

struct FeedListHeader: View {
        
    var isOnProfilePage: Bool
    @ObservedObject var contacts: Contacts
    
    var body: some View {
      
        VStack(spacing: 0) {

            if (isOnProfilePage) {
                HStack {
                    Spacer()
                    VStack(spacing: 0) {
                        
                        Button(action: {
        //                                self.showMoreActions = true
                        }) {
                            Image(systemName: "circle.fill")
                                .resizable()
                            
                                .scaledToFit()
                                .foregroundColor(Color(UIColor.systemGray3))
                                .clipShape(Circle())
                            
                                .frame(width: 50, height: 50, alignment: .center)
                                .padding(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))

                        }
                            
                        Text("\(self.contacts.xmpp.userData.phone)")
                    }

                    
                    Spacer()
                }
                .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            
            
            
            HStack() {

                VStack (spacing: 0) {
                    
                    Spacer()
                }
                
                Spacer()

            }
            
            Spacer()
            

        }
        
        .padding(EdgeInsets(top: 30, leading: 0, bottom: 10, trailing: 0))
        .background(Color(UIColor.systemGroupedBackground))
    }
    

}


