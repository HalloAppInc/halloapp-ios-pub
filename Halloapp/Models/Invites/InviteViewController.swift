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
import MessageUI
import UIKit

enum InviteSection {
    case contactsWithFriendCount
    case contactsWithoutFriendCount
    case contactsOnHallo
}

let InviteCellReuse = "InviteCellReuse"

final class InviteViewController: UIViewController {

    init(manager: InviteManager, showSearch: Bool = true, dismissAction: (() -> Void)?) {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.register(InviteCollectionViewCell.self, forCellWithReuseIdentifier: InviteCellReuse)

        inviteManager = manager

        self.dismissAction = dismissAction

        self.searchController = {
            guard showSearch else { return nil }
            let searchResultsController = InviteViewController(manager: manager, showSearch: false, dismissAction: nil)
            let searchController = UISearchController(searchResultsController: searchResultsController)
            searchController.searchResultsUpdater = searchResultsController
            searchController.searchBar.autocapitalizationType = .none
            searchController.searchBar.tintColor = .systemBlue
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

    lazy var dataSource: UICollectionViewDiffableDataSource<InviteSection, InviteContact> = {
        UICollectionViewDiffableDataSource<InviteSection, InviteContact>(collectionView: collectionView) { [weak self] collectionView, indexPath, contact in
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: InviteCellReuse, for: indexPath)
            if let self = self, let itemCell = cell as? InviteCollectionViewCell {
                let actions: [InviteActionType] = {
                    guard contact.userID == nil else { return [] }
                    guard self.isWhatsAppInstalled else { return [.sms] }
                    return [.sms, .whatsApp]
                }()
                itemCell.configure(
                    with: contact,
                    actions: InviteActions(
                        action: { [weak self] action in self?.inviteAction(action, contact: contact)},
                        types: actions),
                    visitedActions: self.visitedActions[contact] ?? Set(),
                    isTopDividerHidden: indexPath.item == 0)
            }
            return cell
        }
    }()

    // MARK: Private

    private let isWhatsAppInstalled: Bool = {
        guard let url = URL(string: "whatsapp://app") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }()

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
            string: Localizations.inviteTitle,
            attributes: [.font: titleFont, .paragraphStyle: paragraphStyle])
        if let countAttributedString = countAttributedString {
            titleString.append(countAttributedString)
        }

