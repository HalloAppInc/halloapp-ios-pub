//
//  FeedPermissionTutorialAlert.swift
//  HalloApp
//
//  Created by Matt Geimer on 5/27/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import Core
import CoreCommon

final class FeedPermissionTutorialAlert: UIView {
    struct Action {
        var title: String
        var handler: (FeedPermissionTutorialAlert) -> Void
    }
    
    let goToSettingsAction: Action
    
    let titleLabel = UILabel()
    let labelOne = UILabel()
    let labelTwo = UILabel()
    let goToSettingsButton = UIButton()
    let horizontalLine = UIView()
    
    init(goToSettingsAction: Action) {
        self.goToSettingsAction = goToSettingsAction
        
        super.init(frame: .zero)
        
        translatesAutoresizingMaskIntoConstraints = false
        layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = Localizations.contactsTutorialTitle
        titleLabel.numberOfLines = 0
        titleLabel.font = .systemFont(forTextStyle: .title3, weight: .medium)
        titleLabel.textColor = UIColor.label

        labelOne.translatesAutoresizingMaskIntoConstraints = false
        labelOne.text = "1.\t" + Localizations.tutorialTapBelow.replacingOccurrences(of: "%@", with: Localizations.buttonGoToSettings)
        labelOne.numberOfLines = 0
        labelOne.font = .systemFont(forTextStyle: .callout)
        labelOne.textColor = UIColor.label.withAlphaComponent(0.5)
        
        labelTwo.translatesAutoresizingMaskIntoConstraints = false
        labelTwo.numberOfLines = 0
        labelTwo.font = .systemFont(forTextStyle: .callout)
        labelTwo.textColor = UIColor.label.withAlphaComponent(0.5)
        
        let fullSecondLabelString = NSMutableAttributedString(string: "2.\t")
        if let image = UIImage(named: "ToggleContacts") {
            let imageAttachment = NSTextAttachment()
            imageAttachment.image = image
            let font = UIFont.systemFont(ofSize: labelTwo.font.pointSize - 1)
            let scale = font.capHeight / image.size.height * 1.2
            imageAttachment.bounds.size = CGSize(width: ceil(image.size.width * scale), height: ceil(image.size.height * scale))
            
            let imageString = NSAttributedString(attachment: imageAttachment)
            fullSecondLabelString.append(imageString)
        }
        
        let localizedString = NSAttributedString(string: " " + Localizations.tutorialTurnOnContacts)
        fullSecondLabelString.append(localizedString)
        
        labelTwo.attributedText = fullSecondLabelString
        
        horizontalLine.translatesAutoresizingMaskIntoConstraints = false
        horizontalLine.backgroundColor = .black
        horizontalLine.alpha = 0.2
        
        goToSettingsButton.translatesAutoresizingMaskIntoConstraints = false
        goToSettingsButton.setContentCompressionResistancePriority(.required, for: .vertical)
        goToSettingsButton.setTitle(Localizations.buttonGoToSettings, for: .normal)
        goToSettingsButton.setTitleColor(UIColor.NUX, for: .normal)
        goToSettingsButton.titleLabel?.font = .systemFont(forTextStyle: .callout, weight: .regular)
        goToSettingsButton.addTarget(self, action: #selector(didTapOpenSettings), for: .touchUpInside)
        self.translatesAutoresizingMaskIntoConstraints = false

        self.addSubview(titleLabel)
        self.addSubview(labelOne)
        self.addSubview(labelTwo)
        self.addSubview(goToSettingsButton)
        self.addSubview(horizontalLine)

        titleLabel.constrainMargins([.top, .leading, .trailing], to: self)

        labelOne.setContentCompressionResistancePriority(.required, for: .vertical)
        labelOne.constrainMargins([.leading, .trailing], to: self)
        labelOne.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 15).isActive = true

        labelTwo.setContentCompressionResistancePriority(.required, for: .vertical)
        labelTwo.constrainMargins([.leading, .trailing], to: self)
        labelTwo.topAnchor.constraint(equalTo: labelOne.bottomAnchor, constant: 15).isActive = true
        
        horizontalLine.setContentCompressionResistancePriority(.required, for: .vertical)
        horizontalLine.heightAnchor.constraint(equalToConstant: 1).isActive = true
        horizontalLine.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
        horizontalLine.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
        horizontalLine.topAnchor.constraint(equalTo: labelTwo.bottomAnchor, constant: 30).isActive = true
        
        goToSettingsButton.constrainMargins([.leading, .trailing, .bottom], to: self)
        goToSettingsButton.topAnchor.constraint(equalTo: horizontalLine.bottomAnchor, constant: 30).isActive = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc
    private func didTapOpenSettings() {
        self.goToSettingsAction.handler(self)
    }
}
