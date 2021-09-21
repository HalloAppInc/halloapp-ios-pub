//
//  HalloApp
//
//  Created by Tony Jiang on 4/29/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Combine
import CocoaLumberjackSwift
import Core
import CoreData
import UIKit

protocol NewGroupMembersViewControllerDelegate: AnyObject {
    func newGroupMembersViewController(_ viewController: NewGroupMembersViewController, selected: [UserID])
    func newGroupMembersViewController(_ viewController: NewGroupMembersViewController, didCreateGroup: GroupID)
}

class NewGroupMembersViewController: UIViewController, NSFetchedResultsControllerDelegate {

    weak var delegate: NewGroupMembersViewControllerDelegate?
    
    let cellReuseIdentifier = "NewGroupMembersViewCell"
    
    private var fetchedResultsController: NSFetchedResultsController<ABContact>?

    private var searchController: UISearchController!
   
    var isSearchBarEmpty: Bool {
        return searchController.searchBar.text?.isEmpty ?? true
    }
    var isFiltering: Bool {
        return searchController.isActive && !isSearchBarEmpty
    }
    private var filteredContacts: [ABContact] = []
    
    private var trackedContacts: [String:TrackedContact] = [:]

    private var selectedMembers: [UserID] = [] {
        didSet {
            if selectedMembers.count == 0 {
                memberAvatarsRow.isHidden = true
            } else {
                memberAvatarsRow.isHidden = false
            }
        }
    }

    private var alreadyHaveMembers: Bool = false
    private var currentMembers: [UserID] = []
    
    private var cancellableSet: Set<AnyCancellable> = []

    init(currentMembers: [UserID] = []) {
        self.currentMembers = currentMembers
        self.alreadyHaveMembers = self.currentMembers.count > 0 ? true : false
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        DDLogInfo("NewGroupMembersViewController/viewDidLoad")

        if alreadyHaveMembers {
            navigationItem.title = Localizations.titleSelectGroupMembers
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: Localizations.buttonAdd, style: .done, target: self, action: #selector(addAction))
        } else {
            navigationItem.title = Localizations.titleSelectGroupMembersCreateGroup
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarClose"), style: .plain, target: self, action: #selector(cancelAction))
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: Localizations.buttonNext, style: .done, target: self, action: #selector(nextAction))
        }

        navigationItem.rightBarButtonItem?.tintColor = UIColor.systemBlue

        tableView.backgroundColor = .primaryBg
        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: cellReuseIdentifier)

        searchController = UISearchController(searchResultsController: nil)
        searchController.delegate = self
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.definesPresentationContext = true
        searchController.hidesNavigationBarDuringPresentation = false

        searchController.searchBar.showsCancelButton = false
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.searchTextField.placeholder = Localizations.labelSearch

        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        tableView.tableHeaderView = nil

        view.addSubview(mainView)
        view.backgroundColor = UIColor.primaryBg
        isModalInPresentation = true

        mainView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        mainView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        mainView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true

        let keyWindow = UIApplication.shared.windows.filter({$0.isKeyWindow}).first

