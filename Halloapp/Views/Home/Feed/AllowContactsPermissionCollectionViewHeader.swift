//
//  AllowContactsPermissionHeaderView.swift
//  HalloApp
//
//  Created by Tanveer on 9/19/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import CoreCommon

class AllowContactsPermissionHeaderView: UIView {

    private lazy var imageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.image = UIImage(named: "ContactsPermissionsBlue")
        return view
    }()

    fileprivate private(set) lazy var label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.font = .systemFont(forTextStyle: .subheadline, weight: .medium)
        label.adjustsFontSizeToFitWidth = true
        label.textColor = .white
        label.text = Localizations.allowContactsMessage
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .systemBlue
        layoutMargins = UIEdgeInsets(top: 12, left: 15, bottom: 12, right: 15)

        addSubview(imageView)
        addSubview(label)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            imageView.heightAnchor.constraint(equalToConstant: 36),
            imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),

            label.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 15),
            label.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            label.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            label.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),

            heightAnchor.constraint(lessThanOrEqualToConstant: 100),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(didTap))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("AllowContactsPermissionHeaderView coder init not implemented...")
    }

    @objc
    private func didTap(_ gesture: UITapGestureRecognizer) {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        UIApplication.shared.open(url)
    }
}

// MARK: - AllowContactsPermissionReusableHeader implementation

class AllowContactsPermissionCollectionViewHeader: UICollectionReusableView {

    static let reuseIdentifier = "allowContactsPermissionHeader"
    private lazy var header = AllowContactsPermissionHeaderView()

    var text: String {
        set { header.label.text = newValue }
        get { header.label.text ?? "" }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layoutMargins = .zero

        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            header.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("AllowContactsPermissionReusableHeader coder init not implemented...")
    }
}

// MARK: - AllowContactsPermissionTableViewHeader implementation

class AllowContactsPermissionTableViewHeader: UITableViewHeaderFooterView {

    static let reuseIdentifier = "allowContactsPermissionHeader"
    private lazy var header = AllowContactsPermissionHeaderView()

    var text: String {
        set { header.label.text = newValue }
        get { header.label.text ?? "" }
    }

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        layoutMargins = .zero
        contentView.layoutMargins = .zero

        header.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(header)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            header.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            header.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("AllowContactsPermissionTableViewHeader coder init not implemented...")
    }
}

// MARK: - Localization

extension Localizations {

    static var allowContactsPermissionPromptForPosts: String {
        NSLocalizedString("allow.contacts.permission.posts.prompt",
                   value: "To connect with your friends & family and see their posts, allow HalloApp to access your contacts.",
                 comment: "Displayed in the sticky header that's on the feed when the user has not given contacts access.")
    }
}
