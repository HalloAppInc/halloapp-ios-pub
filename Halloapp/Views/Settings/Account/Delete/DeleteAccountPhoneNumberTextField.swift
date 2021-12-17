//
//  DeleteAccountPhoneNumberTextField.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 12/15/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import PhoneNumberKit
import SwiftUI

struct DeleteAccountPhoneNumberTextField: UIViewRepresentable {

    @Binding var phoneNumber: String

    func makeUIView(context: Context) -> PhoneNumberTextField {
        let phoneNumberTextField = PhoneNumberTextField(withPhoneNumberKit: AppContext.shared.phoneNumberFormatter)
        phoneNumberTextField.withFlag = true
        phoneNumberTextField.withExamplePlaceholder = true
        phoneNumberTextField.withPrefix = true
        phoneNumberTextField.withDefaultPickerUI = true
        phoneNumberTextField.delegate = context.coordinator
        phoneNumberTextField.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        phoneNumberTextField.numberPlaceholderColor = .placeholder
        phoneNumberTextField.textContentType = .telephoneNumber
        phoneNumberTextField.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        return phoneNumberTextField
    }

    func updateUIView(_ uiView: PhoneNumberTextField, context: Context) {
        uiView.text = phoneNumber
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        private let phoneNumberTextField: DeleteAccountPhoneNumberTextField

        init(_ phoneNumberTextField: DeleteAccountPhoneNumberTextField) {
            self.phoneNumberTextField = phoneNumberTextField
        }

        @objc func editingChanged(_ textField: UITextField) {
            phoneNumberTextField.phoneNumber = (textField.text ?? "").strippingNonDigits()
        }
    }
}

struct DeleteAccountPhoneNumberTextField_Previews: PreviewProvider {

    static var previews: some View {
        DeleteAccountPhoneNumberTextField(phoneNumber: .constant("15555555555"))
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 300, height: 60)

    }
}
