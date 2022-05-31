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

// MARK: - static methods for layout values

extension MomentView {
    /// - note: Also used by `MomentPromptView`.
    struct Layout {
        static func cornerRadius(for style: Style = .normal) -> CGFloat {
            style == .minimal ? 7 : 12
        }

        static func innerRadius(for style: Style = .normal) -> CGFloat {
            let difference: CGFloat = style == .minimal ? 2 : 5
            return cornerRadius(for: style) - difference
        }

        static func mediaPadding(for style: Style = .normal) -> CGFloat {
            style == .minimal ? 3 : 7
        }

        static func footerPadding(for style: Style = .normal) -> CGFloat {
            style == .minimal ? 9 : 14
        }

        static var avatarDiameter: CGFloat {
            95
        }
    }
}

class MomentView: UIView {
    typealias LayoutConstants = FeedPostCollectionViewCell.LayoutConstants

    enum Style { case normal, minimal }
    enum State { case locked, unlocked, indeterminate }
    
    let style: Style
    private(set) var state: State = .locked
    
    private(set) var feedPost: FeedPost?

    private(set) lazy var mediaView: MediaCarouselView = {
        var config = MediaCarouselViewConfiguration.default
        config.cornerRadius = Layout.innerRadius(for: style)
        config.borderWidth = 0
        let view = MediaCarouselView(media: [], initialIndex: nil, configuration: config)
        view.delegate = self
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private lazy var blurView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = Layout.innerRadius(for: style)
        view.layer.cornerCurve = .continuous
        view.layer.masksToBounds = true
        return view
    }()
    
    private lazy var avatarView: AvatarView = {
        let view = AvatarView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(avatarTapped))
        view.addGestureRecognizer(tap)
        return view
    }()
    
    private lazy var actionButton: ShadowedCapsuleButton = {
        let view = ShadowedCapsuleButton()
        view.button.setTitle(Localizations.view, for: .normal)
        view.button.addTarget(self, action: #selector(actionButtonPushed), for: .touchUpInside)
        return view
    }()
    
    private lazy var promptLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(forTextStyle: .title3, pointSizeChange: -3, weight: .medium, maximumPointSize: 23)
        label.textColor = .white
        label.shadowColor = .black.withAlphaComponent(0.1)
        label.shadowOffset = .init(width: 0, height: 0.5)
        label.layer.shadowRadius = 2
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()
    
    private lazy var overlayStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [avatarView, promptLabel, actionButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 3, left: 20, bottom: 0, right: 20)
        stack.distribution = .fill
        stack.alignment = .center
        stack.setCustomSpacing(20, after: avatarView)
        stack.setCustomSpacing(10, after: promptLabel)
        return stack
    }()
    
    private(set) lazy var dayOfWeekLabel: UILabel = {
        let label = UILabel()
        label.font = .handwritingFont(forTextStyle: .body, weight: .regular, maximumPointSize: 26)
        label.textColor = .black.withAlphaComponent(0.9)
        return label
    }()
    
    private(set) lazy var timeLabel: UILabel = {
        let label = UILabel()
        label.font = .handwritingFont(forTextStyle: .body, weight: .regular, maximumPointSize: 26)
        label.textColor = .black.withAlphaComponent(0.9)
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
    var avatarAction: (() -> Void)?
    var buttonAction: (() -> Void)?

    init(style: Style = .normal) {
        self.style = style
        super.init(frame: .zero)
        layer.cornerRadius = Layout.cornerRadius(for: style)
        layer.cornerCurve = .circular
        backgroundColor = .momentPolaroid

        addSubview(mediaView)
        addSubview(footerView)

        let footerPadding = Layout.footerPadding(for: style)
        let mediaPadding = Layout.mediaPadding(for: style)

        let mediaHeightConstraint = mediaView.heightAnchor.constraint(equalTo: mediaView.widthAnchor)
        let footerBottomConstraint = footerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -footerPadding)
        mediaHeightConstraint.priority = .defaultHigh
        footerBottomConstraint.priority = .defaultHigh
        
        NSLayoutConstraint.activate([
            mediaView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: mediaPadding),
            mediaView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -mediaPadding),
            mediaView.topAnchor.constraint(equalTo: topAnchor, constant: mediaPadding),
            mediaHeightConstraint,
            footerView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -footerPadding - 8),
            footerView.topAnchor.constraint(equalTo: mediaView.bottomAnchor, constant: footerPadding - 2),
            footerBottomConstraint,
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

        MainAppContext.shared.feedData.validMoment.sink { [weak self] id in
            DispatchQueue.main.async {
                let title = id == nil ? Localizations.unlock : Localizations.view
                self?.actionButton.button.setTitle(title, for: .normal)
                self?.setNeedsLayout()
            }
        }.store(in: &cancellables)
    }

    private func installDetailViews() {
        footerView.addArrangedSubview(dayOfWeekLabel)
        footerView.addArrangedSubview(timeLabel)
        addSubview(blurView)
        addSubview(overlayStack)

        let diameter = Layout.avatarDiameter
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
            avatarView.widthAnchor.constraint(equalToConstant: diameter),
            avatarView.heightAnchor.constraint(equalToConstant: diameter),
        ])

        footerView.setCustomSpacing(-1, after: dayOfWeekLabel)
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Layout.cornerRadius(for: style)).cgPath
    }
    
    func configure(with post: FeedPost) {
        feedPost = post
        mediaView.refreshData(media: post.feedMedia, index: 0, animated: false)

        for media in post.feedMedia where !media.isMediaAvailable {
            media.loadImage()
        }

        dayOfWeekLabel.text = DateFormatter.dateTimeFormatterDayOfWeekLong.string(from: post.timestamp).uppercased()
        timeLabel.text = DateFormatter.dateTimeFormatterTime.string(from: post.timestamp)

        avatarView.configure(with: post.userID, using: MainAppContext.shared.avatarStore)
        let name = MainAppContext.shared.contactStore.firstName(for: post.userID)
        promptLabel.text = String(format: Localizations.secretPostEntice, name)

        let buttonTitle = MainAppContext.shared.feedData.validMoment.value == nil ? Localizations.unlock : Localizations.view
        actionButton.button.setTitle(buttonTitle, for: .normal)
        
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
        buttonAction?()
    }

    @objc
    private func avatarTapped(_ gesture: UITapGestureRecognizer) {
        avatarAction?()
    }
}