        titleLabel.attributedText = titleString
        titleLabel.textAlignment = .center
    }

    private func makeDataSnapshot(searchString: String?) -> NSDiffableDataSourceSnapshot<InviteSection, InviteContact> {
        var snapshot = NSDiffableDataSourceSnapshot<InviteSection, InviteContact>()

        let contacts = inviteContactsManager.contacts(searchString: searchString)
        let halloAppUsers = contacts.filter { $0.userID != nil }
        let inviteCandidates = contacts.filter { $0.userID == nil }
        let withFriends = inviteCandidates.filter { ($0.friendCount ?? 0) > 1 }.sorted { $0.friendCount ?? 0 > $1.friendCount ?? 0 }
        let withoutFriends = inviteCandidates.filter { ($0.friendCount ?? 0) <= 1 }

        snapshot.appendSections([.contactsWithFriendCount, .contactsWithoutFriendCount, .contactsOnHallo])

        snapshot.appendItems(withFriends, toSection: .contactsWithFriendCount)
        snapshot.appendItems(withoutFriends, toSection: .contactsWithoutFriendCount)
        snapshot.appendItems(halloAppUsers, toSection: .contactsOnHallo)

        return snapshot
    }

    private func redeemInvite(for contact: InviteContact, completion: ((InviteResult) -> Void)?) {
        busyView.isHidden = false
        busyView.startAnimating()
        collectionView.isUserInteractionEnabled = false
        DDLogInfo("InviteViewController/redeem/\(contact.normalizedPhoneNumber)/start")
        inviteManager.redeemInviteForPhoneNumber(contact.normalizedPhoneNumber) { [weak self] result in
            DDLogInfo("InviteViewController/redeem/\(contact.normalizedPhoneNumber)/result [\(result)]")
            self?.collectionView.isUserInteractionEnabled = true
            self?.busyView.stopAnimating()
            self?.busyView.isHidden = true
            completion?(result)
        }
    }

    private func inviteAction(_ action: InviteActionType, contact: InviteContact) {
        guard proceedIfConnected() else { return }
        switch action {
        case .sms:
            smsAction(contact: contact)
        case .whatsApp:
            whatsAppAction(contact: contact)
        }

        var visitedActionsForContact = visitedActions[contact] ?? Set()
        visitedActionsForContact.insert(action)
        visitedActions[contact] = visitedActionsForContact

        collectionView.reloadData()
    }

    private func smsAction(contact: InviteContact) {
        DDLogInfo("InviteViewController/sms/\(contact.normalizedPhoneNumber)")
        redeemInvite(for: contact) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success, .failure(.existingUser):
                #if targetEnvironment(simulator)
                let vc = UIAlertController(
                    title: "Not available on Simulator",
                    message: "Please use a physical device to test SMS",
                    preferredStyle: .alert)
                vc.addAction(.init(title: "OK", style: .default, handler: nil))
                self.present(vc, animated: true, completion: nil)
                #else
                let vc = MFMessageComposeViewController()
                vc.body = Localizations.inviteText(name: contact.givenName ?? contact.fullName, number: contact.formattedPhoneNumber)
                vc.recipients = [contact.formattedPhoneNumber]
                vc.messageComposeDelegate = self
                self.present(vc, animated: true, completion: nil)
                #endif

            case .failure(let reason):
                self.presentFailureAlert(for: reason)
            }
        }
    }

    private func whatsAppAction(contact: InviteContact) {
        DDLogInfo("InviteViewController/WhatsApp/\(contact.normalizedPhoneNumber)")
        redeemInvite(for: contact) { [weak self] result in
            switch result {
            case .success, .failure(.existingUser):
                var allowedCharacters = CharacterSet.urlHostAllowed
                allowedCharacters.remove("+")
                guard let urlEncodedInviteText = Localizations
                        .inviteText(name: contact.givenName ?? contact.fullName, number: contact.formattedPhoneNumber)
                        .addingPercentEncoding(withAllowedCharacters: allowedCharacters),
                      let whatsAppURL = URL(string: "https://wa.me/\(contact.normalizedPhoneNumber)/?text=\(urlEncodedInviteText)") else
                {
                    return
                }
                UIApplication.shared.open(whatsAppURL, options: [:], completionHandler: nil)
            case .failure(let reason):
                self?.presentFailureAlert(for: reason)
            }
        }
    }

    private func presentFailureAlert(for reason: InviteResult.FailureReason) {
        switch reason {
        case .existingUser:
            DDLogInfo("InviteViewController/presentFailureAlert/skipping [existingUser]")
        case .noInvitesLeft:
            let vc = UIAlertController(
                title: Localizations.inviteErrorTitle,
                message: Localizations.outOfInvitesWith(date: inviteManager.nextRefreshDate ?? Date()),
                preferredStyle: .alert)
            vc.addAction(.init(title: Localizations.buttonOK, style: .default, handler: nil))
            present(vc, animated: true, completion: nil)
        case .invalidNumber, .unknown:
            let vc = UIAlertController(
                title: Localizations.inviteErrorTitle,
                message: Localizations.inviteErrorMessage,
                preferredStyle: .alert)
            vc.addAction(.init(title: Localizations.buttonOK, style: .default, handler: nil))
            present(vc, animated: true, completion: nil)
        }
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
}

extension InviteViewController: MFMessageComposeViewControllerDelegate {
    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        guard result == .cancelled else { return }
        // NB: We should really be calling this on the presenting view controller (see: https://developer.apple.com/documentation/uikit/uiviewcontroller/1621505-dismiss)
        // Unfortunately, that isn't working correctly (Apple bug?) so we have to call it on the presented controller instead
        controller.dismiss(animated: true, completion: nil)
    }
}

extension InviteViewController: UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 0, bottom: 30, right: 0)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard !isWhatsAppInstalled else {
            // Trigger SMS action on cell tap only if WhatsApp is not installed
            return
        }

        guard let contact = dataSource.itemIdentifier(for: indexPath), contact.userID == nil else {
            return
        }

        inviteAction(.sms, contact: contact)
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

final class InviteCollectionViewCell: UICollectionViewCell {

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.layoutMargins = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        contentView.addSubview(inviteCellView)
        inviteCellView.translatesAutoresizingMaskIntoConstraints = false
        inviteCellView.constrainMargins(to: contentView)

        contentView.addSubview(topDivider)
        topDivider.backgroundColor = UIColor.label.withAlphaComponent(0.15)
        topDivider.translatesAutoresizingMaskIntoConstraints = false
        topDivider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        topDivider.constrainMargins([.top, .leading, .trailing], to: contentView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    let inviteCellView = InviteCellView()
    let topDivider = UIView()

    func configure(with contact: InviteContact, actions: InviteActions?, visitedActions: Set<InviteActionType>, isTopDividerHidden: Bool) {
        inviteCellView.configure(with: contact, actions: actions, visitedActions: visitedActions)
        topDivider.isHidden = isTopDividerHidden
    }
}

final class InviteCellView: UIView {

    init() {
        super.init(frame: .zero)

        contactInfoPanel.addSubview(nameLabel)
        contactInfoPanel.addSubview(subtitleLabel)
        addSubview(contactInfoPanel)
        addSubview(whatsAppButton)
        addSubview(smsButton)

        backgroundColor = .systemBackground

        layoutMargins = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)

