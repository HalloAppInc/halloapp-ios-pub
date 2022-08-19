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
            85
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
    
    private lazy var actionButton: RoundedRectButton = {
        let button = RoundedRectButton()
        button.setTitle(Localizations.view, for: .normal)
        button.overrideUserInterfaceStyle = .dark
        button.backgroundTintColor = .systemBlue
        button.tintColor = .white

        button.titleLabel?.font = .gothamFont(forTextStyle: .title3, pointSizeChange: -2, weight: .medium, maximumPointSize: 30)

        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 17, bottom: 10, right: 17)
        let imageEdgeInset: CGFloat = effectiveUserInterfaceLayoutDirection == .leftToRight ? -4 : 4
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: imageEdgeInset, bottom: 0, right: -imageEdgeInset)
        button.layer.allowsEdgeAntialiasing = true
        button.layer.cornerCurve = .circular

        button.addTarget(self, action: #selector(actionButtonPushed), for: .touchUpInside)
        return button
    }()

    private lazy var lockedButtonImage: UIImage? = {
        let config = UIImage.SymbolConfiguration(pointSize: actionButton.titleLabel?.font.pointSize ?? 16, weight: .medium)
        return UIImage(systemName: "eye.slash", withConfiguration: config)
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
        label.adjustsFontSizeToFitWidth = true
        return label
    }()

    private lazy var disclaimerLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(forTextStyle: .footnote)
        label.adjustsFontSizeToFitWidth = true
        label.textAlignment = .center
        label.textColor = .white
        label.shadowColor = .black.withAlphaComponent(0.15)
        label.shadowOffset = .init(width: 0, height: 0.5)
        label.layer.shadowRadius = 2
        label.text = Localizations.momentUnlockDisclaimer
        return label
    }()
    
    private lazy var overlayStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [avatarView, promptLabel, actionButton, disclaimerLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 5, left: 20, bottom: 5, right: 20)
        stack.distribution = .fill
        stack.alignment = .center

        stack.setCustomSpacing(10, after: avatarView)
        stack.setCustomSpacing(10, after: promptLabel)
        stack.setCustomSpacing(10, after: actionButton)

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

        mediaView.layer.allowsEdgeAntialiasing = true

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
            overlayStack.topAnchor.constraint(greaterThanOrEqualTo: blurView.topAnchor, constant: 10),
            overlayStack.trailingAnchor.constraint(equalTo: blurView.trailingAnchor),
            overlayStack.bottomAnchor.constraint(lessThanOrEqualTo: blurView.bottomAnchor, constant: -10),
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

        layer.shadowOpacity = 0.85
        layer.shadowColor = UIColor.feedPostShadow.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowRadius = 7

        layer.masksToBounds = false
        clipsToBounds = false

        footerView.addArrangedSubview(dayOfWeekLabel)

        layer.borderWidth = 0.5 / UIScreen.main.scale
        layer.borderColor = UIColor(red: 0.71, green: 0.71, blue: 0.71, alpha: 1.00).cgColor
        // helps with how the border renders when the view is being rotated
        layer.allowsEdgeAntialiasing = true

        MainAppContext.shared.feedData.validMoment
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                if let state = self?.state, state != .prompt {
                    self?.setState(state, animated: true)
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
        
        promptLabel.layer.shadowPath = UIBezierPath(rect: promptLabel.bounds).cgPath
        disclaimerLabel.layer.shadowPath = UIBezierPath(rect: disclaimerLabel.bounds).cgPath
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
            return UIView.transition(with: self, duration: 0.3, options: [.transitionCrossDissolve]) { self.setState(newState) }
        }

        let hasValidMoment = MainAppContext.shared.feedData.validMoment.value != nil

        var blurAlpha: CGFloat = 1
        var overlayAlpha: CGFloat = 1
        var mediaHidden = false
        var dayHidden = false
        var promptText = ""
        var buttonText = Localizations.view
        var buttonImage = hasValidMoment ? nil : lockedButtonImage
        var hideDisclaimer = hasValidMoment

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
            buttonImage = nil
            hideDisclaimer = true
        }

        blurView.effect = blurAlpha == .zero ? nil : UIBlurEffect(style: .regular)
        blurView.isUserInteractionEnabled = newState != .unlocked

        overlayStack.alpha = overlayAlpha
        mediaView.isHidden = mediaHidden
        dayOfWeekLabel.isHidden = dayHidden
        promptLabel.text = promptText

        actionButton.setTitle(buttonText, for: .normal)
        actionButton.setImage(buttonImage?.withRenderingMode(.alwaysTemplate), for: .normal)

        if disclaimerLabel.isHidden != hideDisclaimer {
            disclaimerLabel.isHidden = hideDisclaimer
        }

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

    static var momentUnlockDisclaimer: String {
        NSLocalizedString("moment.unlock.disclaimer",
                   value: "To see their moment, share your own",
                 comment: "Text on a locked moment that explains the need to post your own in order to view it.")
    }
}
