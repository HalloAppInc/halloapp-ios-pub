//
//  MomentComposerViewController.swift
//  HalloApp
//
//  Created by Tanveer on 6/12/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import Core
import CoreCommon
import CocoaLumberjackSwift

class MomentComposerViewController: UIViewController, UIScrollViewDelegate {

    let context: MomentContext

    private var media: PendingMedia?
    /// Used to wait for the creation of the media's file path.
    private var mediaLoader: AnyCancellable?

    private lazy var audienceIndicator: UIView = {
        let pill = PillView()
        let image = UIImage(named: "PrivacySettingMyContacts")?.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
        let imageView = UIImageView(image: image)
        let label = UILabel()
        let stack = UIStackView(arrangedSubviews: [imageView, label])

        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.fillColor = .darkGray.withAlphaComponent(0.8)
        imageView.contentMode = .scaleAspectFit

        label.text = PrivacyList.title(forPrivacyListType: .all)
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabel

        stack.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: pill.topAnchor),
            stack.leadingAnchor.constraint(equalTo: pill.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: pill.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: pill.bottomAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 13),
            imageView.heightAnchor.constraint(equalToConstant: 13),
        ])

        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 5, left: 9, bottom: 5, right: 9)
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 5

        return pill
    }()

    /// Displayed when the user taps on `audienceIndicator`
    private var audienceDisclaimerView: UIView?
    private var hideAudienceDisclaimerItem: DispatchWorkItem?

    private lazy var scrollViewContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        view.layer.cornerRadius = NewCameraViewController.Layout.innerRadius(for: .moment)
        view.layer.cornerCurve = .continuous
        return view
    }()

    private lazy var leadingImageScrollView: ScrollableImageView = {
        let view = ScrollableImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var trailingImageScrollView: ScrollableImageView = {
        let view = ScrollableImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var trailingImageLeadingConstraint: NSLayoutConstraint = {
        let constraint = trailingImageScrollView.leadingAnchor.constraint(equalTo: background.centerXAnchor)
        constraint.priority = .defaultHigh
        return constraint
    }()

    private lazy var hideTrailingImageViewConstraint: NSLayoutConstraint = {
        let constraint = trailingImageScrollView.leadingAnchor.constraint(equalTo: scrollViewContainer.trailingAnchor)
        return constraint
    }()

    private lazy var closeTrailingImageButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        button.addTarget(self, action: #selector(pushedCloseTrailingImageButton), for: .touchUpInside)
        return button
    }()

    private(set) lazy var background: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .momentPolaroid
        view.layer.cornerRadius = NewCameraViewController.Layout.cornerRadius(for: .moment)
        view.layer.cornerCurve = .continuous
        return view
    }()

    private lazy var sendButtonContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private(set) lazy var sendButton: CircleButton = {
        let button = CircleButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(UIImage(named: "icon_share"), for: .normal)
        button.setBackgroundColor(.lavaOrange, for: .normal)
        button.setBackgroundColor(.lavaOrange.withAlphaComponent(0.6), for: .disabled)
        button.addTarget(self, action: #selector(sendButtonPushed), for: .touchUpInside)
        button.isEnabled = false
        return button
    }()

    @UserDefault(key: "shown.replace.moment.disclaimer", defaultValue: false)
    private static var hasShownReplacementDisclaimer: Bool

    var onPost: (() -> Void)?
    var onCancel: (() -> Void)?

    init(context: MomentContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
        title = Localizations.newMomentTitle
    }

    required init?(coder: NSCoder) {
        fatalError("MomentComposerViewController coder init not implemented...")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        navigationController?.overrideUserInterfaceStyle = .dark

        let appearance = UINavigationBarAppearance()
        appearance.backgroundColor = .black
        appearance.shadowColor = nil
        appearance.titleTextAttributes = [.font: UIFont.gothamFont(ofFixedSize: 16, weight: .medium)]
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance

        view.addSubview(audienceIndicator)
        view.addSubview(background)
        background.addSubview(scrollViewContainer)

        scrollViewContainer.addSubview(leadingImageScrollView)
        scrollViewContainer.addSubview(trailingImageScrollView)
        trailingImageScrollView.addSubview(closeTrailingImageButton)

        background.addSubview(sendButtonContainer)
        sendButtonContainer.addSubview(sendButton)

        let padding = NewCameraViewController.Layout.padding(for: .moment)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            scrollViewContainer.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: padding),
            scrollViewContainer.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -padding),
            scrollViewContainer.topAnchor.constraint(equalTo: background.topAnchor, constant: padding),
            scrollViewContainer.heightAnchor.constraint(equalTo: scrollViewContainer.widthAnchor),

            leadingImageScrollView.leadingAnchor.constraint(equalTo: scrollViewContainer.leadingAnchor),
            leadingImageScrollView.trailingAnchor.constraint(equalTo: trailingImageScrollView.leadingAnchor),
            leadingImageScrollView.topAnchor.constraint(equalTo: scrollViewContainer.topAnchor),
            leadingImageScrollView.heightAnchor.constraint(equalTo: scrollViewContainer.heightAnchor),

            trailingImageScrollView.trailingAnchor.constraint(equalTo: scrollViewContainer.trailingAnchor),
            trailingImageLeadingConstraint,
            trailingImageScrollView.topAnchor.constraint(equalTo: scrollViewContainer.topAnchor),
            trailingImageScrollView.heightAnchor.constraint(equalTo: scrollViewContainer.heightAnchor),
            hideTrailingImageViewConstraint,

            sendButtonContainer.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            sendButtonContainer.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            sendButtonContainer.topAnchor.constraint(equalTo: leadingImageScrollView.bottomAnchor),
            sendButtonContainer.bottomAnchor.constraint(equalTo: background.bottomAnchor),

            sendButton.centerXAnchor.constraint(equalTo: sendButtonContainer.centerXAnchor),
            sendButton.centerYAnchor.constraint(equalTo: sendButtonContainer.centerYAnchor),
            sendButton.heightAnchor.constraint(equalToConstant: 65),
            sendButton.widthAnchor.constraint(equalToConstant: 65),

            closeTrailingImageButton.leadingAnchor.constraint(equalTo: trailingImageScrollView.frameLayoutGuide.leadingAnchor, constant: 10),
            closeTrailingImageButton.topAnchor.constraint(equalTo: trailingImageScrollView.frameLayoutGuide.topAnchor, constant: 10),

            audienceIndicator.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            audienceIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
        
        navigationItem.setHidesBackButton(true, animated: false)
        let configuration = UIImage.SymbolConfiguration(weight: .bold)
        let image = UIImage(systemName: "xmark", withConfiguration: configuration)?.withRenderingMode(.alwaysTemplate)
        let barButton = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(dismissTapped))

        navigationItem.leftBarButtonItem = barButton
        barButton.tintColor = .white

        let showTap = UITapGestureRecognizer(target: self, action: #selector(audiencePillTapped))
        audienceIndicator.addGestureRecognizer(showTap)

        let hideTap = UITapGestureRecognizer(target: self, action: #selector(hideAudiencePillTapped))
        view.addGestureRecognizer(hideTap)
        hideTap.cancelsTouchesInView = false
    }

    func configure(with media: PendingMedia) {
        DDLogInfo("MomentComposerViewController/configure/start")
        self.media = media

        mediaLoader = media.ready
            .first { $0 }
            .sink { [weak self] _ in
                guard let self = self else {
                    return
                }

                self.leadingImageScrollView.imageView.image = media.image
                self.leadingImageScrollView.sizeImage()

                self.sendButton.isEnabled = true
                self.mediaLoader = nil
            }
    }

    func configure(with results: [CaptureResult], animateTrailing: Bool) {
        for result in results {
            let scrollView = result.isPrimary ? leadingImageScrollView : trailingImageScrollView

            scrollView.imageView.image = result.image.correctlyOrientedImage()
            scrollView.sizeImage()

            if !result.isPrimary {
                updateTrailingImageViewDisplay(show: true, animate: animateTrailing)
            }
        }
    }

    private func updateTrailingImageViewDisplay(show: Bool, animate: Bool) {
        hideTrailingImageViewConstraint.isActive = !show
        leadingImageScrollView.setNeedsLayout()
        trailingImageScrollView.setNeedsLayout()

        if animate {
            return UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: .curveEaseOut) {
                self.view.layoutIfNeeded()
                self.leadingImageScrollView.sizeImage()
                self.trailingImageScrollView.sizeImage()
            }
        }

        view.layoutIfNeeded()
        leadingImageScrollView.sizeImage()
        trailingImageScrollView.sizeImage()
    }

    @objc
    private func pushedCloseTrailingImageButton(_ button: UIButton) {
        updateTrailingImageViewDisplay(show: false, animate: true)
    }

    @objc
    private func dismissTapped(_ button: UIBarButtonItem) {
        mediaLoader = nil

        leadingImageScrollView.imageView.image = nil
        trailingImageScrollView.imageView.image = nil
        hideTrailingImageViewConstraint.isActive = true

        sendButton.isEnabled = false
        onCancel?()
    }

    @objc
    private func sendButtonPushed(_ button: UIButton) {
        DDLogInfo("MomentComposerViewController/send/start")
        sendButton.isEnabled = false
        let media = PendingMedia(type: .image)

        if !hideTrailingImageViewConstraint.isActive, let cropped = cropAndJoinImages() {
            media.image = cropped
        } else if hideTrailingImageViewConstraint.isActive, let cropped = leadingImageScrollView.croppedImage {
            media.image = cropped
        } else {
            DDLogError("MomentComposerViewController/sendButtonPushed/unable to crop images")
            return dismiss(animated: true)
        }

        // becuase we're creating the media object at the time of posting, we have to wait for its file url
        // to be ready. otherwise we'd crash as FeedData assumes there is a valid path.
        mediaLoader = media.ready
            .first { $0 }
            .sink { [weak self] _ in
                self?.post(media: media)
            }
    }

    private func cropAndJoinImages() -> UIImage? {
        guard
            let leading = leadingImageScrollView.croppedImage,
            let trailing = trailingImageScrollView.croppedImage
        else {
            return nil
        }

        let size = CGSize(width: leading.size.height, height: leading.size.height)

        UIGraphicsBeginImageContext(size)
        leading.draw(in: .init(x: 0, y: 0, width: leading.size.width, height: leading.size.height))
        trailing.draw(in: .init(x: leading.size.width, y: 0, width: leading.size.width, height: size.width))

        let result = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return result
    }

    private func post(media: PendingMedia) {
        if MainAppContext.shared.feedData.validMoment.value != nil {
            // user has already posted a moment for the day
            if !Self.hasShownReplacementDisclaimer {
                presentReplacementDisclaimer(mediaToPost: media)
            } else {
                replaceMoment(with: media)
            }
        } else {
            MainAppContext.shared.feedData.postMoment(context: context, media: media)
            onPost?()
        }
    }

    @objc
    private func audiencePillTapped(_ gesture: UITapGestureRecognizer) {
        if audienceDisclaimerView == nil {
            showAudienceDisclaimer()
        } else {
            hideAudienceDisclaimer()
        }
    }

    @objc
    private func hideAudiencePillTapped(_ gesture: UITapGestureRecognizer) {
        if audienceDisclaimerView != nil {
            hideAudienceDisclaimer()
        }
    }

    private func showAudienceDisclaimer() {
        let label = UILabel()
        label.text = Localizations.momentAllContactsDisclaimer
        label.font = .systemFont(forTextStyle: .subheadline, maximumPointSize: 22)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center

        let container = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialDark))
        container.translatesAutoresizingMaskIntoConstraints = false

        let background = UIView()
        background.backgroundColor = .black
        background.translatesAutoresizingMaskIntoConstraints = false

        container.contentView.addSubview(label)
        view.addSubview(container)

        let padding: CGFloat = 12
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.contentView.leadingAnchor, constant: padding),
            label.trailingAnchor.constraint(equalTo: container.contentView.trailingAnchor, constant: -padding),
            label.topAnchor.constraint(equalTo: container.contentView.topAnchor, constant: padding),
            label.bottomAnchor.constraint(equalTo: container.contentView.bottomAnchor, constant: -padding),

            container.topAnchor.constraint(equalTo: audienceIndicator.bottomAnchor, constant: padding),
            container.centerXAnchor.constraint(equalTo: audienceIndicator.centerXAnchor),
            container.widthAnchor.constraint(lessThanOrEqualToConstant: view.bounds.width - 100),
        ])

        container.layer.masksToBounds = true
        container.layer.cornerRadius = 12
        container.layer.cornerCurve = .continuous
        container.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        container.layer.borderWidth = 0.5

        container.transform = .identity.scaledBy(x: 0.2, y: 0.2)
        container.alpha = 0

        audienceDisclaimerView = container

        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
            container.transform = .identity
            container.alpha = 1
        } completion: { [weak self] _ in
            self?.scheduleAudienceDisclaimerHide()
        }
    }

    private func scheduleAudienceDisclaimerHide() {
        let item = DispatchWorkItem { [weak self] in
            self?.hideAudienceDisclaimer()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: item)
        hideAudienceDisclaimerItem = item
    }

    private func hideAudienceDisclaimer() {
        hideAudienceDisclaimerItem?.cancel()
        hideAudienceDisclaimerItem = nil

        UIView.animate(withDuration: 0.65, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5) {
            self.audienceDisclaimerView?.transform = .identity.scaledBy(x: 0.2, y: 0.2)
            self.audienceDisclaimerView?.alpha = 0
        } completion: { [weak self] _ in
            self?.audienceDisclaimerView?.removeFromSuperview()
            self?.audienceDisclaimerView = nil
        }
    }

    private func presentReplacementDisclaimer(mediaToPost: PendingMedia) {
        let alert = UIAlertController(title: Localizations.momentReplacementDisclaimerTitle,
                                    message: Localizations.momentReplacementDisclaimerBody,
                             preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default) { [weak self] _ in
            self?.replaceMoment(with: mediaToPost)
        })

        present(alert, animated: true) {
            Self.hasShownReplacementDisclaimer = true
        }
    }

    private func replaceMoment(with media: PendingMedia) {
        Task {
            do {
                try await MainAppContext.shared.feedData.replaceMoment(media: media)
                DDLogInfo("FeedData/replaceMoment task/replace task finished")
            } catch {
                // not sure if this is sufficient; would like to show some error to the user but the
                // view controller will have been dismissed by this point
                DDLogError("FeedData/replaceMoment task/replace failed with error: \(String(describing: error))")
            }
        }

        onPost?()
    }
}

