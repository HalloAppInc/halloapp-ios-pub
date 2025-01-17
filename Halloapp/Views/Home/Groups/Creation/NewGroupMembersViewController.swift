//
//  HalloApp
//
//  Created by Tony Jiang on 4/29/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import Combine
import CocoaLumberjackSwift
import Core
import CoreCommon
import CoreData
import UIKit

class NewGroupMembersViewController: UIViewController, NSFetchedResultsControllerDelegate {

    let cellReuseIdentifier = "NewGroupMembersViewCell"
    
    private var fetchedResultsController: NSFetchedResultsController<UserProfile>?

    private var searchController: UISearchController!

    var isSearchBarEmpty: Bool {
        return searchController.searchBar.text?.isEmpty ?? true
    }
    var isFiltering: Bool {
        return searchController.isActive && !isSearchBarEmpty
    }

    var disableCreateOrAddAction = false {
        didSet {
            navigationItem.rightBarButtonItem?.isEnabled = !disableCreateOrAddAction
        }
    }

    private var filteredContacts: [UserProfile] = []

    private var trackedContacts: [String:TrackedContact] = [:]

    private var selectedMembers: [UserID] = [] {
        didSet {
            updateMemberAvatarsRowVisibility()
        }
    }

    private var isNewCreationFlow: Bool = false
    private var currentMembers: [UserID] = []
    private var groupID: GroupID? = nil
    private var completion: (NewGroupMembersViewController, Bool, [UserID]) -> Void

    private let sharedNUX = MainAppContext.shared.nux
    private let isZeroZone: Bool
    private var cancellableSet: Set<AnyCancellable> = []

    init(isNewCreationFlow: Bool,
         currentMembers: [UserID] = [],
         groupID: GroupID? = nil,
         completion: @escaping (NewGroupMembersViewController, Bool, [UserID]) -> Void) {
        self.isNewCreationFlow = isNewCreationFlow
        // We should be able to modify current members if this is the new group creation flow
        if isNewCreationFlow {
            self.selectedMembers = currentMembers
        } else {
            self.currentMembers = currentMembers
        }
        self.groupID = groupID
        self.completion = completion

        self.isZeroZone = sharedNUX.state == .zeroZone
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }

    override func viewDidLoad() {
        DDLogInfo("NewGroupMembersViewController/viewDidLoad")

        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarBack"),
                                                           style: .plain,
                                                           target: self,
                                                           action: #selector(cancelAction))

        if isNewCreationFlow {
            navigationItem.title = Localizations.titleSelectGroupMembersCreateGroup
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: Localizations.buttonCreate,
                                                                style: .done,
                                                                target: self,
                                                                action: #selector(createAction))
        } else {
            navigationItem.title = Localizations.titleSelectGroupMembers
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: Localizations.buttonAdd,
                                                                style: .done,
                                                                target: self,
                                                                action: #selector(addAction))
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

        // when using insetgroup style and header is set to nil,
        // iOS will default a view that takes up space so an empty view is needed to remove space
        var emptyHeaderViewFrame = CGRect.zero
        emptyHeaderViewFrame.size.height = .leastNormalMagnitude
        tableView.tableHeaderView = UIView(frame: emptyHeaderViewFrame)

        view.addSubview(mainView)
        view.backgroundColor = UIColor.primaryBg
        isModalInPresentation = true

        NSLayoutConstraint.activate([
            mainView.topAnchor.constraint(equalTo: view.topAnchor),
            mainView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        setupFetchedResultsController()

        view.addSubview(emptyPlaceholderView)
        emptyPlaceholderView.constrain(to: view)

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)

        updateMemberAvatarsRowVisibility()
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
            self.mainView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: keyboardFrame.height, right: 0)
        }
    }

