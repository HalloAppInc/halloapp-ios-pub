//
//  AlbumSuggestionCallToActionCollectionViewCell.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 9/6/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CoreCommon
import CoreLocation
import UIKit

class AlbumSuggestionCallToActionCollectionViewCell: UICollectionViewCell {

    static let reuseIdentifier = "AlbumSuggestionCallToActionCollectionViewCell"

    enum CallToActionType {
        case firstTimeUse
        case enablePhotoLocations
        case enableAlwaysOnLocation
    }

    private let closeButton: UIButton = {
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)), for: .normal)
        closeButton.tintColor = .primaryBlackWhite.withAlphaComponent(0.3)
        return closeButton
    }()

    private let imageView: UIImageView = {
        return UIImageView(image: UIImage(named: "MagicPostsEmptyStateIcon"))
    }()

    private let titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.font = .scaledSystemFont(ofSize: 16, weight: .semibold)
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        titleLabel.textColor = .primaryBlackWhite
        return titleLabel
    }()

    private let subtitleLabel: UILabel = {
        let subtitleLabel = UILabel()
        subtitleLabel.font = .scaledSystemFont(ofSize: 14, weight: .regular)
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textAlignment = .center
        subtitleLabel.textColor = .primaryBlackWhite.withAlphaComponent(0.5)
        return subtitleLabel
    }()

    private let ctaButton: UIButton = {
        let ctaButton = UIButton(type: .system)
        ctaButton.setTitleColor(.systemBlue, for: .normal)
        ctaButton.titleLabel?.font = .scaledSystemFont(ofSize: 17, weight: .medium)
        return ctaButton
    }()

    private var currentCallToActionType: CallToActionType = .enableAlwaysOnLocation
    private var dismissAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        closeButton.addTarget(self, action: #selector(didTapDismiss), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(closeButton)

        ctaButton.addTarget(self, action: #selector(didTapCTA), for: .touchUpInside)

        let contentStackView = UIStackView(arrangedSubviews: [imageView, titleLabel, subtitleLabel, ctaButton])
        contentStackView.alignment = .center
        contentStackView.axis = .vertical
        contentStackView.setCustomSpacing(20, after: imageView)
        contentStackView.setCustomSpacing(6, after: titleLabel)
        contentStackView.setCustomSpacing(20, after: subtitleLabel)
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStackView)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),

            contentStackView.topAnchor.constraint(equalTo: closeButton.bottomAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 15),
            contentStackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -15),
        ])
    }

    private static let subtitleFormatRegex: NSRegularExpression? = {
        return try? NSRegularExpression(pattern: "(\\*)(?<text>.+?)(\\*)")
    }()

    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(type: CallToActionType, dismissAction: @escaping () -> Void) {
        currentCallToActionType = type
        self.dismissAction = dismissAction

        let title: String
        let subtitle: NSAttributedString
        let ctaText: String?
        let canDismiss: Bool

        switch type {
        case .firstTimeUse:
            title = Localizations.magicPostsExplainerTitle
            subtitle = NSAttributedString(string: Localizations.magicPostsExplainerSubtitle)
            ctaText = nil
            canDismiss = true
        case .enablePhotoLocations:
            title = Localizations.enablePhotoLocationCtaTitle

            let instructionsSubtitle = NSMutableAttributedString(string: Localizations.enablePhotoLocationCtaSubtitle2)
            var rangeAdjustment = 0
            Self.subtitleFormatRegex?.enumerateMatches(in: instructionsSubtitle.string,
                                                       range: NSMakeRange(0, instructionsSubtitle.length),
                                                       using: { result, matchingFlags, _ in
                guard let result else {
                    return
                }
                let updatedResult = result.adjustingRanges(offset: rangeAdjustment)
                let selectionRange = updatedResult.range(at: 0)
                let textRange = updatedResult.range(withName: "text")
                guard selectionRange.location != NSNotFound, textRange.location != NSNotFound else {
                    return
                }
                let text = (instructionsSubtitle.string as NSString).substring(with: textRange)
                instructionsSubtitle.replaceCharacters(in: selectionRange,
                                                       with: NSAttributedString(string: text, attributes: [.foregroundColor: UIColor.primaryBlackWhite]))
                rangeAdjustment += (textRange.length - selectionRange.length)
            })

            let mutableSubtitle = NSMutableAttributedString()
            mutableSubtitle.append(NSAttributedString(string: Localizations.enablePhotoLocationCtaSubtitle1))
            mutableSubtitle.append(NSAttributedString(string: "\n\n"))
            mutableSubtitle.append(instructionsSubtitle)
            subtitle = mutableSubtitle
            ctaText = Localizations.enablePhotoLocationCtaAction
            canDismiss = false
        case .enableAlwaysOnLocation:
            title = Localizations.enableAlwaysOnLocationCtaTitle
            subtitle = NSAttributedString(string: Localizations.enableAlwaysOnLocationCtaSubtitle)
            ctaText = Localizations.enableAlwaysOnLocationCtaAction
            canDismiss = false
        }

        titleLabel.text = title
        subtitleLabel.attributedText = subtitle
        ctaButton.setTitle(ctaText, for: .normal)
        ctaButton.isHidden = ctaText == nil
        closeButton.isHidden = !canDismiss
    }

    @objc private func didTapDismiss() {
        dismissAction?()
    }

    @objc private func didTapCTA() {
        switch currentCallToActionType {
        case .firstTimeUse:
            // button should be hidden, how did this happen?
            break
        case .enablePhotoLocations:
            // TODO: see if we can direct link to settings
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        case .enableAlwaysOnLocation:
            switch CLLocationManager().authorizationStatus {
            case .authorizedAlways:
                break
            case .notDetermined:
                CLLocationManager().requestAlwaysAuthorization()
            default:
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
        }
    }
}