// MARK: - FeedData extension for posting moments

extension FeedData {
    /// - note: These methods are `@MainActor` since creating new `FeedPost` objects is done using
    ///         the view context.
    @MainActor
    func replaceMoment(media: PendingMedia) async throws {
        guard let current = MainAppContext.shared.feedData.validMoment.value else {
            await MainActor.run { postMoment(context: .normal, media: media) }
            return
        }

        DDLogInfo("FeedData/replaceMoment/start")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            MainAppContext.shared.feedData.retract(post: current) { result in
                switch result {
                case .success(_):
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }

        DDLogInfo("FeedData/replaceMoment/finished retraction of post with id: \(current.id)")
        await MainActor.run { postMoment(context: .normal, media: media) }
    }

    func postMoment(context: MomentContext, media: PendingMedia) {
        DDLogInfo("FeedData/postMoment/start")
        MainAppContext.shared.feedData.post(text: MentionText(collapsedText: "", mentionArray: []),
                                           media: [media],
                                 linkPreviewData: nil,
                                linkPreviewMedia: nil,
                                              to: .feed(.all),
                                   momentContext: context)
    }
}

// MARK: - ScrollableImageView implementation

fileprivate class ScrollableImageView: UIScrollView, UIScrollViewDelegate {

    private(set) lazy var imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self

        clipsToBounds = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bounces = false
        bouncesZoom = false
        maximumZoomScale = 2

        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("ScrollableImageView coder init not implemented...")
    }

