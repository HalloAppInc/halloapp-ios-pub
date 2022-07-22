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

protocol MomentViewDelegate: AnyObject {
    func momentView(_ momentView: MomentView, didSelect action: MomentView.Action)
}

// MARK: - static methods for layout values

extension MomentView {
    struct Layout {
        static var cornerRadius: CGFloat {
            12
        }

        static var innerRadius: CGFloat {
            cornerRadius - 5
        }

        static var mediaPadding: CGFloat {
            7
        }

        static var footerPadding: CGFloat {
            14
        }

        static var avatarDiameter: CGFloat {
            95
        }
    }
}

class MomentView: UIView {
    typealias LayoutConstants = FeedPostCollectionViewCell.LayoutConstants
    enum State { case locked, unlocked, indeterminate, prompt }

    enum Action { case open(moment: FeedPost), camera, view(profile: UserID) }

    private(set) var state: State = .locked
    private(set) var feedPost: FeedPost?

    private(set) lazy var mediaView: MediaCarouselView = {
        let view = MediaCarouselView(media: [], initialIndex: nil, configuration: .moment)
        view.delegate = self
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .systemGray
        view.layer.cornerRadius = Layout.innerRadius
        view.layer.cornerCurve = .continuous
        return view
    }()
    
    private lazy var blurView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = Layout.innerRadius
        view.layer.cornerCurve = .continuous
        view.layer.masksToBounds = true
        return view
    }()

    private lazy var gradientView: GradientView = {
        let view = GradientView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = Layout.innerRadius
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
        label.font = .handwritingFont(forTextStyle: .body, pointSizeChange: 2, weight: .regular, maximumPointSize: 26)
        label.textColor = .black.withAlphaComponent(0.9)
        return label
    }()
    
    private lazy var footerView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .trailing
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 7, left: 0, bottom: 7, right: 0)
        return stack
    }()
    
    private var cancellables: Set<AnyCancellable> = []

    weak var delegate: MomentViewDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)

        layer.cornerRadius = Layout.cornerRadius
        layer.cornerCurve = .circular
        backgroundColor = .momentPolaroid

        addSubview(gradientView)
        addSubview(mediaView)
        addSubview(footerView)
        addSubview(blurView)
        addSubview(overlayStack)

        let footerPadding = Layout.footerPadding
        let mediaPadding = Layout.mediaPadding

        let mediaHeightConstraint = mediaView.heightAnchor.constraint(equalTo: mediaView.widthAnchor)
        let footerBottomConstraint = footerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -footerPadding)
        let avatarDiameter = Layout.avatarDiameter
        mediaHeightConstraint.priority = .defaultHigh
        footerBottomConstraint.priority = .defaultHigh

        let minimizeFooterHeight = footerView.heightAnchor.constraint(equalToConstant: 1)
        minimizeFooterHeight.priority = UILayoutPriority(1)

        NSLayoutConstraint.activate([
            mediaView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: mediaPadding),
            mediaView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -mediaPadding),
            mediaView.topAnchor.constraint(equalTo: topAnchor, constant: mediaPadding),
            mediaHeightConstraint,

            gradientView.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor),
            gradientView.topAnchor.constraint(equalTo: mediaView.topAnchor),
            gradientView.bottomAnchor.constraint(equalTo: mediaView.bottomAnchor),

            blurView.leadingAnchor.constraint(equalTo: mediaView.leadingAnchor),
            blurView.topAnchor.constraint(equalTo: mediaView.topAnchor),
            blurView.trailingAnchor.constraint(equalTo: mediaView.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: mediaView.bottomAnchor),

            overlayStack.leadingAnchor.constraint(equalTo: blurView.leadingAnchor),
            overlayStack.topAnchor.constraint(greaterThanOrEqualTo: blurView.topAnchor),
            overlayStack.trailingAnchor.constraint(equalTo: blurView.trailingAnchor),
            overlayStack.bottomAnchor.constraint(lessThanOrEqualTo: blurView.bottomAnchor),
            overlayStack.centerYAnchor.constraint(equalTo: blurView.centerYAnchor),

            avatarView.widthAnchor.constraint(equalToConstant: avatarDiameter),
            avatarView.heightAnchor.constraint(equalToConstant: avatarDiameter),

            footerView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -footerPadding - 8),
            footerView.topAnchor.constraint(equalTo: mediaView.bottomAnchor, constant: footerPadding - 2),
            footerView.heightAnchor.constraint(greaterThanOrEqualTo: mediaView.heightAnchor, multiplier: 0.15),
            minimizeFooterHeight,
            footerBottomConstraint,
        ])

        layer.shadowOpacity = 0.75
        layer.shadowColor = UIColor.feedPostShadow.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 5)
        layer.shadowRadius = 5

        layer.masksToBounds = false
        clipsToBounds = false

        footerView.addArrangedSubview(dayOfWeekLabel)

        layer.borderWidth = 0.4 / UIScreen.main.scale
        layer.borderColor = UIColor(red: 0.83, green: 0.83, blue: 0.83, alpha: 1.00).cgColor

        MainAppContext.shared.feedData.validMoment
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if let state = self?.state, state != .prompt {
                    self?.setState(state)
                }
            }
            .store(in: &cancellables)
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Layout.cornerRadius).cgPath
    }

    func configure(with post: FeedPost?) {
        guard let post = post else {
            return configureForPrompt()
        }

        feedPost = post
        mediaView.refreshData(media: post.feedMedia, index: 0, animated: false)
        for media in post.feedMedia where !media.isMediaAvailable {
            media.loadImage()
        }

        dayOfWeekLabel.text = DateFormatter.dateTimeFormatterDayOfWeekLong.string(from: post.timestamp).uppercased()
        avatarView.configure(with: post.userID, using: MainAppContext.shared.avatarStore)

        let isOwnPost = MainAppContext.shared.userData.userId == post.userId
        let state: State = isOwnPost ? .unlocked : .locked

        setState(state)
    }

    private func configureForPrompt() {
        feedPost = nil
        avatarView.configure(with: MainAppContext.shared.userData.userId, using: MainAppContext.shared.avatarStore)

        setState(.prompt)
    }

    func prepareForReuse() {
        avatarView.prepareForReuse()
    }

    func setState(_ newState: State, animated: Bool = false) {
        if animated {
            return UIView.animate(withDuration: 0.3) { self.setState(newState) }
        }

        var blurAlpha: CGFloat = 1
        var overlayAlpha: CGFloat = 1
        var mediaHidden = false
        var dayHidden = false
        var promptText = ""
        var buttonText = MainAppContext.shared.feedData.validMoment.value == nil ? Localizations.unlock : Localizations.view

        if let post = feedPost {
            let name = MainAppContext.shared.contactStore.firstName(for: post.userID,
                                                                     in: MainAppContext.shared.contactStore.viewContext)
            promptText = String(format: Localizations.secretPostEntice, name)
        }

        switch newState {
        case .locked:
            break
        case .unlocked:
            blurAlpha = 0
            overlayAlpha = 0
        case .indeterminate:
            overlayAlpha = 0
        case .prompt:
            blurAlpha = 0
            mediaHidden = true
            dayHidden = true
            promptText = Localizations.shareMoment
            buttonText = Localizations.openCamera
        }

        blurView.effect = blurAlpha == .zero ? nil : UIBlurEffect(style: .regular)
        blurView.isUserInteractionEnabled = newState != .unlocked
        overlayStack.alpha = overlayAlpha
        mediaView.isHidden = mediaHidden
        dayOfWeekLabel.isHidden = dayHidden
        promptLabel.text = promptText
        actionButton.button.setTitle(buttonText, for: .normal)

        state = newState
        setNeedsLayout()
    }
    
    @objc
    private func actionButtonPushed(_ button: UIButton) {
        if let post = feedPost {
            delegate?.momentView(self, didSelect: .open(moment: post))
        } else {
            delegate?.momentView(self, didSelect: .camera)
        }
    }

    @objc
    private func avatarTapped(_ gesture: UITapGestureRecognizer) {
        if let id = feedPost?.userId {
            delegate?.momentView(self, didSelect: .view(profile: id))
        } else if case .prompt = state {
            delegate?.momentView(self, didSelect: .view(profile: MainAppContext.shared.userData.userId))
        }
    }
}

