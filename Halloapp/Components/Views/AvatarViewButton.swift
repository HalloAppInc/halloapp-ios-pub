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

    // MARK: New Posts Indicator

    private var newGroupPostsCancellable: AnyCancellable?

    private var ringView: RingView?

    var newPostsIndicatorRingWidth: CGFloat {
        get {
            if let ringView = ringView {
                return ringView.lineWidth
            }
            return 0
        }
        set {
            if let ringView = ringView {
                ringView.lineWidth = newValue
                setNeedsLayout()
            }
        }
    }

    private enum NewPostsIndicatorState {
        case noIndicator
        case newPosts
        case noNewPosts
    }

    private var newPostsIndicatorState: FeedData.GroupFeedState = .noPosts {
        didSet {
            guard let ringView = ringView else { return }
            switch newPostsIndicatorState {
            case .noPosts:
                ringView.isHidden = true

            case .newPosts(_,_):
                ringView.isHidden = false
                ringView.strokeColor = .lavaOrange

            case .seenPosts(_):
                ringView.isHidden = false
                ringView.strokeColor = UIColor.systemGray.withAlphaComponent(0.3)
            }
        }
    }

    var hasNewPostsIndicator: Bool = false {
        didSet {
            if hasNewPostsIndicator {
                if ringView == nil {
                    let ringView = RingView(frame: bounds)
                    ringView.strokeColor = .lavaOrange
                    ringView.fillColor = .clear
                    ringView.lineWidth = 3
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
        let avatarViewRectInset = hasNewPostsIndicator ? newPostsIndicatorRingWidth : 0
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
        
        newPostsIndicatorState = .noPosts
    }

    func configure(groupId: GroupID, using avatarStore: AvatarStore) {
        if newGroupPostsCancellable != nil {
            newGroupPostsCancellable?.cancel()
            newGroupPostsCancellable = nil
        }

        avatarView.configure(groupId: groupId, using: avatarStore)

        if hasNewPostsIndicator {
            newGroupPostsCancellable = MainAppContext.shared.feedData
                .groupFeedStates
                .map({ $0[groupId] ?? .noPosts })
                .sink(receiveValue: { [weak self] (state) in
                    guard let self = self else { return }
                    self.newPostsIndicatorState = state
                })
        }
    }
}
