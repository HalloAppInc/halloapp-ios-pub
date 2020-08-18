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
        didSet { reloadConfigurationItems() }
    }
    private var hasMedia = false {
        didSet { validateContent() }
    }
    private var isMediaReady = false {
        didSet { validateContent() }
    }

    private let imageServer = ImageServer()
    private var mediaToSend = [PendingMedia]()
    private var dataStore: ShareExtensionDataStore!
    private var xmppController: XMPPController!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        /*
         Prevent the interactive dismissal of the view,
         since we need to disconnet XMPP before the user left
         */
        isModalInPresentation = true
        
        initAppContext(ShareExtensionContext.self, xmppControllerClass: XMPPControllerShareExtension.self, contactStoreClass: ContactStore.self)
        dataStore = ShareExtensionContext.shared.dataStore
        xmppController = ShareExtensionContext.shared.xmppController

        /*
         If the user switches from the host app (the app that starts the share extension request)
         to HalloApp while the compose view is still active,
         the connection in HalloApp will override the connection here,
         when the user comes back, we need to reconnect.
         */
        NotificationCenter.default.addObserver(forName: .NSExtensionHostWillEnterForeground, object: nil, queue: nil) { [weak self] _ in
            guard let self = self else { return }
            ShareExtensionContext.shared.shareExtensionIsActive = true
            self.xmppController.startConnectingIfNecessary()
        }
        
        NotificationCenter.default.addObserver(forName: .NSExtensionHostDidEnterBackground, object: nil, queue: nil) { _ in
            ShareExtensionContext.shared.shareExtensionIsActive = false
        }
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
        xmppController.startConnectingIfNecessary()
        
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
                loadWebpage(itemProvider) { (_) in
                    itemLoadingGroup.leave()
                }
            } else if itemProvider.hasItemConformingToTypeIdentifier(AttachmentType.text.rawValue) {
                // No need to handle public.plain-text for now
            } else if itemProvider.hasItemConformingToTypeIdentifier(AttachmentType.url.rawValue) {
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
            self.prepareMedia()
        }
    }
    
    override func didSelectPost() {
        ///TODO: Show progress indicator and disable UI.

        xmppController.execute(whenConnectionStateIs: .connected, onQueue: .main) {
            self.startSending()
        }
    }
    
    override func didSelectCancel() {
        imageServer.cancel()
        dataStore.cancelSending()

        ///TODO: delete saved data

        ShareExtensionContext.shared.shareExtensionIsActive = false
        xmppController.disconnect()
        
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
            let destinationVC = DestinationViewController(style: .insetGrouped)
            destinationVC.delegate = self
            self.pushConfigurationViewController(destinationVC)
        }
        
        return [destinationItem]
    }

    private func startSending() {
        let text = contentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch destination {
        case .post:
            dataStore.post(text: text, media: mediaToSend) { (result) in
                switch result {
                case .success(_):
                    ShareExtensionContext.shared.shareExtensionIsActive = false
                    self.xmppController.disconnect()
                    super.didSelectPost()

                case .failure(_):
                    self.presentSimpleAlert(title: "Failed to Post", message: "Please open HalloApp and retry posting.") {
                        // This is rare
                        // The ComposeView already disappeared, we cannot go back
                        ShareExtensionContext.shared.shareExtensionIsActive = false
                        self.xmppController.disconnect()
                        super.didSelectCancel()
                    }
                }
            }

        case .contact(let userId, _):
            dataStore.send(to: userId, text: text, media: mediaToSend) { (result) in
                switch result {
                case .success(_):
                    ShareExtensionContext.shared.shareExtensionIsActive = false
                    self.xmppController.disconnect()
                    super.didSelectPost()

                case .failure(_):
                    // This should never happen
                    ShareExtensionContext.shared.shareExtensionIsActive = false
                    self.xmppController.disconnect()
                    super.didSelectCancel()
                }
            }
        }
    }
    
    private func prepareMedia() {
        DDLogInfo("ComposeViewController/prepareMedia start")

        mediaToSend.sort { $0.order < $1.order }

        imageServer.prepare(mediaItems: mediaToSend) { (success) in
            if success {
                DDLogInfo("ComposeViewController/prepareMedia success")
                self.isMediaReady = true
            } else {
                DDLogError("ComposeViewController/prepareMedia failed")
                self.presentSimpleAlert(title: nil, message: "One or more items you have selected could not be send. Please choose different item(s).") {
                    self.didSelectCancel()
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
            mediaItem.size = image.size
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
            mediaItem.videoURL = url
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
        let okAction = UIAlertAction(title: "OK", style: .default) { _ in completion() }
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
