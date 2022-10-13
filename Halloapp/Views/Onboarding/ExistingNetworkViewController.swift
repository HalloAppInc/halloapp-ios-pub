//
//  ExistingNetworkViewController.swift
//  HalloApp
//
//  Created by Tanveer on 8/18/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import UIKit
import Core
import CoreCommon
import CocoaLumberjackSwift

class ExistingNetworkViewController: UIViewController, UserActionHandler {

    let onboardingManager: OnboardingManager
    let fellowUserIDs: [UserID]

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentInset = UIEdgeInsets(top: 50, left: 0, bottom: 20, right: 0)
        scrollView.showsVerticalScrollIndicator = false
        return scrollView
    }()

    private lazy var vStack: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [titleStack, collectionView, collectionViewFooterLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        stack.spacing = 10

        stack.setCustomSpacing(fellowUserIDs.count == 0 ? 10 : 20, after: titleStack)
        stack.setCustomSpacing(90, after: collectionViewFooterLabel)
        return stack
    }()

    private lazy var titleStack: UIStackView = {
        let emojiLabel = UILabel()
        emojiLabel.text = "🤗"
        emojiLabel.font = .systemFont(ofSize: 36)
        emojiLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [emojiLabel, titleLabel])
        stack.axis = .vertical
        stack.spacing = 10
        return stack
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = .gothamFont(forTextStyle: .title3, weight: .medium)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = Localizations.fellowContactsDescription(n: fellowUserIDs.count)
        return label
    }()

    private lazy var collectionViewHeightConstraint: NSLayoutConstraint = {
        let constraint = collectionView.heightAnchor.constraint(equalToConstant: 50)
        constraint.priority = .defaultHigh
        return constraint
    }()

    private lazy var collectionView: InsetCollectionView = {
        let collectionView = InsetCollectionView()

        let section = InsetCollectionView.defaultLayoutSection
        section.contentInsets = .zero
        let layout = UICollectionViewCompositionalLayout(section: section)
        let config = InsetCollectionView.defaultLayoutConfiguration
        layout.configuration = config
        collectionView.collectionViewLayout = layout

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = nil
        collectionView.clipsToBounds = false
        collectionView.alwaysBounceVertical = false
        collectionView.bounces = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.delegate = self

        return collectionView
    }()

    private lazy var collectionViewFooterLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0

        switch fellowUserIDs.count {
        case 0:
            label.textAlignment = .center
            label.text = Localizations.fellowContactsWillArrive
        default:
            label.text = Localizations.contactsPrivacyDisclaimer(n: fellowUserIDs.count)
        }

        return label
    }()

    private lazy var bottomStack: UIStackView = {
        let label = UILabel()
        label.text = "🐣"
        label.font = .systemFont(ofSize: 36)

        let stack = UIStackView(arrangedSubviews: [label, bottomLabel, nextButton])
        let padding = OnboardingConstants.bottomButtonPadding
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: padding, left: 45, bottom: padding, right: 45)
        stack.alignment = .center
        stack.spacing = 10
        stack.setCustomSpacing(20, after: bottomLabel)
        return stack
    }()

    private lazy var bottomLabel: UILabel = {
        let label = UILabel()
        label.font = .gothamFont(forTextStyle: .title3, pointSizeChange: -4, weight: .medium, maximumPointSize: 33)
        label.textAlignment = .center
        label.text = fellowUserIDs.count == 0 ? Localizations.createFirstPostAndInvite : Localizations.createFirstPost
        label.numberOfLines = 0
        return label
    }()

    private lazy var nextButton: RoundedRectChevronButton = {
        let button = RoundedRectChevronButton()
        button.backgroundTintColor = .lavaOrange
        button.setTitle(Localizations.buttonNext, for: .normal)
        button.tintColor = .white
        button.contentEdgeInsets = OnboardingConstants.bottomButtonInsets
        let imageInset: CGFloat = 12

        button.addTarget(self, action: #selector(nextButtonPushed), for: .touchUpInside)
        return button
    }()

    init(onboardingManager: OnboardingManager, userIDs: [UserID]) {
        self.onboardingManager = onboardingManager
        self.fellowUserIDs = userIDs
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("FellowContactsViewController coder init not implemented...")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        DDLogInfo("FellowContactsViewController/viewDidLoad with [\(fellowUserIDs.count)] contacts")
        view.backgroundColor = .feedBackground
        navigationController?.setNavigationBarHidden(false, animated: false)

        view.addSubview(bottomStack)
        view.addSubview(scrollView)
        scrollView.addSubview(vStack)

        let vStackCenterYConstraint = vStack.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        vStackCenterYConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            bottomStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -OnboardingConstants.bottomButtonBottomDistance),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomStack.topAnchor),

            vStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            vStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            vStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            vStack.topAnchor.constraint(greaterThanOrEqualTo: scrollView.topAnchor),
            vStack.bottomAnchor.constraint(lessThanOrEqualTo: scrollView.bottomAnchor),
            vStackCenterYConstraint,

            collectionViewHeightConstraint,
        ])

        buildCollectionView()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // we want to display all items in the collection view without scrolling
        // (there will be at most 4 items in the collection view)
        collectionViewHeightConstraint.constant = .greatestFiniteMagnitude
        collectionView.layoutIfNeeded()
        collectionViewHeightConstraint.constant = collectionView.contentSize.height
    }

    private func buildCollectionView() {
        collectionView.apply(InsetCollectionView.Collection {
            InsetCollectionView.Section {

                for id in fellowUserIDs {
                    InsetCollectionView.Item(style: .user(id: id, menu: {
                        HAMenu.menu(for: id,
                                options: [.viewProfile, .safetyNumber, .favorite, .block],
                                handler: { [weak self] in self?.handle(action: $0) })
                    }))
                }
            }
        }
        .separators())
    }

    @objc
    private func nextButtonPushed(_ button: UIButton) {
        let preset = Localizations.onboardingPostText
        let length = preset.utf16Extent.length
        let location = length == 0 ? 0 : length - 1

        let composer = ComposerViewController(config: .onboardingPost,
                                                type: .unified,
                                               input: .init(text: preset, mentions: [:], selectedRange: NSMakeRange(location, 0)),
                                               media: [],
                                           voiceNote: nil) { viewController, result, tappedShare in

            if tappedShare {
                self.showDestinationPicker(result: result)
            } else {
                self.navigationController?.popViewController(animated: true)
            }
        }

        composer.onCancel = { [onboardingManager] in
            onboardingManager.didCompleteOnboardingFlow()
        }

        navigationController?.pushViewController(composer, animated: true)
    }

    private func showDestinationPicker(result: ComposerResult) {
        let picker = DestinationPickerViewController(config: .composer, destinations: result.destinations) { viewController, destinations in
            guard !destinations.isEmpty else {
                viewController.navigationController?.popViewController(animated: true)
                return
            }

            for destination in destinations {
                if case let .contact(userID, _, _) = destination {
                    self.sendChat(to: userID, with: result)
                } else {
                    self.createPost(for: destination, with: result)
                }
            }

            self.onboardingManager.didCompleteOnboardingFlow()
        }

        navigationController?.pushViewController(picker, animated: true)
    }

    private func sendChat(to userID: UserID, with result: ComposerResult) {
        guard let text = result.text else {
            return
        }

        let recipient: ChatMessageRecipient = .oneToOneChat(toUserId: userID, fromUserId: AppContext.shared.userData.userId)
        MainAppContext.shared.chatData.sendMessage(chatMessageRecipient: recipient,
                                                                   text: text.trimmed().collapsedText,
                                                                  media: result.media,
                                                                  files: [],
                                                        linkPreviewData: result.linkPreviewData,
                                                       linkPreviewMedia: result.linkPreviewMedia,
                                                             feedPostId: nil,
                                                     feedPostMediaIndex: 0,
                                                     chatReplyMessageID: nil,
                                               chatReplyMessageSenderID: nil,
                                             chatReplyMessageMediaIndex: 0)
    }

    private func createPost(for destination: ShareDestination, with result: ComposerResult) {
        guard let text = result.text else {
            return
        }

        MainAppContext.shared.feedData.post(text: text,
                                           media: result.media,
                                 linkPreviewData: result.linkPreviewData,
                                linkPreviewMedia: result.linkPreviewMedia,
                                              to: destination)
    }
}

