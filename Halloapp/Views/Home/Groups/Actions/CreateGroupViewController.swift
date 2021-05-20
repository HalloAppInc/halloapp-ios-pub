//
//  HalloApp
//
//  Created by Tony Jiang on 8/14/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjack
import Combine
import Core
import UIKit

fileprivate struct Constants {
    static let MaxNameLength = 25
    static let AvatarSize: CGFloat = 100
    static let PhotoIconSize: CGFloat = 40
}

protocol CreateGroupViewControllerDelegate: AnyObject {
    func createGroupViewController(_ controller: CreateGroupViewController, didCreateGroup: GroupID)
}

class CreateGroupViewController: UIViewController {
    weak var delegate: CreateGroupViewControllerDelegate?
    
    private var selectedMembers: [UserID] = []
    private var placeholderText = Localizations.chatCreateGroupNamePlaceholder
    private var cancellableSet: Set<AnyCancellable> = []
    
    private var avatarData: Data? = nil
    
    init(selectedMembers: [UserID]) {
        self.selectedMembers = selectedMembers
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) disabled") }
    
    override func viewDidLoad() {
        DDLogInfo("CreateGroupViewController/viewDidLoad")

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: Localizations.buttonCreate, style: .done, target: self, action: #selector(createAction))
        navigationItem.rightBarButtonItem?.tintColor = UIColor.systemBlue
        navigationItem.rightBarButtonItem?.isEnabled = canCreate
        
        navigationItem.title = Localizations.chatCreateGroupTitle
        navigationItem.standardAppearance = .transparentAppearance
        navigationItem.standardAppearance?.backgroundColor = UIColor.primaryBg
        
        setupView()
    }

    deinit {
        DDLogDebug("CreateGroupViewController/deinit ")
    }

    var canCreate: Bool {
//        return !textView.text.isEmpty && selectedMembers.count > 0
        return !textView.text.isEmpty
    }

    func setupView() {
        view.addSubview(mainView)
        view.backgroundColor = UIColor.feedBackground
        mainView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        mainView.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        mainView.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        mainView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        
        textView.text = placeholderText
        textView.textColor = .placeholderText
        textView.becomeFirstResponder()
        textView.selectedTextRange = textView.textRange(from: textView.beginningOfDocument, to: textView.beginningOfDocument)
        
        updateCount()
    }
    
    private lazy var mainView: UIStackView = {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        
        let view = UIStackView(arrangedSubviews: [ avatarRow, groupNameLabelRow, textView, membersRow, tableView ])
        
        view.axis = .vertical
        view.spacing = 20
        view.setCustomSpacing(0, after: groupNameLabelRow)
        view.setCustomSpacing(0, after: membersRow)
        
        view.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private lazy var avatarRow: UIStackView = {
        let leftSpacer = UIView()
        leftSpacer.translatesAutoresizingMaskIntoConstraints = false
    
        let rightSpacer = UIView()
        rightSpacer.translatesAutoresizingMaskIntoConstraints = false
        
        let view = UIStackView(arrangedSubviews: [ leftSpacer, avatarBox, rightSpacer ])

        view.axis = .horizontal
        view.distribution = .equalCentering
        
        view.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private lazy var avatarBox: UIView = {
        let viewWidth = Constants.AvatarSize + 40
        let viewHeight = Constants.AvatarSize
        let view = UIView()

        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: viewWidth).isActive = true
        view.heightAnchor.constraint(equalToConstant: viewHeight).isActive = true
        
        view.addSubview(avatarView)
        
        avatarView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        avatarView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        
        photoIcon.frame = CGRect(x: 0 - Constants.PhotoIconSize, y: viewHeight - Constants.PhotoIconSize, width: Constants.PhotoIconSize, height: Constants.PhotoIconSize)
        view.addSubview(photoIcon)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(chooseAvatar))
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(tapGesture)
        
        return view
    }()
    
    private lazy var avatarView: UIImageView = {
        let view = UIImageView()
        view.image = AvatarView.defaultGroupImage
        view.backgroundColor = .avatarDefaultBg
        view.contentMode = .scaleAspectFit

        let radiusRatio: CGFloat = 16/52

        view.layer.masksToBounds = false
        view.layer.cornerRadius = Constants.AvatarSize*radiusRatio
        view.clipsToBounds = true
     
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: Constants.AvatarSize).isActive = true
        view.heightAnchor.constraint(equalToConstant: Constants.AvatarSize).isActive = true
        
