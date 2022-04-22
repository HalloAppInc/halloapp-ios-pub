//
//  InviteViewController.swift
//  HalloApp
//
//  Created by Garrett on 3/15/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import MessageUI
import UIKit

enum InviteSection {
    case inviteViaLink
    case contactsWithFriendCount
    case contactsWithoutFriendCount
    case contactsOnHallo
}

let InviteCellReuse = "InviteCellReuse"
let inviteViaLinkCellReuse = "InviteViaLinkCellReuse"

final class InviteViewController: UIViewController, InviteContactViewController {

    private var screenTitle: String?
    private var showDividers: Bool = true
    private var opensInSearch: Bool

    init(manager: InviteManager,
         title: String? = nil,
         showSearch: Bool = true,
         showDividers: Bool = true,
         opensInSearch: Bool = false,
         dismissAction: (() -> Void)?) {
        self.screenTitle = title
        self.showDividers = showDividers
        self.opensInSearch = opensInSearch

        collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(InviteCollectionViewCell.self, forCellWithReuseIdentifier: InviteCellReuse)
        collectionView.register(InviteViaLinkCell.self, forCellWithReuseIdentifier: inviteViaLinkCellReuse)

        inviteManager = manager

        self.dismissAction = dismissAction

        self.searchController = {
            guard showSearch else { return nil }
            let searchResultsController = InviteViewController(manager: manager, showSearch: false, dismissAction: nil)
            let searchController = UISearchController(searchResultsController: searchResultsController)
            searchController.searchResultsUpdater = searchResultsController
            searchController.searchBar.autocapitalizationType = .none
            searchController.searchBar.tintColor = .systemBlue
            searchController.searchBar.searchTextField.placeholder = Localizations.labelSearch
            searchController.obscuresBackgroundDuringPresentation = false
            searchController.hidesNavigationBarDuringPresentation = false
            searchController.definesPresentationContext = true

            // Set the background color we want...
            searchController.searchBar.searchTextField.backgroundColor = .searchBarBg
            // ... then work around the weird extra background layer Apple adds (see https://stackoverflow.com/questions/61364175/uisearchbar-with-a-white-background-is-impossible)
            searchController.searchBar.setSearchFieldBackgroundImage(UIImage(), for: .normal)
            searchController.searchBar.searchTextField.layer.cornerRadius = 10

            return searchController
        }()

        super.init(nibName: nil, bundle: nil)

        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        updateTitle(invitesLeft: inviteManager.isDataCurrent ? inviteManager.numberOfInvitesAvailable: nil)
        navigationItem.titleView = titleLabel

        if dismissAction != nil {
            navigationItem.leftBarButtonItem = .init(image: UIImage(named: "ReplyPanelClose"), style: .plain, target: self, action: #selector(didTapDismiss))
        }
        if searchController != nil {
            navigationItem.searchController = searchController
            navigationItem.hidesSearchBarWhenScrolling = false
        }

        collectionView.dataSource = dataSource
        collectionView.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        searchController?.searchBar.delegate = self

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)

        collectionView.backgroundColor = .primaryBg
        view.addSubview(collectionView)

        busyView.translatesAutoresizingMaskIntoConstraints = false
        busyView.isHidden = true
        view.addSubview(busyView)

        cancellableSet.insert(
            inviteManager.$numberOfInvitesAvailable.sink { [weak self] invites in
                guard let self = self, self.inviteManager.isDataCurrent else { return }
                self.updateTitle(invitesLeft: invites)
            })

        updateLoading(!inviteManager.isDataCurrent)
        cancellableSet.insert(
            inviteManager.$isLoading.sink { [weak self] isLoading in
                self?.updateLoading(isLoading)
            }
        )

        dataSource.apply(makeDataSnapshot(searchString: nil), animatingDifferences: false)

        collectionView.constrain(to: view)
        busyView.constrain([.centerX, .centerY], to: view)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if opensInSearch {
            opensInSearch = false
            // Needs to be dispatched asynchronously otherwise it will have no effect
            DispatchQueue.main.async { [weak searchController] in
                searchController?.searchBar.becomeFirstResponder()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        if itemWidth != view.bounds.width {
            itemWidth = view.bounds.width
        }
    }

    let titleLabel = UILabel()
    let collectionView: UICollectionView
    let busyView = UIActivityIndicatorView(style: .large)

    let inviteManager: InviteManager
    let inviteContactsManager = InviteContactsManager()
    let searchController: UISearchController?

    lazy var dataSource: UICollectionViewDiffableDataSource<InviteSection, AnyHashable> = {
        UICollectionViewDiffableDataSource<InviteSection, AnyHashable>(collectionView: collectionView) { [weak self] collectionView, indexPath, item in
            guard let self = self else { return UICollectionViewCell() }
            let isFirstCell = indexPath.row == 0
            let isLastCell = indexPath.row == collectionView.numberOfItems(inSection: indexPath.section) - 1
            if let inviteViaLinkCell = item.base as? InviteViaLinkRow {
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: inviteViaLinkCellReuse, for: indexPath)
                if let inviteViaLinkCell = cell as? InviteViaLinkCell {
                    inviteViaLinkCell.configure(showDividers: self.showDividers, isFirstCell: isFirstCell, isLastCell: isLastCell, openShareLinkAction: { [weak self] link in
                        self?.inviteViaLink(link)
                    })
                    // todo: cleaner to move this ui config into configure, but couldn't figure how to make it appear properly
                    if self.showDividers, isLastCell {
                        inviteViaLinkCell.layer.shadowColor = UIColor.systemGray5.cgColor
                        inviteViaLinkCell.layer.shadowRadius = 0
                        inviteViaLinkCell.layer.shadowOpacity = 1
                        inviteViaLinkCell.layer.shadowOffset = CGSize(width: 0, height: 1)
                    }
                }
                return cell
            } else if let contact = item.base as? InviteContact {
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: InviteCellReuse, for: indexPath)
                if let itemCell = cell as? InviteCollectionViewCell {
                    var actions = [InviteActionType]()
                    if contact.userID == nil {
                        if self.isIMessageAvailable { actions.append(.sms) }
                        if self.isWhatsAppAvailable { actions.append(.whatsApp) }
                    }
                    itemCell.configure(
                        with: contact,
                        actions: InviteActions(action: { [weak self] action in self?.inviteAction(action, contact: contact) }, types: actions),
                        visitedActions: self.visitedActions[contact] ?? Set(),
                        showDividers: self.showDividers,
                        isTopDividerHidden: indexPath.item == 0,
                        isFirstCell: isFirstCell,
                        isLastCell: isLastCell
                    )
                    if self.showDividers, isLastCell {
                        itemCell.layer.shadowColor = UIColor.systemGray5.cgColor
                        itemCell.layer.shadowRadius = 0
                        itemCell.layer.shadowOpacity = 1
                        itemCell.layer.shadowOffset = CGSize(width: 0, height: 1)
                    }
                }
                return cell
            }
            return UICollectionViewCell()
        }
    }()

