//
//  ExportDataView.swift
//  HalloApp
//
//  Created by Matt Geimer on 6/28/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import SwiftUI
import Core
import CoreCommon
import CocoaLumberjackSwift

struct ExportDataView: View {
    
    @ObservedObject var model: ExportDataModel
    
    var body: some View {
        mainBody
            .navigationBarTitleDisplayMode(.inline)
    }
    
    private var mainBody: some View {
        VStack {
            Image(systemName: "arrow.up.doc")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .font(Font.title.weight(.thin))
                .frame(height: 100)
                .padding(.vertical)
                .foregroundColor(Color(UIColor.tertiaryLabel))
            Text(Localizations.explanationLabelText)
                .padding(.bottom)
            
            switch model.status {
                case .awaitingResponse: AwaitingServerResponseView()
                case .notRequested: NotRequestedView(model: model)
                case .requested: RequestedView(model: model)
                case .available: AvailableView(model: model)
            }
            
            Spacer()
        }
            .padding(.horizontal)
            .navigationBarTitle(Localizations.navBarTitle)
    }
}

private struct AwaitingServerResponseView: View {
    var body: some View {
        ProgressView()
            .scaleEffect(2.5)
            .frame(width: 100, height: 100)
    }
}

private struct NotRequestedView: View {
    
    @ObservedObject var model: ExportDataModel
    
    var body: some View {
        Button(action: {
            model.requestDataPressed()
        }, label: {
            Text(Localizations.requestDataButton)
                .foregroundColor(Color(UIColor.systemBlue))
        })
    }
}

private struct RequestedView: View {
    
    @ObservedObject var model: ExportDataModel
    
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "checkmark.circle")
                Text(Localizations.dataRequestedLabel)
            }
            .foregroundColor(Color(UIColor.primaryBg))
            .padding(6)
            .background(
                Color.lavaOrange.clipShape(Capsule())
            )
            
            if let readyDate = model.readyDate {
                Text(String(format: Localizations.dataAvailableDateLabel, readyDate.shortDateFormat()))
                    .font(.caption)
            } else {
                Text(Localizations.dataAvailabilityDateNotFound)
            }
        }
    }
}

private struct AvailableView: View {
    
    @ObservedObject var model: ExportDataModel
    
    var body: some View {
        if let urlToOpen = model.url {
            VStack {
                Button(action: {
                    DDLogInfo("ExportDataView/AvailableView/ButtonAction: User opened exported data")
                    UIApplication.shared.open(urlToOpen)
                }, label: {
                    Text(Localizations.openDataLink)
                        .foregroundColor(Color(UIColor.systemBlue))
                })
                    .padding()
                
                Text(urlToOpen.absoluteString)
                    .font(.caption)
            }
        } else {
            Text(Localizations.urlError)
        }
    }
}

struct ExportDataView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ExportDataView(model: PreviewDataModel)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Initialize the model with dummy values and disable contacting the server for previews.
private var PreviewDataModel: ExportDataModel {
    let model = ExportDataModel(previewMode: true)
    model.status = .available
    model.readyDate = Date()
    model.url = URL(string: "https://www.halloapp.com")
    
    return model
}

private extension Localizations {
    static var navBarTitle: String {
        NSLocalizedString("settings.account.export.navbar", value: "Export Data", comment: "Navigation bar title informing the user that this page lets them export their user data.")
    }
    
    static var explanationLabelText: String {
        NSLocalizedString("settings.account.export.explanation", value: "Create a report of your HalloApp account information and settings, which you can access or port to another app. This report does not include your messages.", comment: "Explanation about what the data export function is. English language version taken from WhatsApp.")
    }
    
    static var requestDataButton: String {
        NSLocalizedString("settings.account.export.request.button", value: "Request Data Export", comment: "Navigation bar title informing the user that this page lets them export their user data.")
    }
    
    static var loadingDataLabel: String {
        NSLocalizedString("settings.account.export.loading", value: "Loading Data...", comment: "String indicating device is awaiting a server response. Only visible in iOS 13.")
    }
    
    static var dataRequestedLabel: String {
        NSLocalizedString("settings.account.export.requested", value: "Data requested", comment: "Label informing the user that they have requested their data.")
    }
    
    static var dataAvailableDateLabel: String {
        let formatString = NSLocalizedString("settings.account.export.date.available", value: "For security reasons, your data will be available on %1$@", comment: "Label telling the user when their data export will be made available. %1$@ is a date.")
        return formatString
    }
    
    static var dataAvailabilityDateNotFound: String {
        NSLocalizedString("settings.account.export.not.found", value: "Date when your data will be available could not be determined.", comment: "Label for when the date at which the exported user data will be available is not determined.")
    }
    
    static var openDataLink: String {
        NSLocalizedString("settings.account.export.open.data", value: "Open exported data", comment: "Button to open the user data exported from HalloApp.")
    }
    
    static var urlError: String {
        NSLocalizedString("settings.account.export.error", value: "There was an error retrieving your data.", comment: "Label alerting the user that we were unable to retrieve the data.")
    }
}
