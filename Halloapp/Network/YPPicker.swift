//
//  YPPicker.swift
//  Halloapp
//
//  Created by Tony Jiang on 11/14/19.
//  Copyright © 2019 Halloapp, Inc. All rights reserved.
//

import Foundation
import Combine
import SwiftUI
import YPImagePicker

struct PickerWrapper: UIViewControllerRepresentable {
 
    typealias UIViewControllerType = ExampleViewController


    func makeCoordinator() -> PickerWrapper.Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<PickerWrapper>) -> PickerWrapper.UIViewControllerType {
 
        return ExampleViewController()
        
    }

    func updateUIViewController(_ uiViewController: PickerWrapper.UIViewControllerType, context: UIViewControllerRepresentableContext<PickerWrapper>) {
        //
    }
    
    class Coordinator: NSObject, YPImagePickerDelegate {
        
        var parent: PickerWrapper
        
        init(_ pickerWrapper: PickerWrapper) {
            self.parent = pickerWrapper
        }
        
        func noPhotos() {
            
        }
        
    
    }
    
}
