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

    static var filesInChatsOnly: String {
        NSLocalizedString("files.in.chats.only", value: "Files may only be sent directly to contacts, not included in posts.", comment: "Alert dialog when users try to share files to group or home feed")
    }

    static var edit: String {
        NSLocalizedString("share.composer.button.edit", value: "Edit", comment: "Title on edit button")
    }

    static var shareWith: String {
        NSLocalizedString("share.composer.destinations.label", value: "Share with", comment: "Label above the list with whom you share")
    }

    static var processingMedia: String {
        NSLocalizedString("share.composer.processing.media", value: "Processing Media...", comment: "Title of alert displayed while processing media shared by share extension")
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
    private var files: [FileSharingData] = []
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
    private var progressMonitor: ProcessingProgressMonitor? // new uploader

    private var mentions = MentionRangeMap()
    private lazy var mentionableUsers: [MentionableUser] = {
        Mentions.mentionableUsersForNewPost(privacyListType: .all, in: AppContext.shared.mainDataStore.viewContext)
    }()
    var mentionInput: MentionInput {
        MentionInput(text: textView.text, mentions: mentions, selectedRange: textView.selectedRange)
    }
    private lazy var documentView: MessageDocumentView = {
        let view = MessageDocumentView()
        return view
    }()

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

    private lazy var shareButton: UIBarButtonItem = {
        return UIBarButtonItem(title: Localizations.buttonShare, style: .done, target: self, action: #selector(shareAction))
    }()

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
            self.files = ShareDataLoader.shared.files

            self.loadingView.stopAnimating()
            self.setupUI()
        })
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        pauseAllVideos()
    }

    private func setupNavigationBar() {
        shareButton.tintColor = .systemBlue

        let chatsOnly = destinations.filter {
            if case .chat(_) = $0 {
                return false
            } else {
                return true
            }
        }.count == 0

        if chatsOnly {
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

        if let file = files.first {
            documentView.isHidden = false
            documentView.setDocument(url: file.localURL, name: file.name)
        } else {
            documentView.isHidden = true
        }

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
            contentView.addArrangedSubview(documentView)
            contentView.addArrangedSubview(textView)
            contentView.addArrangedSubview(linkPreviewView)


            bottomConstraint = scrollView.bottomAnchor.constraint(equalTo: destinationRowLabel.topAnchor, constant: -8)

            constraints.append(contentsOf: [
                textViewPlaceholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 16),
                textViewPlaceholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: 10),
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
                self.textView.selectedTextRange = self.textView.textRange(from: self.textView.beginningOfDocument, to: self.textView.beginningOfDocument)
                self.highlightLinks()
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

        let chats = destinations.filter {
            if case .chat(_) = $0 {
                return true
            } else {
                return false
            }
        }

        if chats.count == 0 {
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
        placeholder.isHidden = isPlaceholderHidden()

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

    private func isPlaceholderHidden() -> Bool {
        guard !textView.text.isEmpty else { return false }
        guard media.count == 0 else { return true }
        // Show placeholder for text of the form "\n\n(url)" (likely created by sharing a link)
        guard textView.text.starts(with: "\n\n") else { return true }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return true }

        let rest = String(textView.text[textView.text.index(textView.text.startIndex, offsetBy: 2)...])
        let matches = detector.matches(in: rest, options: [], range: NSRange(location: 0, length: rest.count))

        guard matches.count > 0 else { return true }
        guard let lower = matches.map({ $0.range.lowerBound }).min(), lower >= 0, lower < textView.text.count else { return true }

        return lower != 0
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

    private func highlightLinks()  {
        guard media.count == 0 else { return }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return }
        guard let text = textView.text else { return }

        let matches = detector.matches(in: text, range: NSRange(location: 0, length: text.utf16.count))

        let attributedText = NSMutableAttributedString(attributedString: textView.attributedText)

        for match in matches {
            attributedText.addAttributes(
                [.foregroundColor: UIColor.systemBlue, .underlineStyle: NSUnderlineStyle.single.rawValue],
                range: match.range)
        }

        let selectedRange = textView.selectedTextRange
        textView.attributedText = attributedText
        textView.selectedTextRange = selectedRange
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
        textViewDidChange(textView)
    }
    
    private func updateWithMention() {
        guard mentionInput.mentions.isEmpty == false,
        let selected = textView.selectedTextRange
        else {
            return
        }
        let defaultFont = textView.font ?? UIFont.preferredFont(forTextStyle: .body)
        let attributedString = NSMutableAttributedString(attributedString: self.textView.attributedText)
        for range in mentionInput.mentions.keys {
            attributedString.setAttributes([
                .strokeWidth: NSNumber.init(value: -3.0),
                .font: defaultFont,
                .foregroundColor: Constants.textViewTextColor,
            ], range: range)
        }
        textView.attributedText = attributedString
        textView.selectedTextRange = selected
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
        guard media.count > 0 || files.count > 0 || !(textView?.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) else { return }

        guard files.isEmpty || !destinations.contains(where: { !$0.supportsFileSharing }) else {
            let alert = UIAlertController(title: Localizations.uploadingFailedTitle, message: Localizations.filesInChatsOnly, preferredStyle: .alert)
            alert.addAction(.init(title: Localizations.buttonOK, style: .default))
            present(alert, animated: true)
            return
        }

        shareButton.isEnabled = false

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
        let text = mentionInput.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let mentionText = MentionText(
            expandedText: mentionInput.text,
            mentionRanges: mentionInput.mentions).trimmed()

        upload(text: text, mentionText: mentionText, media: media, files: files, linkPreviewData: linkPreviewData, linkPreviewMedia: linkPreviewMedia)
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

    private func showProcessingAlertIfNeeded(for mediaIDs: [CommonMediaID]) {
        guard !mediaIDs.isEmpty else {
            return
        }
        progressMonitor = ProcessingProgressMonitor(mediaIDs: mediaIDs) { [weak self] in
            self?.shareButton.isEnabled = true
        }

        DispatchQueue.main.async {
            guard let alert = self.progressMonitor?.alert else { return }
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

    // MARK: New Upload Flow

    private func upload(text: String, mentionText: MentionText, media: [PendingMedia], files: [FileSharingData], linkPreviewData: LinkPreviewData?, linkPreviewMedia: PendingMedia?) {
        let taskCompletion = AppContext.shared.startBackgroundTask(withName: "share-extension-media-processing")
        let expectedCompletionCount = destinations.count

        // post/message creation completions
        var creationCount = 0
        var createdMediaIDs: [CommonMediaID] = []
        let showProcessingAlertIfNeeded: (Result<(String, [String]), Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                creationCount += 1
                if case .success(let (_, mediaIDs)) = result {
                    createdMediaIDs += mediaIDs
                }
                if creationCount == expectedCompletionCount {
                    self?.showProcessingAlertIfNeeded(for: createdMediaIDs)
                }
            }
        }

        // upload media completions
        var completionCount = 0
        var failureCount = 0

        let checkCompletionCountAndCompleteIfNeeded: (Result<String, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    completionCount += 1
                case .failure:
                    failureCount += 1
                }

                guard let self = self, (completionCount + failureCount) == expectedCompletionCount else {
                    return
                }

                if failureCount > 0 {
                    self.dismiss(animated: false)
                    self.showUploadingFailedAlert()
                    self.shareButton.isEnabled = true
                } else {
                    ImageServer.shared.clearAllTasks(keepFiles: false)
                    ShareDataLoader.shared.reset()
                    self.progressMonitor?.setProgress(1, animated: true)

                    // We need to update presence after successfully posting.
                    ShareExtensionContext.shared.coreService.sendPresenceIfPossible(.available)
                    ShareExtensionContext.shared.coreService.sendPresenceIfPossible(.away)

                    // let the user observe the full progress
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        self.shareButton.isEnabled = true

                        DDLogInfo("ShareComposerViewController/Extension context complete request")
                        self.extensionContext?.completeRequest(returningItems: nil)

                        // We only have ~5 sec of background execution time in the share extension before it is force quit by the system.
                        // Try to exit early if no background tasks are added, so we don't quit in the middle of any atomic operations.
                        // Background tasks should be limited to background upload callbacks which will be handled by the main app.
                        AppContext.shared.addBackgroundTaskCompletionHandler {
                            DDLogInfo("ShareComposerViewController/All background tasks ended - exiting")
                            exit(EX_OK)
                        }
                    }
                }

                taskCompletion()
            }
        }

        destinations.forEach { destination in
            switch destination {
            case .feed(let privacyListType):
                let destination: Core.ShareDestination = .feed(privacyListType)
                AppContext.shared.coreFeedData.post(text: mentionText,
                                                    media: media,
                                                    linkPreviewData: linkPreviewData,
                                                    linkPreviewMedia: linkPreviewMedia,
                                                    to: destination,
                                                    didCreatePost: showProcessingAlertIfNeeded,
                                                    didBeginUpload: checkCompletionCountAndCompleteIfNeeded)

            case .group(let groupListSyncItem):
                let destination: Core.ShareDestination = .group(id: groupListSyncItem.id, type: groupListSyncItem.type, name: groupListSyncItem.name)
                switch groupListSyncItem.type {
                case .groupFeed:
                    AppContext.shared.coreFeedData.post(text: mentionText,
                                                        media: media,
                                                        linkPreviewData: linkPreviewData,
                                                        linkPreviewMedia: linkPreviewMedia,
                                                        to: destination,
                                                        didCreatePost: showProcessingAlertIfNeeded,
                                                        didBeginUpload: checkCompletionCountAndCompleteIfNeeded)
                case .groupChat:
                    AppContext.shared.coreChatData.sendMessage(chatMessageRecipient: .groupChat(toGroupId: groupListSyncItem.id, fromUserId: AppContext.shared.userData.userId),
                                                               mentionText: mentionText,
                                                               media: media,
                                                               files: files,
                                                               linkPreviewData: linkPreviewData,
                                                               linkPreviewMedia: linkPreviewMedia,
                                                               didCreateMessage: showProcessingAlertIfNeeded,
                                                               didBeginUpload: checkCompletionCountAndCompleteIfNeeded)
                case .oneToOne:
                    break
                    
                }
                
                
            case .chat(let chatListSyncItem):
                AppContext.shared.coreChatData.sendMessage(chatMessageRecipient: .oneToOneChat(toUserId: chatListSyncItem.userId, fromUserId: AppContext.shared.userData.userId),
                                                           mentionText: mentionText,
                                                           media: media,
                                                           files: files,
                                                           linkPreviewData: linkPreviewData,
                                                           linkPreviewMedia: linkPreviewMedia,
                                                           didCreateMessage: showProcessingAlertIfNeeded,
                                                           didBeginUpload: checkCompletionCountAndCompleteIfNeeded)
            }
        }
    }
}


