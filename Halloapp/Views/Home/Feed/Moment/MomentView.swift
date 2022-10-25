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
import CocoaLumberjackSwift

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

        static var smallAvatarDiameter: CGFloat {
            45
        }

        static var footerVerticalPadding: CGFloat {
            9
        }

        static var footerHorizontalPadding: CGFloat {
            20
        }
    }
}

class MomentView: UIView {

    typealias LayoutConstants = FeedPostCollectionViewCell.LayoutConstants

    enum Configuration { case stacked, fullscreen }
    enum State { case locked, unlocked, indeterminate, prompt }
    enum Action { case open(moment: FeedPost), camera, view(profile: UserID), seenBy(moment: FeedPost) }

    let configuration: Configuration

    private(set) var state: State = .locked {
        didSet { statePublisher.send(state) }
    }
    private(set) lazy var statePublisher: CurrentValueSubject<State, Never> = {
        CurrentValueSubject<State, Never>(state)
    }()

    private(set) var feedPost: FeedPost?

    private var cancellables: Set<AnyCancellable> = []
    private var imageLoadingCancellables: Set<AnyCancellable> = []
    private var uploadProgressCancellables: Set<AnyCancellable> = []
    private var downloadProgressCancellable: AnyCancellable?
    private var stateCancellable: AnyCancellable?