    // MARK: Private

    private func inviteViaLink(_ link: String) {
        // nb: link is not used for now
        let shareText = "\(Localizations.shareHalloAppString)"
        let objectsToShare = [shareText]
        let activityVC = UIActivityViewController(activityItems: objectsToShare, applicationActivities: nil)
        present(activityVC, animated: true, completion: nil)
    }

    private let dismissAction: (() -> Void)?
    private var cancellableSet: Set<AnyCancellable> = []

    private var visitedActions = [InviteContact: Set<InviteActionType>]()

    @objc
    private func didTapDismiss() {
        dismissAction?()
    }

    @objc
    private func keyboardWillShow(notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: keyboardFrame.cgRectValue.height, right: 0)
    }

    @objc
    private func keyboardWillHide(notification: Notification) {
        collectionView.contentInset = .zero
    }

    private func updateLoading(_ isLoading: Bool) {
        if isLoading {
            busyView.startAnimating()
            busyView.isHidden = false
            collectionView.isUserInteractionEnabled = false
        } else {
            busyView.startAnimating()
            busyView.isHidden = true
            collectionView.isUserInteractionEnabled = true
        }
    }

    private func updateTitle(invitesLeft: Int?) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 8
        let titleFont = UIFont.gothamFont(ofFixedSize: 15, weight: .semibold)
        let countText: String? = {
            guard let invitesLeft = invitesLeft else { return Localizations.pleaseWait }
            guard invitesLeft < 10000 else { return nil }
            return Localizations.invitesRemaining(invitesLeft)
        }()
        let countAttributedString: NSAttributedString? = {
            guard let countText = countText else { return nil }
            let mutableString = NSMutableAttributedString(
                string: "\n" + countText,
                attributes: [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 13)])
            if let invitesLeft = invitesLeft, let range = countText.range(of: "\(invitesLeft)") {
                mutableString.addAttribute(
                    .font,
                    value: UIFont.systemFont(ofSize: 13, weight: .bold),
                    range: NSRange(range, in: countText))
            }
            return mutableString
        }()

        let titleString = NSMutableAttributedString(
            string: screenTitle ?? Localizations.inviteTitle,
            attributes: [.font: titleFont, .paragraphStyle: paragraphStyle])
        if let countAttributedString = countAttributedString {
            titleString.append(countAttributedString)
        }

        titleLabel.attributedText = titleString
        titleLabel.textAlignment = .center
    }

    private func makeDataSnapshot(searchString: String?) -> NSDiffableDataSourceSnapshot<InviteSection, AnyHashable> {
        var snapshot = NSDiffableDataSourceSnapshot<InviteSection, AnyHashable>()

        let contacts = inviteContactsManager.contacts(searchString: searchString)
        let halloAppUsers = contacts.filter { $0.userID != nil }
        let inviteCandidates = contacts.filter { $0.userID == nil }
        let withFriends = inviteCandidates.filter { ($0.friendCount ?? 0) > 1 }.sorted { $0.friendCount ?? 0 > $1.friendCount ?? 0 }
        let withoutFriends = inviteCandidates.filter { ($0.friendCount ?? 0) <= 1 }

        snapshot.appendSections([.inviteViaLink, .contactsWithFriendCount, .contactsWithoutFriendCount, .contactsOnHallo])

        snapshot.appendItems([InviteViaLinkRow.invite], toSection: .inviteViaLink)
        snapshot.appendItems(withFriends, toSection: .contactsWithFriendCount)
        snapshot.appendItems(withoutFriends, toSection: .contactsWithoutFriendCount)
        snapshot.appendItems(halloAppUsers, toSection: .contactsOnHallo)

        return snapshot
    }

    private var itemWidth: CGFloat = 0 {
        didSet {
            let layout = UICollectionViewFlowLayout()
            let cellHeight = InviteCellView.forSizing.systemLayoutSizeFitting(CGSize(width: itemWidth, height: 0)).height
            layout.itemSize = CGSize(width: itemWidth, height: cellHeight)
            layout.minimumLineSpacing = 0
            layout.minimumInteritemSpacing = 0
            collectionView.setCollectionViewLayout(layout, animated: true)
        }
    }

    func showLoadIndicator(_ isLoading: Bool) {
        busyView.isHidden = !isLoading
        isLoading ? busyView.startAnimating() : busyView.stopAnimating()
        collectionView.isUserInteractionEnabled = !isLoading
    }

    func didInviteContact(_ contact: InviteContact, with action: InviteActionType) {
        var visitedActionsForContact = visitedActions[contact] ?? Set()
        visitedActionsForContact.insert(action)
        visitedActions[contact] = visitedActionsForContact

        collectionView.reloadData()
    }
}

