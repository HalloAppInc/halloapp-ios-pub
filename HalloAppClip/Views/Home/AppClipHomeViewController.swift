//
//  HomeViewController.swift
//  HalloAppClip
//
//  Created by Nandini Shetty on 6/10/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//
import CocoaLumberjack
import Combine
import Core
import StoreKit
import UIKit

fileprivate struct Constants {
    static let MaxFontPointSize: CGFloat = 30
}

class AppClipHomeViewController: UIViewController {

    let logo = UIImageView()
    let buttonInstall = UIButton()
    var inputVerticalCenterConstraint: NSLayoutConstraint?

    let scrollView = UIScrollView()
    var scrollViewBottomMargin: NSLayoutConstraint?

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        buttonInstall.layer.cornerRadius = (0.5 * buttonInstall.frame.height).rounded()
        let effectiveContentHeight = scrollView.contentSize.height + scrollView.adjustedContentInset.bottom + scrollView.adjustedContentInset.top
        scrollView.isScrollEnabled = effectiveContentHeight > self.scrollView.frame.height

        inputVerticalCenterConstraint?.constant = -scrollView.adjustedContentInset.top
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.preservesSuperviewLayoutMargins = true

        navigationItem.backButtonTitle = ""

        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.image = UIImage(named: "RegistrationLogo")?.withRenderingMode(.alwaysTemplate)
        logo.tintColor = .lavaOrange
        logo.setContentCompressionResistancePriority(.required, for: .vertical)

        let installAppTitle = UILabel()
        installAppTitle.translatesAutoresizingMaskIntoConstraints = false
        installAppTitle.font = .systemFont(forTextStyle: .title1, weight: .medium, maximumPointSize: Constants.MaxFontPointSize)
        installAppTitle.numberOfLines = 0
        installAppTitle.setContentCompressionResistancePriority(.required, for: .vertical)
        installAppTitle.textAlignment = .center
        installAppTitle.text = Localizations.installAppToContinue

        let freeDownloadLabel = UILabel()
        freeDownloadLabel.text = Localizations.freeAppDownloadText
        freeDownloadLabel.font = .systemFont(forTextStyle: .footnote, maximumPointSize: Constants.MaxFontPointSize - 14)
        freeDownloadLabel.textColor = .secondaryLabel
        freeDownloadLabel.numberOfLines = 0
        freeDownloadLabel.textAlignment = .center
        freeDownloadLabel.translatesAutoresizingMaskIntoConstraints = false

        buttonInstall.layer.masksToBounds = true
        buttonInstall.setTitle(Localizations.buttonInstall, for: .normal)
        buttonInstall.setBackgroundColor(.lavaOrange, for: .normal)
        buttonInstall.setBackgroundColor(UIColor.lavaOrange.withAlphaComponent(0.5), for: .highlighted)
        buttonInstall.setBackgroundColor(.systemGray4, for: .disabled)
        buttonInstall.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true

        buttonInstall.addTarget(self, action: #selector(didTapInstall), for: .touchUpInside)


        let stackView = UIStackView(arrangedSubviews: [installAppTitle, buttonInstall, freeDownloadLabel])
        stackView.alignment = .fill
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false

        view.backgroundColor = .feedBackground

        // View hierarchy
        scrollView.addSubview(logo)
        scrollView.addSubview(stackView)

        view.addSubview(scrollView)

        // Constraints
        scrollView.constrain([.leading, .trailing, .top], to: view)
        scrollViewBottomMargin = scrollView.constrain(anchor: .bottom, to: view)

        logo.constrain(anchor: .centerX, to: scrollView.contentLayoutGuide, constant: 100)
        logo.constrainMargin(anchor: .leading, to: scrollView)

        stackView.constrainMargins([.leading, .trailing], to: view)
        stackView.topAnchor.constraint(greaterThanOrEqualTo: logo.bottomAnchor, constant: 32).isActive = true
        inputVerticalCenterConstraint = stackView.constrain(anchor: .centerY, to: scrollView, priority: .defaultHigh)
    }
    
    @objc
    private func didTapInstall(sender: AnyObject) {
        self.buttonInstall.isEnabled = false
        let storeViewController = SKStoreProductViewController()
        storeViewController.delegate = self

        storeViewController.loadProduct(withParameters: [SKStoreProductParameterITunesItemIdentifier:NSNumber(value: AppContext.appStoreProductID)]) { (result, error) in
          self.buttonInstall.isEnabled = true
          if(error != nil)
          {
            DDLogError("AppClipHomeViewController/error opening App Store view")
            return
          }
          else
          {
            self.present(storeViewController, animated: true, completion:
            {
                DDLogInfo("AppClipHomeViewController/opening App Store view")
            })
          }
        }
    }
}

extension AppClipHomeViewController:SKStoreProductViewControllerDelegate
{
    func productViewControllerDidFinish(_ viewController: SKStoreProductViewController) {
        viewController.dismiss(animated: true, completion: nil)
    }
}

