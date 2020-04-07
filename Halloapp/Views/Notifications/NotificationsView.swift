//
//  Notifications.swift
//  Halloapp
//
//  Created by Tony Jiang on 11/17/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import CoreData
import SwiftUI

struct NotificationsView: View {
    @Binding var isViewPresented: Bool

    @Environment(\.managedObjectContext) var managedObjectContext

    @FetchRequest(
        entity: FeedNotification.entity(),
        sortDescriptors: [ NSSortDescriptor(keyPath: \FeedNotification.timestamp, ascending: false) ]
    ) var notifications: FetchedResults<FeedNotification>

    var body: some View {
        NavigationView {
            VStack {
                if notifications.isEmpty {
                    Spacer()

                    Text("Nothing to see here").font(.title)

                    Spacer()
                } else {
                    List(notifications, id: \.self) { notification in
                        HStack {
                            // Contact photo
                            Image(systemName: "person.crop.circle")
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(Color.gray)
                                .clipShape(Circle())
                                .frame(width: 36, height: 36, alignment: .center)
                                .padding(.zero)

                            // TODO: formatted text
                            Text(notification.formattedText.string).font(.footnote)

                            Spacer()

                            // Post preview
                            if notification.image != nil {
                                Image(uiImage: notification.image!)
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundColor(Color.gray)
                                    .frame(width: 36, height: 36, alignment: .center)
                                    .padding(.zero)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                    .onAppear {
                        UITableView.appearance().separatorStyle = .none
                    }
                }
            }

            .navigationBarTitle(Text("Notifications"), displayMode: .inline)

            .navigationBarItems(leading:
                HStack {
                    Button(action: {
                        self.isViewPresented = false
                    }) {
                        Image(systemName: "xmark")
                            .padding(8)
                    }
                }
                .foregroundColor(Color.primary)
                .font(Font.system(size: 20))
            )
        }
    }
}
