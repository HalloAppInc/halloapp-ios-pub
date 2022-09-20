//
//  PermissionExplainerView.swift
//  HalloApp
//
//  Created by Tanveer on 9/19/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit

class PermissionsExplainerView: ShadowView {

    enum PermissionType { case contacts, notifications }
    let permissionType: PermissionType

    private lazy var imageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit

        switch permissionType {
        case .contacts:
            view.image = UIImage(named: "ContactPermissions")
        case .notifications:
            view.image = UIImage(named: "NotificationPermissions")
        }

        return view
    }()

    private(set) lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = .gothamFont(forTextStyle: .subheadline, weight: .medium)
        return label
    }()

    private(set) lazy var bodyLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.textColor = .secondaryLabel
        label.font = .systemFont(forTextStyle: .body)
        return label
    }()

    private lazy var vStack: UIStackView = {
        let titleStack = UIStackView(arrangedSubviews: [imageView, titleLabel])
        titleStack.axis = .horizontal
        titleStack.spacing = 12

        let stack = UIStackView(arrangedSubviews: [titleStack, bodyLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)
        stack.spacing = 12

        return stack
    }()

    init(permissionType: PermissionType) {
        self.permissionType = permissionType
        super.init(frame: .zero)

        backgroundColor = .feedPostBackground
        layer.cornerCurve = .continuous
        layer.cornerRadius = 15

        layer.shadowColor = UIColor.black.withAlphaComponent(0.15).cgColor
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowRadius = 0.75
        layer.shadowOpacity = 1

        addSubview(vStack)

        let imageLength: CGFloat = 35
        NSLayoutConstraint.activate([
            vStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            vStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            vStack.topAnchor.constraint(equalTo: topAnchor),
            vStack.bottomAnchor.constraint(equalTo: bottomAnchor),

            imageView.heightAnchor.constraint(equalToConstant: imageLength),
            imageView.widthAnchor.constraint(equalToConstant: imageLength),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("PermissionsExplainerView coder init not implemented...")
    }
}
