//
//  UserFeedViewController.swift
//  HalloApp
//
//  Created by Garrett on 7/28/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Combine
import Core
import CoreData
import SwiftUI
import UIKit

class UserFeedViewController: FeedCollectionViewController {

    private enum Constants {
        static let sectionHeaderReuseIdentifier = "header-view"
    }

    init(userId: UserID) {
        self.userId = userId
        super.init(title: nil, fetchRequest: FeedDataSource.userFeedRequest(userID: userId))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let userId: UserID
    private var headerViewController: ProfileHeaderViewController!
    private var cancellables = Set<AnyCancellable>()

    private lazy var exchangeNumbersView: UIView = {
        let image = UIImage(named: "FeedExchangeNumbers")?.withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: image)
        imageView.tintColor = UIColor.label.withAlphaComponent(0.2)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.text = Localizations.exchangePhoneNumbersToConnect
        label.textAlignment = .center
        label.textColor = .secondaryLabel

        let stackView = UIStackView(arrangedSubviews: [imageView, label])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 12

        return stackView
    }()

    // MARK: View Controller

    override func viewDidLoad() {
        super.viewDidLoad()

        installExchangeNumbersView()

        headerViewController = ProfileHeaderViewController()
        if isOwnFeed {
            title = Localizations.titleMyPosts
            
            headerViewController.isEditingAllowed = true
            cancellables.insert(MainAppContext.shared.userData.userNamePublisher.sink(receiveValue: { [weak self] (userName) in
                guard let self = self else { return }
                self.headerViewController.configureForCurrentUser(withName: userName)
                self.viewIfLoaded?.setNeedsLayout()
            }))
        } else {
            headerViewController.configureWith(userId: userId)
            navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: self, action: #selector(moreButtonTapped))
        }

        collectionViewDataSource?.supplementaryViewProvider = { [weak self] (collectionView, kind, path) -> UICollectionReusableView? in
            guard let self = self else {
                return UICollectionReusableView()
            }
            return self.collectionView(collectionView, viewForSupplementaryElementOfKind: kind, at: path)
        }
        collectionView.register(UICollectionReusableView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: Constants.sectionHeaderReuseIdentifier)
    }
    
    @objc func moreButtonTapped() {
        guard !isOwnFeed else { return }
        
        let alert = UIAlertController(title: MainAppContext.shared.contactStore.fullName(for: userId), message: nil, preferredStyle: .actionSheet)
        
        if let userKeys = MainAppContext.shared.keyStore.keyBundle(),
              let contactKeyBundle = MainAppContext.shared.keyStore.messageKeyBundle(for: userId)?.keyBundle,
              let contactData = SafetyNumberData(keyBundle: contactKeyBundle)
        {
            let verifySafetyNumberAction = UIAlertAction(title: Localizations.safetyNumberTitle, style: .default) { [weak self] _ in
                self?.viewSafetyNumber(contactData: contactData, userKeyBundle: userKeys)
            }
            alert.addAction(verifySafetyNumberAction)
        }
        
        
        let blockUserAction = UIAlertAction(title: Localizations.userOptionBlock, style: .destructive) { [weak self] _ in
            self?.blockUserTapped()
        }
        alert.addAction(blockUserAction)
        
        let cancel = UIAlertAction(title: Localizations.buttonCancel, style: .cancel, handler: nil)
        alert.view.tintColor = .systemBlue
        alert.addAction(cancel)
        
        present(alert, animated: true)
    }
    
    private func viewSafetyNumber(contactData: SafetyNumberData, userKeyBundle: UserKeyBundle) {
        let vc = SafetyNumberViewController(
            currentUser: SafetyNumberData(
                userID: MainAppContext.shared.userData.userId,
                identityKey: userKeyBundle.identityPublicKey),
            contact: contactData,
            contactName: MainAppContext.shared.contactStore.fullName(for: userId),
            dismissAction: { [weak self] in self?.dismiss(animated: true, completion: nil) })
        present(vc.withNavigationController(), animated: true)
    }
    
