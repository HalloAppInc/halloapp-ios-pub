//
//  ComposeView.swift
//  Shared Extension
//
//  Created by Alan Luo on 7/6/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

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
        case url = "public.url"
        case text = "public.plain-text"
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
            ShareExtensionContext.shared.xmppController.startConnectingIfNecessary()
        }
    }
    
    override func presentationAnimationDidFinish() {
        guard ShareExtensionContext.shared.userData.isLoggedIn else {
            DDLogError("ComposeViewController/presentationAnimationDidFinish/error user has not logged in")
            
            let alert = UIAlertController(title: nil, message: "Please go to HalloApp and sign in", preferredStyle: .alert)
            let okAction = UIAlertAction(title: "OK", style: .default) { _ in self.didSelectCancel() }
            alert.addAction(okAction)
            present(alert, animated: true, completion: nil)
            
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
                processImage(itemProvider, attachmentType: .image, mediaOrder: orderCounter)
                orderCounter += 1
            } else if itemProvider.hasItemConformingToTypeIdentifier(AttachmentType.propertyList.rawValue) {
                processWebpage(itemProvider)
            } else if itemProvider.hasItemConformingToTypeIdentifier(AttachmentType.url.rawValue) {
                processURL(itemProvider)
            } else if itemProvider.hasItemConformingToTypeIdentifier(AttachmentType.text.rawValue) {
                // No need to handle public.plain-text for now
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
                // TODO: Handle failed request
                ShareExtensionContext.shared.shareExtensionIsActive = false
                ShareExtensionContext.shared.xmppController.disconnect()
                
                super.didSelectPost()
            }
            
        case .contact(_, _):
            // TODO
            return
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
                // TODO: Cancel?
            }
        }
    }
    
    private func processImage(_ itemProvider: NSItemProvider, attachmentType: AttachmentType, mediaOrder: Int) {
        itemProvider.loadItem(forTypeIdentifier: attachmentType.rawValue, options: nil) { (media, error) in
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
    
    private func processWebpage(_ itemProvider: NSItemProvider) {
        itemProvider.loadItem(forTypeIdentifier: "com.apple.property-list", options: nil) { (item, error) in
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
            }
        }
    }
    
    private func processURL(_ itemProvider: NSItemProvider) {
        itemProvider.loadItem(forTypeIdentifier: "public.url", options: nil) { (url, error) in
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
}

extension ComposeViewController: ShareDestinationDelegate {
    func setDestination(to newDestination: ShareDestination) {
        destination = newDestination
        popConfigurationViewController()
    }
}