        return view
    }()
    
    private lazy var photoIcon: UIImageView = {
        let icon = UIImageView()
        let image = UIImage(named: "ProfileHeaderCamera")
        icon.image = image?.imageResized(to: CGSize(width: 20, height: 20)).withRenderingMode(.alwaysTemplate)
        
        icon.contentMode = .center
        icon.tintColor = UIColor.secondarySystemGroupedBackground
        icon.backgroundColor = UIColor.systemBlue
        icon.layer.masksToBounds = false
        icon.layer.cornerRadius = Constants.PhotoIconSize/2
        icon.clipsToBounds = true
        icon.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
        
        return icon
    }()
    
    private lazy var groupNameLabelRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [groupNameLabel])
        view.axis = .horizontal
        
        view.layoutMargins = UIEdgeInsets(top: 0, left: 15, bottom: 5, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        
        return view
    }()
    
    private lazy var groupNameLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .left
        label.textColor = .secondaryLabel
        label.font = UIFont.preferredFont(forTextStyle: .caption1)
        label.text = "GROUP NAME"
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
    private lazy var textView: UITextView = {
        let view = UITextView()
        view.isScrollEnabled = false
        view.delegate = self
        
        view.backgroundColor = .secondarySystemGroupedBackground
        
        view.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.tintColor = .systemBlue
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private lazy var countRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [characterCounter])
        view.axis = .horizontal
        
        view.layoutMargins = UIEdgeInsets(top: 3, left: 3, bottom: 3, right: 5)
        view.isLayoutMarginsRelativeArrangement = true
        
        return view
    }()
    
    private lazy var characterCounter: UILabel = {
        let label = UILabel()
        label.textAlignment = .right
        label.textColor = .secondaryLabel
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()
    
    private lazy var membersRow: UIStackView = {
        let view = UIStackView(arrangedSubviews: [ membersLabel ])
        
        view.axis = .horizontal
        view.spacing = 20

        view.layoutMargins = UIEdgeInsets(top: 0, left: 15, bottom: 5, right: 0)
        view.isLayoutMarginsRelativeArrangement = true
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    private lazy var membersLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        
        label.font = UIFont.preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.text = "MEMBERS (\(String(selectedMembers.count)))"
      
        label.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
      
        label.translatesAutoresizingMaskIntoConstraints = false
        
        return label
    }()

    private let cellReuseIdentifier = "TableViewCell"
    private lazy var tableView: UITableView = {
        let view = UITableView()
        
        view.backgroundColor = .feedBackground
        view.register(ContactTableViewCell.self, forCellReuseIdentifier: cellReuseIdentifier)
        view.delegate = self
        view.dataSource = self
        
        view.tableFooterView = UIView()
        
        view.translatesAutoresizingMaskIntoConstraints = false
        
        return view
    }()
    
    // MARK: Actions

    @objc private func createAction() {
        navigationItem.rightBarButtonItem?.isEnabled = false
        
        let name = textView.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        MainAppContext.shared.chatData.createGroup(name: name, members: selectedMembers, data: avatarData) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let groupID):
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.view.window?.rootViewController?.dismiss(animated: true, completion: nil)
                    if ServerProperties.isGroupFeedEnabled {
                        self.delegate?.createGroupViewController(self, didCreateGroup: groupID)
                    }
                }
            case .failure(let error):
                DDLogError("CreateGroupViewController/createAction/error \(error)")
                let alert = UIAlertController(title: "No Internet Connection", message: "Please check if you have internet connectivity, then try again.", preferredStyle: UIAlertController.Style.alert)
                alert.addAction(UIAlertAction(title: Localizations.buttonOK, style: UIAlertAction.Style.default, handler: nil))
                self.present(alert, animated: true, completion: nil)

                self.navigationItem.rightBarButtonItem?.isEnabled = true
            }
        }
    }
    
    @objc private func chooseAvatar() {
        let actionSheet = UIAlertController(title: Localizations.chatGroupPhotoTitle, message: nil, preferredStyle: .actionSheet)
        actionSheet.view.tintColor = UIColor.systemBlue
        
        actionSheet.addAction(UIAlertAction(title: Localizations.chatGroupTakeOrChoosePhoto, style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.presentPhotoLibraryPicker()
        })
        
//        actionSheet.addAction(UIAlertAction(title: "Delete Photo", style: .destructive) { _ in
//
//        })
        
        actionSheet.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .cancel))
        present(actionSheet, animated: true)
    }
    
    // MARK: Helpers
    
    private func updateCount() {
        textView.text = String(textView.text.prefix(Constants.MaxNameLength))
        var label = "0"
        if textView.textColor != .placeholderText {
            label = String(textView.text.count)
        }
        characterCounter.text = "\(label)/\(Constants.MaxNameLength)"
    }

    private func presentPhotoLibraryPicker() {
        let pickerController = MediaPickerViewController(filter: .image, multiselect: false, camera: true) { [weak self] controller, media, cancel in
            guard let self = self else { return }

            if cancel || media.count == 0 {
                controller.dismiss(animated: true)
            } else {
                let edit = MediaEditViewController(cropRegion: .square, mediaToEdit: media, selected: 0) { controller, media, index, cancel in
                    controller.dismiss(animated: true)

                    if !cancel && media.count > 0 {
                        if media[0].ready.value {
                            guard let image = media[0].image else { return }
                            self.setAvatar(image: image)
                        } else {
                            self.cancellableSet.insert(
                                media[0].ready.sink { [weak self] ready in
                                    guard let self = self else { return }
                                    guard ready else { return }
                                    guard let image = media[0].image else { return }
                                    self.setAvatar(image: image)
                                }
                            )
                        }
                        
                        self.dismiss(animated: true)
                    }
                }
                
                edit.modalPresentationStyle = .fullScreen
                controller.present(edit, animated: true)
            }
        }
        
        self.present(UINavigationController(rootViewController: pickerController), animated: true)
    }

    private func setAvatar(image: UIImage) {
        guard let resizedImage = image.fastResized(to: CGSize(width: AvatarStore.avatarSize, height: AvatarStore.avatarSize)) else {
            DDLogError("CreateGroupViewController/resizeImage error resize failed")
            return
        }

        let data = resizedImage.jpegData(compressionQuality: CGFloat(UserData.compressionQuality))!

        self.avatarView.image =  UIImage(data: data)
        self.avatarData = data
    }
}

