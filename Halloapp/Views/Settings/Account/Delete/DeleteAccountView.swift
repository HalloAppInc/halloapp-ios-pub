//
//  DeleteAccountView.swift
//  HalloApp
//
//  Created by Matt Geimer on 7/1/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import SwiftUI
import Core

struct DeleteAccountView: View {
    
    @ObservedObject var model: DeleteAccountModel
    
    init(isPreview: Bool = false) {
        if isPreview {
            model = DeleteAccountModel.previewModel
        } else {
            model = DeleteAccountModel()
        }
    }
    
    var body: some View {
        if #available(iOS 14.0, *) {
            mainBody
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarTitle(Localizations.deleteAccountAction)
        } else {
            mainBody
                .navigationBarTitle(Localizations.deleteAccountAction)
        }
    }
    
    var mainBody: some View {
        switch model.status {
            case .notDeleted:
                return AnyView(RequestDeletionView(model: model))
            case .deleted:
                return AnyView(AccountDeletedView())
            default:
                return AnyView(AwaitingResponseView())
        }
    }
}

private struct RequestDeletionView: View {
    
    @ObservedObject var model: DeleteAccountModel
    
    @State var isShowingConfirmationAlert = false
    
    @State var phoneNumber = ""
    
    var body: some View {
        VStack (alignment: .leading) {
            Image(systemName: "exclamationmark.triangle")
                .font(Font.largeTitle.weight(.light))
                .foregroundColor(.red)
                .padding()
                .frame(width: UIScreen.main.bounds.width)
            ExplanationView()
            
            TextField(Localizations.yourPhoneNumber, text: $phoneNumber)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .padding()
                .alert(isPresented: $model.isShowingErrorMessage, content: {
                    Alert(title: Text(Localizations.deletionError))
                })
            
            Button(action: {
                isShowingConfirmationAlert.toggle()
            }, label: {
                HStack {
                    Spacer()
                    Text(Localizations.deleteAccountAction)
                        .foregroundColor(Color(UIColor.primaryBg))
                    Spacer()
                }
                .padding(8)
                .background(Capsule().foregroundColor(Color.red))
            })
                .padding()
                .alert(isPresented: $isShowingConfirmationAlert, content: {
                    Alert(title: Text(Localizations.deleteAccountAction), message: Text(Localizations.irreversibleLabel), primaryButton: .destructive(Text(Localizations.buttonDelete), action: {
                        model.requestAccountDeletion(phoneNumber: phoneNumber)
                    }), secondaryButton: .cancel({
                        phoneNumber = ""
                    }))
                })
            
            Spacer()
        }
    }
    
    private struct ExplanationView: View {
        
        private let accountDeletionActions: [String] = [
            Localizations.deletingAccountLabel1,
            Localizations.deletingAccountLabel2,
            Localizations.deletingAccountLabel3
        ]
        
        var body: some View {
            Text(Localizations.deletingAccountHeaderLabel)
                .bold()
                .padding(.horizontal)
                .padding(.bottom, 2)
            ForEach(accountDeletionActions, id: \.self) { accountAction in
                BulletPointView(accountAction)
                    .padding(.horizontal)
            }
        }
    }

    private struct BulletPointView: View {
        
        let content: String
        
        init(_ content: String) {
            self.content = content
        }
        
        var body: some View {
            HStack {
                Text("• \(content)")
                    .font(.caption)
            }
        }
    }
}

/// This view should never be displayed since the user will be logged out beforehand.
private struct AccountDeletedView: View {
    var body: some View {
        Text(Localizations.accountDeletedLabel)
    }
}

private struct AwaitingResponseView: View {
    var body: some View {
        if #available(iOS 14, *) {
            ProgressView()
                .scaleEffect(2.5)
                .frame(width: 100, height: 100)
        } else {
            Text(Localizations.waitingForResponseLabel)
                .font(.title)
        }
    }
}

struct DeleteAccountView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            DeleteAccountView(isPreview: true)
        }
    }
}

private extension DeleteAccountModel {
    static var previewModel: DeleteAccountModel = {
        let model = DeleteAccountModel()
        model.status = .notDeleted
        return model
    }()
}

private extension Localizations {
    static var accountDeletedLabel: String {
        NSLocalizedString("settings.account.delete.deleted", value: "Account Deleted", comment: "Label telling the user that their account has been deleted")
    }
    
    static var deletingAccountHeaderLabel: String {
        NSLocalizedString("settings.account.delete.header", value: "Deleting your account will:", comment: "Label above list of things that will happen if they delete their account")
    }
    
    static var deletingAccountLabel1: String {
        NSLocalizedString("settings.account.delete.bullet1", value: "Delete your account info and profile photo", comment: "Action that will occur when users delete their account")
    }
    
    static var deletingAccountLabel2: String {
        NSLocalizedString("settings.account.delete.bullet2", value: "Remove you from all HalloApp groups", comment: "Action that will occur when users delete their account")
    }
    
    static var deletingAccountLabel3: String {
        NSLocalizedString("settings.account.delete.bullet3", value: "Delete your message history on this phone", comment: "Action that will occur when users delete their account")
    }
    
    static var deleteAccountAction: String {
        NSLocalizedString("settings.account.delete.action.title", value: "Delete Account", comment: "Title of alert telling the user they're about to delete their account")
    }
    
    static var irreversibleLabel: String {
        NSLocalizedString("settings.account.delete.irreversible.label", value: "This action is irreversible", comment: "Alert message telling the user that account deletion is irreversible")
    }
    
    static var deletionError: String {
        NSLocalizedString("settings.account.delete.error", value: "There was an error deleting your account. Please make sure your phone number is correct.", comment: "Alert telling user that their account could not be deleted, and that it's likely due to their phone number")
    }
    
    static var yourPhoneNumber: String {
        NSLocalizedString("settings.account.delete.phone.number", value: "Your Phone Number", comment: "Text field placeholder telling the user that their phone number should go into the field")
    }
    
    static var waitingForResponseLabel: String {
        NSLocalizedString("settings.account.delete.spinner.replacement", value: "Waiting for server response", comment: "String that's displayed when a spinner is not available to indicate that the view is waiting for a response from the server")
    }
}
