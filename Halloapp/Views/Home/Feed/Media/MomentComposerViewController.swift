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

class MomentComposerViewController: UIViewController {

    let context: MomentContext

    private var media: PendingMedia?
    var image: UIImage? {
        didSet { updateImage() }
    }

    private var mediaProcessor: AnyCancellable?

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

    private lazy var imageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.masksToBounds = true
        view.layer.cornerRadius = NewCameraViewController.Layout.innerRadius(for: .moment)
        view.layer.cornerCurve = .continuous
        view.backgroundColor = .black
        return view
    }()

    private(set) lazy var container: UIView = {
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

    /// Used to align the card with the camera on the previous screen.
    private(set) lazy var momentCardTopConstraint = container.topAnchor.constraint(equalTo: view.topAnchor)
    private(set) lazy var momentCardHeightConstraint = container.heightAnchor.constraint(equalToConstant: 200)

    private var hasShownReplacementDisclaimerBefore: Bool {
        get {
            MainAppContext.shared.userDefaults.bool(forKey: "shown.replace.moment.disclaimer")
        }

        set {
            MainAppContext.shared.userDefaults.set(newValue, forKey: "shown.replace.moment.disclaimer")
        }
    }

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
        view.addSubview(container)
        container.addSubview(imageView)
        container.addSubview(sendButtonContainer)
        sendButtonContainer.addSubview(sendButton)

        let padding = NewCameraViewController.Layout.padding(for: .moment)
        let imageViewHeight = imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor)
        momentCardHeightConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            momentCardTopConstraint,
            momentCardHeightConstraint,

            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            imageView.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            imageViewHeight,

            sendButtonContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sendButtonContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sendButtonContainer.topAnchor.constraint(equalTo: imageView.bottomAnchor),
            sendButtonContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            sendButton.centerXAnchor.constraint(equalTo: sendButtonContainer.centerXAnchor),
            sendButton.centerYAnchor.constraint(equalTo: sendButtonContainer.centerYAnchor),
            sendButton.heightAnchor.constraint(equalToConstant: 65),
            sendButton.widthAnchor.constraint(equalToConstant: 65),

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

    private func updateImage() {
        guard let image = image?.correctlyOrientedImage() else {
            return
        }

        let media = PendingMedia(type: .image)
        media.image = image
        self.media = media

        mediaProcessor = media.ready.sink { [weak self] ready in
            guard ready, let url = media.fileURL else {
                return
            }

            ImageServer.shared.prepare(media.type, url: url, shouldStreamVideo: false)
            self?.mediaProcessor = nil
        }

        imageView.image = image
        sendButton.isEnabled = true
    }

    @objc
    private func dismissTapped(_ button: UIBarButtonItem) {
        mediaProcessor?.cancel()
        onCancel?()
    }

    @objc
    private func sendButtonPushed(_ button: UIButton) {
        guard let media = media else {
            return
        }

        sendButton.isEnabled = false

        if MainAppContext.shared.feedData.validMoment.value != nil {
            // user has already posted a moment for the day
            if !hasShownReplacementDisclaimerBefore {
                presentReplacementDisclaimer()
            } else {
                replaceMoment()
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

    private func presentReplacementDisclaimer() {
        let alert = UIAlertController(title: Localizations.momentReplacementDisclaimerTitle,
                                    message: Localizations.momentReplacementDisclaimerBody,
                             preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default) { [weak self] _ in
            self?.replaceMoment()
        })

        present(alert, animated: true) {
            self.hasShownReplacementDisclaimerBefore = true
        }
    }

    private func replaceMoment() {
        guard let media = media else { return }
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
        guard let audience = try? MainAppContext.shared.privacySettings.feedAudience(for: .all) else {
            DDLogError("FeedData/postMoment/unable to get feed audience")
            return
        }

        DDLogInfo("FeedData/postMoment/start")
        MainAppContext.shared.feedData.post(text: MentionText(collapsedText: "", mentionArray: []),
                                           media: [media],
                                 linkPreviewData: nil,
                                linkPreviewMedia: nil,
                                              to: .userFeed,
                                    feedAudience: audience,
                                   momentContext: context)
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
