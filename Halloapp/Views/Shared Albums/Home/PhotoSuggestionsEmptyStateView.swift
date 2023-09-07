//
//  PhotoSuggestionsEmptyStateView.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 9/5/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CoreCommon
import Photos
import UIKit

class PhotoSuggestionsEmptyStateView: UIView {

    enum EmptyStateType {
        case magicPostsExplainer
        case allowPhotoAccess
    }

    private let type: EmptyStateType

    init(_ type: EmptyStateType) {
        self.type = type

        super.init(frame: .zero)

        let title: String
        let subtitle: String
        let showActionButton: Bool

        switch type {
        case .magicPostsExplainer:
            title = Localizations.magicPostsExplainerTitle
            subtitle = Localizations.magicPostsExplainerSubtitle
            showActionButton = false
        case .allowPhotoAccess:
            title = Localizations.photoSuggestionsEmptyStatePhotoPermissionTitle
            subtitle = Localizations.magicPostsExplainerSubtitle
            showActionButton = true
        }

        let imageView = UIImageView(image: UIImage(named: "MagicPostsEmptyStateIcon"))

        let titleLabel = UILabel()
        titleLabel.font = .scaledSystemFont(ofSize: 16, weight: .medium)
        titleLabel.numberOfLines = 0
        titleLabel.text = title
        titleLabel.textAlignment = .center
        titleLabel.textColor = .primaryBlue

        let subtitleLabel = UILabel()
        subtitleLabel.font = .scaledSystemFont(ofSize: 15, weight: .regular)
        subtitleLabel.numberOfLines = 0
        subtitleLabel.text = subtitle
        subtitleLabel.textAlignment = .center
        subtitleLabel.textColor = .primaryBlackWhite.withAlphaComponent(0.5)

        let actionButton = RoundedRectButton()
        actionButton.addTarget(self, action: #selector(performAction), for: .touchUpInside)
        actionButton.backgroundTintColor = .primaryBlue
        actionButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 15, bottom: 10, right: 15)
        actionButton.isHidden = !showActionButton
        actionButton.setTitle(Localizations.photoSuggestionsEmptyStatePhotoPermissionsGrantAction, for: .normal)
        actionButton.setTitleColor(.white, for: .normal)
        actionButton.titleLabel?.font = .scaledSystemFont(ofSize: 15, weight: .bold)

        let contentStackView = UIStackView(arrangedSubviews: [imageView, titleLabel, subtitleLabel, actionButton])
        contentStackView.alignment = .center
        contentStackView.axis = .vertical
        contentStackView.setCustomSpacing(20, after: imageView)
        contentStackView.setCustomSpacing(4, after: titleLabel)
        contentStackView.setCustomSpacing(20, after: subtitleLabel)
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStackView)

        let stackCenterYConstraint = NSLayoutConstraint(item: contentStackView,
                                                        attribute: .centerY,
                                                        relatedBy: .equal,
                                                        toItem: self,
                                                        attribute: .centerY,
                                                        multiplier: 0.8,
                                                        constant: 0)
        stackCenterYConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            contentStackView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 50),
            stackCenterYConstraint,
            contentStackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            contentStackView.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }

    @objc private func performAction() {
        switch type {
        case .allowPhotoAccess:
            switch PhotoPermissionsHelper.authorizationStatus(for: .readWrite) {
            case .notDetermined:
                PhotoPermissionsHelper.requestAuthorization(for: .readWrite)
            case .restricted, .denied, .limited:
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            default:
                break
            }
        case .magicPostsExplainer:
            break
        }
    }
}

extension Localizations {

    static var photoSuggestionsEmptyStatePhotoPermissionTitle: String {
        NSLocalizedString("photosuggestions.emptystate.photopermission.title",
                          value: "Allow full access to Photos to use Magic Posts",
                          comment: "Explanatory text on empty state view")
    }

    static var photoSuggestionsEmptyStatePhotoPermissionsGrantAction: String {
        NSLocalizedString("photosuggestions.emptystate.photopermission.action",
                          value: "Enable",
                          comment: "Button to allow access to photos")
    }
}