// MARK: - media carousel delegate methods

extension MomentView: MediaCarouselViewDelegate {
    func mediaCarouselView(_ view: MediaCarouselView, indexChanged newIndex: Int) {
        
    }
    
    func mediaCarouselView(_ view: MediaCarouselView, didTapMediaAtIndex index: Int) {
        buttonAction?()
    }
    
    func mediaCarouselView(_ view: MediaCarouselView, didDoubleTapMediaAtIndex index: Int) {
        
    }
    
    func mediaCarouselView(_ view: MediaCarouselView, didZoomMediaAtIndex index: Int, withScale scale: CGFloat) {
        
    }
}

// MARK: - ShadowedCapsuleButton implementation

extension MomentView {
    ///
    class ShadowedCapsuleButton: UIView {
        let button: UIButton

        override init(frame: CGRect) {
            button = UIButton(type: .system)
            super.init(frame: frame)

            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)

            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: leadingAnchor),
                button.trailingAnchor.constraint(equalTo: trailingAnchor),
                button.topAnchor.constraint(equalTo: topAnchor),
                button.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])

//            layer.shadowOpacity = 1
//            layer.shadowColor = UIColor.black.withAlphaComponent(0.2).cgColor
//            layer.shadowRadius = 1
//            layer.shadowOffset = .init(width: 0, height: 1)
            layer.masksToBounds = false
            clipsToBounds = false

            button.layer.masksToBounds = true
            button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 17, bottom: 10, right: 17)
            button.setBackgroundColor(.systemBlue, for: .normal)
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = .gothamFont(forTextStyle: .title3, pointSizeChange: -2, weight: .medium, maximumPointSize: 30)
        }

        required init?(coder: NSCoder) {
            fatalError("ShadowedCapsuleButton coder init not implemented...")
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            button.layer.cornerRadius = min(bounds.width, bounds.height) / 2.0
            // trying with no shadow for now; might change later
            //layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: button.layer.cornerRadius).cgPath
        }
    }
}

// MARK: - localization

extension Localizations {
    static var secretPostEntice: String {
        NSLocalizedString("secret.post.entice",
                   value: "%@ shared a moment",
                 comment: "Text placed on the blurred overlay of a secret post.")
    }

    static var view: String {
        NSLocalizedString("view.title",
                   value: "View",
                 comment: "Text that indicates a view action.")
    }

    static var unlock: String {
        NSLocalizedString("unlock.title",
                   value: "Unlock",
                 comment: "Text that indicates the unlock action for a moment.")
    }
}
