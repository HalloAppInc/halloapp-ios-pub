//
//  GroupGridNewPostToast.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 5/13/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import CoreCommon

class GroupGridNewPostToast: UIView {

    private let label: UILabel = {
        let label = UILabel()
        label.font = .scaledSystemFont(ofSize: 14, weight: .semibold)
        label.textColor = .lavaOrange
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .groupNewPostsToastBackground

        layer.shadowColor = UIColor.groupNewPostsToastShadow.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowOpacity = 0.23
        layer.shadowRadius = 8

        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func configure(unreadCount: Int, animated: Bool) {
        let showToast = unreadCount > 0
        let isShowing = alpha > 0

        layoutIfNeeded()

        let updatedText = showToast ? Localizations.groupsGridNewPosts(count: unreadCount) : nil
        let updatedAlpha = showToast ? 1.0 : 0.0
        let updatedTransform = CGAffineTransform(translationX: 0.0, y: showToast ? 0.0 : -bounds.height)

        if animated {
            if showToast, isShowing {
                UIView.transition(with: self,
                                  duration: 0.2,
                                  options: [.transitionCrossDissolve]) {
                    self.label.text = updatedText
                }
            } else {
                // If we're hiding the toast, do not update label
                if showToast {
                    label.text = updatedText
                }
                UIView.animate(withDuration: 0.3) {
                    self.alpha = updatedAlpha
                    self.transform = updatedTransform
                }
            }
        } else {
            label.text = updatedText
            alpha = updatedAlpha
            transform = updatedTransform
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let cornerRadius = min(bounds.width, bounds.height) / 2
        layer.cornerRadius = cornerRadius
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
    }
}

extension Localizations {

    static func groupsGridNewPosts(count: Int) -> String {
        let format = NSLocalizedString("group.grid.n.posts", comment: "Indicates number of new posts on groups grid")
        return String.localizedStringWithFormat(format, count)
    }
}
