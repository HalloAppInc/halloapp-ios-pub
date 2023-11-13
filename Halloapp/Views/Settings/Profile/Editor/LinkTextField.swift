//
//  LinkTextField.swift
//  HalloApp
//
//  Created by Tanveer on 10/23/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import SwiftUI

struct LinkTextField: UIViewRepresentable {

    @StateObject private var link: EditableLink
    private let font = UIFont.scaledSystemFont(ofSize: 16)

    init(link: EditableLink) {
        self._link = StateObject(wrappedValue: link)
    }

    func makeUIView(context: Context) -> BackspaceDetectingTextField {
        let textField = BackspaceDetectingTextField(frame: .zero)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.font = font
        textField.text = link.text

        context.coordinator.connect(textField)
        return textField
    }

    func updateUIView(_ uiView: BackspaceDetectingTextField, context: Context) {
        let textField = uiView
        let attributed = NSMutableAttributedString(string: textField.text ?? "")
        let entireRange = NSMakeRange(0, attributed.length)
        let attributedRange = link.usernameRange
        let selectedRange = textField.selectedTextRange

        if let attributedRange, entireRange.contains(attributedRange) {
            attributed.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: entireRange)
            attributed.addAttribute(.foregroundColor, value: UIColor.label, range: attributedRange)
        } else {
            attributed.addAttribute(.foregroundColor, value: UIColor.label, range: entireRange)
        }

        textField.attributedText = attributed
        textField.selectedTextRange = selectedRange
        textField.typingAttributes = [.foregroundColor: UIColor.label, .font: font]
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(link: link)
    }

    class Coordinator: NSObject, UITextFieldDelegate {

        let link: EditableLink

        init(link: EditableLink) {
            self.link = link
        }

        func connect(_ textField: BackspaceDetectingTextField) {
            textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
            textField.delegate = self
            textField.onEmptyBackspace = { [link] in
                link.isDeleted = true
            }
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            textField.typingAttributes = [.foregroundColor: UIColor.label]
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if string.rangeOfCharacter(from: .whitespaces) != nil {
                return false
            }

            if let text = textField.text, let range = Range(range, in: text) {
                return text.replacingCharacters(in: range, with: string).count <= 55
            }

            return true
        }

        @objc
        func textFieldDidChange(_ textField: UITextField) {
            link.update(with: textField.text ?? "")
        }
    }
}

// MARK: - BackspaceDetectingTextField

class BackspaceDetectingTextField: UITextField {

    var onEmptyBackspace: (() -> Void)?

    override func deleteBackward() {
        let isEmpty = text?.isEmpty ?? true
        super.deleteBackward()

        if isEmpty {
            onEmptyBackspace?()
        }
    }
}
