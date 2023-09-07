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
        closeButton.setImage(UIImage(systemName: "xmark")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)), for: .normal)
        closeButton.tintColor = .primaryBlackWhite.withAlphaComponent(0.5)
        return closeButton
    }()

    private let imageView: UIImageView = {
        return UIImageView(image: UIImage(named: "MagicPostsEmptyStateIcon"))
    }()

    private let titleLabel: UILabel = {
        let titleLabel = UILabel()
        titleLabel.font = .scaledSystemFont(ofSize: 15, weight: .medium)
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        titleLabel.textColor = .primaryBlackWhite.withAlphaComponent(0.75)
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
        contentStackView.setCustomSpacing(4, after: titleLabel)
        contentStackView.setCustomSpacing(20, after: subtitleLabel)
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStackView)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            contentStackView.topAnchor.constraint(equalTo: closeButton.bottomAnchor),
            contentStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            contentStackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            contentStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(type: CallToActionType, dismissAction: @escaping () -> Void) {
        currentCallToActionType = type
        self.dismissAction = dismissAction

        let title: String
        let subtitle: String
        let ctaText: String?
        let canDismiss: Bool

        switch type {
        case .firstTimeUse:
            title = Localizations.magicPostsExplainerTitle
            subtitle = Localizations.magicPostsExplainerSubtitle
            ctaText = nil
            canDismiss = true
        case .enablePhotoLocations:
            title = Localizations.enablePhotoLocationCtaTitle
            subtitle = Localizations.enablePhotoLocationCtaSubtitle
            ctaText = Localizations.enablePhotoLocationCtaAction
            canDismiss = false
        case .enableAlwaysOnLocation:
            title = Localizations.enableAlwaysOnLocationCtaTitle
            subtitle = Localizations.enableAlwaysOnLocationCtaSubtitle
            ctaText = Localizations.enableAlwaysOnLocationCtaAction
            canDismiss = false
        }

        titleLabel.text = title
        subtitleLabel.text = subtitle
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
            switch CLLocationManager.authorizationStatus() {
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
                          value: "Allow Location access for the Photos app",
                          comment: "title for explanation of why we want location access for photos app")
    }

    static var enablePhotoLocationCtaSubtitle: String {
        NSLocalizedString("photosuggestions.cta.photolocation.subtitle", 
                          value: "Allow Location access for the Photos app to improve Magic Posts. HalloApp uses location metadata from your photos to help sort and name them.",
                          comment: "explanation for why we need to turn on location access for photos")
    }

    static var enablePhotoLocationCtaAction: String {
        NSLocalizedString("photosuggestions.cta.photolocation.action",
                          value: "Allow in Settings",
                          comment: "Button to link to settings to enable location permission for Photos app")
    }

    // MARK: Enable always on location

    static var enableAlwaysOnLocationCtaTitle: String {
        NSLocalizedString("photosuggestions.cta.alwaysonlocation.title",
                          value: "Allow HalloApp to access Location to be notified of new Magic Posts",
                          comment: "title for explanation of why we want always location access")
    }

    static var enableAlwaysOnLocationCtaSubtitle: String {
        NSLocalizedString("photosuggestions.cta.alwaysonlocation.subtitle",
                          value: "HalloApp will notify you of new Magic Posts when you take photos and leave a location",
                          comment: "explanation of why we want always location access")
    }

    static var enableAlwaysOnLocationCtaAction: String {
        NSLocalizedString("photosuggestions.cta.alwaysonlocation.action",
                          value: "Allow location access",
                          comment: "Button to link to settings to enable location permission for HalloApp")
    }
}
