//
//  AccountList.swift
//  HalloApp
//
//  Created by Matt Geimer on 6/30/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import SwiftUI
import Core

struct AccountSettingsList: View {
    var body: some View {
        if #available(iOS 14, *) {
            mainBody
                .navigationBarTitleDisplayMode(.inline)
        } else {
            mainBody
        }
    }
    
    private var mainBody: some View {
        List {
            NavigationLink(
                destination: ExportDataView(model: ExportDataModel()),
                label: {
                    HStack {
                        Image(systemName: "arrow.up.doc")
                            .foregroundColor(.lavaOrange)
                        Text(Localizations.exportData)
                    }
                }
            )
            
            NavigationLink(
                destination: DeleteAccountView(),
                label: {
                    HStack {
                        Image(systemName: "person.badge.minus")
                            .foregroundColor(.lavaOrange)
                        Text(Localizations.deleteAccount)
                    }
                }
            )
        }
        .navigationBarTitle(Localizations.account)
    }
}

struct AccountList_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            AccountSettingsList()
        }
        
    }
}

private extension Localizations {
    static var account: String {
        NSLocalizedString("settings.account.list.title", value: "Account", comment: "Title for settings page containing account options.")
    }
    
    static var exportData: String {
        NSLocalizedString("settings.account.list.export.data", value: "Request Account Info", comment: "Row to export user data for GDPR compliance.")
    }
    
    static var deleteAccount: String {
        NSLocalizedString("settings.account.list.delete.account", value: "Delete My Account", comment: "Button to delete a user's account.")
    }
}