// MARK: - UICollectionViewDelegate methods

extension ExistingNetworkViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        return false
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        return false
    }
}

// MARK: - Localization

extension Localizations {

    static func fellowContactsDescription(n: Int) -> String {
        let format = NSLocalizedString("n.fellow.contacts", comment: "Number of contacts that are already on HalloApp.")
        return String.localizedStringWithFormat(format, n)
    }

    static func contactsPrivacyDisclaimer(n: Int) -> String {
        let format = NSLocalizedString("n.contacts.privacy.disclaimer",
                              comment: "Explains that the listed contacts will be able to see posts that are shared with all contacts")
        return String.localizedStringWithFormat(format, n)
    }

    static var createFirstPost: String {
        NSLocalizedString("create.your.first.post.1",
                   value: "Create your first post",
                 comment: "Prompt for the user to create their first post.")
    }

    static var createFirstPostAndInvite: String {
        NSLocalizedString("create.your.first.post.2",
                   value: "Create your first post and invite friends to see it",
                 comment: "Prompt for the user to create their first post.")
    }

    static var fellowContactsWillArrive: String {
        NSLocalizedString("fellow.contacts.will.arrive",
                   value: "Your phone contacts that register with HalloApp will appear here automatically.",
                 comment: "Explains that as more contacts join the app, they will appear in this list automatically.")
    }

    static var onboardingPostText: String {
        NSLocalizedString("onboarding.post.text",
                   value: "Hey there! I’m using HalloApp.",
                 comment: "Preset text for the composer when the user is creating their first post.")
    }
}