        let safeAreaInsetBottom = (keyWindow?.safeAreaInsets.bottom ?? 0) + 10
        mainView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: safeAreaInsetBottom).isActive = true

        setupFetchedResultsController()

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)

        cancellableSet.insert(
            MainAppContext.shared.contactStore.didDiscoverNewUsers.sink { [weak self] _ in
                guard let self = self else { return }
                guard self.isFiltering else { return }
                DDLogInfo("NewGroupMembersViewController/didDiscoverNewUsers")
                self.searchController.isActive = true  // edge case: refresh search if user is searching and then add contact in address book
            }
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        DDLogInfo("NewGroupMembersViewController/viewWillAppear")
        super.viewWillAppear(animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        DDLogInfo("NewGroupMembersViewController/viewDidAppear")
        super.viewDidAppear(animated)
    }

    deinit {
        DDLogDebug("NewGroupMembersViewController/deinit ")
    }

    @objc private func keyboardWillShow(notification: Notification) {
        animateWithKeyboard(notification: notification) { (keyboardFrame) in
            self.mainView.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: keyboardFrame.height, right: 0)
        }
    }

    @objc private func keyboardWillHide(notification: Notification) {
        animateWithKeyboard(notification: notification) { (keyboardFrame) in
            self.mainView.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        }
    }

    private lazy var mainView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ tableView, memberAvatarsRow ])
        view.axis = .vertical

        view.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    private lazy var memberAvatarsRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ groupMemberAvatars ])
        view.axis = .horizontal

        view.layoutMargins = UIEdgeInsets(top: 15, left: 0, bottom: 10, right: 0)
        view.isLayoutMarginsRelativeArrangement = true

        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 120).isActive = true

        let subView = UIView(frame: view.bounds)
        subView.layer.masksToBounds = true
        subView.clipsToBounds = true
        subView.backgroundColor = UIColor.primaryBg
        subView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(subView, at: 0)

        let topBorder = UIView(frame: view.bounds)
        topBorder.frame.size.height = 1
        topBorder.backgroundColor = UIColor.secondarySystemGroupedBackground
        topBorder.autoresizingMask = [.flexibleWidth]
        view.insertSubview(topBorder, at: 1)

        view.isHidden = true
        return view
    }()

    private lazy var groupMemberAvatars: GroupMemberAvatars = {
        let view = GroupMemberAvatars()
        view.delegate = self
        return view
    }()

    private lazy var tableView: UITableView = {
        let view = UITableView()
        view.backgroundColor = .primaryBg
        view.register(ContactTableViewCell.self, forCellReuseIdentifier: cellReuseIdentifier)
        view.delegate = self
        view.dataSource = self

        view.tableFooterView = UIView()

        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    // MARK: Top Nav Button Actions

    @objc private func cancelAction() {
        searchController.isActive = false
        dismiss(animated: true)
    }

    @objc private func nextAction() {
        let controller = CreateGroupViewController(selectedMembers: selectedMembers)
        controller.isModalInPresentation = true
        controller.delegate = self
        navigationController?.pushViewController(controller, animated: true)
    }

    @objc private func addAction() {
        navigationController?.popViewController(animated: true)
        delegate?.newGroupMembersViewController(self, selected: selectedMembers)
    }

    // MARK: Customization

    public var fetchRequest: NSFetchRequest<ABContact> {
        get {
            let fetchRequest = NSFetchRequest<ABContact>(entityName: "ABContact")
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \ABContact.fullName, ascending: true)
            ]
            fetchRequest.predicate = NSPredicate(format: "userId != nil AND userId != %@", MainAppContext.shared.userData.userId)
            return fetchRequest
        }
    }

    // MARK: Fetched Results Controller

    private var trackPerRowFRCChanges = false

    private var reloadTableViewInDidChangeContent = false

    private func setupFetchedResultsController() {
        self.fetchedResultsController = self.newFetchedResultsController()
        do {
            try self.fetchedResultsController?.performFetch()
        } catch {
            fatalError("Failed to fetch feed items \(error)")
        }
    }

    private func newFetchedResultsController() -> NSFetchedResultsController<ABContact> {
        // Setup fetched results controller the old way because it allows granular control over UI update operations.
        let fetchedResultsController = NSFetchedResultsController<ABContact>(fetchRequest: self.fetchRequest, managedObjectContext: AppContext.shared.contactStore.viewContext,
                                                                            sectionNameKeyPath: nil, cacheName: nil)
        fetchedResultsController.delegate = self
        return fetchedResultsController
    }

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        reloadTableViewInDidChangeContent = false
        trackPerRowFRCChanges = view.window != nil && UIApplication.shared.applicationState == .active
        DDLogDebug("NewGroupMembersView/frc/will-change perRowChanges=[\(trackPerRowFRCChanges)]")
        if trackPerRowFRCChanges {
            tableView.beginUpdates()
        }
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            guard let indexPath = newIndexPath, let abContact = anObject as? ABContact else { break }
            DDLogDebug("NewGroupMembersView/frc/insert [\(abContact)] at [\(indexPath)]")
            if trackPerRowFRCChanges && !isFiltering {
                tableView.insertRows(at: [ indexPath ], with: .automatic)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .delete:
            guard let indexPath = indexPath, let abContact = anObject as? ABContact else { break }
            DDLogDebug("NewGroupMembersView/frc/delete [\(abContact)] at [\(indexPath)]")
            if trackPerRowFRCChanges && !isFiltering {
                tableView.deleteRows(at: [ indexPath ], with: .automatic)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .move:
            guard let fromIndexPath = indexPath, let toIndexPath = newIndexPath, let abContact = anObject as? ABContact else { break }
            DDLogDebug("NewGroupMembersView/frc/move [\(abContact)] from [\(fromIndexPath)] to [\(toIndexPath)]")
            if trackPerRowFRCChanges && !isFiltering {
                tableView.moveRow(at: fromIndexPath, to: toIndexPath)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        case .update:
            guard let indexPath = indexPath, let abContact = anObject as? ABContact else { return }
            DDLogDebug("NewGroupMembersView/frc/update [\(abContact)] at [\(indexPath)]")
            if trackPerRowFRCChanges && !isFiltering {
                tableView.reloadRows(at: [ indexPath ], with: .automatic)
            } else {
                reloadTableViewInDidChangeContent = true
            }

        default:
            break
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DDLogDebug("NewGroupMembersView/frc/did-change perRowChanges=[\(trackPerRowFRCChanges)]  reload=[\(reloadTableViewInDidChangeContent)]")
        if trackPerRowFRCChanges {
            tableView.endUpdates()
        }
        if reloadTableViewInDidChangeContent || isFiltering {
            tableView.reloadData()
        }
    }

    func isDuplicate(_ abContact: ABContact) -> Bool {
        guard let identifier = abContact.identifier else { return false }
        guard let phoneNumber = abContact.phoneNumber else { return false }
        guard let normalizedPhoneNumber = abContact.normalizedPhoneNumber else { return false }
        let id = "\(identifier)-\(phoneNumber)" // account for contacts that have multiple registered numbers
        if trackedContacts[id] == nil {
            var trackedContact = TrackedContact(with: abContact)
            if trackedContacts.keys.first(where: { trackedContacts[$0]?.normalizedPhone == normalizedPhoneNumber }) != nil {
                trackedContact.isDuplicate = true
            }
            trackedContacts[id] = trackedContact
        }
        return trackedContacts[id]?.isDuplicate ?? false
    }
    
    // MARK: Helpers
    
    private func animateWithKeyboard(notification: Notification, animations: ((_ keyboardFrame: CGRect) -> Void)?) {
        
        let durationKey = UIResponder.keyboardAnimationDurationUserInfoKey
        guard let duration = notification.userInfo?[durationKey] as? Double else { return }
        
        let frameKey = UIResponder.keyboardFrameEndUserInfoKey
        guard let keyboardFrameValue = notification.userInfo?[frameKey] as? NSValue else { return }
        
        let curveKey = UIResponder.keyboardAnimationCurveUserInfoKey
        guard let curveValue = notification.userInfo?[curveKey] as? Int else { return }
        guard let curve = UIView.AnimationCurve(rawValue: curveValue) else { return }

        let animator = UIViewPropertyAnimator(duration: duration, curve: curve) {
            animations?(keyboardFrameValue.cgRectValue)
            self.view?.layoutIfNeeded()
        }
        animator.startAnimation()
    }
}

// MARK: UITableView Delegates
extension NewGroupMembersViewController: UITableViewDelegate, UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return self.fetchedResultsController?.sections?.count ?? 0
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sections = self.fetchedResultsController?.sections else { return 0 }
        if isFiltering {
          return filteredContacts.count
        }
        return sections[section].numberOfObjects
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier, for: indexPath) as! ContactTableViewCell

        let abContact: ABContact?
        
        if isFiltering {
            abContact = filteredContacts[indexPath.row]
        } else {
            abContact = fetchedResultsController?.object(at: indexPath)
        }

        if let abContact = abContact {
            if let userId = abContact.userId {
                cell.configure(with: abContact)
                let isSelected = selectedMembers.contains(userId)
                cell.setContact(selected: isSelected, animated: false) // animation flickers if true due to too many reloads
            }
        }
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        var contact: ABContact?
        
        if isFiltering {
            contact = filteredContacts[indexPath.row]
        } else {
            contact = fetchedResultsController?.object(at: indexPath)
        }
        if let contact = contact, self.isDuplicate(contact) {
            return 0
        }
        
        guard contact?.userId != nil else { return 0 }

        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        var contact: ABContact?

        if isFiltering {
            contact = filteredContacts[indexPath.row]
        } else {
            contact = fetchedResultsController?.object(at: indexPath)
        }
        if let contact = contact, self.isDuplicate(contact) {
            cell.isHidden = true
        }

        guard let userId = contact?.userId else { return }
        if currentMembers.contains(userId) {
            if let contactCell = cell as? ContactTableViewCell {
                contactCell.setContact(selected: true, animated: true)
                contactCell.isUserInteractionEnabled = false
            }
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let cell = tableView.cellForRow(at: indexPath) as? ContactTableViewCell else { return }
        let abContact: ABContact?
        if isFiltering {
            abContact = filteredContacts[indexPath.row]
        } else {
            abContact = fetchedResultsController?.object(at: indexPath)
        }

        guard let contact = abContact else { return }

        var isSelected = false
        guard let userId = contact.userId else { return }
        if !selectedMembers.contains(userId) {
            var totalMembers = currentMembers.count + selectedMembers.count
            if !alreadyHaveMembers {
                totalMembers += 1 // count yourself also if this is a new creation flow
            }
            guard totalMembers < ServerProperties.maxGroupSize else {
                let alert = UIAlertController(title: "", message: Localizations.newGroupMembersMaxSizeAlert(ServerProperties.maxGroupSize), preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: nil))
                self.present(alert, animated: true)
                return
            }
            selectedMembers.append(userId)
            groupMemberAvatars.insert(with: [userId])
            isSelected = true
        } else {
            selectedMembers.removeAll(where: {$0 == userId})
            groupMemberAvatars.removeUser(userId)
        }
        cell.setContact(selected: isSelected, animated: true)
        tableView.deselectRow(at: indexPath, animated: true)

        searchController.searchBar.text = ""
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        searchController.searchBar.endEditing(true)
    }
}