    @objc private func keyboardWillHide(notification: Notification) {
        animateWithKeyboard(notification: notification) { (keyboardFrame) in
            self.mainView.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 10, right: 0)
        }
    }

    private func updateMemberAvatarsRowVisibility() {
        memberAvatarsRow.isHidden = (selectedMembers.count == 0)
    }

    private lazy var emptyPlaceholderView: UIView = {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.alpha = 0
        containerView.backgroundColor = .primaryBg

        let textLabel = UILabel()
        textLabel.text = Localizations.newGroupMembersEmptyStatePlaceholder
        textLabel.numberOfLines = 0
        textLabel.textAlignment = .center
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.textColor = .tertiaryLabel

        containerView.addSubview(textLabel)

        textLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor).isActive = true
        textLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor).isActive = true
        textLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor).isActive = true
        textLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor).isActive = true
        
        let welcomeView = AddGroupMembersWelcomeView()
        if let groupID = groupID {
            welcomeView.configure(groupID: groupID)
            welcomeView.openShareLink = { [weak self] link in
                guard let self = self else { return }
                self.shareGroupInviteLink(link)
            }
        }
        welcomeView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(welcomeView)

        welcomeView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor).isActive = true
        welcomeView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor).isActive = true
        welcomeView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor).isActive = true
        welcomeView.heightAnchor.constraint(equalToConstant: 230).isActive = true

        return containerView
    }()

    private lazy var mainView: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ tableView, memberAvatarsRow ])
        view.axis = .vertical

        view.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 10, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        view.insetsLayoutMarginsFromSafeArea = false

        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()

    private lazy var memberAvatarsRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ groupMemberAvatars ])
        view.axis = .horizontal

        view.layoutMargins = UIEdgeInsets(top: 15, left: 0, bottom: 10, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        view.insetsLayoutMarginsFromSafeArea = false

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

        if !self.selectedMembers.isEmpty {
            self.groupMemberAvatars.insert(with: self.selectedMembers)
        }

        return view
    }()

    private lazy var groupMemberAvatars: GroupMemberAvatars = {
        let view = GroupMemberAvatars()
        view.delegate = self
        return view
    }()

    private lazy var tableView: UITableView = {
        let view = UITableView(frame: CGRect.zero, style: .insetGrouped)
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
        let navigateBackAndCallCompletion = { [weak self] in
            guard let self = self else {
                return
            }
            self.navigationController?.popViewController(animated: true)
            self.completion(self, false, self.selectedMembers)
        }
        if searchController.isActive {
            searchController.dismiss(animated: true) {
                navigateBackAndCallCompletion()
            }
        } else {
            navigateBackAndCallCompletion()
        }
    }

    @objc private func createAction() {
        completion(self, true, selectedMembers)
    }

    @objc private func addAction() {
        navigationController?.popViewController(animated: true)
        completion(self, true, selectedMembers)
    }

    // MARK: Customization

    public var fetchRequest: NSFetchRequest<UserProfile> {
        get {
            let fetchRequest = UserProfile.fetchRequest()
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \UserProfile.name, ascending: true)
            ]
            fetchRequest.predicate = NSPredicate(format: "friendshipStatusValue == %d AND id != %@", UserProfile.FriendshipStatus.friends.rawValue, MainAppContext.shared.userData.userId)
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
            updateEmptyView()
        } catch {
            fatalError("Failed to fetch feed items \(error)")
        }
    }

    private func newFetchedResultsController() -> NSFetchedResultsController<UserProfile> {
        // Setup fetched results controller the old way because it allows granular control over UI update operations.
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: self.fetchRequest, 
                                                                  managedObjectContext: AppContext.shared.mainDataStore.viewContext,
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
        updateEmptyView()
    }

    func isDuplicate(_ abContact: ABContact) -> Bool {
        guard let phoneNumber = abContact.phoneNumber else { return false }
        guard let normalizedPhoneNumber = abContact.normalizedPhoneNumber else { return false }
        let id = "\(abContact.identifier)-\(phoneNumber)" // account for contacts that have multiple registered numbers
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

    private func updateEmptyView() {
        guard !isNewCreationFlow else { return }
        let isEmpty = (fetchedResultsController?.sections?.first?.numberOfObjects ?? 0) == 0
        if isEmpty {
            navigationItem.rightBarButtonItem = nil
        }
        emptyPlaceholderView.alpha = isEmpty ? 1 : 0
    }

    private func shareGroupInviteLink(_ link: String) {
        if let urlStr = NSURL(string: link) {
            let shareText = "\(Localizations.groupInviteShareLinkMessage) \(urlStr)"
            let objectsToShare = [shareText]
            let activityVC = UIActivityViewController(activityItems: objectsToShare, applicationActivities: nil)

            present(activityVC, animated: true, completion: nil)
        }
    }

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
        if isZeroZone, isNewCreationFlow { return 1 }
        return fetchedResultsController?.sections?.count ?? 0
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if isZeroZone, isNewCreationFlow {
            return 1 // for the cell that shows the user
        }
        guard let sections = self.fetchedResultsController?.sections else { return 0 }
        if isFiltering {
          return filteredContacts.count
        }
        return sections[section].numberOfObjects
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if isZeroZone, isNewCreationFlow {
            let cell = ContactTableViewCell()
            cell.configure(with: MainAppContext.shared.userData.userId)
            cell.setContact(selected: true, animated: false)
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier, for: indexPath) as! ContactTableViewCell

        let friend: UserProfile?

        if isFiltering {
            friend = filteredContacts[indexPath.row]
        } else {
            friend = fetchedResultsController?.object(at: indexPath)
        }

        if let friend {
            cell.configure(with: friend.id)
            let isSelected = selectedMembers.contains(friend.id)
            cell.setContact(selected: isSelected, animated: false) // animation flickers if true due to too many reloads
        }

        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if isZeroZone, isNewCreationFlow { return }

        var friend: UserProfile?

        if isFiltering {
            friend = filteredContacts[indexPath.row]
        } else {
            friend = fetchedResultsController?.object(at: indexPath)
        }

        if let friend, currentMembers.contains(friend.id) {
            if let contactCell = cell as? ContactTableViewCell {
                contactCell.setContact(selected: true, animated: true)
                contactCell.isUserInteractionEnabled = false
            }
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if isZeroZone, isNewCreationFlow { return }
        guard let cell = tableView.cellForRow(at: indexPath) as? ContactTableViewCell else { return }
        let profile: UserProfile?
        if isFiltering {
            profile = filteredContacts[indexPath.row]
        } else {
            profile = fetchedResultsController?.object(at: indexPath)
        }

        guard let profile else {
            return
        }

        var isSelected = false
        if !selectedMembers.contains(profile.id) {
            var totalMembers = currentMembers.count + selectedMembers.count
            if isNewCreationFlow {
                totalMembers += 1 // count yourself also if this is a new creation flow
            }
            guard totalMembers < ServerProperties.maxGroupSize else {
                let alert = UIAlertController(title: "", message: Localizations.newGroupMembersMaxSizeAlert(ServerProperties.maxGroupSize), preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: .default, handler: nil))
                self.present(alert, animated: true)
                return
            }
            selectedMembers.append(profile.id)
            groupMemberAvatars.insert(with: [profile.id])
            isSelected = true
        } else {
            selectedMembers.removeAll(where: {$0 == profile.id})
            groupMemberAvatars.removeUser(profile.id)
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
            NSComparisonPredicate(leftExpression: NSExpression(forKeyPath: "searchItems"),
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

fileprivate struct TrackedContact {
    let normalizedPhone: String?
    var isDuplicate: Bool = false

    init(with abContact: ABContact) {
        normalizedPhone = abContact.normalizedPhoneNumber
    }
}

private extension ContactTableViewCell {

    func configure(with userID: UserID) {
        options.insert(.hasCheckmark)
        options.insert(.useBlueCheckmark)

        let profile = UserProfile.find(with: userID, in: MainAppContext.shared.mainDataStore.viewContext)
        nameLabel.text = profile?.name
        subtitleLabel.text = profile?.username

        contactImage.configure(with: userID, using: MainAppContext.shared.avatarStore)
    }

}

extension Localizations {

    static var newGroupMembersEmptyStatePlaceholder: String {
        NSLocalizedString("new.group.members.empty.placeholder", value: "Your contacts who are on HalloApp will appear here", comment: "Placeholder text shown in the middle of the Add New Group Members screen when user have no contacts (in ZeroZone) to add")
    }

    static func newGroupMembersMaxSizeAlert(_ maxGroupSize: Int) -> String {
        return String(
            format: NSLocalizedString("new.group.members.max.size.alert",
            value: "The max group size is %d",
            comment: "Alert text shown when max group size is reached when selecting/adding group members"),
            maxGroupSize)
    }
}
