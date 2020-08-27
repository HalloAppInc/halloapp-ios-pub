//
//  PrivacyListView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import SwiftUI

struct PrivacyListView: UIViewControllerRepresentable {

    typealias UIViewControllerType = UIViewController

    @EnvironmentObject var privacySettings: PrivacySettings

    private let privacyList: PrivacyList
    private let dismissAction: () -> ()

    init(_ privacyList: PrivacyList, dismissAction: @escaping () -> ()) {
        self.privacyList = privacyList
        self.dismissAction = dismissAction
    }

    func makeUIViewController(context: Context) -> UIViewControllerType {
        let viewController = PrivacyListViewController(privacyList: privacyList, settings: privacySettings)
        viewController.dismissAction = dismissAction
        return UINavigationController(rootViewController: viewController)
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) { }

}
