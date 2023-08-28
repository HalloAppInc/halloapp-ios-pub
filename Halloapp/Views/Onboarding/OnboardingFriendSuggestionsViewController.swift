//
//  OnboardingFriendSuggestionsViewController.swift
//  HalloApp
//
//  Created by Tanveer on 8/22/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import UIKit
import Combine
import Core
import CoreCommon
import CocoaLumberjackSwift

class OnboardingFriendSuggestionsViewController: UIViewController {

    let onboarder: any Onboarder
    private let dataSource: SuggestionsDataSource

    private var cancellables: Set<AnyCancellable> = []

    private var selectedUsers: Set<UserID> = []
    private var showAllSuggestions = false {
        didSet { makeAndApplySnapshot() }
    }

    private lazy var collectionViewLayout: UICollectionViewLayout = {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.boundarySupplementaryItems = [
            .init(layoutSize: .init(widthDimension: .fractionalWidth(0.95),
                                    heightDimension: .estimated(44)),
                  elementKind: UICollectionView.elementKindSectionFooter,
                  alignment: .bottom),
        ]

        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1),
                                                            heightDimension: .estimated(44)))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: .init(widthDimension: .fractionalWidth(1),
                                                                       heightDimension: .estimated(44)),
                                                     subitems: [item])

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = .init(top: 0, leading: 0, bottom: 10, trailing: 0)

        return UICollectionViewCompositionalLayout(section: section, configuration: configuration)
    }()

    private lazy var collectionViewDataSource: UICollectionViewDiffableDataSource<Int, Item> = {
        let dataSource = UICollectionViewDiffableDataSource<Int, Item>(collectionView: collectionView) { [weak self] in
            self?.cellProvider(collectionView: $0, indexPath: $1, item: $2)
        }
        dataSource.supplementaryViewProvider = { [weak self] in
            self?.supplementaryViewProvider(collectionView: $0, elementKind: $1, indexPath: $2)
        }
        return dataSource
    }()

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: collectionViewLayout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = nil
        collectionView.showsVerticalScrollIndicator = false
        collectionView.alwaysBounceVertical = false
        return collectionView
    }()

    private let headerView: SuggestionHeaderView = {
        let view = SuggestionHeaderView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let fetchingView: FetchingStateView = {
        let view = FetchingStateView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let nextButton: UIButton = {
        let button = OnboardingConstants.AdvanceButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(Localizations.buttonNext, for: .normal)
        return button
    }()

    init(onboarder: any Onboarder) {
        self.onboarder = onboarder
        self.dataSource = SuggestionsDataSource(model: onboarder)
        super.init(nibName: nil, bundle: nil)
    }

    required init(coder: NSCoder) {
        fatalError("OnboardingFriendSuggestionsViewController coder init not implemented...")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .feedBackground

        collectionView.dataSource = collectionViewDataSource
        collectionView.delegate = self
        collectionView.allowsMultipleSelection = true

        collectionView.register(SuggestionCollectionViewCell.self, forCellWithReuseIdentifier: SuggestionCollectionViewCell.reuseIdentifier)
        collectionView.register(ExpanderCollectionViewCell.self, forCellWithReuseIdentifier: ExpanderCollectionViewCell.reuseIdentifier)
        collectionView.register(PrivacyDisclaimerFooterView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
                                withReuseIdentifier: PrivacyDisclaimerFooterView.reuseIdentifier)

        view.addSubview(fetchingView)
        view.addSubview(headerView)
        view.addSubview(collectionView)
        view.addSubview(nextButton)

        NSLayoutConstraint.activate([
            headerView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 50),

            collectionView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 20),
            collectionView.bottomAnchor.constraint(equalTo: nextButton.topAnchor, constant: -20),

            fetchingView.leadingAnchor.constraint(equalTo: collectionView.leadingAnchor),
            fetchingView.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor),
            fetchingView.topAnchor.constraint(equalTo: headerView.topAnchor),
            fetchingView.bottomAnchor.constraint(equalTo: collectionView.bottomAnchor),

            nextButton.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor),
            nextButton.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
            nextButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            nextButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -OnboardingConstants.bottomButtonBottomDistance),
        ])

        nextButton.addTarget(self, action: #selector(nextButtonPushed), for: .touchUpInside)

        var animateChanges = false
        var selectAllUsers = true
        dataSource.$state
            .sink { [weak self] state in
                guard let self else {
                    return
                }

                let suggestions: [Suggestion]

                switch state {
                case .fetched(let fetched) where selectAllUsers:
                    self.selectedUsers = Set(fetched.map { $0.userID })
                    selectAllUsers = false
                    fallthrough
                case .fetched(let fetched):
                    suggestions = fetched
                case .fetching:
                    suggestions = []
                }

                self.makeAndApplySnapshot(from: suggestions)
                self.updateFetchingViewVisibility(fetchState: state, animated: animateChanges)
                animateChanges = true
            }
            .store(in: &cancellables)
    }

    private func sectionProvider(sectionIndex: Int, layoutEnvironment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection? {
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1),
                                                            heightDimension: .estimated(44)))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: .init(widthDimension: .fractionalWidth(1),
                                                                       heightDimension: .estimated(44)),
                                                     subitems: [item])
        let footerItem = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: .init(widthDimension: .fractionalWidth(0.95),
                                                                                       heightDimension: .estimated(44)),
                                                                     elementKind: UICollectionView.elementKindSectionFooter,
                                                                     alignment: .bottom)

        let section = NSCollectionLayoutSection(group: group)
        section.boundarySupplementaryItems = [footerItem]
        section.contentInsets = .init(top: 15, leading: 0, bottom: 10, trailing: 0)

        return section
    }

    private func cellProvider(collectionView: UICollectionView, indexPath: IndexPath, item: Item) -> UICollectionViewCell {
        let cell: UICollectionViewCell
        let numberOfItems = collectionViewDataSource.collectionView(collectionView, numberOfItemsInSection: indexPath.section)
        let lastItemIndex = numberOfItems - 1

        switch item {
        case .suggestion(let suggestion):
            cell = collectionView.dequeueReusableCell(withReuseIdentifier: SuggestionCollectionViewCell.reuseIdentifier, for: indexPath)
            let isFirst = indexPath.row == 0
            let isLast = indexPath.row == lastItemIndex
            let isSelected = selectedUsers.contains(suggestion.userID)

            (cell as? SuggestionCollectionViewCell)?.configure(with: suggestion,
                                                               isSelected: isSelected,
                                                               isFirst: isFirst,
                                                               isLast: isLast)
        case .expander:
            cell = collectionView.dequeueReusableCell(withReuseIdentifier: ExpanderCollectionViewCell.reuseIdentifier, for: indexPath)
        }

        return cell
    }

    private func supplementaryViewProvider(collectionView: UICollectionView, elementKind: String, indexPath: IndexPath) -> UICollectionReusableView? {
        let view: UICollectionReusableView?

        switch elementKind {
        case UICollectionView.elementKindSectionFooter:
            view = collectionView.dequeueReusableSupplementaryView(ofKind: elementKind,
                                                                   withReuseIdentifier: PrivacyDisclaimerFooterView.reuseIdentifier,
                                                                   for: indexPath)
        default:
            view = nil
        }

        return view
    }

    private func makeAndApplySnapshot(from suggestions: [Suggestion]? = nil) {
        let suggestions = suggestions ?? dataSource.suggestions
        var snapshot = NSDiffableDataSourceSnapshot<Int, Item>()
        let items: [Item]

        if !showAllSuggestions {
            items = suggestions
                .prefix(5)
                .map { Item.suggestion($0) }
        } else {
            items = suggestions.map { Item.suggestion($0) }
        }

        snapshot.appendSections([0])
        snapshot.appendItems(items, toSection: 0)

        if items.count != suggestions.count {
            snapshot.appendSections([1])
            snapshot.appendItems([.expander], toSection: 1)
        }

        collectionViewDataSource.apply(snapshot)
    }

    private func updateFetchingViewVisibility(fetchState: SuggestionsDataSource.State, animated: Bool) {
        if animated {
            return UIView.transition(with: view, duration: 0.45, options: [.transitionCrossDissolve]) {
                self.updateFetchingViewVisibility(fetchState: fetchState, animated: false)
            }
        }

        let collectionViewAlpha: CGFloat
        let fetchViewAlpha: CGFloat
        var numberOfSuggestions = 0

        switch fetchState {
        case .fetching:
            collectionViewAlpha = .zero
            fetchViewAlpha = 1
        case .fetched(let suggestions):
            collectionViewAlpha = 1
            fetchViewAlpha = .zero
            numberOfSuggestions = suggestions.count
        }

        collectionView.alpha = collectionViewAlpha
        headerView.alpha = collectionViewAlpha
        fetchingView.alpha = fetchViewAlpha
        headerView.configure(numberOfSuggestions: numberOfSuggestions)
    }

    @objc
    private func nextButtonPushed(_ button: UIButton) {
        if let viewController = onboarder.nextViewController() {
            navigationController?.setViewControllers([viewController], animated: true)
        }
    }
}