    private func blockUserTapped() {
        guard !isOwnFeed else { return }
        
        let blockMessage = Localizations.blockMessage(username: MainAppContext.shared.contactStore.fullName(for: userId))
        
        let alert = UIAlertController(title: nil, message: blockMessage, preferredStyle: .actionSheet)
        let button = UIAlertAction(title: Localizations.blockButton, style: .destructive) { [weak self] _ in
            let privacySettings = MainAppContext.shared.privacySettings
            guard let blockedList = privacySettings.blocked else { return }
            guard let userId = self?.userId else { return }
            privacySettings.update(privacyList: blockedList, with: [userId])
        }
        alert.addAction(button)
        
        let cancel = UIAlertAction(title: Localizations.buttonCancel, style: .cancel, handler: nil)
        alert.addAction(cancel)
        
        present(alert, animated: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(true)
        DispatchQueue.main.async {
            self.tabBarController?.tabBar.isHidden = false
        }
    }
    
    override func showGroupName() -> Bool {
        return true
    }

    private func installExchangeNumbersView() {
        view.addSubview(exchangeNumbersView)

        exchangeNumbersView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.6).isActive = true
        exchangeNumbersView.constrain([.centerX, .centerY], to: view)
    }

    private func updateExchangeNumbersView(isFeedEmpty: Bool) {
        let isKnownContact = MainAppContext.shared.contactStore.contact(withUserId: userId) != nil

        exchangeNumbersView.isHidden = !isFeedEmpty || isKnownContact || isOwnFeed
    }

    private var isOwnFeed: Bool {
        return MainAppContext.shared.userData.userId == userId
    }
    
    // MARK: FeedCollectionViewController

    override func shouldOpenFeed(for userId: UserID) -> Bool {
        return userId != self.userId
    }

    override func willUpdate(with items: [FeedDisplayItem]) {
        super.willUpdate(with: items)

        updateExchangeNumbersView(isFeedEmpty: items.isEmpty)
    }

    // MARK: Collection View Header

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        if kind == UICollectionView.elementKindSectionHeader && indexPath.section == 0 {
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: Constants.sectionHeaderReuseIdentifier, for: indexPath)
            if let superView = headerViewController.view.superview, superView != headerView {
                headerViewController.willMove(toParent: nil)
                headerViewController.view.removeFromSuperview()
                headerViewController.removeFromParent()
            }
            if headerViewController.view.superview == nil {
                addChild(headerViewController)
                headerView.addSubview(headerViewController.view)
                headerView.preservesSuperviewLayoutMargins = true
                headerViewController.view.translatesAutoresizingMaskIntoConstraints = false
                headerViewController.view.constrain(to: headerView)
                headerViewController.didMove(toParent: self)
            }
            return headerView
        }
        return UICollectionReusableView()
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        guard section == 0 else {
            return .zero
        }
        let targetSize = CGSize(width: collectionView.frame.width, height: UIView.layoutFittingCompressedSize.height)
        let headerSize = headerViewController?.view.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel) ?? .zero
        return headerSize
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        let layout = collectionViewLayout as! UICollectionViewFlowLayout
        var inset = layout.sectionInset
        if section == 0 {
            inset.top = 8
            inset.bottom = 20
        }
        return inset
    }
    
    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        super.scrollViewDidScroll(scrollView)

        guard !headerViewController.isEditingAllowed else { return }
        let offset = scrollView.contentOffset.y
        let scrolledLimit:CGFloat = headerViewController.view.frame.size.height/3.5
        var titleText = ""

        if offset > scrolledLimit {
            titleText = headerViewController.name ?? ""
        }
        
        if title != titleText {
            title = titleText
        }
    }
}

extension Localizations {
    static var exchangePhoneNumbersToConnect: String {
        NSLocalizedString(
            "exchange.phone.numbers.to.connect",
            value: "To connect you must exchange phone numbers",
            comment: "Text to show on profile for users you are not connected with")
    }
}
