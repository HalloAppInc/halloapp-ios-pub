//
//  ComposeViewController.swift
//  Shared Extension
//
//  Copyright © 2021 Halloapp, Inc. All rights reserved.
//

import AVFoundation
import CocoaLumberjack
import Combine
import Core
import UIKit
import Social

private extension Localizations {
    static var titleDestinationFeed: String {
        NSLocalizedString("share.composer.title.feed", value: "New Post", comment: "Composer title when sharing to feed")
    }

    static var titleDestinationContact: String {
        NSLocalizedString("share.composer.title.contact", value: "New Message", comment: "Composer title when sharing with a contact")
    }

    static func subtitle(group name: String) -> String {
        let format = NSLocalizedString("share.composer.subtitle.group", value: "Sharing with %@", comment: "Composer subtitle for group posts")
        return String.localizedStringWithFormat(format, name)
    }

    static func subtitle(contact name: String) -> String {
        let format = NSLocalizedString("share.composer.subtitle.contact", value: "Sending to %@", comment: "Composer subtitle when sharing with a contact")
        return String.localizedStringWithFormat(format, name)
    }

    static var placeholder: String {
        NSLocalizedString("share.composer.placeholder", value: "Write a description", comment: "Placeholder for media caption.")
    }

    static var placeholderTextOnly: String {
        NSLocalizedString("share.composer.placeholder.text", value: "Write a post", comment: "Placeholder when sharing text only.")
    }

    static var uploadingTitle: String {
        NSLocalizedString("share.composer.uploading.title", value: "Uploading...", comment: "Alert dialog title shown when uploading begins.")
    }

    static var uploadingFailedTitle: String {
        NSLocalizedString("share.composer.uploading.fail.title", value: "Uploading failed", comment: "Alert dialog title shown when uploading fails.")
    }

    static var uploadingFailedMessage: String {
        NSLocalizedString("share.composer.uploading.fail.title", value: "Please try again later.", comment: "Alert dialog message shown when uploading fails.")
    }
}

class ShareComposerViewController: UIViewController {
    private enum AttachmentType: String {
        case image = "public.image"
        case propertyList = "com.apple.property-list"
        case text = "public.plain-text"
        case url = "public.url"
        case video = "public.movie"
    }

    private var destination: ShareDestination
    private var media: [PendingMedia] = []
    private var text: String = ""
    private var textView: UITextView!
    private var textViewPlaceholder: UILabel!
    private var textViewHeightConstraint: NSLayoutConstraint!
    private var bottomConstraint: NSLayoutConstraint!
    private var cardViewHeightConstraint: NSLayoutConstraint!
    private var mentionPicker: MentionPickerView?
    private var collectionView: UICollectionView!
    private var pageControl: UIPageControl!
    private var cancellableSet: Set<AnyCancellable> = []

    private var mentions = MentionRangeMap()
    private lazy var mentionableUsers: [MentionableUser] = {
        Mentions.mentionableUsersForNewPost()
    }()
    var mentionInput: MentionInput {
        MentionInput(text: textView.text, mentions: mentions, selectedRange: textView.selectedRange)
    }