    private lazy var imageContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = Layout.innerRadius
        view.layer.cornerCurve = .continuous
        view.layer.masksToBounds = true
        view.layer.allowsEdgeAntialiasing = true
        return view
    }()

    private lazy var leadingImageView: ZoomableImageView = {
        let view = ZoomableImageView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.layer.allowsEdgeAntialiasing = true
        return view
    }()

    private lazy var trailingImageView: ZoomableImageView = {
        let view = ZoomableImageView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.layer.allowsEdgeAntialiasing = true
        return view
    }()

    private lazy var showTrailingImageViewConstraint: NSLayoutConstraint = {
        trailingImageView.widthAnchor.constraint(equalTo: imageContainer.widthAnchor, multiplier: 0.5)
    }()
    
    private lazy var blurView: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = Layout.innerRadius
        view.layer.cornerCurve = .continuous
        view.layer.masksToBounds = true
        view.layer.allowsEdgeAntialiasing = true
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

    private lazy var downloadProgressView: MomentDownloadProgressView = {
        let view = MomentDownloadProgressView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var uploadProgressIndicator: GroupGridProgressView = {
        let indicator = GroupGridProgressView()
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    private lazy var avatarView: AvatarView = {
        let view = AvatarView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(avatarTapped))
        view.addGestureRecognizer(tap)
        return view
    }()

    private(set) lazy var smallAvatarView: AvatarView = {
        let view = AvatarView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = true
        view.layer.shadowColor = UIColor.black.withAlphaComponent(0.1).cgColor
        view.layer.shadowRadius = 2
        view.layer.shadowOffset = .zero
        view.layer.shadowOpacity = 1

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

    private lazy var footerContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layoutMargins = UIEdgeInsets(top: Layout.footerVerticalPadding,
                                         left: Layout.footerHorizontalPadding,
                                       bottom: Layout.footerVerticalPadding,
                                        right: Layout.footerHorizontalPadding)
        return view
    }()
    
    private(set) lazy var footerLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .black.withAlphaComponent(0.9)
        label.font = configuration == .fullscreen ? .handwritingFont(forTextStyle: .title1, pointSizeChange: -2) : .handwritingFont(forTextStyle: .title3)
        label.adjustsFontSizeToFitWidth = true
        label.baselineAdjustment = .alignCenters
        label.numberOfLines = 2
        label.textAlignment = effectiveUserInterfaceLayoutDirection == .rightToLeft ? .left : .right
        return label
    }()

    private lazy var facePileView: FacePileView = {
        let view = FacePileView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.avatarViews.forEach { $0.borderColor = backgroundColor }
        view.addTarget(self, action: #selector(seenByPushed), for: .touchUpInside)
        return view
    }()

    private lazy var openTapGesture: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(target: self, action: #selector(openTapped))
        tap.delegate = self
        return tap
    }()

    weak var delegate: MomentViewDelegate?

    init(configuration: Configuration) {
        self.configuration = configuration
        super.init(frame: .zero)

        layer.cornerRadius = Layout.cornerRadius
        layer.cornerCurve = .circular
        backgroundColor = .momentPolaroid

        addGestureRecognizer(openTapGesture)

        addSubview(gradientView)
        addSubview(downloadProgressView)
        addSubview(imageContainer)
        addSubview(uploadProgressIndicator)
        addSubview(smallAvatarView)
        addSubview(footerContainer)
        addSubview(blurView)
        addSubview(overlayStack)
        imageContainer.addSubview(leadingImageView)
        imageContainer.addSubview(trailingImageView)
        footerContainer.addSubview(footerLabel)
        footerContainer.addSubview(facePileView)

        let hideTrailingImageConstraint = trailingImageView.widthAnchor.constraint(equalToConstant: 0)
        let footerBottomConstraint = footerContainer.bottomAnchor.constraint(equalTo: bottomAnchor)
        let avatarDiameter = Layout.avatarDiameter

        hideTrailingImageConstraint.priority = .defaultHigh
        footerBottomConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            imageContainer.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            imageContainer.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            imageContainer.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            imageContainer.heightAnchor.constraint(equalTo: imageContainer.widthAnchor),

            leadingImageView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            leadingImageView.trailingAnchor.constraint(equalTo: trailingImageView.leadingAnchor, constant: 1), // constant here is to remove aliasing
            leadingImageView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            leadingImageView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),

            trailingImageView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            trailingImageView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            trailingImageView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),
            hideTrailingImageConstraint,

            gradientView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            gradientView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            gradientView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),

            downloadProgressView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            downloadProgressView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),
            downloadProgressView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            downloadProgressView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),

            uploadProgressIndicator.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            uploadProgressIndicator.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            uploadProgressIndicator.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            uploadProgressIndicator.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),

            blurView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            blurView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            blurView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),

            overlayStack.leadingAnchor.constraint(equalTo: blurView.leadingAnchor),
            overlayStack.topAnchor.constraint(greaterThanOrEqualTo: blurView.topAnchor, constant: 10),
            overlayStack.trailingAnchor.constraint(equalTo: blurView.trailingAnchor),
            overlayStack.bottomAnchor.constraint(lessThanOrEqualTo: blurView.bottomAnchor, constant: -10),
            overlayStack.centerYAnchor.constraint(equalTo: blurView.centerYAnchor),

            avatarView.widthAnchor.constraint(equalToConstant: avatarDiameter),
            avatarView.heightAnchor.constraint(equalToConstant: avatarDiameter),

            smallAvatarView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor, constant: 10),
            smallAvatarView.topAnchor.constraint(equalTo: imageContainer.topAnchor, constant: 10),
            smallAvatarView.widthAnchor.constraint(equalToConstant: Layout.smallAvatarDiameter),
            smallAvatarView.heightAnchor.constraint(equalTo: smallAvatarView.widthAnchor),

            footerContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footerContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerContainer.heightAnchor.constraint(equalTo: imageContainer.heightAnchor, multiplier: 0.25),
            footerContainer.topAnchor.constraint(equalTo: imageContainer.bottomAnchor),
            footerBottomConstraint,

            footerLabel.leadingAnchor.constraint(equalTo: footerContainer.layoutMarginsGuide.leadingAnchor, constant: 75),
            footerLabel.trailingAnchor.constraint(equalTo: footerContainer.layoutMarginsGuide.trailingAnchor),
            footerLabel.centerYAnchor.constraint(equalTo: footerContainer.centerYAnchor),
            footerLabel.topAnchor.constraint(greaterThanOrEqualTo: footerContainer.layoutMarginsGuide.topAnchor),
            footerLabel.bottomAnchor.constraint(lessThanOrEqualTo: footerContainer.layoutMarginsGuide.bottomAnchor),

            facePileView.trailingAnchor.constraint(equalTo: footerContainer.layoutMarginsGuide.trailingAnchor),
            facePileView.centerYAnchor.constraint(equalTo: footerContainer.centerYAnchor),
            facePileView.topAnchor.constraint(greaterThanOrEqualTo: footerContainer.topAnchor),
            facePileView.bottomAnchor.constraint(lessThanOrEqualTo: footerContainer.bottomAnchor),
        ])

        layer.shadowOpacity = 0.85
        layer.shadowColor = UIColor.feedPostShadow.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowRadius = 7

        layer.masksToBounds = false
        clipsToBounds = false

        layer.borderWidth = 0.5 / UIScreen.main.scale
        layer.borderColor = UIColor(red: 0.71, green: 0.71, blue: 0.71, alpha: 1.00).cgColor
        // helps with how the border renders when the view is being rotated
        layer.allowsEdgeAntialiasing = true
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Layout.cornerRadius).cgPath
        
        promptLabel.layer.shadowPath = UIBezierPath(rect: promptLabel.bounds).cgPath
        disclaimerLabel.layer.shadowPath = UIBezierPath(rect: disclaimerLabel.bounds).cgPath
        smallAvatarView.layer.shadowPath = UIBezierPath(ovalIn: smallAvatarView.bounds).cgPath
    }

    private func reset() {
        imageLoadingCancellables = []
        uploadProgressCancellables = []
        downloadProgressCancellable = nil
        stateCancellable = nil

        uploadProgressIndicator.setState(.hidden, animated: false)
    }

    func configure(with post: FeedPost?) {
        reset()
        guard let post = post else {
            return configureForPrompt()
        }

        feedPost = post

        if let location = post.locationString {
            footerLabel.text = location
        } else {
            footerLabel.text = DateFormatter.dateTimeFormatterDayOfWeekLong.string(from: post.timestamp)
        }

        avatarView.configure(with: post.userID, using: MainAppContext.shared.avatarStore)
        smallAvatarView.configure(with: post.userID, using: MainAppContext.shared.avatarStore)
        facePileView.configure(with: post)

        setupMedia()

        let statusPublisher = post.publisher(for: \.statusValue)
        let validMomentPublisher = MainAppContext.shared.feedData.validMoment
        var isInitialSetup = true

        stateCancellable = Publishers.CombineLatest(statusPublisher, validMomentPublisher)
            .flatMap { _, validMoment -> AnyPublisher<Void, Never> in
                if let validMomentStatusPublisher = validMoment?.publisher(for: \.statusValue) {
                    return Publishers.CombineLatest3(statusPublisher, validMomentPublisher, validMomentStatusPublisher)
                        .map { _, _, _ in }
                        .eraseToAnyPublisher()
                } else {
                    return Publishers.CombineLatest(statusPublisher, validMomentPublisher)
                        .map { _, _ in }
                        .eraseToAnyPublisher()
                }
            }
            .compactMap { [weak self] in
                return self?.determineState()
            }
            .filter { [weak self] newState in
                guard let self else {
                    return false
                }

                return isInitialSetup || newState != self.state
            }
            .sink { [weak self] newState in
                DDLogInfo("MomentView/stateCancellable/setting [\(newState)] for post id [\(post.id)]; animated [\(!isInitialSetup)]")
                self?.setState(newState, animated: !isInitialSetup)
                isInitialSetup = false
            }
    }

    private func determineState() -> State {
        guard let feedPost else {
            return .prompt
        }

        if feedPost.userID == MainAppContext.shared.userData.userId {
            return .unlocked
        }

        let hasUploadedMoment: Bool
        let state: State

        switch MainAppContext.shared.feedData.validMoment.value {
        case .some(let moment) where moment.status == .sent:
            hasUploadedMoment = true
        default:
            hasUploadedMoment = false
        }

        switch (configuration, feedPost.status) {
        case (.stacked, .seenSending) where hasUploadedMoment:
            fallthrough
        case (.stacked, .seen) where hasUploadedMoment:
            state = .unlocked

        case (.fullscreen, _) where hasUploadedMoment:
            state = .unlocked
        case (.fullscreen, _):
            state = .indeterminate

        case (.stacked, _):
            state = .locked
        }

        return state
    }

    private func setupMedia() {
        guard let (leading, trailing) = arrangedMedia else {
            return
        }

        leading.imagePublisher
            .sink { [weak self] image in
                self?.leadingImageView.image = image
            }
            .store(in: &imageLoadingCancellables)

        trailing?.imagePublisher
            .sink { [weak self] image in
                self?.trailingImageView.image = image
            }
            .store(in: &imageLoadingCancellables)

        selfieMedia?.imagePublisher
            .compactMap { $0 }
            .sink { [weak self] image in
                self?.avatarView.contentMode = .scaleAspectFill
                self?.avatarView.configure(image: image)
            }
            .store(in: &imageLoadingCancellables)

        [leading, trailing]
            .compactMap { $0 }
            .forEach { media in
                media.loadImage()
            }

        showTrailingImageViewConstraint.isActive = trailing != nil
        subscribeToDownloadProgressIfNecessary()
        subscribeToUploadProgress()
    }

    /// The media items in their display order.
    private var arrangedMedia: (leading: FeedMedia, trailing: FeedMedia?)? {
        guard let feedPost else {
            return nil
        }

        let media = feedPost.feedMedia
        if let selfieMedia, let first = media.first {
            return feedPost.isMomentSelfieLeading ? (selfieMedia, first) : (first, selfieMedia)
        }

        if let first = media.first {
            return (first, nil)
        }

        return nil
    }

    /// The media item that corresponds to the front camera.
    private var selfieMedia: FeedMedia? {
        guard let feedPost else {
            return nil
        }

        let media = feedPost.feedMedia
        return media.count == 2 ? media[1] : nil
    }

    @discardableResult
    private func subscribeToDownloadProgressIfNecessary() -> Bool {
        guard let publisher = downloadProgressPublisher else {
            DDLogInfo("MomentView/subscribeToDownloadProgress/not subscribing")
            return false
        }

        DDLogInfo("MomentView/subscribeToDownloadProgress/subscribing")

        downloadProgressCancellable = publisher
            .sink { [weak self] _ in
                guard let self = self, let arranged = self.arrangedMedia else {
                    return
                }

                DDLogInfo("MomentView/subscribeToDownloadProgress/received completion")
                [arranged.leading, arranged.trailing]
                    .compactMap { $0 }
                    .forEach { media in
                        media.loadImage()
                    }

                self.downloadProgressCancellable = nil
                self.setState(self.state, animated: true)

            } receiveValue: { [weak self] progress in
                DDLogInfo("MomentView/subscribeToDownloadProgress/received progress [\(progress)]")
                self?.downloadProgressView.set(progress: progress)
            }

        return true
    }

    private var downloadProgressPublisher: AnyPublisher<Float, Never>? {
        guard let media = feedPost?.feedMedia, let first = media.first else {
            return nil
        }

        let needsDownloads = {
            media.contains { $0.isDownloadRequired }
        }

        guard needsDownloads() else {
            return nil
        }

        var statusPublishers: [AnyPublisher<FeedMedia, Never>] = [Just(first).eraseToAnyPublisher()]
        statusPublishers.append(contentsOf: media.compactMap { $0.mediaStatusDidChange.eraseToAnyPublisher() })

        return Publishers.MergeMany(statusPublishers)
            .receive(on: DispatchQueue.main)
            .prefix { _ in
                needsDownloads()
            }
            .flatMap { _ -> AnyPublisher<Float, Never> in
                let needed = media.reduce(0) { $1.isDownloadRequired ? $0 + 1 : $0 }
                let completed = media.count - needed
                let publishers = media.compactMap { $0.progress }

                return Publishers.MergeMany(publishers)
                    .map { _ -> Float in
                        let total: Float = publishers.reduce(0) { $0 + $1.value }
                        return (total + Float(completed)) / Float(media.count)
                    }
                    .removeDuplicates()
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    private func subscribeToUploadProgress() {
        guard case .stacked = configuration, let feedPost else {
            return
        }

        let indicator = uploadProgressIndicator
        var animateState = false
        var animateProgress = false

        feedPost.publisher(for: \.statusValue)
            .compactMap { FeedPost.Status(rawValue: $0) }
            .sink { status in
                switch status {
                case .sendError:
                    indicator.setState(.failed, animated: animateState)
                case .sending:
                    indicator.setState(.uploading, animated: animateState)
                default:
                    indicator.setState(.hidden, animated: animateState)
                }

                animateState = true
            }
            .store(in: &uploadProgressCancellables)

        MainAppContext.shared.feedData.uploadProgressPublisher(for: feedPost)
            .receive(on: DispatchQueue.main)
            .sink { progress in
                indicator.setProgress(progress, animated: animateProgress)
                animateProgress = true
            }
            .store(in: &uploadProgressCancellables)

        indicator.cancelAction = {
            MainAppContext.shared.feedData.cancelMediaUpload(postId: feedPost.id)
        }

        indicator.deleteAction = {
            MainAppContext.shared.feedData.deleteUnsentPost(postID: feedPost.id)
        }

        indicator.retryAction = {
            MainAppContext.shared.feedData.retryPosting(postId: feedPost.id)
        }
    }

    private func configureForPrompt() {
        feedPost = nil
        leadingImageView.image = nil
        trailingImageView.image = nil

        avatarView.configure(with: MainAppContext.shared.userData.userId, using: MainAppContext.shared.avatarStore)
        setState(.prompt)
    }

    func prepareForReuse() {
        imageLoadingCancellables = []
        downloadProgressCancellable = nil

        avatarView.prepareForReuse()
    }

    func setState(_ newState: State, animated: Bool = false) {
        state = newState
        if animated {
            return UIView.transition(with: self, duration: 0.3, options: [.transitionCrossDissolve]) { self.setState(newState) }
        }

        let hasValidMoment = MainAppContext.shared.feedData.validMoment.value != nil

        var showBlur = true
        var overlayAlpha: CGFloat = 1
        var dayHidden = false
        var promptText = ""
        var buttonText = Localizations.view
        var buttonImage = hasValidMoment ? nil : lockedButtonImage
        var hideDisclaimer = hasValidMoment
        let hideImageContainer = downloadProgressCancellable != nil
        var enableOpenTap = false
        var hideBackgroundGradient = downloadProgressCancellable == nil
        let showFacePile = configuration == .stacked && feedPost?.userID == MainAppContext.shared.userData.userId
        let hideSmallAvatar = configuration == .fullscreen || newState == .prompt

        if let feedPost {
            let name = MainAppContext.shared.contactStore.firstName(for: feedPost.userID,
                                                                     in: MainAppContext.shared.contactStore.viewContext)
            promptText = String(format: Localizations.otherUsersMoment, name)
        }

        switch newState {
        case .locked:
            break
        case .unlocked:
            showBlur = false
            overlayAlpha = 0
            enableOpenTap = true
        case .indeterminate:
            overlayAlpha = 0
        case .prompt:
            showBlur = false
            dayHidden = true
            promptText = Localizations.shareMoment
            buttonText = Localizations.openCamera
            buttonImage = nil
            hideDisclaimer = true
            hideBackgroundGradient = false
        }

        imageContainer.isHidden = hideImageContainer
        downloadProgressView.isHidden = !hideImageContainer
        gradientView.isHidden = hideBackgroundGradient
        smallAvatarView.isHidden = hideSmallAvatar

        blurView.effect = showBlur ? UIBlurEffect(style: .regular) : nil
        blurView.isUserInteractionEnabled = newState != .unlocked

        overlayStack.alpha = overlayAlpha
        promptLabel.text = promptText

        facePileView.isHidden = !showFacePile
        footerLabel.isHidden = dayHidden || showFacePile

        actionButton.setTitle(buttonText, for: .normal)
        actionButton.setImage(buttonImage?.withRenderingMode(.alwaysTemplate), for: .normal)

        openTapGesture.isEnabled = enableOpenTap

        if disclaimerLabel.isHidden != hideDisclaimer {
            disclaimerLabel.isHidden = hideDisclaimer
        }

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

    @objc
    private func openTapped(_ gesture: UITapGestureRecognizer) {
        if let feedPost {
            delegate?.momentView(self, didSelect: .open(moment: feedPost))
        }
    }

    @objc
    private func seenByPushed(_ sender: UIControl) {
        if let feedPost {
            delegate?.momentView(self, didSelect: .seenBy(moment: feedPost))
        }
    }

    func additionalAnimationsForTransition() {
        facePileView.alpha = 0
        uploadProgressIndicator.setState(.hidden, animated: false)
    }
}

// MARK: - UIGestureRecognizerDelegate methods

extension MomentView: UIGestureRecognizerDelegate {

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UITapGestureRecognizer, !facePileView.isHidden {
            return !facePileView.frame.contains(gestureRecognizer.location(in: footerContainer))
        }

        return true
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
    static var otherUsersMoment: String {
        NSLocalizedString("shared.moment",
                   value: "%@’s Moment",
                 comment: "Text placed on the blurred overlay of someone else's moment.")
    }

    static var view: String {
        NSLocalizedString("view.title",
                   value: "View",
                 comment: "Text that indicates a view action.")
    }

    static var shareMoment: String {
        NSLocalizedString("share.moment.prompt",
                   value: "Share a Moment",
                 comment: "Prompt for the user to share a moment.")
    }

    static var openCamera: String {
        NSLocalizedString("open.camera",
                   value: "Open Camera",
                 comment: "Title of the button that opens the camera.")
    }

    static var momentUnlockDisclaimer: String {
        NSLocalizedString("moment.unlock.disclaimer",
                   value: "To see their Moment, share your own",
                 comment: "Text on a locked moment that explains the need to post your own in order to view it.")
    }
}
