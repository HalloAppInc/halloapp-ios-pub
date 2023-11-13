//
//  ProfileLinksPanel.swift
//  HalloApp
//
//  Created by Tanveer on 11/7/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit
import CoreCommon

class ProfileLinksPanel: UIView {

    var onTapAdd: (() -> Void)?
    var onTapShow: ((ProfileLink.`Type`) -> Void)?

    private let promptButton: UIButton = {
        let button = UIButton()
        let attributes = AttributeContainer([.font: UIFont.systemFont(ofSize: 18, weight: .medium)])
        button.configuration = .filledCapsule(backgroundColor: .secondarySystemFill)
        button.configuration?.contentInsets = .init(top: 11, leading: 14, bottom: 11, trailing: 14)
        button.configuration?.baseForegroundColor = .primaryBlue
        button.configuration?.attributedTitle = AttributedString(Localizations.addLinksPrompt, attributes: attributes)
        return button
    }()

    private let linkButtons: [LinkButton] = {
        let linkTypes: [ProfileLink.`Type`] = [.instagram, .tiktok, .twitter, .youtube, .other]
        let buttons = linkTypes.map { LinkButton(type: .link($0)) }
        return buttons + [LinkButton(type: .add)]
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        let stack = UIStackView(arrangedSubviews: [promptButton] + linkButtons)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.alignment = .center
        stack.distribution = .fillEqually
        stack.spacing = 6
        addSubview(stack)

        let buttonConstraints = linkButtons.flatMap {
            [$0.widthAnchor.constraint(equalTo: $0.heightAnchor, multiplier: 1)]
        }

        NSLayoutConstraint.activate(buttonConstraints)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        promptButton.addAction(.init { [weak self] _ in
            self?.onTapAdd?()
        }, for: .touchUpInside)

        for button in linkButtons {
            button.addAction(.init { [weak self, type = button.type] _ in
                switch type {
                case .link(let link):
                    self?.onTapShow?(link)
                case .add:
                    self?.onTapAdd?()
                }
            }, for: .touchUpInside)
        }
    }

    required init(coder: NSCoder) {
        fatalError("ProfileLinksPanel coder init not implemented...")
    }

    func configure(with links: [ProfileLink]) {
        let types = links.reduce(into: Set()) { $0.insert($1.type) }

        for button in linkButtons {
            let shouldHide: Bool
            switch button.type {
            case .link(let link):
                shouldHide = !types.contains(link)
            case .add:
                shouldHide = links.count >= 4 || links.isEmpty
            }

            if shouldHide != button.isHidden {
                button.isHidden = shouldHide
            }
        }

        promptButton.isHidden = !links.isEmpty
    }
}

// MARK: - LinkButton

fileprivate class LinkButton: UIButton {

    enum ButtonType {
        case link(ProfileLink.`Type`)
        case add
    }

    let type: ButtonType

    init(type: ButtonType) {
        self.type = type
        super.init(frame: .zero)

        let image: UIImage?
        switch type {
        case .link(let link):
            image = Self.image(for: link)
        case .add:
            image = UIImage(systemName: "plus")
        }

        configuration = .filledCapsule(backgroundColor: .secondarySystemFill)
        configuration?.baseForegroundColor = .primaryBlue
        configuration?.buttonSize = .large
        configuration?.contentInsets = .init(top: 11, leading: 11, bottom: 11, trailing: 11)
        configuration?.image = image
        configuration?.preferredSymbolConfigurationForImage = .init(scale: .small)
    }

    required init(coder: NSCoder) {
        fatalError("LinkButton coder init not implemented...")
    }

    private class func image(for type: ProfileLink.`Type`) -> UIImage? {
        let image: UIImage?
        switch type {
        case .instagram:
            image = UIImage(named: "InstagramOutline")
        case .tiktok:
            image = UIImage(named: "TikTokOutline")
        case .twitter:
            image = UIImage(named: "TwitterOutline")
        case .youtube:
            image = UIImage(named: "YouTubeOutline")
        case .other:
            image = UIImage(systemName: "link")
        }

        return image
    }
}

// MARK: - Localization

extension Localizations {

    static var addLinksPrompt: String {
        NSLocalizedString("add.links.prompt",
                          value: "@ Add My Social Media",
                          comment: "Displayed when the user has not added any links to their profile.")
    }
}