extension CreateGroupViewController: UITextViewDelegate {
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let currentText:String = textView.text
        let updatedText = (currentText as NSString).replacingCharacters(in: range, with: text)

        if updatedText.isEmpty {
            textView.text = placeholderText
            textView.textColor = .placeholderText
            textView.selectedTextRange = textView.textRange(from: textView.beginningOfDocument, to: textView.beginningOfDocument)
            navigationItem.rightBarButtonItem?.isEnabled = false
        } else if textView.textColor == .placeholderText && !text.isEmpty {
            textView.textColor = .label
            DispatchQueue.main.async { // workaround for bug in iOS that causes double capitalizations
                textView.text = text
                self.updateCount()
            }
            
            navigationItem.rightBarButtonItem?.isEnabled = canCreate
        } else {
            return true
        }

        updateCount()
        return false
    }
    
    func textViewDidChangeSelection(_ textView: UITextView) {
        if view.window != nil {
            if textView.textColor == .placeholderText {
                textView.selectedTextRange = textView.textRange(from: textView.beginningOfDocument, to: textView.beginningOfDocument)
            }
        }
    }
    
    func textViewDidChange(_ textView: UITextView) {
        updateCount()
        navigationItem.rightBarButtonItem?.isEnabled = canCreate
    }
    
}

extension CreateGroupViewController: UITableViewDelegate, UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return selectedMembers.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseIdentifier, for: indexPath) as? ContactTableViewCell else {
            return UITableViewCell()
        }
        let index = indexPath.row
        guard selectedMembers.count > index else { return cell }
        let abContacts = MainAppContext.shared.contactStore.contacts(withUserIds: [selectedMembers[index]])
        guard let contact = abContacts.first else { return cell }
        cell.configure(with: contact)
        cell.isUserInteractionEnabled = false
        return cell
    }
    
    // resign keyboard so the entire tableview can be seen
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        textView.resignFirstResponder()
    }
    
}

private extension ContactTableViewCell {

    func configure(with abContact: ABContact) {

        nameLabel.text = abContact.fullName
        subtitleLabel.text = abContact.phoneNumber

        if let userId = abContact.userId {
            contactImage.configure(with: userId, using: MainAppContext.shared.avatarStore)
        }

    }
}

fileprivate extension UIImage {
    func imageResized(to size: CGSize) -> UIImage {
        return UIGraphicsImageRenderer(size: size).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private extension Localizations {
    
    static var chatCreateGroupTitle: String {
        NSLocalizedString("chat.create.group.title", value: "Group Info", comment: "Title of group creation screen")
    }
    
    static var chatCreateGroupNamePlaceholder: String {
        NSLocalizedString("chat.create.group.name.placeholder", value: "Name your group", comment: "Placeholder text shown inside the group name input box when it's empty")
    }
    
    static var chatCreateGroupFailureTitle: String {
        NSLocalizedString("chat.create.group.failure.title", value: "No Internet Connection", comment: "Placeholder text shown inside the group name input box when it's empty")
    }
    
    static var chatCreateGroupFailureDescription: String {
        NSLocalizedString("chat.create.group.failure.description", value: "Please check if you have internet connectivity, then try again.", comment: "Placeholder text shown inside the group name input box when it's empty")
    }
    
}