// MARK: - media carousel delegate methods

extension MomentView: MediaCarouselViewDelegate {
    func mediaCarouselView(_ view: MediaCarouselView, indexChanged newIndex: Int) {
        
    }
    
    func mediaCarouselView(_ view: MediaCarouselView, didTapMediaAtIndex index: Int) {
        if let post = feedPost {
            delegate?.momentView(self, didSelect: .open(moment: post))
        }
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

// MARK: - GradientView implementation

fileprivate class GradientView: UIView {
    override class var layerClass: AnyClass {
        get {
            return CAGradientLayer.self
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        guard let gradient = layer as? CAGradientLayer else {
            return
        }

        gradient.colors = [
            UIColor(red: 0.45, green: 0.45, blue: 0.43, alpha: 1.00).cgColor,
            UIColor(red: 0.22, green: 0.22, blue: 0.20, alpha: 1.00).cgColor,
        ]

        gradient.startPoint = CGPoint.zero
        gradient.endPoint = CGPoint(x: 0, y: 1)
        gradient.locations = [0.0, 1.0]
    }

    required init?(coder: NSCoder) {
        fatalError("GradientView coder init not implemented...")
    }
}

// MARK: - localization

extension Localizations {
    static var secretPostEntice: String {
        NSLocalizedString("shared.moment",
                   value: "%@’s moment",
                 comment: "Text placed on the blurred overlay of someone else's moment.")
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

    static var shareMoment: String {
        NSLocalizedString("share.moment.prompt",
                   value: "Share a moment",
                 comment: "Prompt for the user to share a moment.")
    }

    static var openCamera: String {
        NSLocalizedString("open.camera",
                   value: "Open Camera",
                 comment: "Title of the button that opens the camera.")
    }
}
