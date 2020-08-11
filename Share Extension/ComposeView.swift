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
    private var imageServer:ImageServer?
    private let mediaProcessingGroup = DispatchGroup()
    private var mediaToSend: [PendingMedia] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()

        /*
         Prevent the interactive dismissal of the view,
         since we need to disconnet XMPP before the user left
         */
        self.isModalInPresentation = true
        
        initAppContext(ShareExtensionContext.self, xmppControllerClass: XMPPControllerShareExtension.self, contactStoreClass: ContactStore.self)
        
        /*
         If the user switches from the host app (the app that starts the share extension request)
         to HalloApp while the compose view is still active,
         the connection in HalloApp will override the connection here,
         when the user comes back, we need to reconnect.
         */
        NotificationCenter.default.addObserver(forName: .NSExtensionHostWillEnterForeground, object: nil, queue: nil) { _ in
            ShareExtensionContext.shared.shareExtensionIsActive = true
            ShareExtensionContext.shared.xmppController.startConnectingIfNecessary()
        }
        
        NotificationCenter.default.addObserver(forName: .NSExtensionHostDidEnterBackground, object: nil, queue: nil) { _ in
            ShareExtensionContext.shared.shareExtensionIsActive = false
        }
    }
    
    override func presentationAnimationDidFinish() {
        guard ShareExtensionContext.shared.userData.isLoggedIn else {
            DDLogError("ComposeViewController/presentationAnimationDidFinish/error user has not logged in")
            presentSimpleAlert(title: nil, message: "Please go to HalloApp and sign in") {
                self.didSelectCancel()
            }
            
            return
        }
        
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem else {
            DDLogError("ComposeViewController/presentationAnimationDidFinish/error Failed to get NSExtensionItem")
            self.didSelectCancel()
            return
        }
        
        guard let attachments = item.attachments else {
            DDLogError("ComposeViewController/presentationAnimationDidFinish/error Failed to get [NSItemProvider]")
            self.didSelectCancel()
            return
        }
        
        ShareExtensionContext.shared.shareExtensionIsActive = true
        ShareExtensionContext.shared.xmppController.startConnectingIfNecessary()
        
        DDLogInfo("ComposeViewController/presentationAnimationDidFinish start loading attachments")
        
        var orderCounter: Int = 1
        
        for itemProvider in attachments {
            DDLogDebug("TypeIdentifiers: \(itemProvider.registeredTypeIdentifiers)")
            
            if itemProvider.hasItemConformingToTypeIdentifier(AttachmentType.image.rawValue) {
                hasMedia = true
                mediaProcessingGroup.enter()
                processImage(itemProvider, mediaOrder: orderCounter)
                orderCounter += 1
            } else if itemProvider.hasItemConformingToTypeIdentifier(AttachmentType.propertyList.rawValue) {
                processWebpage(itemProvider)
            } else if itemProvider.hasItemConformingToTypeIdentifier(AttachmentType.text.rawValue) {
                // No need to handle public.plain-text for now
            } else if itemProvider.hasItemConformingToTypeIdentifier(AttachmentType.url.rawValue) {
                processURL(itemProvider)
            } else if itemProvider.hasItemConformingToTypeIdentifier(AttachmentType.video.rawValue) {
                hasMedia = true
                mediaProcessingGroup.enter()
                processVideo(itemProvider, mediaOrder: orderCounter)
                orderCounter += 1
            } else {
                DDLogError("ComposeViewController/presentationAnimationDidFinish/error unknown TypeIdentifier: \(itemProvider.registeredTypeIdentifiers)")
            }
        }
        
        mediaProcessingGroup.notify(queue: .main) {
            guard self.mediaToSend.count > 0 else { return }
            
            DDLogInfo("ComposeViewController/presentationAnimationDidFinish \(self.mediaToSend.count) of \(attachments.count) items have been loaded")
            
            self.mediaToSend.sort { $0.order < $1.order }
            
            if ShareExtensionContext.shared.xmppController.connectionState == .connected {
                self.uploadMedia()
            } else {
                ShareExtensionContext.shared.xmppController.execute(whenConnectionStateIs: .connected, onQueue: .main) {
                    self.uploadMedia()
                }
            }
        }
    }
    
    override func didSelectPost() {
        switch destination {
        case .post:
            ShareExtensionContext.shared.sharedDataStore.post(text: contentText, media: mediaToSend, using: ShareExtensionContext.shared.xmppController) { result in
                switch result {
                case .success(_):
                    ShareExtensionContext.shared.shareExtensionIsActive = false
                    ShareExtensionContext.shared.xmppController.disconnect()
                    super.didSelectPost()
                    
                case .failure(let error):
                    let message = "We encountered an error when posting: \(error.localizedDescription)"
                    self.presentSimpleAlert(title: "Failed to Post", message: message) {
                        // This is rare
                        // The ComposeView already disappeared, we cannot go back
                        ShareExtensionContext.shared.shareExtensionIsActive = false
                        ShareExtensionContext.shared.xmppController.disconnect()
                        super.didSelectCancel()
                    }
                }
            }
            
        case .contact(let userId, _):
            ShareExtensionContext.shared.sharedDataStore.sned(to: userId, text: contentText, media: mediaToSend, using: ShareExtensionContext.shared.xmppController) { result in
                switch result {
                case .success(_):
                    ShareExtensionContext.shared.shareExtensionIsActive = false
                    ShareExtensionContext.shared.xmppController.disconnect()
                    super.didSelectPost()
                    
                case .failure(_):
                    // This should never happen
                    ShareExtensionContext.shared.shareExtensionIsActive = false
                    ShareExtensionContext.shared.xmppController.disconnect()
                    super.didSelectCancel()
                }
            }
        }
    }
    
    override func didSelectCancel() {
        imageServer?.cancel()
        ShareExtensionContext.shared.shareExtensionIsActive = false
        ShareExtensionContext.shared.xmppController.disconnect()
        
        super.didSelectCancel()
    }
    
    override func isContentValid() -> Bool {
        if hasMedia {
            return isMediaReady
        } else {
            return !contentText.isEmpty
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
    
    private func uploadMedia() {
        DDLogInfo("ComposeViewController/uploadMedia start")
        
        imageServer = ImageServer()
        imageServer!.upload(mediaToSend) { (didSuccess) in
            if didSuccess {
                DDLogInfo("ComposeViewController/uploadMedia success")
                self.isMediaReady = true
            } else {
                DDLogError("ComposeViewController/uploadMedia failed")
                self.presentSimpleAlert(title: nil, message: "There is a problem uploading your media. Please try again later.") {
                    self.didSelectCancel()
                }
            }
        }
    }
    
    private func processImage(_ itemProvider: NSItemProvider, mediaOrder: Int) {
        itemProvider.loadItem(forTypeIdentifier: AttachmentType.image.rawValue, options: nil) { (media, error) in
            guard error == nil else {
                DDLogError("ComposeViewController/processImage/error while loading item: \(error!.localizedDescription)")
                // TODO: show error message?
                self.mediaProcessingGroup.leave()
                return
            }
            
            let item: UIImage?
            
            switch media {
            case let img as UIImage:
                item = img
            case let data as Data:
                item = UIImage(data: data)
            case let url as URL:
                item = UIImage(contentsOfFile: url.path)
            default:
                item = nil
                DDLogError("ComposeViewController/processImage/error unexpected type: \(type(of: media))")
                // TODO: show error message?
            }
            
            guard let image = item else {
                DDLogError("ComposeViewController/processImage/error can't get image")
                // TODO: show error message?
                self.mediaProcessingGroup.leave()
                return
            }
            
            let mediaItem = PendingMedia(type: .image)
            mediaItem.order = mediaOrder
            mediaItem.image = image
            mediaItem.size = image.size
            self.mediaToSend.append(mediaItem)
            
            self.mediaProcessingGroup.leave()
        }
    }
    
    private func processVideo(_ itemProvider: NSItemProvider, mediaOrder: Int) {
        itemProvider.loadItem(forTypeIdentifier: AttachmentType.video.rawValue, options: nil) { (item, error) in
            guard error == nil else {
                DDLogError("ComposeViewController/processVideo/error while loading item: \(error!.localizedDescription)")
                // TODO: show error message?
                self.mediaProcessingGroup.leave()
                return
            }
            
            guard let url = item as? URL else {
                DDLogError("ComposeViewController/processVideo/error can't load video url")
                // TODO: show error message?
                self.mediaProcessingGroup.leave()
                return
            }
            
            let avAsset = AVURLAsset(url: url)
            guard CMTimeGetSeconds(avAsset.duration) <= 60 else {
                self.mediaProcessingGroup.leave()
                self.presentSimpleAlert(title: nil, message: "Please pick a video less than 60 seconds long.") {
                    self.didSelectCancel()
                }
                return
            }
            
            
            let mediaItem = PendingMedia(type: .video)
            mediaItem.order = mediaOrder
            mediaItem.videoURL = url
            self.mediaToSend.append(mediaItem)
            
            self.mediaProcessingGroup.leave()
        }
    }
    
    private func processWebpage(_ itemProvider: NSItemProvider) {
        itemProvider.loadItem(forTypeIdentifier: AttachmentType.propertyList.rawValue, options: nil) { (item, error) in
            guard error == nil else {
                DDLogError("ComposeViewController/processImage/error while loading item: \(error!.localizedDescription)")
                // TODO: show error message?
                return
            }
            
            guard let dictionary = item as? NSDictionary,
                let results = dictionary[NSExtensionJavaScriptPreprocessingResultsKey] as? NSDictionary,
                let title = results["title"] as? String,
                let url = results["url"] as? String else {
                    return
            }
            
            DispatchQueue.main.async {
                self.textView.text = "\(title)\n\(url)"
                self.validateContent()
            }
        }
    }
    
    private func processURL(_ itemProvider: NSItemProvider) {
        itemProvider.loadItem(forTypeIdentifier: AttachmentType.url.rawValue, options: nil) { (url, error) in
            guard error == nil else {
                DDLogError("ComposeViewController/processImage/error while loading item: \(error!.localizedDescription)")
                // TODO: show error message?
                return
            }
            
            guard let url = url as? URL else { return }
            
            let text = self.contentText.isEmpty ? url.absoluteString : "\(self.contentText ?? "")\n\(url.absoluteString)"
            
            DispatchQueue.main.async {
                self.textView.text = text
                self.validateContent()
            }
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
