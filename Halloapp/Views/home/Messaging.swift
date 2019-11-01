//
//  Favorites.swift
//  Halloapp
//
//  Created by Tony Jiang on 10/9/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI
import Contacts

struct Messaging: View {
    
    @EnvironmentObject var authRouteData: AuthRouteData

    @ObservedObject var contacts: Contacts
       
    var body: some View {
        VStack {
            Spacer()
            if contacts.error == nil {
                List(contacts.normalizedContacts) { (contact: NormContact) in

                    return HStack {
                        Text(contact.name)
                        Text(contact.phone)
                    }

                }.onAppear{
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        print("fetching contacts now")
//                        self.store.fetch()
                    }
                }
            } else {
                Text("error: \(contacts.error!.localizedDescription)")
            }
            Spacer()
            Navi()
        }
        
    }
}

struct Messaging_Previews: PreviewProvider {
    static var previews: some View {
        Messaging(contacts: Contacts(xmpp: XMPP(user: "xx", password: "xx")))
            .environmentObject(AuthRouteData())
         

    }
}