// MARK: UITextViewDelegate
extension ShareComposerViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        textViewPlaceholder.isHidden = isPlaceholderHidden()
        textViewHeightConstraint.constant = computeTextViewHeight()

        updateMentionPickerContent()
        updateLinkPreviewViewIfNecessary()
        updateWithMarkdown()
        updateWithMention()
        highlightLinks()
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
            textViewDidChange(textView)
            return false
        }
    }
}

// MARK: UIScrollViewDelegate
extension ShareComposerViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if let collectionView = collectionView, let pageControl = pageControl, scrollView === collectionView, collectionView.frame.width > 0 {
            let rem = collectionView.contentOffset.x.truncatingRemainder(dividingBy: collectionView.frame.width)

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
        case .document:
            return collectionView.dequeueReusableCell(withReuseIdentifier: EmptyCell.reuseIdentifier, for: indexPath)
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return collectionView.bounds.size
    }

    private func edit(index: Int) {
        let controller = MediaEditViewController(config: .default, mediaToEdit: media, selected: index) { [weak self] controller, media, selected, cancel in
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

fileprivate extension UIButton.Configuration {

    static var shareComposerEditButtonConfiguration: UIButton.Configuration {
        var buttonConfiguration: UIButton.Configuration = .plain()
        buttonConfiguration.background.cornerRadius = 17
        buttonConfiguration.background.visualEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        buttonConfiguration.baseForegroundColor = .white
        buttonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 6, bottom: 1, trailing: 12)
        buttonConfiguration.cornerStyle = .fixed
        buttonConfiguration.image = UIImage(systemName: "pencil.circle.fill")
        buttonConfiguration.imagePadding = 4
        buttonConfiguration.imagePlacement = .leading
        buttonConfiguration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14)
        buttonConfiguration.title = Localizations.edit
        buttonConfiguration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributeContainer in
            var updatedAttributeContainer = attributeContainer
            updatedAttributeContainer.font = .systemFont(ofSize: 17, weight: .medium)
            return updatedAttributeContainer
        }
        return buttonConfiguration
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
        let button = UIButton(type: .custom)
        button.configuration = .shareComposerEditButtonConfiguration
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(editAction), for: .touchUpInside)
        
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
        let button = UIButton(type: .custom)
        button.configuration = .shareComposerEditButtonConfiguration
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(editAction), for: .touchUpInside)

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

fileprivate class ProcessingProgressMonitor {
    private var processingProgressCancellable: AnyCancellable?

    let alert: UIAlertController

    private lazy var progressView: UIProgressView = {
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.frame = CGRect(x: 27, y: 56, width: alert.view.bounds.width - 54 , height: 10)
        progressView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        progressView.isUserInteractionEnabled = false
        return progressView
    }()

    init(mediaIDs: [CommonMediaID], cancel: @escaping () -> ()) {
        alert = UIAlertController(title: Localizations.processingMedia, message: "\n\n", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localizations.buttonCancel, style: .default) { _ in
            ShareExtensionContext.shared.dataStore.cancelSending()
            cancel()
        })
        alert.view.addSubview(progressView)
        processingProgressCancellable = ImageServer.shared.progress.receive(on: DispatchQueue.main).sink { [weak self] _ in
            let progress = mediaIDs
                .map {
                    let (_, progress) = ImageServer.shared.progress(for: $0)
                    return progress
                }
                .reduce(0, +) / Float(mediaIDs.count)

            self?.setProgress(progress, animated: true)
        }
    }

    func setProgress(_ progress: Float, animated: Bool) {
        progressView.setProgress(progress, animated: animated)
    }
}