    init(destination: ShareDestination) {
        self.destination = destination
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        isModalInPresentation = true
        view.backgroundColor = .systemGray6
        setupNavigationBar()

        load { [weak self] in
            guard let self = self else { return }
            self.setupUI()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        pauseAllVideos()
    }

    private func setupNavigationBar() {
        let titleView = TitleView()
        titleView.title.text = Localizations.titleDestinationFeed

        let shareButton = UIBarButtonItem(title: Localizations.buttonShare, style: .done, target: self, action: #selector(shareAction))
        shareButton.tintColor = .systemBlue

        switch destination {
        case .feed:
            break
        case .group(let group):
            titleView.subtitle.text = Localizations.subtitle(group: group.name)
        case .contact(let contact):
            titleView.title.text = Localizations.titleDestinationContact
            titleView.subtitle.text = Localizations.subtitle(contact: contact.fullName ?? Localizations.unknownContact)
            shareButton.title = Localizations.buttonSend
        }

        navigationItem.titleView = titleView
        navigationItem.rightBarButtonItem = shareButton
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "NavbarBack"), style: .plain, target: self, action: #selector(backAction))
    }

    private func setupUI() {
        var constraints: [NSLayoutConstraint] = []

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        view.addSubview(scrollView)

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        let cardView = makeCardView()
        contentView.addSubview(cardView)

        if media.count > 0 {
            DDLogInfo("ShareComposerViewController/init media")

            collectionView = makeCollectionView()
            cardView.addSubview(collectionView)

            if media.count > 1 {
                pageControl = makePageControl()
                cardView.addSubview(pageControl)

                constraints.append(contentsOf: [
                    pageControl.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
                    pageControl.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),

                    collectionView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
                    collectionView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
                    collectionView.topAnchor.constraint(equalTo: cardView.topAnchor),
                    collectionView.bottomAnchor.constraint(equalTo: pageControl.topAnchor, constant: 10),
                ])
            } else {
                DDLogInfo("ShareComposerViewController/init text only")

                constraints.append(contentsOf: [
                    collectionView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
                    collectionView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
                    collectionView.topAnchor.constraint(equalTo: cardView.topAnchor),
                    collectionView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
                ])
            }

            textView = makeTextView()
            view.addSubview(textView)

            textViewPlaceholder = makeTextViewPlaceholder()
            textView.addSubview(textViewPlaceholder)

            bottomConstraint = textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            textViewHeightConstraint = textView.heightAnchor.constraint(equalToConstant: computeTextViewHeight())

            constraints.append(contentsOf: [
                bottomConstraint,
                textViewHeightConstraint,
                textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                textViewPlaceholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 25),
                textViewPlaceholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: 20),

                scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                scrollView.bottomAnchor.constraint(equalTo: textView.topAnchor),
                scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

                cardView.heightAnchor.constraint(equalToConstant: computeCardViewHeight()),
            ])
        } else {
            textView = makeTextView()
            cardView.addSubview(textView)

            textViewPlaceholder = makeTextViewPlaceholder()
            textView.addSubview(textViewPlaceholder)

            bottomConstraint = scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            textViewHeightConstraint = textView.heightAnchor.constraint(equalToConstant: computeTextViewHeight())

            constraints.append(contentsOf: [
                bottomConstraint,
                scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

                textView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
                textView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
                textView.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
                textView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
                textViewHeightConstraint,
                textViewPlaceholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 25),
                textViewPlaceholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: 20),

                cardView.heightAnchor.constraint(equalTo: textView.heightAnchor),
            ])
        }

        constraints.append(contentsOf: [
            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),

            contentView.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: cardView.heightAnchor, constant: 16),

            cardView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
        ])

        NSLayoutConstraint.activate(constraints)
        handleKeyboardUpdates()
    }

    private func handleKeyboardUpdates() {
        cancellableSet.insert(Publishers.Merge(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
                .compactMap { $0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect }
                .map { $0.height },
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
                .map { _ in 0 }
        )
        .removeDuplicates()
        .sink { [weak self] in
            guard let self = self else { return }

            self.bottomConstraint.constant = -$0

            if $0 == 0 {
                // Share Extension is displayed modally and when that modal view is scrolled
                // the keyboard is hidden without really resigning the text view
                DispatchQueue.main.async {
                    self.textView.resignFirstResponder()
                }
            }
        })
    }

    private func computeCardViewHeight() -> CGFloat {
        let width = view.bounds.width - 16
        let maxHeight = view.bounds.height - 250

        if media.count == 0 {
            return min(maxHeight, 400)
        }

        let ratios: [CGFloat] = media.compactMap {
            guard let size = $0.size, size.width > 0 else { return nil }
            return size.height / size.width
        }

        guard let maxRatio = ratios.max() else { return 0 }

        return min(maxHeight, width * maxRatio)
    }

    private func computeTextViewHeight() -> CGFloat {
        let size = textView.sizeThatFits(CGSize(width: textView.frame.size.width, height: CGFloat.greatestFiniteMagnitude))

        if media.count > 0 {
            return max(100, min(size.height, 250))
        } else {
            return max(size.height, 400)
        }
    }

    private func makeTextView() -> UITextView {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = UIColor.label.withAlphaComponent(0.9)
        textView.text = text
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        textView.delegate = self

        if media.count > 0 {
            textView.layer.shadowColor = UIColor.black.cgColor
            textView.layer.shadowOpacity = 0.07
            textView.layer.shadowOffset = CGSize(width: 0, height: -5)
            textView.layer.shadowRadius = 15
            textView.clipsToBounds = false
        } else {
            textView.backgroundColor = .clear
        }

        switch destination {
        case .contact:
            break
        default:
            mentionPicker = makeMentionPicker()
            textView.inputAccessoryView = mentionPicker
        }

        return textView
    }

    private func makeTextViewPlaceholder() -> UILabel {
        let placeholder = UILabel()
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.font = .preferredFont(forTextStyle: .body)
        placeholder.textColor = UIColor.black.withAlphaComponent(0.5)
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

    private func makeCardView() -> UIView {
        let cardView = UIView()
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = .white
        cardView.layer.cornerRadius = 15
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.05
        cardView.layer.shadowOffset = CGSize(width: 0, height: 5)
        cardView.layer.shadowRadius = 10

        return cardView
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
        collectionView.dataSource = self
        collectionView.delegate = self

        collectionView.register(ImageCell.self, forCellWithReuseIdentifier: ImageCell.reuseIdentifier)
        collectionView.register(VideoCell.self, forCellWithReuseIdentifier: VideoCell.reuseIdentifier)

        return collectionView
    }

    private func makePageControl() -> UIPageControl {
        let pageControl = UIPageControl()
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.numberOfPages = media.count
        pageControl.currentPageIndicatorTintColor = .lavaOrange
        pageControl.pageIndicatorTintColor = .black.withAlphaComponent(0.2)
        pageControl.addTarget(self, action: #selector(pageChangeAction), for: .valueChanged)

        return pageControl
    }

    // MARK: Load Data

    func load(completion: @escaping () -> ()) {
        guard let items = extensionContext?.inputItems else { return }

        let loadingGroup = DispatchGroup()

        for item in items {
            guard let item = item as? NSExtensionItem else { continue }
            guard let attachments = item.attachments else { continue }

            for (order, provider) in attachments.enumerated() {
                loadingGroup.enter()

                if provider.hasItemConformingToTypeIdentifier(AttachmentType.image.rawValue) {
                    load(image: provider, order: order) {
                        if let error = $0 {
                            DDLogError("ShareComposerViewController/load/image/error [\(error)]")
                        }
                        loadingGroup.leave()
                    }
                } else if provider.hasItemConformingToTypeIdentifier(AttachmentType.video.rawValue) {
                    load(video: provider, order: order) {
                        if let error = $0 {
                            DDLogError("ShareComposerViewController/load/video/error [\(error)]")
                        }
                        loadingGroup.leave()
                    }
                } else if provider.hasItemConformingToTypeIdentifier(AttachmentType.text.rawValue) {
                    load(text: provider) {
                        if let error = $0 {
                            DDLogError("ShareComposerViewController/load/text/error [\(error)]")
                        }
                        loadingGroup.leave()
                    }
                } else if provider.hasItemConformingToTypeIdentifier(AttachmentType.url.rawValue) {
                    load(url: provider, order: order) {
                        if let error = $0 {
                            DDLogError("ShareComposerViewController/load/url/error [\(error)]")
                        }
                        loadingGroup.leave()
                    }
                } else if provider.hasItemConformingToTypeIdentifier(AttachmentType.propertyList.rawValue) {
                    load(webpage: provider) {
                        if let error = $0 {
                            DDLogError("ShareComposerViewController/load/webpage/error [\(error)]")
                        }
                        loadingGroup.leave()
                    }
                } else {
                    DDLogWarn("ShareComposerViewController/load/error unknown attachment")
                    loadingGroup.leave()
                }
            }
        }

        loadingGroup.notify(queue: DispatchQueue.main) {
            completion()
        }
    }

    private func load(image provider: NSItemProvider, order: Int, completion: @escaping (Error?) -> ()) {
        provider.loadItem(forTypeIdentifier: AttachmentType.image.rawValue, options: nil) { [weak self] (item, error) in
            guard let self = self else { return }
            guard error == nil else {
                return completion(error)
            }

            var image: UIImage?
            switch item {
            case let tmp as UIImage:
                image = tmp
            case let data as Data:
                image = UIImage(data: data)
            case let url as URL:
                guard let data = try? Data(contentsOf: url) else { break }
                image = UIImage(data: data)
            default:
                break
            }

            guard image != nil else {
                return completion(ShareError.invalidData)
            }

            let mediaItem = PendingMedia(type: .image)
            self.cancellableSet.insert(
                mediaItem.ready.sink { [weak self] ready in
                    guard let self = self else { return }
                    guard ready else { return }

                    self.media.append(mediaItem)
                    completion(nil)
                }
            )

            mediaItem.order = order
            mediaItem.image = image
        }
    }

    private func load(video provider: NSItemProvider, order: Int, completion: @escaping (Error?) -> ()) {
        provider.loadItem(forTypeIdentifier: AttachmentType.video.rawValue, options: nil) { [weak self] (item, error) in
            guard let self = self else { return }
            guard error == nil else {
                return completion(error)
            }
            guard let url = item as? URL else {
                return completion(ShareError.invalidData)
            }

            let mediaItem = PendingMedia(type: .video)
            self.cancellableSet.insert(
                mediaItem.ready.sink { [weak self] ready in
                    guard let self = self else { return }
                    guard ready else { return }

                    self.media.append(mediaItem)
                    completion(nil)
                }
            )

            mediaItem.order = order
            mediaItem.originalVideoURL = url
            mediaItem.fileURL = url
        }
    }

    private func load(text provider: NSItemProvider, completion: @escaping (Error?) -> ()) {
        provider.loadItem(forTypeIdentifier: AttachmentType.text.rawValue, options: nil) { [weak self] (item, error) in
            guard let self = self else { return }
            guard error == nil else {
                return completion(error)
            }
            guard let text = item as? String else {
                return completion(ShareError.invalidData)
            }

            self.text = self.text + (self.text.isEmpty ? "" : "\n") + text.trimmingCharacters(in: .whitespacesAndNewlines)

            completion(nil)
        }
    }

    private func load(webpage provider: NSItemProvider, completion: @escaping (Error?) -> ()) {
        provider.loadItem(forTypeIdentifier: AttachmentType.propertyList.rawValue, options: nil) { [weak self] (item, error) in
            guard let self = self else { return }
            guard error == nil else {
                return completion(error)
            }
            guard let dictionary = item as? NSDictionary,
                let results = dictionary[NSExtensionJavaScriptPreprocessingResultsKey] as? NSDictionary,
                let title = results["title"] as? String,
                let url = results["url"] as? String else {
                    return completion(ShareError.invalidData)
            }

            self.text = self.text + (self.text.isEmpty ? "" : "\n") + "\(title)\n\(url)"

            completion(nil)
        }
    }

    private func load(url provider: NSItemProvider, order: Int, completion: @escaping (Error?) -> ()) {
        provider.loadItem(forTypeIdentifier: AttachmentType.url.rawValue, options: nil) { [weak self] (url, error) in
            guard let self = self else { return }
            guard error == nil else {
                return completion(error)
            }
            guard let url = url as? URL else {
                return completion(ShareError.invalidData)
            }

            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                let mediaItem = PendingMedia(type: .image)
                self.cancellableSet.insert(
                    mediaItem.ready.sink { [weak self] ready in
                        guard let self = self else { return }
                        guard ready else { return }

                        self.media.append(mediaItem)
                        completion(nil)
                    }
                )

                mediaItem.order = order
                mediaItem.image = image
            } else if AVURLAsset(url: url).isPlayable {
                let mediaItem = PendingMedia(type: .video)
                self.cancellableSet.insert(
                    mediaItem.ready.sink { [weak self] ready in
                        guard let self = self else { return }
                        guard ready else { return }

                        self.media.append(mediaItem)
                        completion(nil)
                    }
                )

                mediaItem.order = order
                mediaItem.originalVideoURL = url
                mediaItem.fileURL = url
            } else {
                self.text = self.text + (self.text.isEmpty ? "" : "\n") + url.absoluteString
                completion(nil)
            }
        }
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

    // MARK: Actions

    @objc func shareAction() {
        guard media.count > 0 || !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let queue = DispatchQueue(label: "com.halloapp.share.prepare", qos: .userInitiated)
        ShareExtensionContext.shared.coreService.execute(whenConnectionStateIs: .connected, onQueue: queue) {
            self.prepareAndUpload()
        }

        showUploadingAlert()
    }

    @objc func backAction() {
        navigationController?.popViewController(animated: true)
    }

    @objc func pageChangeAction() {
        let x = collectionView.frame.width * CGFloat(pageControl.currentPage)
        collectionView.setContentOffset(CGPoint(x: x, y: collectionView.contentOffset.y), animated: true)
    }

    private func showUploadingAlert() {
        let alert = UIAlertController(title: Localizations.uploadingTitle, message: "\n\n", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .default) { _ in
            ShareExtensionContext.shared.dataStore.cancelSending()
        })

        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.frame = alert.view.bounds
        activityIndicator.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        activityIndicator.isUserInteractionEnabled = false
        activityIndicator.startAnimating()
        alert.view.addSubview(activityIndicator)

        DispatchQueue.main.async {
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

        switch destination {
        case .feed:
            DDLogInfo("ShareComposerViewController/upload feed")
            ShareExtensionContext.shared.dataStore.post(text: mentionText, media: media, completion: onUploadFinish(_:))
        case .group(let group):
            DDLogInfo("ShareComposerViewController/upload group")
            ShareExtensionContext.shared.dataStore.post(group: group, text: mentionText, media: media, completion: onUploadFinish(_:))
        case .contact(let contact):
            DDLogInfo("ShareComposerViewController/upload contact")
            guard let userId = contact.userId else { return }
            ShareExtensionContext.shared.dataStore.send(to: userId, text: text, media: media, completion: onUploadFinish(_:))
        }
    }

    private func onUploadFinish(_ result: Result<String, Error>) {
        switch result {
        case .success(let id):
            DDLogInfo("ShareComposerViewController/upload/success id=[\(id)]")
            self.extensionContext?.completeRequest(returningItems: nil)
        case .failure(let error):
            DDLogError("ShareComposerViewController/upload/error [\(error)]")

            dismiss(animated: false)
            showUploadingFailedAlert()
        }
    }
}


// MARK: UITextViewDelegate
extension ShareComposerViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        textViewPlaceholder.isHidden = !textView.text.isEmpty
        textViewHeightConstraint.constant = computeTextViewHeight()

        updateMentionPickerContent()
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
        } else if scrollView.contentOffset.y < 0 {
            textView.resignFirstResponder()
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
            cell.configure(media[indexPath.row])
            return cell
        case .video:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: VideoCell.reuseIdentifier, for: indexPath) as! VideoCell
            cell.configure(media[indexPath.row])
            return cell
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return collectionView.bounds.size
    }
}