extension InviteViewController: UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        if !showDividers, section == 0 {
            return .zero
        }
        return UIEdgeInsets(top: 0, left: 20, bottom: 15, right: 20)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {

        // check if it's the first cell, which is the static share button
        guard !(indexPath.section == 0 && indexPath.row == 0) else { return }

        guard let contact = dataSource.itemIdentifier(for: indexPath) else { return }
        guard let inviteContact = contact as? InviteContact, inviteContact.userID == nil else { return }

        showInviteContactActionSheet(for: inviteContact)
    }
}

extension InviteViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        dataSource.apply(makeDataSnapshot(searchString: searchController.searchBar.text))  { [weak self] in
            // Cells need to be reloaded in order to update the dividers.
            self?.collectionView.reloadData()
        }
    }
}

extension InviteViewController: UISearchBarDelegate {
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(false, animated: true)
    }

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(true, animated: true)
        searchBar.setCancelButtonTitleIfNeeded()
    }
}

final class InviteViaLinkCell: UICollectionViewCell {

    public func configure(showDividers: Bool = true, isFirstCell: Bool = false, isLastCell: Bool = false, openShareLinkAction: ((String) -> ())?) {
        actionCellView.openShareLink = openShareLinkAction
        actionCellView.configure(showDividers: showDividers, isFirstCell: isFirstCell, isLastCell: isLastCell)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupView() {
        contentView.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        contentView.addSubview(actionCellView)
        actionCellView.translatesAutoresizingMaskIntoConstraints = false
        actionCellView.constrainMargins(to: contentView)
    }

    let actionCellView = ActionCellView()
}

final class ActionCellView: UIView {

