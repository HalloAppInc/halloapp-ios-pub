//
//  ComposeViewController.swift
//  Shared Extension
//
//  Copyright © 2021 Halloapp, Inc. All rights reserved.
//
import AVFoundation
import CocoaLumberjackSwift
import Combine
import Core
import CoreCommon
import UIKit
import Social
import Intents
import IntentsUI

fileprivate struct Constants {
    static let textViewTextColor = UIColor.label.withAlphaComponent(0.9)
    static let destinationRowHeight: CGFloat = 100
}

private extension Localizations {

    static var placeholder: String {
        NSLocalizedString("share.composer.placeholder", value: "Write a description", comment: "Placeholder for media caption.")
    }

    static var placeholderTextOnly: String {
        NSLocalizedString("share.composer.placeholder.text", value: "Write a post", comment: "Placeholder when sharing text only.")
    }

    static var uploadingFailedTitle: String {
        NSLocalizedString("share.composer.uploading.fail.title", value: "Uploading failed", comment: "Alert dialog title shown when uploading fails.")
    }

    static var uploadingFailedMessage: String {
        NSLocalizedString("share.composer.uploading.fail.message", value: "Please try again later.", comment: "Alert dialog message shown when uploading fails.")
    }

    static var edit: String {
        NSLocalizedString("share.composer.button.edit", value: "Edit", comment: "Title on edit button")
    }

    static var shareWith: String {
        NSLocalizedString("share.composer.destinations.label", value: "Share with", comment: "Label above the list with whom you share")
    }

    static func uploadingItems(_ numberOfItems: Int) -> String {
        let format = NSLocalizedString("uploading.n.items", comment: "Message how many items are currently being upload")
        return String.localizedStringWithFormat(format, numberOfItems)
    }

    static func upladingBytesProgress(partial: String, total: String) -> String {
        let format = NSLocalizedString("uploading.bytes.progress", value: "%@ of %@", comment: "How many bytes from total have been uploaded")
        return String.localizedStringWithFormat(format, partial, total)
    }
}