        contactInfoPanel.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.textColor = .label
        nameLabel.font = .systemFont(forTextStyle: .callout, weight: .semibold)
        nameLabel.numberOfLines = 1
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.textColor = UIColor.label.withAlphaComponent(0.5)
        subtitleLabel.font = .systemFont(forTextStyle: .footnote, pointSizeChange: 1)
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        smsButton.translatesAutoresizingMaskIntoConstraints = false
        whatsAppButton.translatesAutoresizingMaskIntoConstraints = false

        contactInfoPanel.constrainMargins([.leading, .centerY], to: self)
        contactInfoPanel.topAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.topAnchor).isActive = true
        contactInfoPanel.bottomAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.bottomAnchor).isActive = true

        nameLabel.constrain([.top, .leading, .trailing], to: contactInfoPanel)

        subtitleLabel.constrain([.bottom, .leading, .trailing], to: contactInfoPanel)
        subtitleLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2).isActive = true

        whatsAppButton.constrainMargins([.centerY], to: self)
        whatsAppButton.setContentHuggingPriority(.required, for: .horizontal)
        whatsAppButton.leadingAnchor.constraint(equalTo: contactInfoPanel.trailingAnchor, constant: 0).isActive = true

        smsButton.constrainMargins([.centerY, .trailing], to: self)
        smsButton.setContentHuggingPriority(.required, for: .horizontal)
        smsButton.leadingAnchor.constraint(equalTo: whatsAppButton.trailingAnchor, constant: 16).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with contact: InviteContact, actions: InviteActions?, visitedActions: Set<InviteActionType>) {

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

        smsButton.setImage(visitedActions.contains(.sms) ? smsImageVisited : smsImage, for: .normal)
        whatsAppButton.setImage(visitedActions.contains(.whatsApp) ? whatsAppImageVisited : whatsAppImage, for: .normal)

        let actionTypes = actions?.types ?? []

        smsButton.isHidden = !actionTypes.contains(.sms)
        whatsAppButton.isHidden = !actionTypes.contains(.whatsApp)
        action = actions?.action
    }

    let contactInfoPanel = UIView()
    let nameLabel = UILabel()
    let subtitleLabel = UILabel()
    let actionViewStack = UIStackView()
    var action: InviteAction?

    var contact: InviteContact?

    lazy var smsImage = UIImage(named: "InviteIconMessages")
    lazy var smsImageVisited = UIImage(named: "InviteIconMessagesVisited")
    lazy var smsButton: UIButton = {
        let button = Self.makeActionButton(
            image: smsImage,
            title: Localizations.appNameSMS)
        button.addTarget(self, action: #selector(didTapSMS), for: .touchUpInside)
        return button
    }()

    lazy var whatsAppImage = UIImage(named: "InviteIconWhatsApp")
    lazy var whatsAppImageVisited = UIImage(named: "InviteIconWhatsAppVisited")
    lazy var whatsAppButton: UIButton = {
        let button = Self.makeActionButton(
            image: whatsAppImage,
            title: Localizations.appNameWhatsApp)
        button.addTarget(self, action: #selector(didTapWhatsApp), for: .touchUpInside)
        return button
    }()

    @objc
    private func didTapSMS() {
        action?(.sms)
    }

    @objc
    private func didTapWhatsApp() {
        action?(.whatsApp)
    }

    static var forSizing: InviteCellView {
        let cell = InviteCellView()
        cell.nameLabel.text = " "
        cell.subtitleLabel.text = " \n \n "
        return cell
    }

    static func makeActionButton(image: UIImage?, title: String) -> UIButton {
        let button = UIButton()
        button.setImage(image, for: .normal)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 9)
        button.setTitleColor(.secondaryLabel, for: .normal)
        let width = max(button.titleLabel?.intrinsicContentSize.width ?? 0, image?.size.width ?? 0)
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        button.centerVerticallyWithPadding(padding: 3)
        return button
    }
}

private extension Localizations {
    static var alreadyHalloAppUser: String {
        NSLocalizedString("invite.already.halloapp.user",
                          value: "Already a HalloApp user",
                          comment: "Displayed below contact name in contact list that is displayed when inviting someone to HalloApp.")
    }

    static var pleaseWait: String {
        NSLocalizedString("invite.please.wait", value: "Please wait...", comment: "Displayed white user is inviting someone.")
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

    static func inviteText(name: String?, number: String?) -> String {
        guard let name = name, let number = number else {
            return NSLocalizedString("invite.text",
                              value: "Join me on HalloApp – a simple, private, and secure way to stay in touch with friends and family. Get it at https://halloapp.com/dl",
                              comment: "Text of invitation to join HalloApp.")
        }
        let format = NSLocalizedString("invite.text.specific",
                                       value: "Hey %1$@, I have an invite for you to join me on HalloApp (a simple social app for sharing everyday moments). Use %2$@ to register. Get it at https://halloapp.com/dl",
                                       comment: "Text of invitation to join HalloApp. First argument is the invitee's name, second argument is their phone number.")
        return String(format: format, name, number)
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