    var openShareLink: ((String) -> ())?
    
    private var isFirst: Bool = false
    private var isLast: Bool = false

    func configure(showDividers: Bool, isFirstCell: Bool = false, isLastCell: Bool = false) {
        isFirst = isFirstCell
        isLast = isLastCell
        if !showDividers {
            backgroundColor = .primaryBg
        }
    }

    init() {
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()

        var corner = UIRectCorner()
        if isFirst { corner.insert([.topLeft, .topRight]) }
        if isLast { corner.insert([.bottomLeft, .bottomRight]) }
        roundCorners(corner, radius: 13)
    }

    private func setupView() {
        mainPanel.addSubview(titleLabel)
        mainPanel.addSubview(subtitleLabel)
        addSubview(mainPanel)
        addSubview(inviteViaLinkButton)

        backgroundColor = .systemBackground

        layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        mainPanel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.textColor = .label
        titleLabel.font = .systemFont(forTextStyle: .subheadline, weight: .semibold)
        titleLabel.numberOfLines = 1
        titleLabel.text = Localizations.inviteViaLink
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.textColor = UIColor.label.withAlphaComponent(0.5)
        subtitleLabel.font = .systemFont(forTextStyle: .caption2)
        subtitleLabel.numberOfLines = 1

        let attrStr = NSMutableAttributedString(string: "")

        let shareLinkIcon: UIImage? = {
            return UIImage(named: "InviteShareIcon")?.withTintColor(UIColor.label.withAlphaComponent(0.4))
        }()

        if let icon = shareLinkIcon {
            let iconAttachment = NSTextAttachment(image: icon)
            iconAttachment.bounds = CGRect(x: 0, y: -5, width: 18, height: 18)

            attrStr.append(NSAttributedString(attachment: iconAttachment))
            attrStr.append(NSAttributedString(string: "  " + "https://halloapp.com/dl"))
        }

        subtitleLabel.attributedText = attrStr
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        mainPanel.constrainMargins([.leading, .centerY], to: self)
        mainPanel.topAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.topAnchor).isActive = true
        mainPanel.bottomAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.bottomAnchor).isActive = true

        titleLabel.constrain([.top, .leading, .trailing], to: mainPanel)

        subtitleLabel.constrain([.bottom, .leading, .trailing], to: mainPanel)
        subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2).isActive = true

        inviteViaLinkButton.translatesAutoresizingMaskIntoConstraints = false
        inviteViaLinkButton.constrainMargins([.centerY], to: self)
        inviteViaLinkButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -30).isActive = true
        inviteViaLinkButton.setContentHuggingPriority(.required, for: .horizontal)
    }

    let mainPanel = UIView()
    let titleLabel = UILabel()
    let subtitleLabel = UILabel()

    private lazy var inviteViaLinkButton: UIButton = {
        let button = Self.makeActionButton(title: Localizations.buttonShare)
        button.addTarget(self, action: #selector(didTapInviteViaLinkButton), for: .touchUpInside)
        return button
    }()

    @objc
    private func didTapInviteViaLinkButton() {
        guard let link = subtitleLabel.text else { return }
        openShareLink?(link)
    }

    static func makeActionButton(title: String) -> UIButton {
        let button = UIButton()
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.setTitleColor(UIColor.primaryBlue, for: .normal)
        return button
    }
}

final class InviteCollectionViewCell: UICollectionViewCell {

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        contentView.addSubview(inviteCellView)
        inviteCellView.translatesAutoresizingMaskIntoConstraints = false
        inviteCellView.constrainMargins(to: contentView)

        contentView.addSubview(topDivider)
        topDivider.backgroundColor = UIColor.label.withAlphaComponent(0.07)
        topDivider.translatesAutoresizingMaskIntoConstraints = false
        topDivider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        topDivider.constrainMargins([.top, .trailing], to: contentView)
        topDivider.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    let inviteCellView = InviteCellView()
    let topDivider = UIView()

