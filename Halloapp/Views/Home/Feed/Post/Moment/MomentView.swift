//
//  MomentView.swift
//  HalloApp
//
//  Created by Tanveer on 5/1/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import Core
import CoreCommon

class MomentView: UIView {
    typealias LayoutConstants = FeedPostCollectionViewCell.LayoutConstants

    enum Style { case normal, minimal }
    enum State { case locked, unlocked, indeterminate }
    
    let style: Style
    private(set) var state: State = .locked
    
    private(set) var feedPost: FeedPost?
    let mediaView: MediaCarouselView
    
    private lazy var blurView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = LayoutConstants.backgroundCornerRadius
        view.layer.cornerCurve = .continuous
        view.layer.masksToBounds = true
        return view
    }()
    
    private lazy var avatarView: AvatarView = {
        let view = AvatarView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var actionButton: CapsuleButton = {
        let button = CapsuleButton(type: .system)
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        button.setTitle(Localizations.open, for: .normal)
        button.setBackgroundColor(.systemBlue, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.layer.masksToBounds = true
        button.layer.cornerRadius = button.bounds.height / 2
        button.addTarget(self, action: #selector(actionButtonPushed), for: .touchUpInside)
        
        return button
    }()
    
    private lazy var promptLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(forTextStyle: .body, weight: .regular, maximumPointSize: 33)
        label.textColor = .white
        
        return label
    }()
    
    private lazy var overlayStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [avatarView, actionButton, promptLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.distribution = .equalSpacing
        stack.alignment = .center
        stack.spacing = 12
        
        return stack
    }()
    
    private lazy var dayOfWeekLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17)
        return label
    }()
    
    private(set) lazy var dateLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 17)
        return label
    }()
    
    private lazy var footerView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .trailing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private var cancellables: Set<AnyCancellable> = []
    var action: (() -> Void)?

    init(style: Style = .normal) {
        self.style = style
        
        let cornerRadius: CGFloat = style == .minimal ? 10 : LayoutConstants.backgroundCornerRadius
        let footerSpacing: CGFloat = style == .minimal ? 10 : 14
        let mediaSpacing: CGFloat = style == .minimal ? 5 : 9
        
        var mediaConfig = MediaCarouselViewConfiguration.default
        mediaConfig.cornerRadius = cornerRadius
        mediaView = MediaCarouselView(media: [], initialIndex: nil, configuration: mediaConfig)
        
        super.init(frame: .zero)
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .circular
        backgroundColor = .feedPostBackground
        
        mediaView.delegate = self
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mediaView)
        addSubview(footerView)
        
        let mediaHeight = mediaView.heightAnchor.constraint(equalTo: mediaView.widthAnchor)
        let footerBottom = footerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -footerSpacing)
        mediaHeight.priority = .defaultHigh
        footerBottom.priority = .defaultHigh
        
        NSLayoutConstraint.activate([
            mediaView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: mediaSpacing),
            mediaView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -mediaSpacing),
            mediaView.topAnchor.constraint(equalTo: topAnchor, constant: mediaSpacing),
            mediaHeight,
            footerView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -footerSpacing - 10),
            footerView.topAnchor.constraint(equalTo: mediaView.bottomAnchor, constant: footerSpacing),
            footerBottom,
        ])
        
        layer.shadowOpacity = 0.75
        layer.shadowColor = UIColor.feedPostShadow.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 5)
        layer.shadowRadius = 5
        
        layer.masksToBounds = false
        clipsToBounds = false

        if case .normal = style {
            installDetailViews()
        } else {
            footerView.isHidden = true
        }
    }

    private func installDetailViews() {
        footerView.addArrangedSubview(dayOfWeekLabel)
        footerView.addArrangedSubview(dateLabel)
        addSubview(blurView)
        addSubview(overlayStack)

        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
            blurView.topAnchor.constraint(equalTo: mediaView.topAnchor),
            blurView.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: mediaView.bottomAnchor),
            overlayStack.leadingAnchor.constraint(equalTo: blurView.leadingAnchor),
            overlayStack.topAnchor.constraint(greaterThanOrEqualTo: blurView.topAnchor),
            overlayStack.trailingAnchor.constraint(equalTo: blurView.trailingAnchor),
            overlayStack.bottomAnchor.constraint(lessThanOrEqualTo: blurView.bottomAnchor),
            overlayStack.centerYAnchor.constraint(equalTo: blurView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 85),
            avatarView.heightAnchor.constraint(equalToConstant: 85),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: LayoutConstants.backgroundCornerRadius).cgPath
    }
    
    func configure(with post: FeedPost) {
        feedPost = post
        mediaView.refreshData(media: post.feedMedia, index: 0, animated: false)

        dayOfWeekLabel.text = DateFormatter.dateTimeFormatterDayOfWeekLong.string(from: post.timestamp)
        dateLabel.text = DateFormatter.dateTimeFormatterShortDate.string(from: post.timestamp)

        avatarView.configure(with: post.userID, using: MainAppContext.shared.avatarStore)
        let name = MainAppContext.shared.contactStore.firstName(for: post.userID)
        promptLabel.text = String(format: Localizations.secretPostEntice, name)
        
        let isOwnPost = post.userID == MainAppContext.shared.userData.userId
        blurView.isHidden = isOwnPost
        overlayStack.isHidden = isOwnPost
    }
    
    func prepareForReuse() {
        avatarView.prepareForReuse()
    }

    func setState(_ newState: State, animated: Bool = false) {
        if animated {
            return UIView.animate(withDuration: 0.3) { self.setState(newState) }
        }
        
        switch newState {
        case .locked:
            blurView.alpha = 1
            overlayStack.alpha = 1
        case .unlocked:
            blurView.alpha = 0
            overlayStack.alpha = 0
        case .indeterminate:
            blurView.alpha = 1
            overlayStack.alpha = 0
        }
        
        state = newState
    }
    
    @objc
    private func actionButtonPushed(_ button: UIButton) {
        action?()
    }
}

// MARK: - media carousel delegate methods

extension MomentView: MediaCarouselViewDelegate {
    func mediaCarouselView(_ view: MediaCarouselView, indexChanged newIndex: Int) {
        
    }
    
    func mediaCarouselView(_ view: MediaCarouselView, didTapMediaAtIndex index: Int) {
        action?()
    }
    
    func mediaCarouselView(_ view: MediaCarouselView, didDoubleTapMediaAtIndex index: Int) {
        
    }
    
    func mediaCarouselView(_ view: MediaCarouselView, didZoomMediaAtIndex index: Int, withScale scale: CGFloat) {
        
    }
}

fileprivate class CapsuleButton: UIButton {
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2.0
    }
}

// MARK: - localization

extension Localizations {
    static var secretPostEntice: String {
        NSLocalizedString("secret.post.entice",
                   value: "%@ shared a moment",
                 comment: "Text placed on the blurred overlay of a secret post.")
    }

    static var open: String {
        NSLocalizedString("open.title",
                   value: "Open",
                 comment: "Text that indicates an open action.")
    }
}
