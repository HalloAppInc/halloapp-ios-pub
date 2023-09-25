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

    private lazy var collectionView: InsetCollectionView = {
        let collectionView = InsetCollectionView()
        let section = InsetCollectionView.defaultLayoutSection
        let edgeInset: CGFloat = 20

        section.contentInsets = .init(top: 15, leading: edgeInset, bottom: 15, trailing: edgeInset)

        let headerItem = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44)),
                                                                    elementKind: UICollectionView.elementKindSectionHeader,
                                                                      alignment: .top)
        let footerItem = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(44)),
                                                                    elementKind: UICollectionView.elementKindSectionFooter,
                                                                      alignment: .bottom)
        section.boundarySupplementaryItems = [headerItem, footerItem]

        let layout = UICollectionViewCompositionalLayout(section: section)
        let configuration = InsetCollectionView.defaultLayoutConfiguration
        layout.configuration = configuration
        collectionView.collectionViewLayout = layout

        collectionView.register(ExistingNetworkCollectionViewHeader.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: ExistingNetworkCollectionViewHeader.reuseIdentifier)
        collectionView.register(ExistingNetworkCollectionViewFooter.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
                                withReuseIdentifier: ExistingNetworkCollectionViewFooter.reuseIdentifier)

        collectionView.data.supplementaryViewProvider = { [weak self] in
            self?.supplementaryViewProvider($0, elementKind: $1, indexPath: $2)
        }

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = nil
        collectionView.alwaysBounceVertical = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.delegate = self

        return collectionView
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

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

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
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            bottomStack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomStack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -OnboardingConstants.bottomButtonBottomDistance),

            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomStack.topAnchor),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let contentHeight = collectionView.contentSize.height
        let difference = collectionView.bounds.height - contentHeight

        if contentHeight > 0, difference > 0 {
            collectionView.contentInset.top = difference / 2
        } else {
            collectionView.contentInset.top = 0
        }
    }

    private func supplementaryViewProvider(_ collectionView: UICollectionView, elementKind: String, indexPath: IndexPath) -> UICollectionReusableView {
        switch elementKind {
        case UICollectionView.elementKindSectionHeader:
            let header = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader,
                                                            withReuseIdentifier: ExistingNetworkCollectionViewHeader.reuseIdentifier,
                                                                            for: indexPath)

            (header as? ExistingNetworkCollectionViewHeader)?.titleLabel.text = Localizations.fellowContactsDescription(n: fellowUserIDs.count)
            return header

        case UICollectionView.elementKindSectionFooter:
            let footer = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionFooter,
                                                            withReuseIdentifier: ExistingNetworkCollectionViewFooter.reuseIdentifier,
                                                                            for: indexPath)

            let casted = footer as? ExistingNetworkCollectionViewFooter
            switch fellowUserIDs.count {
            case 0:
                casted?.label.textAlignment = .center
                casted?.label.text = Localizations.fellowContactsWillArrive
            default:
                casted?.label.textAlignment = .natural
                casted?.label.text = Localizations.contactsPrivacyDisclaimer(n: fellowUserIDs.count)
            }

            return footer

        default:
            return UICollectionReusableView()
        }
    }

    @objc
    private func nextButtonPushed(_ button: UIButton) {
        let preset = Localizations.onboardingPostText
        let length = preset.utf16Extent.length
        let location = length == 0 ? 0 : length - 1

        let composer = ComposerViewController(config: .onboardingPost,
                                              type: .unified,
                                              showDestinationPicker: true,
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
            composer.view.endEditing(true)
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
                if case let .user(userID, _, _) = destination {
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
                                                   mentionText: text,
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

// MARK: - ExistingNetworkCollectionViewHeader implementation

fileprivate class ExistingNetworkCollectionViewHeader: UICollectionReusableView {

    static let reuseIdentifier = "existingNetworkHeader"

    private lazy var vStack: UIStackView = {
        let emojiLabel = UILabel()
        emojiLabel.text = "🤗"
        emojiLabel.font = .systemFont(ofSize: 36)
        emojiLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [emojiLabel, titleLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 10
        return stack
    }()

    private(set) lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = .gothamFont(forTextStyle: .title3, weight: .medium)
        label.numberOfLines = 0
        label.textAlignment = .center
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(vStack)

        NSLayoutConstraint.activate([
            vStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            vStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            vStack.topAnchor.constraint(equalTo: topAnchor),
            vStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("ExistingNetworkCollectionViewHeader coder init not implemented...")
    }
}

// MARK: - ExistingNetworkCollectionViewFooter implementation

fileprivate class ExistingNetworkCollectionViewFooter: UICollectionReusableView {

    static let reuseIdentifier = "existingNetworkFooter"

    private(set) lazy var label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("ExistingNetworkCollectionViewFooter coder init not implemented...")
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
