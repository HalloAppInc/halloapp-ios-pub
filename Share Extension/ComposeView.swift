//
//  ComposeView.swift
//  Shared Extension
//
//  Created by Alan Luo on 7/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import AVFoundation
import CocoaLumberjack
import Core
import UIKit
import Social

enum ShareDestination {
    case post
    case contact(UserID, String)
}

enum ItemLoadingError: Error {
    case invalidData
    case videoTooLong
}

@objc(ComposeViewController)
class ComposeViewController: SLComposeServiceViewController {
    private enum AttachmentType: String {
        case image = "public.image"
        case propertyList = "com.apple.property-list"
        case text = "public.plain-text"
        case url = "public.url"
        case video = "public.movie"
    }
    
    private var destination: ShareDestination = .post {
        didSet {
            reloadConfigurationItems()

            // Update mention picker since it's not relevant for 1-1 messages.
            // Do not clear existing mentions (in case they switch back to post later)
            updateMentionPickerContent()
        }
    }
    private var hasMedia = false {
        didSet { validateContent() }
    }
    private var isMediaReady = false {
        didSet { validateContent() }
    }

    private var mediaToSend = [PendingMedia]()
    private var dataStore: DataStore!
    private var service: CoreService!

    private let serviceBuilder: ServiceBuilder = {
        return ProtoServiceCore(userData: $0, passiveMode: true, automaticallyReconnect: false)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        /*
         Prevent the interactive dismissal of the view,
         since we need to disconnet XMPP before the user left
         */
        isModalInPresentation = true

        initAppContext(ShareExtensionContext.self, serviceBuilder: serviceBuilder, contactStoreClass: ContactStore.self)
        dataStore = ShareExtensionContext.shared.dataStore
        service = ShareExtensionContext.shared.coreService

        /*
         If the user switches from the host app (the app that starts the share extension request)
         to HalloApp while the compose view is still active,
         the connection in HalloApp will override the connection here,
         when the user comes back, we need to reconnect.
         */
        NotificationCenter.default.addObserver(forName: .NSExtensionHostWillEnterForeground, object: nil, queue: nil) { [weak self] _ in
            guard let self = self else { return }
            ShareExtensionContext.shared.shareExtensionIsActive = true
            self.service.startConnectingIfNecessary()
        }
        
        NotificationCenter.default.addObserver(forName: .NSExtensionHostDidEnterBackground, object: nil, queue: nil) { _ in
            ShareExtensionContext.shared.shareExtensionIsActive = false
        }

        textView.inputAccessoryView = mentionPicker
        textView.delegate = self
    }
    
    override func presentationAnimationDidFinish() {
        guard ShareExtensionContext.shared.userData.isLoggedIn else {
            DDLogError("User has not logged in")
            presentSimpleAlert(title: nil, message: "Please go to HalloApp and sign in") {
                self.didSelectCancel()
            }
            
            return
        }
        
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let attachments = item.attachments else {
            DDLogError("Failed to get NSItemProvider items")
            self.didSelectCancel()
            return
        }

        ShareExtensionContext.shared.shareExtensionIsActive = true
        service.startConnectingIfNecessary()
        
        DDLogInfo("Start loading attachments")
        
        var mediaCount: Int = 1
        let itemLoadingGroup = DispatchGroup()
        
        for itemProvider in attachments {
            DDLogDebug("TypeIdentifiers: \(itemProvider.registeredTypeIdentifiers)")
            
            if itemProvider.hasItemConformingToTypeIdentifier(AttachmentType.image.rawValue) {
                hasMedia = true
                itemLoadingGroup.enter()
                loadImage(itemProvider, mediaOrder: mediaCount) { (_) in
                    itemLoadingGroup.leave()
                }
                mediaCount += 1
            } else if itemProvider.hasItemConformingToTypeIdentifier(AttachmentType.video.rawValue) {
                hasMedia = true
                itemLoadingGroup.enter()
                loadVideo(itemProvider, mediaOrder: mediaCount) { (_) in
                    itemLoadingGroup.leave()
                }
                mediaCount += 1
            } else if itemProvider.hasItemConformingToTypeIdentifier(AttachmentType.propertyList.rawValue) {
                itemLoadingGroup.enter()
                loadWebpage(itemProvider) { (_) in
                    itemLoadingGroup.leave()
                }
            } else if itemProvider.hasItemConformingToTypeIdentifier(AttachmentType.text.rawValue) {
                // No need to handle public.plain-text for now
            } else if itemProvider.hasItemConformingToTypeIdentifier(AttachmentType.url.rawValue) {
                itemLoadingGroup.enter()
                loadURL(itemProvider) { (_) in
                    itemLoadingGroup.leave()
                }
            } else {
                DDLogError("Failer to load item. Unknown TypeIdentifier: \(itemProvider.registeredTypeIdentifiers)")
            }
        }
        
        itemLoadingGroup.notify(queue: .main) {
            guard !self.mediaToSend.isEmpty else { return }

            DDLogInfo("\(self.mediaToSend.count) of \(attachments.count) items have been loaded")
            self.isMediaReady = true
        }
    }
    