// MARK: - UICollectionViewDelegate

extension OnboardingFriendSuggestionsViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let cell = collectionView.cellForItem(at: indexPath),
              let item = collectionViewDataSource.itemIdentifier(for: indexPath) else {
            return
        }

        switch item {
        case .suggestion(let suggestion):
            selectedUsers.insert(suggestion.userID)
            (cell as? SuggestionCollectionViewCell)?.setSelected(true)
        case .expander:
            showAllSuggestions = true
        }
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard let cell = collectionView.cellForItem(at: indexPath) as? SuggestionCollectionViewCell,
              let item = collectionViewDataSource.itemIdentifier(for: indexPath) else {
            return
        }

        switch item {
        case .suggestion(let suggestion):
            selectedUsers.remove(suggestion.userID)
            cell.setSelected(false)
        default:
            break
        }
    }
}

// MARK: - SuggestionsDataSource

@MainActor
fileprivate class SuggestionsDataSource {

    enum State { case fetching, fetched([Suggestion]) }

    private let model: OnboardingModel
    @Published private(set) var state: State = .fetching

    var suggestions: [Suggestion] {
        if case let .fetched(suggestions) = state {
            return suggestions
        }

        return []
    }

    init(model: OnboardingModel) {
        self.model = model

        Task {
            let suggestions = await withTaskGroup(of: Suggestion?.self, returning: [Suggestion].self) { group in
                let suggestionUserIDs = await model.friendSuggestions
                let ownUserID = MainAppContext.shared.userData.userId
                DDLogInfo("SuggestionsDataSource/fetching profiles for \(suggestionUserIDs.count) users")

                for userID in suggestionUserIDs {
                    group.addTask(priority: .userInitiated) { [weak self] in
                        await self?.suggestion(for: userID)
                    }
                }

                return await group
                    .compactMap { $0 }
                    .filter { $0.userID != ownUserID }
                    .reduce(into: [Suggestion]()) {
                        $0.append($1)
                    }
            }

            state = .fetched(suggestions)
        }
    }

    private func suggestion(for userID: UserID) async -> Suggestion? {
        await withCheckedContinuation { continuation in
            MainAppContext.shared.coreService.userProfile(userID: userID) { result in
                switch result {
                case .success(let serverProfile):
                    let suggestion = Suggestion(serverProfile: serverProfile)
                    DDLogInfo("SuggestionsDataSource/suggestion-for-userID/fetched profile")
                    continuation.resume(returning: suggestion)
                case .failure(let error):
                    DDLogError("SuggestionsDataSource/suggestion-for-userID/fetch failed with error \(String(describing: error))")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - Item

fileprivate enum Item: Hashable {
    case suggestion(Suggestion)
    case expander
}

// MARK: - Suggestion

fileprivate struct Suggestion: Hashable {

    let userID: UserID
    let name: String
    let username: String

    init(serverProfile: Server_HalloappUserProfile) {
        self.userID = UserID(serverProfile.uid)
        self.name = serverProfile.name
        self.username = serverProfile.username
    }

    init(userID: UserID, name: String, username: String) {
        self.userID = userID
        self.name = name
        self.username = username
    }
}

// MARK: - SuggestionCollectionViewCell

fileprivate class SuggestionCollectionViewCell: UICollectionViewCell {

    static let reuseIdentifier = "suggestionCell"

    private let avatarView: AvatarView = {
        let view = AvatarView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.font = .scaledSystemFont(ofSize: 16)
        return label
    }()

    private let usernameLabel: UILabel = {
        let label = UILabel()
        label.font = .scaledSystemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        return label
    }()

    private let selectionImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.preferredSymbolConfiguration = .init(pointSize: 18, weight: .medium)
        imageView.tintColor = .systemBlue
        return imageView
    }()

    private let separator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .separator
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .feedPostBackground

        contentView.layoutMargins = UIEdgeInsets(top: 11, left: 11, bottom: 11, right: 11)

        contentView.layer.cornerCurve = .continuous
        contentView.layer.cornerRadius = 15

        let stack = UIStackView(arrangedSubviews: [nameLabel, usernameLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 3

        contentView.addSubview(avatarView)
        contentView.addSubview(stack)
        contentView.addSubview(selectionImageView)
        contentView.addSubview(separator)

        let avatarHeight = avatarView.widthAnchor.constraint(equalToConstant: 32)
        avatarHeight.priority = .defaultHigh

        NSLayoutConstraint.activate([
            avatarHeight,
            avatarView.heightAnchor.constraint(equalTo: avatarView.widthAnchor, multiplier: 1),
            avatarView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            avatarView.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            stack.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            stack.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.trailingAnchor.constraint(equalTo: selectionImageView.leadingAnchor, constant: -10),

            selectionImageView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor, constant: -10),
            selectionImageView.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor),
            selectionImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            selectionImageView.widthAnchor.constraint(equalToConstant: 22),
            selectionImageView.heightAnchor.constraint(equalTo: selectionImageView.widthAnchor, multiplier: 1),

            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
        ])
    }

    required init(coder: NSCoder) {
        fatalError("SuggestionCollectionViewCell coder init not implemented...")
    }

    func configure(with suggestion: Suggestion, isSelected: Bool, isFirst: Bool = false, isLast: Bool = false) {
        nameLabel.text = suggestion.name
        usernameLabel.text = suggestion.username
        avatarView.configure(with: suggestion.userID, using: MainAppContext.shared.avatarStore)

        var cornerMask = CACornerMask()

        if isFirst {
            cornerMask.insert(.layerMinXMinYCorner)
            cornerMask.insert(.layerMaxXMinYCorner)
        }

        if isLast {
            cornerMask.insert(.layerMinXMaxYCorner)
            cornerMask.insert(.layerMaxXMaxYCorner)
        }

        contentView.layer.maskedCorners = cornerMask
        separator.isHidden = isLast

        setSelected(isSelected)
    }

    func setSelected(_ isSelected: Bool) {
        selectionImageView.image = isSelected ? UIImage(systemName: "checkmark.circle.fill") : UIImage(systemName: "circle")
    }
}

// MARK: - ExpanderCollectionViewCell

fileprivate class ExpanderCollectionViewCell: UICollectionViewCell {

    static let reuseIdentifier = "expanderCell"

    private let label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .scaledSystemFont(ofSize: 17)
        label.textColor = .systemBlue
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layoutMargins = UIEdgeInsets(top: 11, left: 11, bottom: 11, right: 11)

        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            label.topAnchor.constraint(equalTo: contentView.layoutMarginsGuide.topAnchor),
            label.bottomAnchor.constraint(equalTo: contentView.layoutMarginsGuide.bottomAnchor),
        ])

        label.text = Localizations.seeAll
    }

    required init(coder: NSCoder) {
        fatalError()
    }
}