    func sizeImage() {
        guard let image = imageView.image else {
            return
        }

        setZoomScale(1, animated: false)

        let size = bounds.size
        let factor = max(size.width / image.size.width, size.height / image.size.height)
        let height = image.size.height * factor
        let width = image.size.width * factor

        let imageViewSize = CGSize(width: width, height: height)
        imageView.frame = CGRect(origin: .zero, size: imageViewSize)
        contentSize = imageViewSize

        center()
    }

    private func center() {
        if contentSize.width > bounds.width {
            contentOffset.x = (contentSize.width - frame.size.width) / 2
        } else if contentSize.height > bounds.height {
            contentOffset.y = (contentSize.height - frame.size.height) / 2
        }
    }

    var croppedImage: UIImage? {
        guard let image = imageView.image else {
            return nil
        }

        let scaleFactor = max(image.size.width / imageView.bounds.size.width, image.size.height / imageView.bounds.size.height)
        let zoomFactor = 1 / zoomScale
        let x = contentOffset.x * scaleFactor * zoomFactor
        let y = contentOffset.y * scaleFactor * zoomFactor

        let width = bounds.size.width * scaleFactor * zoomFactor
        let height = bounds.size.height * scaleFactor * zoomFactor
        let rect = CGRect(x: x, y: y, width: width, height: height).integral

        if let cropped = image.cgImage?.cropping(to: rect) {
            return UIImage(cgImage: cropped)
        }

        return nil
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let currentOffset = scrollView.contentOffset
        targetContentOffset.pointee = currentOffset
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
}

// MARK: - localization

fileprivate extension Localizations {
    static var momentReplacementDisclaimerTitle: String {
        NSLocalizedString("moment.replacement.title",
                   value: "Heads Up",
                 comment: "Title of text displayed the first time the user acts to post a second moment in the same day.")
    }

    static var momentReplacementDisclaimerBody: String {
        NSLocalizedString("moment.replacement.disclaimer",
                   value: "This new moment will replace your previous one.",
                 comment: "Text displayed the first time the user acts to post a second moment in the same day.")
    }

    static var momentAllContactsDisclaimer: String {
        NSLocalizedString("moment.contacts.disclaimer",
                   value: "Your Moment will only be shared with your contacts on HalloApp",
                 comment: "Disclaimer to tell the user that their moments go to all of their contacts on HalloApp.")
    }
}
