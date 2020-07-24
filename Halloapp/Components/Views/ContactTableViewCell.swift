//
//  ContactTableViewCell.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 5/5/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Core
import UIKit

enum PostStatus: Int {
    case seen = 0
    case delivered = 1
}

class ContactTableViewCell: UITableViewCell {
    override var isUserInteractionEnabled: Bool {
        didSet {
            if isUserInteractionEnabled {
                nameLabel.textColor = .label
            } else {
                nameLabel.textColor = .systemGray
            }
        }
    }
    
    private lazy var contactImage: AvatarView = {
        return AvatarView()
    }()
    
    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        let hStack = UIStackView(arrangedSubviews: [contactImage, nameLabel])
        hStack.axis = .horizontal
        hStack.spacing = 8
        hStack.translatesAutoresizingMaskIntoConstraints = false
        
        self.contentView.addSubview(hStack)
        
        hStack.leadingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        hStack.topAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.topAnchor).isActive = true
        hStack.trailingAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.trailingAnchor).isActive = true
        hStack.bottomAnchor.constraint(equalTo: self.contentView.layoutMarginsGuide.bottomAnchor).isActive = true
        
        contactImage.heightAnchor.constraint(equalToConstant: 25).isActive = true
        contactImage.heightAnchor.constraint(equalTo: contactImage.widthAnchor).isActive = true
    }
    
    public func configureForSeenBy(with userId: UserID, name: String, status: PostStatus, using avatarStore: AvatarStore) {
        contactImage.configure(with: userId, using: avatarStore)
        
        nameLabel.text = name
        
        let showDoubleBlueCheck = status == .seen
        let checkmarkImage = UIImage(named: showDoubleBlueCheck ? "CheckmarkDouble" : "CheckmarkSingle")?.withRenderingMode(.alwaysTemplate)
        
        if let imageView = self.accessoryView as? UIImageView {
            imageView.image = checkmarkImage
        } else {
            self.accessoryView = UIImageView(image: checkmarkImage)
        }
        
        self.accessoryView?.tintColor = showDoubleBlueCheck ? .systemBlue : .systemGray
    }
    
    public func configure(with userId: UserID, name: String, using avatarStore: AvatarStore) {
        contactImage.configure(with: userId, using: avatarStore)
        nameLabel.text = name
    }

    override func prepareForReuse() {
        contactImage.prepareForReuse()
        nameLabel.text = ""
    }
}