    func configure( with contact: InviteContact,
                    actions: InviteActions?,
                    visitedActions: Set<InviteActionType>,
                    showDividers: Bool,
                    isTopDividerHidden: Bool,
                    isFirstCell: Bool = false,
                    isLastCell: Bool = false) {
        inviteCellView.configure(with: contact, actions: actions, visitedActions: visitedActions, isFirstCell: isFirstCell, isLastCell: isLastCell)
        if !showDividers {
            inviteCellView.backgroundColor = .primaryBg
            topDivider.isHidden = true
        } else {
            topDivider.isHidden = isTopDividerHidden
        }
    }
}

final class InviteCellView: UIView {

    var action: InviteAction?

    private var isFirst: Bool = false
    private var isLast: Bool = false

    init() {
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        var corner = UIRectCorner()
        if isFirst { corner.insert([.topLeft, .topRight]) }
        if isLast { corner.insert([.bottomLeft, .bottomRight]) }
        roundCorners(corner, radius: 13)
    }

    func configure(with contact: InviteContact, actions: InviteActions?, visitedActions: Set<InviteActionType>, isFirstCell: Bool = false, isLastCell: Bool = false) {
        isFirst = isFirstCell
        isLast = isLastCell

        let isUserAlready = contact.userID != nil

        let secondLine = contact.formattedPhoneNumber
        let thirdLine: String? = {
            guard !isUserAlready else {
                return Localizations.alreadyHalloAppUser
            }
            guard let friendCount = contact.friendCount, friendCount > 1 else {
                return nil
            }
            return Localizations.contactsOnHalloApp(friendCount)
        }()

        nameLabel.text = contact.fullName
        subtitleLabel.text = [secondLine, thirdLine].compactMap({ $0 }).joined(separator: "\n")

        let actionTypes = actions?.types ?? []

        let canInvite = actionTypes.contains(.sms) || actionTypes.contains(.whatsApp)
        inviteButton.isHidden = !canInvite

        let haveInvitedBefore = visitedActions.contains(.sms) || visitedActions.contains(.whatsApp)
        inviteButton.backgroundColor = haveInvitedBefore ? .systemGray : .primaryBlue

        action = actions?.action
        
        layoutSubviews() // needed for rounded corners when reusing cell
    }

    private func setupView() {
        backgroundColor = .systemBackground
        addSubview(mainPanel)
        mainPanel.constrain(to: self)
    }

    private lazy var mainPanel: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ contactInfoPanel, inviteButton ])
        view.axis = .horizontal
        view.alignment = .center
        view.distribution = .fill
        view.spacing = 5

        view.layoutMargins = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var contactInfoPanel: UIView = {
        let view = UIStackView(arrangedSubviews: [ nameLabel, subtitleLabel ])
        view.axis = .vertical
        view.spacing = 3
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }()

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.textColor = .label
        label.font = .systemFont(forTextStyle: .subheadline, weight: .semibold)
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.textColor = UIColor.label.withAlphaComponent(0.5)
        label.font = .systemFont(forTextStyle: .caption2)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var inviteButton: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ inviteLabel ])
        view.axis = .horizontal
        view.alignment = .center
        view.backgroundColor = UIColor.primaryBlue
        view.layer.cornerRadius = 8

        view.layoutMargins = UIEdgeInsets(top: 0, left: 15, bottom: 0, right: 15)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
        return view
    }()

    private lazy var inviteLabel: UILabel = {
        let label = UILabel()
        label.backgroundColor = .clear
        label.numberOfLines = 1 // setContentHuggingPriority will not be respected when set to 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = UIColor.primaryWhiteBlack
        label.text = Localizations.buttonInvite

        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        return label
    }()

    static var forSizing: InviteCellView {
        let cell = InviteCellView()
        cell.nameLabel.text = " "
        cell.subtitleLabel.text = " \n \n "
        return cell
    }
}

extension Localizations {

    static var inviteViaLink: String {
        NSLocalizedString("invite.via.link", value: "Invite via link", comment: "Title of cell at the top of the invite screen")
    }

    static var alreadyHalloAppUser: String {
        NSLocalizedString("invite.already.halloapp.user",
                          value: "Already a HalloApp user",
                          comment: "Displayed below contact name in contact list that is displayed when inviting someone to HalloApp.")
    }

