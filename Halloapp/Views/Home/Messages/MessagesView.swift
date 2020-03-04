//
//  Favorites.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/9/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI
import Contacts

struct MessagesView: View {
    @EnvironmentObject var authRouteData: AuthRouteData
    @EnvironmentObject var contacts: Contacts
    @EnvironmentObject var mainViewController: MainViewController

    @State var showSheet = false
    @State var showWrite = false
    @State var showCameraAll = false

    var body: some View {
        VStack {
            List() {
                /* id is required else it crashes every now and then */
                ForEach(contacts.connectedContacts, id: \.id) { contact in
                    HStack {
                        Image(systemName: "circle.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(Color.gray)
                            .clipShape(Circle())
                            .frame(width: 50, height: 50, alignment: .center)
                            .padding(.zero)

                        VStack(alignment: .leading) {
                            Text(contact.name)
                                .foregroundColor(Color.primary)
                                .padding(.zero)

                            Text(contact.normPhone != "" ? contact.normPhone : contact.phone)
                                .font(.system(size: 12, weight: .regular))
                                .padding(EdgeInsets(top: 5, leading: 0, bottom: 0, trailing: 0))
                                .foregroundColor(Color.secondary)
                        }
                    }
                    .padding(EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 5))
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

            .onAppear {
                UITableView.appearance().separatorStyle = .none
            }
        }

            .overlay(
                BottomBarView(),
                alignment: .bottom
            )

            .edgesIgnoringSafeArea(.bottom)

            .navigationBarTitle(Text("Messages"))

            .navigationBarItems(trailing:
                HStack {
                    Button(action: {
                        self.showCameraAll = true
                        self.showSheet = true
                    }) {
                        Image(systemName: "magnifyingglass")
                            .font(Font.title.weight(.regular))
                            .foregroundColor(Color.primary)
                    }
                    .padding(.trailing, 8)

                    Button(action: {
                        self.showWrite = true
                        self.showSheet = true
                    }) {
                        Image(systemName: "square.and.pencil")
                            .font(Font.title.weight(.regular))
                            .foregroundColor(Color.primary)
                    }
            })

            .sheet(isPresented: self.$showSheet, content: {
                if (self.showCameraAll) {
                    MessageUser(onDismiss: {
                        self.showSheet = false
                    })
                } else if (self.showWrite) {
                    MessageUser(onDismiss: {
                        self.showSheet = false
                    })
                }
            })
    }
}
