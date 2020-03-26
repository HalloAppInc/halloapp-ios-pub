//
//  Favorites.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/9/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import CoreData
import SwiftUI

struct MessagesView: View {
    @EnvironmentObject var mainViewController: MainViewController
    @Environment(\.managedObjectContext) var managedObjectContext

    @FetchRequest(
        entity: ABContact.entity(),
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ABContact.statusValue, ascending: true),
            NSSortDescriptor(keyPath: \ABContact.sort, ascending: true)
        ],
        predicate: NSPredicate(format: "statusValue = %d OR (statusValue = %d AND userId != nil)", ABContact.Status.in.rawValue, ABContact.Status.out.rawValue)
    ) var contacts: FetchedResults<ABContact>

    @State var showComposeView = false
    @State var showSearchView = false

    var body: some View {
        VStack {
            List(contacts, id: \.self) { contact in
                HStack {
                    Image(systemName: "circle.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundColor(Color.gray)
                        .clipShape(Circle())
                        .frame(width: 50, height: 50, alignment: .center)
                        .padding(.zero)

                    VStack(alignment: .leading) {
                        Text(contact.fullName!)
                            .foregroundColor(contact.status == .in ? Color.primary : Color.secondary)
                            .padding(.zero)

                        Text(contact.phoneNumber!)
                            .font(.system(size: 12, weight: .regular))
                            .padding(EdgeInsets(top: 5, leading: 0, bottom: 0, trailing: 0))
                            .foregroundColor(Color.secondary)
                    }
                }
                .padding(EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 5))
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button(action: {
                    self.showSearchView = true
                }) {
                    Image(systemName: "magnifyingglass")
                    .padding(8)
                }
                .sheet(isPresented: self.$showSearchView) {
                    MessageUser(isViewPresented: self.$showSearchView)
                }

                Button(action: {
                    self.showComposeView = true
                }) {
                    Image(systemName: "square.and.pencil")
                    .padding(8)
                }
                .sheet(isPresented: self.$showComposeView) {
                    MessageUser(isViewPresented: self.$showComposeView)
                }
            }
            .foregroundColor(Color.primary)
            .font(Font.system(size: 20))
        )
    }
}