extension Localizations {

    // MARK: Magic Posts FTUX

    static var magicPostsExplainerTitle: String {
        NSLocalizedString("photosuggestions.explainer.title",
                          value: "Try Magic Posts",
                          comment: "title for explanation of photo suggestions")
    }

    static var magicPostsExplainerSubtitle: String {
        NSLocalizedString("photosuggestions.explainer.subtitle",
                          value: "When you take new photos, we find the best shots and organize them into a post draft, so it’s ready for you if you feel like posting.",
                          comment: "explanation for photo suggestions")
    }

    // MARK: Enable Photos app location

    static var enablePhotoLocationCtaTitle: String {
        NSLocalizedString("photosuggestions.cta.photolocation.title",
                          value: "Allow Location Access For The Photos App",
                          comment: "title for explanation of why we want location access for photos app")
    }

    static var enablePhotoLocationCtaSubtitle1: String {
        NSLocalizedString("photosuggestions.cta.photolocation.subtitle1",
                          value: "Allow Location access for the Photos app to improve Magic Posts. HalloApp uses location metadata from your photos to help sort and name them.",
                          comment: "explanation for why we need to turn on location access for photos")
    }

    static var enablePhotoLocationCtaSubtitle2: String {
        NSLocalizedString("photosuggestions.cta.photolocation.subtitle2",
                          value: "To allow Location access, go to: *Settings* > *Privacy & Security* > *Location Services* > *Photos*",
                          comment: "instructions for enabling location access for photos app. maintain '*' to indicate bold text.")
    }

    static var enablePhotoLocationCtaAction: String {
        NSLocalizedString("photosuggestions.cta.photolocation.action",
                          value: "Open Settings",
                          comment: "Button to link to settings to enable location permission for Photos app")
    }

    // MARK: Enable always on location

    static var enableAlwaysOnLocationCtaTitle: String {
        NSLocalizedString("photosuggestions.cta.alwaysonlocation.title",
                          value: "To Use Magic Posts, Allow HalloApp to Access Location",
                          comment: "title for explanation of why we want always location access")
    }

    static var enableAlwaysOnLocationCtaSubtitle: String {
        NSLocalizedString("photosuggestions.cta.alwaysonlocation.subtitle",
                          value: "When you take new photos, we find the best shots and organize them into a post draft, so it’s ready for you if you feel like posting.",
                          comment: "explanation of why we want always location access")
    }

    static var enableAlwaysOnLocationCtaAction: String {
        NSLocalizedString("photosuggestions.cta.alwaysonlocation.action",
                          value: "Allow in Settings",
                          comment: "Button to link to settings to enable location permission for HalloApp")
    }
}
