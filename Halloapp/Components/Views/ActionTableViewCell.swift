//
//  HalloApp
//
//  Created by Tony Jiang on 6/14/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import UIKit

fileprivate struct Constants {
    static let ActionIconSize: CGFloat = 30
}

class ActionTableViewCell: UITableViewCell {

    public func configure(icon: UIImage? = nil, attrText: NSMutableAttributedString? = nil, label: String? = nil) {
        iconView.image = icon
        if let attrText = attrText {
            bodyLabel.attributedText = attrText
        } else if let label = label {
            bodyLabel.text = label
        }
    }

    public var color: UIColor = UIColor.primaryBlue {
        didSet {
            iconView.tintColor = color
            bodyLabel.textColor = color
        }
    }
    public var imageBgColor: UIColor = UIColor.primaryBg {
        didSet {
            iconView.backgroundColor = imageBgColor
        }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .secondarySystemGroupedBackground

        contentView.addSubview(iconView)
        contentView.addSubview(bodyLabel)

        contentView.addConstraints([
            iconView.widthAnchor.constraint(equalToConstant: Constants.ActionIconSize),
            iconView.heightAnchor.constraint(equalTo: iconView.widthAnchor),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            iconView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor, constant: 8),

            bodyLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            bodyLabel.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            bodyLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),

            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])
    }

    lazy var iconView: UIImageView = {
        let image = UIImage()
        let view = UIImageView(image: image)
        view.contentMode = .center
        view.backgroundColor = imageBgColor
        view.tintColor = color
        view.layer.cornerRadius = Constants.ActionIconSize / 2
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    lazy var bodyLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(forTextStyle: .body, weight: .regular)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
}
