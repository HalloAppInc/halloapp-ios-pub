//
//  PrivacyListView.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 6/26/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import CoreCommon
import SwiftUI

struct PrivacyListView: UIViewControllerRepresentable {

    typealias UIViewControllerType = UIViewController

    @EnvironmentObject var privacySettings: PrivacySettings

    private let privacyList: PrivacyList?
    private let dismissAction: () -> ()

    init(_ privacyList: PrivacyList?, dismissAction: @escaping () -> ()) {
        self.privacyList = privacyList
        self.dismissAction = dismissAction
    }

    func makeUIViewController(context: Context) -> UIViewControllerType {
        guard ContactStore.contactsAccessAuthorized  else {
            let vc = PrivacyPermissionDeniedController()
            return UINavigationController(rootViewController: vc)
        }
        if let privacyList = privacyList {
            let vc = ContactSelectionViewController.forPrivacyList(privacyList, in: privacySettings, setActiveType: false, dismissAction: dismissAction)
            return UINavigationController(rootViewController: vc)
        }
        let vc = ContactSelectionViewController.forAllContacts(.all, in: MainAppContext.shared.privacySettings, dismissAction: dismissAction)
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) { }

}