class ShareComposerViewController: UIViewController {
    private lazy var loadingView: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .large)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.hidesWhenStopped = true

        return view
    }()

    private var destinations: [ShareDestination]
    private var completion: ([ShareDestination]) -> Void
    private var media: [PendingMedia] = []
    private var text: String = ""
    private var textView: UITextView!
    private var linkPreviewView: PostComposerLinkPreviewView!
    private var textViewPlaceholder: UILabel!
    private var textViewHeightConstraint: NSLayoutConstraint!
    private var bottomConstraint: NSLayoutConstraint!
    private var cardViewHeightConstraint: NSLayoutConstraint!
    private var mentionPicker: MentionPickerView?
    private var collectionView: UICollectionView!
    private var pageControl: UIPageControl!
    private var cancellableSet: Set<AnyCancellable> = []
    private var linkPreviewData: LinkPreviewData?
    private var linkViewImage: UIImage?
    private var linkPreviewMedia: PendingMedia?
    private var progressUploadMonitor: ProgressUploadMonitor?

    private var mentions = MentionRangeMap()
    private lazy var mentionableUsers: [MentionableUser] = {
        Mentions.mentionableUsersForNewPost()
    }()
    var mentionInput: MentionInput {
        MentionInput(text: textView.text, mentions: mentions, selectedRange: textView.selectedRange)
    }

    private lazy var destinationRowLabel: UIView = {
        let labelText = Localizations.shareWith.uppercased() + ":"
        let attributedText = NSMutableAttributedString(string: labelText)
        attributedText.addAttribute(.kern, value: 0.7, range: NSRange(location: 0, length: labelText.count))

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.attributedText = attributedText
        label.textColor = .primaryBlackWhite.withAlphaComponent(0.45)
        label.font = .preferredFont(forTextStyle: .caption1)

        return label
    }()

    private lazy var destinationRow: ShareDestinationRowView = {
        let rowView = ShareDestinationRowView() { [weak self] index in
            guard let self = self else { return }

            self.destinations.remove(at: index)

            if self.destinations.isEmpty {
                self.backAction()
            } else {
                self.destinationRow.update(with: self.destinations)
            }
        }
        rowView.translatesAutoresizingMaskIntoConstraints = false

        return rowView
    } ()

    init(destinations: [ShareDestination], completion: @escaping ([ShareDestination]) -> Void) {
        self.destinations = destinations
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        isModalInPresentation = true
        view.backgroundColor = .primaryBg
        setupNavigationBar()

        view.addSubview(loadingView)
        loadingView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        loadingView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true

        loadingView.startAnimating()

        cancellableSet.insert(ShareDataLoader.shared.ready.sink { [weak self] ready in
            guard ready else { return }
            guard let self = self else { return }

            self.text = ShareDataLoader.shared.text
            self.media = ShareDataLoader.shared.media

            self.loadingView.stopAnimating()
            self.setupUI()
        })
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        pauseAllVideos()
    }

    private func setupNavigationBar() {
        let shareButton = UIBarButtonItem(title: Localizations.buttonShare, style: .done, target: self, action: #selector(shareAction))
        shareButton.tintColor = .systemBlue

        let contactsOnly = destinations.filter {
            if case .contact(_) = $0 {
                return false
            } else {
                return true
            }
        }.count == 0

        if contactsOnly {
            shareButton.title = Localizations.buttonSend
        }

        title = Localizations.appNameHalloApp
        navigationItem.rightBarButtonItem = shareButton
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarBack"), style: .plain, target: self, action: #selector(backAction))
    }

    private func setupUI() {
        var constraints: [NSLayoutConstraint] = []

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .onDrag
        scrollView.delegate = self
        view.addSubview(scrollView)

        let contentView = UIStackView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.axis = .vertical
        contentView.alignment = .center
        scrollView.addSubview(contentView)

        textView = makeTextView()
        textViewPlaceholder = makeTextViewPlaceholder()
        textView.addSubview(textViewPlaceholder)

        view.addSubview(destinationRow)
        view.addSubview(destinationRowLabel)

        textViewHeightConstraint = textView.heightAnchor.constraint(equalToConstant: computeTextViewHeight())

        if media.count > 0 {
            contentView.spacing = 10

            collectionView = makeCollectionView()
            contentView.addArrangedSubview(collectionView)

            if media.count > 1 {
                pageControl = makePageControl()
                contentView.addArrangedSubview(pageControl)
            }

            textView.textContainerInset = UIEdgeInsets(top: 14, left: 18, bottom: 8, right: 18)

            let textViewContainer = UIView()
            textViewContainer.translatesAutoresizingMaskIntoConstraints = false
            textViewContainer.backgroundColor = .secondarySystemGroupedBackground
            textViewContainer.layer.cornerRadius = 24
            textViewContainer.layer.shadowColor = UIColor.black.cgColor
            textViewContainer.layer.shadowOpacity = 0.05
            textViewContainer.layer.shadowOffset = CGSize(width: 0, height: 1)
            textViewContainer.layer.shadowRadius = 2
            textViewContainer.addSubview(textView)
            textView.constrain(to: textViewContainer)

            let bottomRowContainer = UIView()
            bottomRowContainer.translatesAutoresizingMaskIntoConstraints = false
            bottomRowContainer.addSubview(textViewContainer)
            view.addSubview(bottomRowContainer)

            bottomConstraint = bottomRowContainer.bottomAnchor.constraint(equalTo: destinationRowLabel.topAnchor, constant: -8)

            constraints.append(contentsOf: [
                textViewHeightConstraint,
                collectionView.widthAnchor.constraint(equalTo: contentView.widthAnchor),
                bottomRowContainer.topAnchor.constraint(equalTo: scrollView.bottomAnchor),
                bottomRowContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                bottomRowContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                textViewContainer.topAnchor.constraint(equalTo: bottomRowContainer.topAnchor, constant: 10),
                textViewContainer.bottomAnchor.constraint(equalTo: bottomRowContainer.bottomAnchor, constant: -10),
                textViewContainer.leadingAnchor.constraint(equalTo: bottomRowContainer.leadingAnchor, constant: 20),
                textViewContainer.trailingAnchor.constraint(equalTo: bottomRowContainer.trailingAnchor, constant: -20),
                textViewPlaceholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 23),
                textViewPlaceholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: 14),
            ])
        } else {
            contentView.spacing = 0
            contentView.backgroundColor = .feedPostBackground
            contentView.layer.cornerRadius = 15
            contentView.layer.shadowColor = UIColor.black.cgColor
            contentView.layer.shadowOpacity = 0.05
            contentView.layer.shadowOffset = CGSize(width: 0, height: 5)
            contentView.layer.shadowRadius = 10
            contentView.clipsToBounds = true
            contentView.alignment = .fill
            contentView.isLayoutMarginsRelativeArrangement = true
            contentView.layoutMargins = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

            textView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
            linkPreviewView = makeLinkPreviewView()
            contentView.addArrangedSubview(textView)
            contentView.addArrangedSubview(linkPreviewView)


            bottomConstraint = scrollView.bottomAnchor.constraint(equalTo: destinationRowLabel.topAnchor, constant: -8)

            constraints.append(contentsOf: [
                textViewPlaceholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 25),
                textViewPlaceholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: 20),
            ])
        }

        cardViewHeightConstraint = contentView.heightAnchor.constraint(equalToConstant: computeCardViewHeight())

        constraints.append(contentsOf: [
            cardViewHeightConstraint,
            bottomConstraint,

            destinationRowLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            destinationRowLabel.bottomAnchor.constraint(equalTo: destinationRow.topAnchor, constant: -8),

            destinationRow.heightAnchor.constraint(equalToConstant: Constants.destinationRowHeight),
            destinationRow.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            destinationRow.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            destinationRow.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            scrollView.contentLayoutGuide.widthAnchor.constraint(equalTo: view.widthAnchor),
            scrollView.contentLayoutGuide.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),
            scrollView.contentLayoutGuide.heightAnchor.constraint(greaterThanOrEqualTo: contentView.heightAnchor, constant: 16),

            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: media.count > 0 ? 0 : 8),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: media.count > 0 ? 0 : -8),
            contentView.centerYAnchor.constraint(equalTo: scrollView.contentLayoutGuide.centerYAnchor),
        ])

        updateLinkPreviewViewIfNecessary()
        NSLayoutConstraint.activate(constraints)
        destinationRow.update(with: destinations)
        handleKeyboardUpdates()

        if media.count == 0 {
            // ensures that layout is done before getting focus
            DispatchQueue.main.async {
                self.textView.becomeFirstResponder()
            }
        }
    }

    private func handleKeyboardUpdates() {
        cancellableSet.insert(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification).sink { [weak self] notification in
            guard let self = self else { return }
            self.animateWithKeyboard(notification: notification) {
                self.bottomConstraint.constant = -$0 + Constants.destinationRowHeight + self.destinationRowLabel.bounds.height + 8
            }
        })

        cancellableSet.insert(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification).sink { [weak self] notification in
            guard let self = self else { return }
            self.animateWithKeyboard(notification: notification) { _ in
                self.bottomConstraint.constant = -8

                // Share Extension is displayed modally and when that modal view is scrolled
                // the keyboard is hidden without really resigning the text view
                DispatchQueue.main.async {
                    self.textView.resignFirstResponder()
                }
            }
        })
    }

    private func animateWithKeyboard(notification: Notification, animations: @escaping (CGFloat) -> Void) {
        let durationKey = UIResponder.keyboardAnimationDurationUserInfoKey
        guard let duration = notification.userInfo?[durationKey] as? Double else { return }

        let frameKey = UIResponder.keyboardFrameEndUserInfoKey
        guard let keyboardFrameValue = notification.userInfo?[frameKey] as? NSValue else { return }

        let curveKey = UIResponder.keyboardAnimationCurveUserInfoKey
        guard let curveValue = notification.userInfo?[curveKey] as? Int else { return }
        guard let curve = UIView.AnimationCurve(rawValue: curveValue) else { return }

        let animator = UIViewPropertyAnimator(duration: duration, curve: curve) {
            animations(keyboardFrameValue.cgRectValue.height)
            self.view?.layoutIfNeeded()
        }

        animator.startAnimation()
    }

    private func computeCardViewHeight() -> CGFloat {
        if media.count == 0 {
            return min(view.bounds.height - 420, 400)
        }

        let ratios: [CGFloat] = media.compactMap {
            guard let size = $0.size, size.width > 0 else { return nil }
            return size.height / size.width
        }

        guard let maxRatio = ratios.max() else { return 0 }

        return min(view.bounds.height - 320, view.bounds.width * maxRatio)
    }

    private func computeTextViewHeight() -> CGFloat {
        var width = textView.frame.size.width > 0 ? textView.frame.size.width : UIScreen.main.bounds.width * 0.9
        width += textView.textContainerInset.left + textView.textContainerInset.right
        let size = textView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))

        if media.count > 0 {
            return max(48, min(size.height, 250))
        } else if let linkPreviewView = linkPreviewView, !linkPreviewView.isHidden {
            let previewHeight = linkPreviewView.frame.size.height > 0 ? linkPreviewView.frame.size.height : 250
            return computeCardViewHeight() - previewHeight - 10
        } else {
            return computeCardViewHeight()
        }
    }

    private func makeTextView() -> UITextView {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = Constants.textViewTextColor
        textView.text = text
        textView.backgroundColor = .clear
        textView.delegate = self

        let contacts = destinations.filter {
            if case .contact(_) = $0 {
                return true
            } else {
                return false
            }
        }

        if contacts.count == 0 {
            mentionPicker = makeMentionPicker()
            textView.inputAccessoryView = mentionPicker
        }

        return textView
    }

    private func makeTextViewPlaceholder() -> UILabel {
        let placeholder = UILabel()
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.font = .preferredFont(forTextStyle: .body)
        placeholder.textColor = UIColor.label.withAlphaComponent(0.5)
        placeholder.text = media.count > 0 ? Localizations.placeholder : Localizations.placeholderTextOnly
        placeholder.isHidden = text.count > 0

        return placeholder
    }

    private func makeMentionPicker() -> MentionPickerView {
        let picker = MentionPickerView(avatarStore: ShareExtensionContext.shared.avatarStore)
        picker.cornerRadius = 10
        picker.borderColor = .systemGray
        picker.borderWidth = 1
        picker.clipsToBounds = true
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.isHidden = true
        picker.didSelectItem = { [weak self] item in self?.acceptMentionPickerItem(item) }
        picker.heightAnchor.constraint(lessThanOrEqualToConstant: 120).isActive = true

        return picker
    }

    private func makeCollectionView() -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.sectionInset = .zero
        layout.scrollDirection = .horizontal

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.backgroundColor = .clear
        collectionView.isPrefetchingEnabled = false
        collectionView.dataSource = self
        collectionView.delegate = self

        collectionView.register(ImageCell.self, forCellWithReuseIdentifier: ImageCell.reuseIdentifier)
        collectionView.register(VideoCell.self, forCellWithReuseIdentifier: VideoCell.reuseIdentifier)
        collectionView.register(EmptyCell.self, forCellWithReuseIdentifier: EmptyCell.reuseIdentifier)

        let closeKeyboardByTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(hideKeyboardAction))
        collectionView.addGestureRecognizer(closeKeyboardByTapRecognizer)

        return collectionView
    }

    private func makeLinkPreviewView() -> PostComposerLinkPreviewView  {
        let linkPreviewView = PostComposerLinkPreviewView() {
            resetLink, linkPreviewData, linkPreviewImage in
            if resetLink {
                self.linkPreviewView.isHidden = true
            }
            self.linkPreviewData = linkPreviewData
            self.linkViewImage = linkPreviewImage
        }
        linkPreviewView.translatesAutoresizingMaskIntoConstraints = false
        linkPreviewView.isHidden = true
        return linkPreviewView
    }

    private func makePageControl() -> UIPageControl {
        let pageControl = UIPageControl()
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.numberOfPages = media.count
        pageControl.currentPageIndicatorTintColor = .lavaOrange
        pageControl.pageIndicatorTintColor = UIColor.black.withAlphaComponent(0.2)
        pageControl.addTarget(self, action: #selector(pageChangeAction), for: .valueChanged)

        return pageControl
    }

    // MARK: Link Preview
    private func updateLinkPreviewViewIfNecessary() {
        if let url = detectLink(text: textView.text), let linkPreviewView = linkPreviewView {
            linkPreviewView.updateLink(url: url)
            linkPreviewView.isHidden = false
        } else {
            // TODO reset link preview info
            if let linkPreviewView = linkPreviewView {
                linkPreviewView.isHidden = true
            }
        }

        textViewHeightConstraint.constant = computeTextViewHeight()
    }

    private func detectLink(text: String) -> URL? {
        let linkDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let text = text
        let matches = linkDetector.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let url = text[range]
            if let url = URL(string: String(url)) {
                // We only care about the first link
                return url
            }
        }
        return nil
    }

    // MARK: Mentions
    private func fetchMentionPickerContent(for input: MentionInput) -> [MentionableUser] {
        guard let mentionCandidateRange = input.rangeOfMentionCandidateAtCurrentPosition() else {
            return []
        }

        let mentionCandidate = input.text[mentionCandidateRange]
        let trimmedInput = String(mentionCandidate.dropFirst())
        
        return mentionableUsers.filter {
            Mentions.isPotentialMatch(fullName: $0.fullName, input: trimmedInput)
        }
    }

    private func updateMentionPickerContent() {
        guard let picker = mentionPicker else { return }
        picker.items = fetchMentionPickerContent(for: mentionInput)
        picker.isHidden = picker.items.isEmpty
    }

    private func acceptMentionPickerItem(_ item: MentionableUser) {
        var input = mentionInput
        guard let mentionCandidateRange = input.rangeOfMentionCandidateAtCurrentPosition() else {
            // For now we assume there is a word to replace (but in theory we could just insert at point)
            return
        }

        let utf16Range = NSRange(mentionCandidateRange, in: input.text)
        input.addMention(name: item.fullName, userID: item.userID, in: utf16Range)
        textView.text = input.text
        textView.selectedRange = input.selectedRange
        mentions = input.mentions

        updateMentionPickerContent()
    }

    // MARK: Markdown

    private func updateWithMarkdown() {
        guard textView.markedTextRange == nil else { return } // account for IME
        let font = textView.font ?? UIFont.preferredFont(forTextStyle: .body)
        let color = Constants.textViewTextColor

        let ham = HAMarkdown(font: font, color: color)
        if let text = textView.text {
            if let selectedRange = textView.selectedTextRange {
                textView.attributedText = ham.parseInPlace(text)
                textView.selectedTextRange = selectedRange
            }
        }
    }

    // MARK: Actions

    @objc func shareAction() {
        guard media.count > 0 || !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let linkViewImage = linkViewImage {
            linkPreviewMedia = PendingMedia(type: .image)
            linkPreviewMedia?.image = linkViewImage
            guard let linkPreviewMedia = linkPreviewMedia else { return }
            if linkPreviewMedia.ready.value {
                share()
            } else {
                self.cancellableSet.insert(
                    linkPreviewMedia.ready.sink { [weak self] ready in
                        guard let self = self else { return }
                        guard ready else { return }
                        self.share()
                    }
                )
            }
        } else {
            share()
        }
    }

    private func share() {
        showUploadingAlert()

        let queue = DispatchQueue(label: "com.halloapp.share.prepare", qos: .userInitiated)
        ShareExtensionContext.shared.coreService.execute(whenConnectionStateIs: .connected, onQueue: queue) {
            self.prepareAndUpload()
        }
    }

    @objc func backAction() {
        navigationController?.popViewController(animated: true)
        completion(destinations)
    }

    @objc func pageChangeAction() {
        let x = collectionView.frame.width * CGFloat(pageControl.currentPage)
        collectionView.setContentOffset(CGPoint(x: x, y: collectionView.contentOffset.y), animated: true)
    }

    @objc func hideKeyboardAction() {
        textView.resignFirstResponder()
    }

    private func showUploadingAlert() {
        let bytesCount = Int64(media
            .compactMap { try? $0.fileURL?.resourceValues(forKeys: [.fileSizeKey]).fileSize }
            .reduce(0) { $0 + $1 })

        progressUploadMonitor = ProgressUploadMonitor(mediaCount: media.count, bytesCount: bytesCount)

        DispatchQueue.main.async {
            guard let alert = self.progressUploadMonitor?.alert else { return }
            self.present(alert, animated: true)
        }
    }

    private func showUploadingFailedAlert() {
        let alert = UIAlertController(title: Localizations.uploadingFailedTitle, message: Localizations.uploadingFailedMessage, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .default))

        DispatchQueue.main.async {
            self.present(alert, animated: true)
        }
    }

    private func pauseAllVideos() {
        guard collectionView != nil else { return }
        for cell in collectionView.visibleCells {
            if let cell = cell as? VideoCell {
                cell.pause()
            }
        }
    }

    private func prepareAndUpload() {
        let text = mentionInput.text.trimmingCharacters(in: .whitespacesAndNewlines)

        let mentionText = MentionText(
            expandedText: mentionInput.text,
            mentionRanges: mentionInput.mentions).trimmed()

        let uploadDispatchGroup = DispatchGroup()
        var results = [Result<String, Error>]()

        for (index, item) in media.enumerated() {
            if let url = item.fileURL {
                ImageServer.shared.attach(for: url, id: ShareExtensionContext.shared.dataStore.mediaProcessingId, index: index)
            }
        }

        for destination in destinations {
            uploadDispatchGroup.enter()

            switch destination {
            case .feed:
                DDLogInfo("ShareComposerViewController/upload feed")
                ShareExtensionContext.shared.dataStore.post(text: mentionText, media: media, linkPreviewData: linkPreviewData, linkPreviewMedia: linkPreviewMedia) {
                    results.append($0)
                    uploadDispatchGroup.leave()
                }
            case .group(let group):
                DDLogInfo("ShareComposerViewController/upload group")
                ShareExtensionContext.shared.dataStore.post(group: group, text: mentionText, media: media, linkPreviewData: linkPreviewData, linkPreviewMedia: linkPreviewMedia) {
                    results.append($0)
                    uploadDispatchGroup.leave()
                }
                addIntent(chatGroup: group)
            case .contact(let contact):
                DDLogInfo("ShareComposerViewController/upload contact")
                guard let userId = contact.userId else { return }
                ShareExtensionContext.shared.dataStore.send(to: userId, text: text, media: media, linkPreviewData: linkPreviewData, linkPreviewMedia: linkPreviewMedia) {
                    results.append($0)
                    uploadDispatchGroup.leave()
                }
                addIntent(toUserId: userId)
            }
        }

        uploadDispatchGroup.notify(queue: DispatchQueue.main) {
            for result in results {
                switch result {
                case .success(let id):
                    DDLogInfo("ShareComposerViewController/upload/success id=[\(id)]")
                case .failure(let error):
                    DDLogError("ShareComposerViewController/upload/error [\(error)]")
                }
            }

            let fail = results.filter {
                switch $0 {
                case .success(_):
                    return false
                case .failure(_):
                    return true
                }
            }.count > 0

            if fail {
                self.dismiss(animated: false)
                self.showUploadingFailedAlert()
            } else {
                ImageServer.shared.clearAllTasks(keepFiles: false)
                ShareDataLoader.shared.reset()
                self.progressUploadMonitor?.setProgress(1, animated: true)

                // We need to update presence after successfully posting.
                ShareExtensionContext.shared.coreService.sendPresenceIfPossible(.available)
                ShareExtensionContext.shared.coreService.sendPresenceIfPossible(.away)

                // let the user observe the full progress
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    self.extensionContext?.completeRequest(returningItems: nil)
                }
            }
        }
    }
    
    /// Donates an intent to Siri for improved suggestions when sharing content.
    /// Intents are used by iOS to provide contextual suggestions to the user for certain interactions. In this case, we are suggesting the user send another message to the user they just shared with.
    /// For more information, see [this documentation](https://developer.apple.com/documentation/sirikit/insendmessageintent)\.
    /// - Parameter chatGroup: The ID for the group the user is sharing to
    /// - Remark: This is different from the implementation in `FeedData.swift` because `MainAppContext` isn't available.
    private func addIntent(chatGroup: GroupListSyncItem) {
        if #available(iOS 14.0, *) {
            let recipient = INSpeakableString(spokenPhrase: chatGroup.name)
            let sendMessageIntent = INSendMessageIntent(recipients: nil,
                                                        content: nil,
                                                        speakableGroupName: recipient,
                                                        conversationIdentifier: ConversationID(id: chatGroup.id, type: .group).description,
                                                        serviceName: nil,
                                                        sender: nil)
            
            let potentialUserAvatar = ShareExtensionContext.shared.avatarStore.groupAvatarData(for: chatGroup.id).image
            guard let defaultAvatar = UIImage(named: "AvatarGroup") else { return }
            
            // Have to convert UIImage to data and then NIImage because NIImage(uiimage: UIImage) initializer was throwing exception
            guard let userAvaterUIImage = (potentialUserAvatar ?? defaultAvatar).pngData() else { return }
            let userAvatar = INImage(imageData: userAvaterUIImage)
            
            sendMessageIntent.setImage(userAvatar, forParameterNamed: \.speakableGroupName)
            
            let interaction = INInteraction(intent: sendMessageIntent, response: nil)
            interaction.donate(completion: { error in
                if let error = error {
                    DDLogDebug("ChatViewController/sendMessage/\(error.localizedDescription)")
                }
            })
        }
    }
    
    /// Donates an intent to Siri for improved suggestions when sharing content.
    ///
    /// Intents are used by iOS to provide contextual suggestions to the user for certain interactions. In this case, we are suggesting the user send another message to the user they just shared with.
    /// For more information, see [this documentation](https://developer.apple.com/documentation/sirikit/insendmessageintent)\.
    /// - Parameter toUserId: The user ID for the person the user just shared with
    /// - Remark: This is different from the implementation in `ChatData.swift` because `MainAppContext` isn't available in the share extension.
    private func addIntent(toUserId: UserID) {
        if #available(iOS 14.0, *) {
            guard let fullName = ShareExtensionContext.shared.contactStore.fullNameIfAvailable(for: toUserId, ownName: Localizations.meCapitalized) else { return }
            
            let recipient = INSpeakableString(spokenPhrase: fullName)
            let sendMessageIntent = INSendMessageIntent(recipients: nil,
                                                        content: nil,
                                                        speakableGroupName: recipient,
                                                        conversationIdentifier: ConversationID(id: toUserId, type: .chat).description,
                                                        serviceName: nil, sender: nil)
            
            let potentialUserAvatar = ShareExtensionContext.shared.avatarStore.userAvatar(forUserId: toUserId).image
            guard let defaultAvatar = UIImage(named: "AvatarUser") else { return }
            
            // Have to convert UIImage to data and then NIImage because NIImage(uiimage: UIImage) initializer was throwing exception
            guard let userAvaterUIImage = (potentialUserAvatar ?? defaultAvatar).pngData() else { return }
            let userAvatar = INImage(imageData: userAvaterUIImage)
            
            sendMessageIntent.setImage(userAvatar, forParameterNamed: \.speakableGroupName)
            
            let interaction = INInteraction(intent: sendMessageIntent, response: nil)
            interaction.donate(completion: { error in
                if let error = error {
                    DDLogDebug("ChatViewController/sendMessage/\(error.localizedDescription)")
                }
            })
        }
    }
}