fileprivate class ImageCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: ImageCell.self)
    }

    private var imageView: UIImageView!

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        imageView = UIImageView(frame: contentView.bounds.insetBy(dx: 8, dy: 8))
        imageView.autoresizingMask = [ .flexibleWidth, .flexibleHeight ]
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true

        contentView.addSubview(imageView)
    }

    // Loading image on demand and resizing instead of using 'media.image'
    // makes it easier for the system to clear memory and avoid
    // going over memory limit (120MB on iPhone 11)
    func configure(_ media: PendingMedia) {
        guard media.type == .image else { return }
        guard let url = media.fileURL else { return }
        guard let image = media.image else { return }

        // 0.25 = 1/4, below that threshold the image quality gets pretty bad on some images
        let ratio = max(0.25, min(frame.size.width / image.size.width, frame.size.height / image.size.height))

        if ratio < 1 {
            DDLogInfo("ShareComposerViewController/ImageCell/config resizing image")

            let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
            if let resized = image.simpleResized(to: size) {
                imageView.image = resized
            }
        } else {
            DDLogInfo("ShareComposerViewController/ImageCell/config image from file")
            
            imageView.image = UIImage(contentsOfFile: url.path)
        }

        imageView.roundCorner(15)
    }
}

class VideoCell: UICollectionViewCell {
    static var reuseIdentifier: String {
        return String(describing: VideoCell.self)
    }

    private lazy var videoView: VideoView = {
        let view = VideoView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.roundCorner(15)
        return view
    }()

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

        NSLayoutConstraint.activate([
            videoView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            videoView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            videoView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            videoView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])
    }

    func configure(_ media: PendingMedia) {
        guard media.type == .video else { return }
        guard let url = media.fileURL else { return }
        videoView.player = AVPlayer(url: url)
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
}

fileprivate class TitleView: UIView {
    lazy var title: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.textColor = .label
        return label
    }()
    lazy var subtitle: UILabel = {
        let label = UILabel()
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    override init(frame: CGRect){
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        let stack = UIStackView(arrangedSubviews: [title, subtitle])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.distribution = .fillProportionally
        stack.spacing = 0

        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
        ])
    }
}
