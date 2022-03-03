//
//  UISearchBar.swift
//  HalloApp
//
//  Created by Tony Jiang on 8/27/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import UIKit

extension UISearchBar {

    /*
     Make the Cancel button text localizable and auto switch when a RTL preferred language is set on the device
     Needs setShowsCancelButton to be called first so that the cancel button exists
     NB: The other two methods to solve this have drawbacks
     1. UIBarButtonItem.appearance - system-wide, weird animation of button sliding in on fresh app start (maybe revisit in the future)
     2. searchBar.setValue - uses internal iOS key, crashes the app if key changes, can't check if key exists first
     */
    func setCancelButtonTitleIfNeeded() {
        guard effectiveUserInterfaceLayoutDirection == .rightToLeft else { return }
        guard let firstView = self.subviews.first else { return }
        guard let containerView = firstView.subviews.last else { return } // should be _UISearchBarSearchContainerView
        guard let cancelButton = containerView.subviews.last as? UIButton else { return }
        cancelButton.setTitle(Localizations.buttonCancel, for: .normal)
    }

}
