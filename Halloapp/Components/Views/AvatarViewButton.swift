//
//  AvatarViewButton.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 10/14/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Combine
import Core
import CoreCommon
import UIKit

class AvatarViewButton: UIButton {

    private(set) var avatarView: AvatarView!

    private override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        avatarView = AvatarView()
        addSubview(avatarView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        avatarView.frame = bounds.insetBy(dx: 0, dy: 0)
    }

    override var intrinsicContentSize: CGSize {
        // Something random but rational.
        get { CGSize(width: 32, height: 32) }
    }

    override var isEnabled: Bool {
        didSet {
            // Value is chosen to mimic behavior of UIButton with type "system".
            avatarView.alpha = isEnabled ? 1 : 0.35
        }
    }

    override var isHighlighted: Bool {
        didSet {
            // Value is chosen to mimic behavior of UIButton with type "system".
            avatarView.alpha = isHighlighted ? 0.2 : 1
        }
    }

    // MARK: AvatarView

    func configure(userId: UserID, using avatarStore: AvatarStore) {
        avatarView.configure(with: userId, using: avatarStore)
    }

    func configure(groupId: GroupID, squareSize: CGFloat = 0, using avatarStore: AvatarStore) {
        avatarView.configure(groupId: groupId, squareSize: squareSize, using: avatarStore)
    }
}
