//
//  AboutViewController.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 12/4/20.
//  Copyright © 2020 HalloApp, Inc. All rights reserved.
//

import Combine
import Core
import CoreCommon
import UIKit

private extension Localizations {

    static var title: String {
        NSLocalizedString("about.title", value: "About", comment: "About screen: navigation bar title.")
    }

    static var ohHallo: String {
        NSLocalizedString("about.hallo", value: "Oh Hallo", comment: "About screen: greeting.")
    }

    static var bodyPart1: String {
        NSLocalizedString("about.body.1",
                          value: "HalloApp is here! And we’re building it for you and your loved ones. We’ve brought social apps back to basics, while adding a layer of security and privacy that we think everyone in the world should have access to. HalloApp will never use your personal information or show you ads. Instead, we plan to eventually offer additional features at a small cost.",
                          comment: "About screen: body text.")
    }

    static var bodyPart2: String {
        NSLocalizedString("about.body.2",
                          value: "Thank you for using and sharing HalloApp with your friends and family. We’re improving it every week.",
                          comment: "About screen: body text.")
    }

    static func footer(textStyle: UIFont.TextStyle, textColor: UIColor) -> NSAttributedString {
        let formatString = NSLocalizedString("about.footer",
                                             value: "If you have any questions or feedback email us at %@",
                                             comment: "About screen: footer text. Parameter is support email address.")
        let emailAddress = "support@halloapp.com"
        let footerText = String(format: formatString, emailAddress) as NSString
        let attributedString = NSMutableAttributedString(string: String(footerText))
        let baseFont = UIFont.systemFont(forTextStyle: textStyle, weight: .regular)
        attributedString.addAttribute(.font, value: baseFont, range: attributedString.utf16Extent)
        let range = footerText.range(of: emailAddress)
        if range.location != NSNotFound {
            let mediumFont = UIFont.systemFont(forTextStyle: textStyle, weight: .medium)
            attributedString.addAttribute(.font, value: mediumFont, range: range)
        }
        attributedString.addAttribute(.foregroundColor, value: textColor, range: attributedString.utf16Extent)
        return attributedString
    }
}

class AboutViewController: UIViewController {

    @IBOutlet weak var vStack: UIStackView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var bodyLabel1: UILabel!
    @IBOutlet weak var bodyLabel2: UILabel!
    @IBOutlet weak var footerLabel: TextLabel!

    private var contentSizeChangedCancellable: AnyCancellable?

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = Localizations.title

        vStack.setCustomSpacing(16, after: titleLabel)
        vStack.setCustomSpacing(32, after: bodyLabel2)

        titleLabel.font = .gothamFont(forTextStyle: .largeTitle, weight: .bold)

        titleLabel.text = Localizations.ohHallo
        bodyLabel1.text = Localizations.bodyPart1
        bodyLabel2.text = Localizations.bodyPart2
        footerLabel.attributedText = Localizations.footer(textStyle: .callout, textColor: .secondaryLabel)
        contentSizeChangedCancellable = NotificationCenter.default.publisher(for: UIContentSizeCategory.didChangeNotification).sink { (_) in
            self.footerLabel.attributedText = Localizations.footer(textStyle: .callout, textColor: .secondaryLabel)
        }

        footerLabel.linkColor = nil
        footerLabel.delegate = self
    }

}

extension AboutViewController: TextLabelDelegate {

    func textLabel(_ label: TextLabel, didRequestHandle link: AttributedTextLink) {
        if let url = link.result?.url {
            UIApplication.shared.open(url)
        }
    }

    func textLabelDidRequestToExpand(_ label: TextLabel) { }
}
