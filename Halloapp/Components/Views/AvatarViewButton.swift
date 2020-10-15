//
//  AvatarViewButton.swift
//  HalloApp
//
//  Created by Igor Solomennikov on 10/14/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Combine
import Core
import UIKit

class AvatarViewButton: UIButton {

    private(set) var avatarView: AvatarView!

    private var newGroupPostsCancellable: AnyCancellable?

    static let newPostsIndicatorRingWidth: CGFloat = 5

    private var ringView: RingView?

    var hasNewPostsIndicator: Bool = false {
        didSet {
            if hasNewPostsIndicator {
                if ringView == nil {
                    let ringView = RingView(frame: bounds)
                    ringView.strokeColor = .lavaOrange
                    ringView.fillColor = .clear
                    ringView.lineWidth = Self.newPostsIndicatorRingWidth - 1
                    ringView.isUserInteractionEnabled = false
                    insertSubview(ringView, belowSubview: avatarView)
                    self.ringView = ringView
                }
            } else {
                ringView?.isHidden = true
            }
            setNeedsLayout()
        }
    }

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
        let avatarViewRectInset = hasNewPostsIndicator ? Self.newPostsIndicatorRingWidth : 0
        avatarView.frame = bounds.insetBy(dx: avatarViewRectInset, dy: avatarViewRectInset)

        if let ringView = ringView {
            ringView.frame = bounds
        }
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
        if newGroupPostsCancellable != nil {
            newGroupPostsCancellable?.cancel()
            newGroupPostsCancellable = nil
        }

        avatarView.configure(with: userId, using: avatarStore)
        if let ringView = ringView {
            ringView.isHidden = true
        }
    }

    func configure(groupId: GroupID, using avatarStore: AvatarStore) {
        if newGroupPostsCancellable != nil {
            newGroupPostsCancellable?.cancel()
            newGroupPostsCancellable = nil
        }

        avatarView.configure(groupId: groupId, using: avatarStore)
        if let ringView = ringView {
            ringView.isHidden = false

            newGroupPostsCancellable = MainAppContext.shared.feedData
                .groupFeedUnreadCounts
                .map({ $0[groupId] ?? 0 })
                .sink(receiveValue: { [weak self] (unreadCount) in
                    guard let self = self else { return }
                    self.ringView?.strokeColor = unreadCount > 0 ? .lavaOrange : UIColor.systemGray.withAlphaComponent(0.3)
                })
        }
    }
}