    override func didSelectPost() {
        ///TODO: Show progress indicator and disable UI.

        service.execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.startSending()
        }
    }
    
    override func didSelectCancel() {
        dataStore.cancelSending()

        ///TODO: delete saved data

        ShareExtensionContext.shared.shareExtensionIsActive = false
        service.disconnect()
        
        super.didSelectCancel()
    }
    
    override func isContentValid() -> Bool {
        if hasMedia {
            return isMediaReady
        } else {
            return !contentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    
    override func configurationItems() -> [Any]! {
        let destinationItem = SLComposeSheetConfigurationItem()!
        destinationItem.title = "Send To"
        
        switch destination {
        case .post:
            destinationItem.value = "Post"
            DDLogInfo("ComposeViewController/destination has been changed to Post")
        case .contact(let userId, let userName):
            destinationItem.value = userName
            DDLogInfo("ComposeViewController/destination has been changed to user \(userId) \(userName)")
        }
        
        destinationItem.tapHandler = {
            let destinationVC = DestinationViewController(style: .insetGrouped, avatarStore: self.avatarStore)
            destinationVC.delegate = self
            self.pushConfigurationViewController(destinationVC)
        }
        
        return [destinationItem]
    }

    private let avatarStore = AvatarStore()
    private(set) var mentions = MentionRangeMap()

    var mentionInput: MentionInput {
        MentionInput(text: textView.text, mentions: mentions, selectedRange: textView.selectedRange)
    }

    private lazy var mentionPicker: MentionPickerView = {
        let picker = MentionPickerView(avatarStore: avatarStore)
        picker.cornerRadius = 10
        picker.borderColor = .systemGray
        picker.borderWidth = 1
        picker.clipsToBounds = true
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.isHidden = true // Hide until content is set
        picker.didSelectItem = { [weak self] item in self?.acceptMentionPickerItem(item) }
        picker.heightAnchor.constraint(lessThanOrEqualToConstant: 120).isActive = true
        return picker
    }()

    private lazy var mentionableUsers: [MentionableUser] = {
        return Mentions.mentionableUsersForNewPost()
    }()

    private func updateMentionPickerContent() {
        let mentionableUsers = fetchMentionPickerContent(for: mentionInput)

        mentionPicker.items = mentionableUsers
        mentionPicker.isHidden = mentionableUsers.isEmpty
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

    private func fetchMentionPickerContent(for input: MentionInput) -> [MentionableUser] {
        guard let mentionCandidateRange = input.rangeOfMentionCandidateAtCurrentPosition() else {
            return []
        }
        if case .contact = destination {
            // Do not show mention picker for 1-1 messages.
            return []
        }
        let mentionCandidate = input.text[mentionCandidateRange]
        let trimmedInput = String(mentionCandidate.dropFirst())
        return mentionableUsers.filter {
            Mentions.isPotentialMatch(fullName: $0.fullName, input: trimmedInput)
        }
    }

    private func startSending() {
        let plainText = mentionInput.text.trimmingCharacters(in: .whitespacesAndNewlines)

        let mentionText = MentionText(
            expandedText: mentionInput.text,
            mentionRanges: mentionInput.mentions).trimmed()

        switch destination {
        case .post:
            dataStore.post(text: mentionText, media: mediaToSend) { (result) in
                switch result {
                case .success(_):
                    ShareExtensionContext.shared.shareExtensionIsActive = false
                    self.service.disconnect()
                    super.didSelectPost()

                case .failure(_):
                    self.presentSimpleAlert(title: "Failed to Post", message: "Please open HalloApp and retry posting.") {
                        // This is rare
                        // The ComposeView already disappeared, we cannot go back
                        ShareExtensionContext.shared.shareExtensionIsActive = false
                        self.service.disconnect()
                        super.didSelectCancel()
                    }
                }
            }

        case .contact(let userId, _):
            dataStore.send(to: userId, text: plainText, media: mediaToSend) { (result) in
                switch result {
                case .success(_):
                    ShareExtensionContext.shared.shareExtensionIsActive = false
                    self.service.disconnect()
                    super.didSelectPost()

                case .failure(_):
                    // This should never happen
                    ShareExtensionContext.shared.shareExtensionIsActive = false
                    self.service.disconnect()
                    super.didSelectCancel()
                }
            }
        }
    }

    typealias ItemLoadingCompletion = (Result<Void, Error>) -> ()
    
    private func loadImage(_ itemProvider: NSItemProvider, mediaOrder: Int, completion: @escaping ItemLoadingCompletion) {
        itemProvider.loadItem(forTypeIdentifier: AttachmentType.image.rawValue, options: nil) { (item, error) in
            guard error == nil else {
                DDLogError("ComposeViewController/loadImage/error \(error!)")
                completion(.failure(error!))
                return
            }

            func image(from item: NSSecureCoding?) -> UIImage? {
                switch item {
                case let img as UIImage:
                    return img

                case let data as Data:
                    return UIImage(data: data)

                case let url as URL:
                    return UIImage(contentsOfFile: url.path)

                default:
                    DDLogError("ComposeViewController/loadImage/error Unexpected type: \(type(of: item))")
                    return nil
                }
            }

            guard let image = image(from: item) else {
                DDLogError("ComposeViewController/loadImage/error Can't get image")
                completion(.failure(ItemLoadingError.invalidData))
                return
            }

            let mediaItem = PendingMedia(type: .image)
            mediaItem.order = mediaOrder
            mediaItem.image = image
            self.mediaToSend.append(mediaItem)
            
            completion(.success(Void()))
        }
    }
    
    private func loadVideo(_ itemProvider: NSItemProvider, mediaOrder: Int, completion: @escaping ItemLoadingCompletion) {
        itemProvider.loadItem(forTypeIdentifier: AttachmentType.video.rawValue, options: nil) { (item, error) in
            guard error == nil else {
                DDLogError("ComposeViewController/loadVideo/error \(error!)")
                completion(.failure(error!))
                return
            }
            
            guard let url = item as? URL else {
                DDLogError("ComposeViewController/loadVideo/error Can't load video url")
                completion(.failure(ItemLoadingError.invalidData))
                return
            }
            
            let avAsset = AVURLAsset(url: url)
            guard CMTimeGetSeconds(avAsset.duration) <= 60 else {
                self.presentSimpleAlert(title: nil, message: "Please pick a video less than 60 seconds long.") {
                    self.didSelectCancel()
                }
                completion(.failure(ItemLoadingError.videoTooLong))
                return
            }
            
            
            let mediaItem = PendingMedia(type: .video)
            mediaItem.order = mediaOrder
            mediaItem.fileURL = url
            self.mediaToSend.append(mediaItem)
            
            completion(.success(Void()))
        }
    }
    
    private func loadWebpage(_ itemProvider: NSItemProvider, completion: @escaping ItemLoadingCompletion) {
        itemProvider.loadItem(forTypeIdentifier: AttachmentType.propertyList.rawValue, options: nil) { (item, error) in
            guard error == nil else {
                DDLogError("ComposeViewController/loadWebpage/error \(error!)")
                completion(.failure(error!))
                return
            }
            
            guard let dictionary = item as? NSDictionary,
                let results = dictionary[NSExtensionJavaScriptPreprocessingResultsKey] as? NSDictionary,
                let title = results["title"] as? String,
                let url = results["url"] as? String else {
                    completion(.failure(ItemLoadingError.invalidData))
                    return
            }
            
            DispatchQueue.main.async {
                self.textView.text = "\(title)\n\(url)"
                self.validateContent()
            }

            completion(.success(Void()))
        }
    }
    
    private func loadURL(_ itemProvider: NSItemProvider, completion: @escaping ItemLoadingCompletion) {
        itemProvider.loadItem(forTypeIdentifier: AttachmentType.url.rawValue, options: nil) { (url, error) in
            guard error == nil else {
                DDLogError("ComposeViewController/loadURL/error \(error!)")
                completion(.failure(error!))
                return
            }
            
            guard let url = url as? URL else {
                completion(.failure(ItemLoadingError.invalidData))
                return
            }

            let text = self.contentText.isEmpty ? url.absoluteString : "\(self.contentText ?? "")\n\(url.absoluteString)"
            DispatchQueue.main.async {
                self.textView.text = text
                self.validateContent()
            }

            completion(.success(Void()))
        }
    }
    
    private func presentSimpleAlert(title: String?, message: String?, completion: @escaping (() -> Void)) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let okAction = UIAlertAction(title: Localizations.buttonOK, style: .default) { _ in completion() }
        alert.addAction(okAction)
        DispatchQueue.main.async {
            self.present(alert, animated: true, completion: nil)
        }
    }
}

extension ComposeViewController: ShareDestinationDelegate {

    func setDestination(to newDestination: ShareDestination) {
        destination = newDestination
        popConfigurationViewController()
    }
}

extension ComposeViewController {

    override func textViewDidChange(_ textView: UITextView) {
        self.updateMentionPickerContent()
    }

    override func textViewDidChangeSelection(_ textView: UITextView) {
        self.updateMentionPickerContent()
    }

    override func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {

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