// MARK: UITextViewDelegate
extension ShareComposerViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        textViewPlaceholder.isHidden = !textView.text.isEmpty
        textViewHeightConstraint.constant = computeTextViewHeight()

        updateMentionPickerContent()
        updateLinkPreviewViewIfNecessary()
        updateWithMarkdown()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        updateMentionPickerContent()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard mentionPicker != nil else { return true }

        var input = mentionInput

        // Treat mentions atomically (editing any part of the mention should remove the whole thing)
        let rangeIncludingImpactedMentions = input
            .impactedMentionRanges(in: range)
            .reduce(range) { range, mention in NSUnionRange(range, mention) }

        input.changeText(in: rangeIncludingImpactedMentions, to: text)

        if range == rangeIncludingImpactedMentions {
            // Update mentions and return true so UITextView can update text without breaking IME
            mentions = input.mentions
            return true
        } else {
            // Update content ourselves and return false so UITextView doesn't issue conflicting update
            textView.text = input.text
            textView.selectedRange = input.selectedRange
            mentions = input.mentions
            return false
        }
    }
}

// MARK: UIScrollViewDelegate
extension ShareComposerViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == collectionView {
            let rem = collectionView.contentOffset.x.truncatingRemainder(dividingBy: scrollView.frame.width)

