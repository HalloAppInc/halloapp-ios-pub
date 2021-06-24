//
//  FeedPermissionTutorialAlert.swift
//  HalloApp
//
//  Created by Matt Geimer on 5/26/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import Core

final class FeedPermissionExplanationAlert: UIView {
    struct Action {
        var title: String
        var handler: (FeedPermissionExplanationAlert) -> Void
    }
    
    let learnMoreAction: Action?
    let notNowAction: Action
    let continueAction: Action
    
    let titleLabel = UILabel()
    let label = UILabel()
    let learnMoreButton = UIButton() // This button is reserved for when the "Learn More" button from the design has an intended use, until then it's not visible.
    let continueButton = UIButton()
    let notNowButton = UIButton()
    let horizontalLine = UIView()
    
    init(learnMoreAction: Action?, notNowAction: Action, continueAction: Action) {
        self.learnMoreAction = learnMoreAction
        self.notNowAction = notNowAction
        self.continueAction = continueAction
        
        super.init(frame: .zero)
        
        translatesAutoresizingMaskIntoConstraints = false
        layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = Localizations.contactsPermissionExplanationTitle
        titleLabel.numberOfLines = 0
        titleLabel.font = .systemFont(forTextStyle: .title3, weight: .medium)
        titleLabel.textColor = UIColor.label

        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = Localizations.contactsPermissionExplanation
        label.numberOfLines = 0
        label.font = .systemFont(forTextStyle: .callout)
        label.textColor = UIColor.label.withAlphaComponent(0.5)
        
        learnMoreButton.translatesAutoresizingMaskIntoConstraints = false
        learnMoreButton.setContentCompressionResistancePriority(.required, for: .vertical)
        learnMoreButton.setTitle(Localizations.linkLearnMore, for: .normal)
        learnMoreButton.setTitleColor(UIColor.nux, for: .normal)
        learnMoreButton.titleLabel?.font = .systemFont(forTextStyle: .callout, weight: .regular)

        learnMoreButton.addTarget(self, action: #selector(didTapLearnMore), for: .touchUpInside)
        
        learnMoreButton.isHidden = learnMoreAction == nil
        
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        continueButton.setContentCompressionResistancePriority(.required, for: .vertical)
        continueButton.setTitle(Localizations.buttonContinue, for: .normal)
        continueButton.setTitleColor(UIColor.nux, for: .normal)
        continueButton.titleLabel?.font = .systemFont(forTextStyle: .callout, weight: .regular)
        continueButton.addTarget(self, action: #selector(didTapContinue), for: .touchUpInside)
        
        notNowButton.translatesAutoresizingMaskIntoConstraints = false
        notNowButton.setContentCompressionResistancePriority(.required, for: .vertical)
        notNowButton.setTitle(Localizations.buttonNotNow, for: .normal)
        notNowButton.setTitleColor(UIColor(red: 1, green: 0.271, blue: 0, alpha: 1), for: .normal)
        notNowButton.titleLabel?.font = .systemFont(forTextStyle: .callout, weight: .regular)
        notNowButton.addTarget(self, action: #selector(didTapNotNow), for: .touchUpInside)
        
        horizontalLine.translatesAutoresizingMaskIntoConstraints = false
        horizontalLine.backgroundColor = .black
        horizontalLine.alpha = 0.2

        self.translatesAutoresizingMaskIntoConstraints = false

        self.addSubview(titleLabel)
        self.addSubview(label)
        self.addSubview(continueButton)
        self.addSubview(notNowButton)
        self.addSubview(learnMoreButton)
        self.addSubview(horizontalLine)

        titleLabel.constrainMargins([.top, .leading, .trailing], to: self)

        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.constrainMargins([.leading, .trailing], to: self)
        label.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 15).isActive = true
        
        learnMoreButton.constrainMargins([.leading], to: self)
        learnMoreButton.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 0).isActive = true
        learnMoreButton.leadingAnchor.constraint(greaterThanOrEqualTo: self.leadingAnchor).isActive = true
        
        horizontalLine.setContentCompressionResistancePriority(.required, for: .vertical)
        horizontalLine.heightAnchor.constraint(equalToConstant: 1).isActive = true
        horizontalLine.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
        horizontalLine.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
        horizontalLine.topAnchor.constraint(equalTo: learnMoreButton.isHidden ? label.bottomAnchor : learnMoreButton.bottomAnchor, constant: 15).isActive = true

        continueButton.constrainMargins([.leading, .trailing], to: self)
        continueButton.topAnchor.constraint(equalTo: horizontalLine.bottomAnchor, constant: 15).isActive = true
        
        notNowButton.constrainMargins([.bottom, .leading, .trailing], to: self)
        notNowButton.topAnchor.constraint(equalTo: continueButton.bottomAnchor, constant: 20).isActive = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc
    private func didTapLearnMore() {
        learnMoreAction?.handler(self)
    }
    
    @objc
    private func didTapNotNow() {
        notNowAction.handler(self)
    }
    
    @objc
    private func didTapContinue() {
        continueAction.handler(self)
    }
}
