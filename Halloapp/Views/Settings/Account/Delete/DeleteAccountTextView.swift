//
//  DeleteAccountTextView.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 12/15/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import SwiftUI

class PlaceholderTextView: UITextView {

    var placeholder: String? {
        get {
            return placeholderLabel.text
        }
        set {
            placeholderLabel.text = newValue
            updatePlaceholderVisibility()
        }
    }

    private let placeholderLabel: UILabel = {
        let placeholderLabel = UILabel()
        placeholderLabel.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        placeholderLabel.textColor = .placeholder
        return placeholderLabel
    }()

    init() {
        super.init(frame: .zero, textContainer: nil)
        addSubview(placeholderLabel)
        updatePlaceholderVisibility()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updatePlaceholderVisibility),
                                               name: UITextView.textDidChangeNotification,
                                               object: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = placeholder?.isEmpty ?? true || !text.isEmpty
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let insets = textContainerInset
        let placeholderSize = placeholderLabel.sizeThatFits(bounds.inset(by: insets).size)
        placeholderLabel.frame = CGRect(origin: CGPoint(x: insets.left, y: insets.top),
                                        size: placeholderSize)
    }
}

struct DeleteAccountTextView: UIViewRepresentable {

    @Binding var text: String
    var placeholder: String?

    func makeUIView(context: Context) -> PlaceholderTextView {
        let textView = PlaceholderTextView()
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        textView.placeholder = placeholder
        return textView
    }

    func updateUIView(_ uiView: PlaceholderTextView, context: Context) {
        uiView.text = text
        uiView.placeholder = placeholder
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {

        let deleteAccountTextView: DeleteAccountTextView

        init(_ deleteAccountTextView: DeleteAccountTextView) {
            self.deleteAccountTextView = deleteAccountTextView
        }

        func textViewDidChange(_ textView: UITextView) {
            deleteAccountTextView.text = textView.text
        }
    }
}

struct DeleteAccountTextView_Previews: PreviewProvider {

    static var previews: some View {
        DeleteAccountTextView(text: .constant(""),
                              placeholder: "Placeholder")
            .frame(width: 300, height: 300)

    }
}