    static var pleaseWait: String {
        NSLocalizedString("invite.please.wait", value: "Please wait...", comment: "Displayed white user is inviting someone.")
    }
    
    static var genericInviteText: String {
        NSLocalizedString("invite.text",
                   value: "Join me on HalloApp – a simple, private, and secure way to stay in touch with friends and family. Get it at https://halloapp.com/dl",
                 comment: "Text of invitation to join HalloApp.")
    }
    
    /// - note: We prefer to get this text from the server. If that's unavailable, we use this value.
    static var specificInviteTextFallback: String {
        NSLocalizedString("invite.text.specific",
                   value: "Hey %1$@, I have an invite for you to join me on HalloApp - a real-relationship network for those closest to me. Use %2$@ to register. Get it at https://halloapp.com/dl",
                 comment: "Text of invitation to join HalloApp. First argument is the invitee's name, second argument is their phone number.")
    }
    
    static var specificInviteTextVariation1: String {
        NSLocalizedString("invite.text.specific.1",
                   value: "Hey %@, I’m on HalloApp. Download to join me https://halloapp.com/install",
                 comment: "Version of an invitation to join HalloApp. The argument is the invitee's name.")
    }
    
    static var specificInviteTextVariation2: String {
        NSLocalizedString("invite.text.specific.2",
                   value: "Hey %@, let’s keep in touch on HalloApp. Download at https://halloapp.com/kit (HalloApp is a new, private social app for close friends and family, with no ads or algorithms).",
                 comment: "Version of an invitation to join HalloApp. The argument is the invitee's name.")
    }
    
    static var specificInviteTextVariation3: String {
        NSLocalizedString("invite.text.specific.3",
                   value: "I am inviting you to install HalloApp. Download for free here: https://halloapp.com/free",
                 comment: "Version of an invitation to join HalloApp.")
    }

    static func outOfInvitesWith(date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .short
        dateFormatter.dateStyle = .medium
        let format = NSLocalizedString("invite.out.of.invites.w.date",
                                       value: "You're out of invites. Please check back after %@",
                                       comment: "Displayed when user does not have any invites left. Parameter is date.")
        return String(format: format, dateFormatter.string(from: date))
    }

    static var inviteErrorTitle: String {
        NSLocalizedString("invite.error.alert.title",
                          value: "Could not invite",
                          comment: "Title of the alert popup that is displayed when something went wrong with inviting a contact to HalloApp.")
    }

    static var inviteErrorMessage: String {
        NSLocalizedString("invite.error.alert.message",
                          value: "Something went wrong. Please try again later.",
                          comment: "Body of the alert popup that is displayed when something went wrong with inviting a contact to HalloApp.")
    }

    static func inviteActionSheetTitle(_ username: String) -> String {
        return String(format: NSLocalizedString("invite.action.sheet.title", value: "Invite %@ via...", comment: "Title of action sheet that allows the user to choose between sms and whatsapp to invite contact"), username)
    }

    static func inviteText(name: String?, number: String?) -> String {
        guard let name = name, let number = number else {
            return Localizations.genericInviteText
        }

        let inviteString = ServerProperties.inviteString ?? Localizations.specificInviteTextFallback
        return String(format: inviteString, name, number)
    }

    static func contactsOnHalloApp(_ count: Int) -> String {
        let format = NSLocalizedString("invite.contact.count",
                                       value: "%d contacts on HalloApp",
                                       comment: "Shows number of current HalloApp users who have this contact in their list")
        return String(format: format, count)
    }

    static var appNameSMS: String {
        NSLocalizedString("invite.app.sms", value: "Messages", comment: "Title for button that launches system SMS app to send invite. As short as possible!")
    }

    static var appNameWhatsApp: String {
        NSLocalizedString("invite.app.whatsapp", value: "WhatsApp", comment: "Title for button that launches WhatsApp to send invite. Should match WhatsApp localization.")
    }

    static func invitesRemaining(_ count: Int) -> String {
        let format = NSLocalizedString("n.invites.remaining", comment: "Indicates how many invites are remaining")
        return String.localizedStringWithFormat(format, count)
    }
}


enum InviteActionType {
    case sms
    case whatsApp
}

typealias InviteAction = (InviteActionType) -> ()

struct InviteActions {
    var action: InviteAction
    var types: [InviteActionType]
}
