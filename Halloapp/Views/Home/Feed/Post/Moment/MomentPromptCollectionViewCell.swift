//
//  MomentPromptCollectionViewCell.swift
//  HalloApp
//
//  Created by Tanveer on 5/5/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import AVFoundation
import CoreCommon
import Core
import Combine

class MomentPromptCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "momentPromptCell"

    private var previewViewLeading: NSLayoutConstraint?
    private var previewViewTrailing: NSLayoutConstraint?

    private(set) lazy var promptView: MomentPromptView = {
        let view = MomentPromptView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        preservesSuperviewLayoutMargins = true
        contentView.preservesSuperviewLayoutMargins = true

        let spacing = FeedPostCollectionViewCell.LayoutConstants.interCardSpacing / 2

        contentView.addSubview(promptView)

        let leading = promptView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
        let trailing = promptView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        NSLayoutConstraint.activate([
            leading,
            trailing,
            promptView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: spacing),
            promptView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -spacing),
        ])

        previewViewLeading = leading
        previewViewTrailing = trailing
    }

    required init?(coder: NSCoder) {
        fatalError("MomentPromptCollectionViewCell coder init not implemented")
    }

    override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()

        previewViewLeading?.constant = layoutMargins.left * FeedPostCollectionViewCell.LayoutConstants.backgroundPanelHMarginRatio * 5

        previewViewTrailing?.constant = -layoutMargins.right * FeedPostCollectionViewCell.LayoutConstants.backgroundPanelHMarginRatio * 5
    }
}

final class MomentPromptView: UIView {
    private typealias Layout = MomentView.Layout
    private var cancellables: Set<AnyCancellable> = []

    private lazy var gradientView: GradientView = {
        let view = GradientView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = Layout.innerRadius()
        view.layer.cornerCurve = .continuous
        view.layer.masksToBounds = true
        return view
    }()

    private lazy var overlayStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [avatarView, displayLabel, actionButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 3, left: 20, bottom: 0, right: 20)
        stack.distribution = .fill
        stack.alignment = .center
        stack.setCustomSpacing(20, after: avatarView)
        stack.setCustomSpacing(10, after: displayLabel)
        return stack
    }()

    private lazy var avatarView: AvatarView = {
        let view = AvatarView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var displayLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(forTextStyle: .title3, pointSizeChange: -3, weight: .medium, maximumPointSize: 23)
        label.textColor = .white
        label.shadowColor = .black.withAlphaComponent(0.1)
        label.shadowOffset = .init(width: 0, height: 0.5)
        label.layer.shadowRadius = 1
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = Localizations.shareMoment
        return label
    }()

    private lazy var actionButton: MomentView.ShadowedCapsuleButton = {
        let view = MomentView.ShadowedCapsuleButton()
        view.button.addTarget(self, action: #selector(actionButtonPushed), for: .touchUpInside)
        view.button.setTitle(Localizations.openCamera, for: .normal)
        return view
    }()

    var openCamera: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        layer.cornerRadius = Layout.cornerRadius()
        layer.masksToBounds = false
        clipsToBounds = false

        layer.shadowOpacity = 0.75
        layer.shadowColor = UIColor.feedPostShadow.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 5)
        layer.shadowRadius = 5

        backgroundColor = .momentPolaroid
        installViews()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    private func installViews() {
        addSubview(gradientView)
        addSubview(overlayStack)

        let spacing = Layout.mediaPadding()
        let avatarDiameter = Layout.avatarDiameter
        NSLayoutConstraint.activate([
            gradientView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: spacing),
            gradientView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -spacing),
            gradientView.topAnchor.constraint(equalTo: topAnchor, constant: spacing),
            gradientView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -60),
            gradientView.heightAnchor.constraint(equalTo: gradientView.widthAnchor),
            overlayStack.topAnchor.constraint(greaterThanOrEqualTo: gradientView.topAnchor),
            overlayStack.bottomAnchor.constraint(lessThanOrEqualTo: gradientView.bottomAnchor),
            overlayStack.leadingAnchor.constraint(equalTo: gradientView.leadingAnchor),
            overlayStack.trailingAnchor.constraint(equalTo: gradientView.trailingAnchor),
            overlayStack.centerYAnchor.constraint(equalTo: gradientView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: avatarDiameter),
            avatarView.heightAnchor.constraint(equalToConstant: avatarDiameter),
        ])

        avatarView.configure(with: MainAppContext.shared.userData.userId, using: MainAppContext.shared.avatarStore)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Layout.cornerRadius()).cgPath
    }

    private func displayPermissionAllowedState() {
        displayLabel.text = Localizations.shareMoment
        actionButton.button.setTitle(Localizations.openCamera, for: .normal)
    }

    @objc
    private func actionButtonPushed(_ button: UIButton) {
        openCamera?()
    }
}

fileprivate class GradientView: UIView {
    override class var layerClass: AnyClass {
        get {
            return CAGradientLayer.self
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        guard let gradient = layer as? CAGradientLayer else {
            return
        }

        gradient.colors = [
            UIColor(red: 0.45, green: 0.45, blue: 0.43, alpha: 1.00).cgColor,
            UIColor(red: 0.22, green: 0.22, blue: 0.20, alpha: 1.00).cgColor,
        ]

        gradient.startPoint = CGPoint.zero
        gradient.endPoint = CGPoint(x: 0, y: 1)
        gradient.locations = [0.0,1.0]
    }

    required init?(coder: NSCoder) {
        fatalError("GradientView coder init not implemented...")
    }
}

// MARK: - localization

extension Localizations {
    static var shareMoment: String {
        NSLocalizedString("share.moment.prompt",
                   value: "Share a moment",
                 comment: "Prompt for the user to share a moment.")
    }

    static var openCamera: String {
        NSLocalizedString("open.camera",
                   value: "Open Camera",
                 comment: "Title of the button that opens the camera.")
    }
}