            if rem == 0 {
                pageControl.currentPage = Int(collectionView.contentOffset.x / collectionView.frame.width)
                pauseAllVideos()
            }
        }
    }
}

// MARK: UICollectionView
extension ShareComposerViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return media.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch media[indexPath.row].type {
        case .image:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ImageCell.reuseIdentifier, for: indexPath) as! ImageCell
            cell.configure(media[indexPath.row]) { [weak self] in
                self?.edit(index: indexPath.row)
            }
            return cell
        case .video:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: VideoCell.reuseIdentifier, for: indexPath) as! VideoCell
            cell.configure(media[indexPath.row]) { [weak self] in
                self?.edit(index: indexPath.row)
            }
            return cell
        case .audio:
            return collectionView.dequeueReusableCell(withReuseIdentifier: EmptyCell.reuseIdentifier, for: indexPath)
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return collectionView.bounds.size
    }

    private func edit(index: Int) {
        let controller = MediaEditViewController(mediaToEdit: media, selected: index, maxAspectRatio: nil) { [weak self] controller, media, selected, cancel in
            controller.dismiss(animated: true)

            guard let self = self else { return }
            guard !cancel else { return }

            self.media = media

            let readyPublisher = Publishers.MergeMany(media.map { $0.ready.filter { $0 } }).allSatisfy { $0 } .eraseToAnyPublisher()
            self.cancellableSet.insert(readyPublisher.sink { [weak self] ready in
                guard let self = self else { return }
                guard ready else { return }

                self.collectionView.reloadData()
                self.collectionView.scrollToItem(at: IndexPath(row: selected, section: 0), at: .centeredHorizontally, animated: false)
            })

        }.withNavigationController()

        present(controller, animated: true)
    }
}

