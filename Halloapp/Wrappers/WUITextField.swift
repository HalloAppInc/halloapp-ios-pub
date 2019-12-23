//
//  WUITextField.swift
//  Halloapp
//
//  Created by Tony Jiang on 12/19/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import SwiftUI


struct WUITextField: UIViewRepresentable {
    
    @Binding var text: String
    
    var textAlignment: NSTextAlignment = .left
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType = .init(rawValue: "")

    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        
        textField.textAlignment = self.textAlignment
        textField.keyboardType = self.keyboardType
        textField.textContentType = .oneTimeCode
        
        
        textField.delegate = context.coordinator
        
//        _ = NotificationCenter.default.publisher(for: UITextField.textDidChangeNotification, object: textField)
//            .compactMap {
//                guard let field = $0.object as? UITextField else {
//                    return nil
//                }
//                return field.text
//            }
//            .sink {
//                self.text = $0
//            }
        
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: WUITextField
        
        init(_ textField: WUITextField) {
            self.parent = textField
        }
        
//        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
//            if let value = textField.text {
//                parent.text = value
//                parent.onChange?(value)
//            }
//
//            return true
//        }
    }
}