// MARK: - SuggestionHeaderView

fileprivate class SuggestionHeaderView: UIView {

    private let emojiLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 33)
        label.text = "🤗"
        return label
    }()

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .scaledGothamFont(ofSize: 18, weight: .medium, scalingTextStyle: .footnote)
        label.numberOfLines = 0
        label.textAlignment = .center
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .feedBackground

        addSubview(emojiLabel)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            emojiLabel.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            emojiLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emojiLabel.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
            emojiLabel.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),

            titleLabel.topAnchor.constraint(equalTo: emojiLabel.bottomAnchor, constant: 5),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    required init(coder: NSCoder) {
        fatalError("SuggestionHeaderView coder init not implemented...")
    }

    func configure(numberOfSuggestions: Int) {
        titleLabel.text = Localizations.registeredContacts(n: numberOfSuggestions)
    }
}

// MARK: - PrivacyDisclaimerFooterView

fileprivate class PrivacyDisclaimerFooterView: UICollectionReusableView {

    static let reuseIdentifier = "privacyFooter"

    private let label: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .scaledSystemFont(ofSize: 13, scalingTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            label.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            label.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
        ])

        label.text = Localizations.friendsPrivacyDisclaimer
    }

    required init(coder: NSCoder) {
        fatalError("PrivacyDisclaimerFooterView coder init not implemented...")
    }
}