fileprivate class EmptyCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: EmptyCell.self)
    }
}

fileprivate class ImageCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: ImageCell.self)
    }

    private lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true

        return imageView
    }()

    private lazy var editButton: UIButton = {
        let background = BlurView(effect: UIBlurEffect(style: .systemUltraThinMaterial), intensity: 1)
        background.translatesAutoresizingMaskIntoConstraints = false
        background.isUserInteractionEnabled = false

        let imageConfig = UIImage.SymbolConfiguration(pointSize: 22)
        let image = UIImage(systemName: "pencil.circle.fill", withConfiguration: imageConfig)?.withTintColor(.white, renderingMode: .alwaysOriginal)

        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(image, for: .normal)
        button.setTitle(Localizations.edit, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        button.layer.cornerRadius = 17
        button.clipsToBounds = true
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 12)
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 1, right: 6)
        button.addTarget(self, action: #selector(editAction), for: .touchUpInside)

        button.insertSubview(background, at: 0)
        if let imageView = button.imageView {
            button.bringSubviewToFront(imageView)
        }
        if let titleLabel = button.titleLabel {
            button.bringSubviewToFront(titleLabel)
        }

        background.constrain(to: button)
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 34)
        ])

        return button
    }()

    private lazy var editButtonTrailing: NSLayoutConstraint = {
        editButton.trailingAnchor.constraint(equalTo: imageView.trailingAnchor)
    }()

    private lazy var editButtonBottom: NSLayoutConstraint = {
        editButton.bottomAnchor.constraint(equalTo: imageView.bottomAnchor)
    }()

    private var onEdit: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        contentView.addSubview(imageView)
        contentView.addSubview(editButton)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            editButtonTrailing,
            editButtonBottom,
        ])
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
    }

    // Loading image on demand instead of using 'media.image'
    // makes it easier for the system to clear memory and avoid
    // going over memory limit (120MB on iPhone 11 & iOS 14)
    func configure(_ media: PendingMedia, onEdit: @escaping () -> Void) {
        guard media.type == .image else { return }
        guard let url = media.fileURL else { return }

        self.onEdit = onEdit

        let maxSize = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * UIScreen.main.scale * 0.75

        imageView.image = UIImage.thumbnail(contentsOf: url, maxPixelSize: maxSize)

        // required to ensure that everything is in place for getting the correct sizes
        DispatchQueue.main.async {
            self.configureAfterImageLoad()
        }
    }

    private func configureAfterImageLoad() {
        imageView.roundCorner(20)

        if let imageRect = imageView.getImageRect() {
            editButtonTrailing.constant = imageRect.maxX - imageView.bounds.width - 9
            editButtonBottom.constant = imageRect.maxY - imageView.bounds.height - 9
        }
    }

    @objc func editAction() {
        onEdit?()
    }
}

class VideoCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: VideoCell.self)
    }

    private lazy var videoView: VideoView = {
        let view = VideoView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.roundCorner(20)
        return view
    }()

    private lazy var editButton: UIButton = {
        let background = BlurView(effect: UIBlurEffect(style: .systemUltraThinMaterial), intensity: 1)
        background.translatesAutoresizingMaskIntoConstraints = false
        background.isUserInteractionEnabled = false

        let imageConfig = UIImage.SymbolConfiguration(pointSize: 18)
        let image = UIImage(systemName: "pencil.circle.fill", withConfiguration: imageConfig)?.withTintColor(.white, renderingMode: .alwaysOriginal)

        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(image, for: .normal)
        button.setTitle(Localizations.edit, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        button.layer.cornerRadius = 15
        button.clipsToBounds = true
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 12)
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 4, bottom: 1, right: 6)
        button.addTarget(self, action: #selector(editAction), for: .touchUpInside)

        button.insertSubview(background, at: 0)
        if let imageView = button.imageView {
            button.bringSubviewToFront(imageView)
        }
        if let titleLabel = button.titleLabel {
            button.bringSubviewToFront(titleLabel)
        }

        background.constrain(to: button)
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 30)
        ])

        return button
    }()

    private lazy var editButtonTrailing: NSLayoutConstraint = {
        editButton.trailingAnchor.constraint(equalTo: videoView.trailingAnchor)
    }()

    private lazy var editButtonBottom: NSLayoutConstraint = {
        editButton.bottomAnchor.constraint(equalTo: videoView.bottomAnchor)
    }()

    private var videoRectDidChangeCancellable: AnyCancellable?
    private var onEdit: (() -> Void)?

    override func prepareForReuse() {
        super.prepareForReuse()

        videoView.player?.pause()
        videoView.player = nil
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        videoView.player?.pause()
        videoView.player = nil
    }

    public func setup() {
        contentView.addSubview(videoView)
        contentView.addSubview(editButton)

        NSLayoutConstraint.activate([
            videoView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            videoView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            videoView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            videoView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            editButtonTrailing,
            editButtonBottom,
        ])
    }

    func configure(_ media: PendingMedia, onEdit: @escaping () -> Void) {
        guard media.type == .video else { return }
        guard let url = media.fileURL else { return }
        videoView.player = AVPlayer(url: url)


        editButtonTrailing.constant = videoView.videoRect.maxX - videoView.bounds.width - 9
        editButtonBottom.constant = videoView.videoRect.maxY - videoView.bounds.height - 9

        videoRectDidChangeCancellable?.cancel()
        videoRectDidChangeCancellable = videoView.videoRectDidChange.sink { [weak self] rect in
            guard let self = self else { return }
            self.editButtonTrailing.constant = rect.maxX - self.videoView.bounds.width - 9
            self.editButtonBottom.constant = rect.maxY - self.videoView.bounds.height - 9
        }

        self.onEdit = onEdit
    }

    func play(time: CMTime = .zero) {
        videoView.player?.seek(to: time)
        videoView.player?.play()
    }

    func pause() {
        videoView.player?.pause()
    }

    func currentTime() -> CMTime {
        guard let player = videoView.player else { return .zero }
        return player.currentTime()
    }

    func isPlaying() -> Bool {
        guard let player = videoView.player else { return false }
        return player.rate > 0
    }

    @objc func editAction() {
        onEdit?()
    }
}

