//
//  PrivacyPermissionDeniedView.swift
//  HalloApp
//
//  Created by Nandini Shetty on 7/8/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import SwiftUI

struct PrivacyPermissionDeniedView: UIViewControllerRepresentable {

    typealias UIViewControllerType = UIViewController
    

    private let dismissAction: () -> ()

    init(dismissAction: @escaping () -> ()) {
        self.dismissAction = dismissAction
    }

    func makeUIViewController(context: Context) -> UIViewControllerType {
        let vc = PrivacyPermissionDeniedController()
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) { }
}