extension NewGroupMembersViewController: UISearchControllerDelegate {

    func willPresentSearchController(_ searchController: UISearchController) {
        if let resultsController = searchController.searchResultsController as? UITableViewController {
            resultsController.tableView.delegate = self
        }
    }
}

extension NewGroupMembersViewController: UISearchResultsUpdating {
    
    func updateSearchResults(for searchController: UISearchController) {
        guard let allContacts = fetchedResultsController?.fetchedObjects else { return }
        let strippedString = searchController.searchBar.text!.trimmingCharacters(in: CharacterSet.whitespaces)
        let searchItems = strippedString.components(separatedBy: " ")

        let andPredicates: [NSPredicate] = searchItems.map { (searchString) in
            NSComparisonPredicate(leftExpression: NSExpression(forKeyPath: "searchTokens"),
                                  rightExpression: NSExpression(forConstantValue: searchString),
                                  modifier: .any,
                                  type: .contains,
                                  options: [.caseInsensitive, .diacriticInsensitive])
        }

        let finalCompoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: andPredicates)

        filteredContacts = allContacts.filter { finalCompoundPredicate.evaluate(with: $0) }
        tableView.reloadData()
    }
}

// MARK: GroupMemberAvatars Delegates
extension NewGroupMembersViewController: GroupMemberAvatarsDelegate {
    