fileprivate class ProgressUploadMonitor {
    private var processingProgressCancellable: AnyCancellable?
    private var uploadProgressCancellable: AnyCancellable?
    private var mediaUploader: MediaUploader {
        ShareExtensionContext.shared.dataStore.mediaUploader
    }
    private let mediaCount: Int
    private let totalBytesCount: Int64
    private let totalBytesString: String

    let alert: UIAlertController

    private lazy var progressView: UIProgressView = {
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.frame = CGRect(x: 27, y: 56, width: alert.view.bounds.width - 54 , height: 10)
        progressView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        progressView.isUserInteractionEnabled = false

        return progressView
    }()

    init(mediaCount: Int, bytesCount: Int64) {
        self.mediaCount = mediaCount
        totalBytesCount = bytesCount
        totalBytesString = ByteCountFormatter.string(fromByteCount: bytesCount, countStyle: .file)

        alert = UIAlertController(title: Localizations.uploadingItems(mediaCount), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .default) { _ in
            ShareExtensionContext.shared.dataStore.cancelSending()
        })

        if mediaCount > 0 {
            alert.message = progressMessage(bytesCount: 0)
            alert.view.addSubview(progressView)
            listenForProgress()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func progressMessage(bytesCount: Int64) -> String {
        let bytesCountString = ByteCountFormatter.string(fromByteCount: bytesCount, countStyle: .file)
        let message = Localizations.upladingBytesProgress(partial: bytesCountString, total: totalBytesString)
        return "\n\n\(message)"
    }

    private func listenForProgress() {
        processingProgressCancellable = ImageServer.shared.progress.receive(on: DispatchQueue.main).sink { [weak self] id in
            guard let self = self else { return }
            self.updateProgress(for: id)
        }

        uploadProgressCancellable = mediaUploader.uploadProgressDidChange.receive(on: DispatchQueue.main).sink { [weak self] id in
            guard let self = self else { return }
            self.updateProgress(for: id)
        }
    }

    private func updateProgress(for id: String) {
        var (processingCount, processingProgress) = ImageServer.shared.progress(for: id)
        var (uploadCount, uploadProgress) = mediaUploader.uploadProgress(forGroupId: id)

        processingProgress = processingProgress * Float(processingCount) / Float(mediaCount)
        uploadProgress = uploadProgress * Float(uploadCount) / Float(mediaCount)
        let progress = (processingProgress + uploadProgress) / 2

        setProgress(progress, animated: true)
    }

    func setProgress(_ progress: Float, animated: Bool) {
        alert.message = progressMessage(bytesCount: Int64(Float(totalBytesCount) * progress))
        progressView.setProgress(progress, animated: animated)
    }
}
