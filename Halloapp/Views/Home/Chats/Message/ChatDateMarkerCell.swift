//
//  ChatDateMarker.swift
//  HalloApp
//
//  Created by Garrett on 2/3/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit

final class ChatDateMarkerCell: UITableViewCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .primaryBg
        contentView.layoutMargins = UIEdgeInsets(top: 5, left: 10, bottom: 10, right: 10)
        contentView.addSubview(dateMarker)
        dateMarker.translatesAutoresizingMaskIntoConstraints = false
        dateMarker.constrainMargins([.top, .bottom, .centerX], to: contentView)
        dateMarker.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.leadingAnchor).isActive = true
        dateMarker.trailingAnchor.constraint(lessThanOrEqualTo: contentView.layoutMarginsGuide.trailingAnchor).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(for timestamp: Date) {
        dateMarker.dateLabel.text = timestamp.chatMsgGroupingTimestamp()
    }

    private var dateMarker = ChatDateMarkerView()
}

final class ChatDateMarkerView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.constrain(to: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    lazy var bubble: UIView = {
        let view = UIView()
        view.layoutMargins = UIEdgeInsets(top: 5, left: 15, bottom: 5, right: 15)
        view.layer.cornerRadius = 10
        view.layer.masksToBounds = true
        view.clipsToBounds = true
        view.backgroundColor = UIColor.systemBlue

        view.addSubview(dateLabel)
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.constrainMargins(to: view)
        return view
    }()

    lazy var dateLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        let baseFont = UIFont.preferredFont(forTextStyle: .footnote)
        let boldFont = UIFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.traitBold)!, size: 0)
        label.font = boldFont
        label.textColor = .systemGray6
        return label
    }()
}
