//
//  UIViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/1/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import UIKit

protocol UIViewControllerScrollsToTop {

    func scrollToTop(animated: Bool)
}

extension UIViewController {

    func installLargeTitleUsingGothamFont() {
        guard let title = title else { return }
        let fontDescriptor = UIFontDescriptor
            .preferredFontDescriptor(withTextStyle: .largeTitle)
            .addingAttributes([ .traits: [ UIFontDescriptor.TraitKey.weight: UIFont.Weight.bold ] ])
        var fontSize = fontDescriptor.pointSize - 8 // 26 for default text size
        if fontSize > 34 { fontSize = 34 }
        let attributes: [ NSAttributedString.Key : Any ] =
            [ .font: UIFont(descriptor: fontDescriptor, size: fontSize),
              .foregroundColor: UIColor.label.withAlphaComponent(0.75),
              .kern: -0.01 ]
        let titleLabel = UILabel()
        titleLabel.attributedText = NSAttributedString(string: title, attributes: attributes)
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: titleLabel)
        navigationItem.title = nil
    }
    
    func proceedIfConnected() -> Bool {
        guard MainAppContext.shared.service.isConnected else {
            let alert = UIAlertController(title: Localizations.alertNoInternetTitle, message: Localizations.alertNoInternetTryAgain, preferredStyle: .alert)
            alert.addAction(.init(title: Localizations.buttonOK, style: .default, handler: nil))
            present(alert, animated: true, completion: nil)
            return false
        }
        return true
    }
    
    func getFailedCallAlert() -> UIAlertController {
        let alert = UIAlertController(title: Localizations.failedCallTitle,
                                    message: Localizations.failedCallNoticeText,
                             preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default) { action in
            self.dismiss(animated: true, completion: nil)
        })
        
        return alert
    }
}
