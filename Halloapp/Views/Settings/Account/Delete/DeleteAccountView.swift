//
//  DeleteAccountView.swift
//  HalloApp
//
//  Created by Matt Geimer on 7/1/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import SwiftUI
import Core
import CoreCommon

// MARK: - DeleteAccountViewController

class DeleteAccountViewController: UIHostingController<DeleteAccountView> {

    private let model = DeleteAccountModel()

    init() {
        super.init(rootView: DeleteAccountView(model: model))
        model.delegate = self
        title = Localizations.deleteAccountAction
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension DeleteAccountViewController: DeleteAccountModelDelegate {

    func deleteAccountModelDidRequestCancel(_ model: DeleteAccountModel) {
        navigationController?.popViewController(animated: true)
    }
}

// MARK: - DeleteAccountView

struct DeleteAccountView: View {

    @ObservedObject var model: DeleteAccountModel

    @State private var isShowingConfirmationAlert = false
    @State private var keyboardVisible = false

    var body: some View {
        ZStack {
            Color.deleteAccountBackground.edgesIgnoringSafeArea(.all)
            VStack(spacing: 0) {
                Spacer()
                switch model.status {
                case .warning:
                    explanation
                case .confirm:
                    phoneNumberForm
                case .waitingForResponse:
                    ProgressView()
                        .scaleEffect(2.5)
                        .frame(width: 100, height: 100)
                case .deleted:
                    Text(Localizations.accountDeletedLabel)
                }
                Spacer()

                if [.warning, .confirm].contains(model.status) {
                    if model.status == .warning {
                        continueButton
                    } else if model.status == .confirm {
                        confirmButton
                    }

                    Button(action: model.cancel) {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.NUX)
                    }
                    .padding(.top, 16)
                    // Use a fixed size from the bottom if the keyboard is hidden
                    // to prevent buttons from moving
                    if keyboardVisible {
                        Spacer()
                    } else {
                        Color.clear.frame(height: 96)
                    }
                }
            }
            .padding(.horizontal, 16)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                keyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardVisible = false
            }
        }
    }

    private var phoneNumberForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Localizations.phoneNumberPrompt)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.deleteAccountHelperText)
            DeleteAccountPhoneNumberTextField(phoneNumber: $model.phoneNumber)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .fixedSize(horizontal: false, vertical: true)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.deleteAccountFieldBackground))
                .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 0.5)
                .padding(.bottom, 32)
            Text(Localizations.feedbackPrompt)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.deleteAccountHelperText)
            DeleteAccountTextView(text: $model.feedback,
                                  placeholder: Localizations.feedbackPlaceholder)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.deleteAccountFieldBackground))
                .shadow(color: .black.opacity(0.15), radius: 0, x: 0, y: 0.5)
                .frame(maxHeight:  90)
        }
        .alert(isPresented: $model.isShowingErrorMessage) {
            Alert(title: Text(Localizations.deletionError))
        }
    }

    private var explanation: some View {
        let accountDeletionActions: [String] = [
            Localizations.deletingAccountLabel1,
            Localizations.deletingAccountLabel2,
            Localizations.deletingAccountLabel3
        ]

        return VStack(alignment: .leading, spacing: 2) {
            Text(Localizations.deletingAccountHeaderLabel)
            ForEach(accountDeletionActions, id: \.self) { action in
                Text("• \(action)")
                    .padding(.leading, 6)
            }
        }
        .font(.system(size: 16, weight: .regular))
        .foregroundColor(.deleteAccountHelperText)
    }

    private var continueButton: some View {
        Button {
            withAnimation {
                model.status = .confirm
            }
        } label: {
            Text(Localizations.continueAction)
                .padding(12)
                .frame(minWidth: 170)
                .foregroundColor(.white)
                .background(Capsule())
                .accentColor(.deleteAccountContinueButtonBackground)
        }
    }

    private var confirmButton: some View {
        Button(action: { isShowingConfirmationAlert = true }) {
            Text(Localizations.deleteAccountAction)
                .padding(12)
                .frame(minWidth: 170)
                .foregroundColor(.white)
                .background(Capsule())
                .accentColor(.lavaOrange)
        }
        .disabled(model.phoneNumber.isEmpty)
        .alert(isPresented: $isShowingConfirmationAlert, content: {
            Alert(title: Text(Localizations.deleteAccountAction),
                  message: Text(Localizations.irreversibleLabel),
                  primaryButton: .destructive(Text(Localizations.buttonDelete),
                                              action: model.requestAccountDeletion),
                  secondaryButton: .cancel({ model.phoneNumber = "" }))
        })
    }
}

struct DeleteAccountView_Previews: PreviewProvider {

    static let model: DeleteAccountModel = {
        let model = DeleteAccountModel()
        model.status = .confirm
        return model
    }()

    static var previews: some View {
        NavigationView {
            DeleteAccountView(model: model)
        }
    }
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

    static var phoneNumberPrompt: String {
        NSLocalizedString("settings.account.delete.phone.number.prompt", value: "Enter phone number to confirm", comment: "Text field label for account deletion phone number")
    }

    static var feedbackPlaceholder: String {
        NSLocalizedString("settings.account.delete.phone.number.placeholder", value: "Feedback", comment: "Text field placeholder for collecting feedback before deleing account")
    }

    static var feedbackPrompt: String {
        NSLocalizedString("settings.account.delete.feedback.prompt", value: "Any feedback for HalloApp's team? (Optional)", comment: "Text field label asking for feedback before deleting account")
    }

    static var continueAction: String {
        NSLocalizedString("settings.account.delete.continue.title",
                          value: "Continue",
                          comment: "Button to continue to the next step of deleting account after warning")
    }

    static var waitingForResponseLabel: String {
        NSLocalizedString("settings.account.delete.spinner.replacement", value: "Waiting for server response", comment: "String that's displayed when a spinner is not available to indicate that the view is waiting for a response from the server")
    }
}