// MARK: - FetchingStateView

fileprivate class FetchingStateView: UIView {

    let indicatorView: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .medium)
        return view
    }()

    private let label: UILabel = {
        let label = UILabel()
        label.font = .scaledGothamFont(ofSize: 20, weight: .medium)
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        let stack = UIStackView(arrangedSubviews: [indicatorView, label])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 15

        addSubview(stack)

        let priority = UILayoutPriority(999)
        label.setContentCompressionResistancePriority(priority, for: .horizontal)
        label.setContentCompressionResistancePriority(priority, for: .vertical)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        label.text = Localizations.loadingSuggestions
        indicatorView.startAnimating()
    }

    required init(coder: NSCoder) {
        fatalError()
    }
}

// MARK: - Localization

extension Localizations {

    fileprivate static func registeredContacts(n: Int) -> String {
        let format = NSLocalizedString("n.fellow.contacts",
                                       comment: "Number of contacts that are already registered on HalloApp.")
        return String.localizedStringWithFormat(format, n)
    }

    static var friendsPrivacyDisclaimer: String {
        NSLocalizedString("friends.privacy.disclaimer",
                          value: "People you added will be able to see your posts shared with all HalloApp friends.",
                          comment: "Disclaimer telling users that their posts can be seen by their friends.")
    }

    static var seeAll: String {
        NSLocalizedString("see.all",
                          value: "See All",
                          comment: "Title of a button that displays all results.")
    }

    static var loadingSuggestions: String {
        NSLocalizedString("loading.suggestions",
                          value: "Loading Suggestions",
                          comment: "Shown to the user when suggestions are being loaded.")
    }
}