    func groupMemberAvatarsDelegate(_ view: GroupMemberAvatars, selectedUser: String) {
        selectedMembers.removeAll(where: { $0 == selectedUser })
        tableView.reloadData()
    }
}

extension NewGroupMembersViewController: CreateGroupViewControllerDelegate {
    func createGroupViewController(_ controller: CreateGroupViewController, didCreateGroup: GroupID) {
        delegate?.newGroupMembersViewController(self, didCreateGroup: didCreateGroup)
    }
}

fileprivate struct TrackedContact {
    let normalizedPhone: String?
    var isDuplicate: Bool = false

    init(with abContact: ABContact) {
        normalizedPhone = abContact.normalizedPhoneNumber
    }
}

private extension ContactTableViewCell {

    func configure(with abContact: ABContact) {
        options.insert(.hasCheckmark)
        options.insert(.useBlueCheckmark)

        nameLabel.text = abContact.fullName
        subtitleLabel.text = abContact.phoneNumber

        if let userId = abContact.userId {
            contactImage.configure(with: userId, using: MainAppContext.shared.avatarStore)
        }
    }
}

extension Localizations {

    static func newGroupMembersMaxSizeAlert(_ maxGroupSize: Int) -> String {
        return String(
            format: NSLocalizedString("new.group.members.max.size.alert",
            value: "The max group size is %d",
            comment: "Alert text shown when max group size is reached when selecting/adding group members"),
            maxGroupSize)
    }
}
