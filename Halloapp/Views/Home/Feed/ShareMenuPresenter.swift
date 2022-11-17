//
//  ShareMenuPresenter.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 4/7/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import UIKit

protocol ShareMenuPresenter: UIViewController {

}

extension ShareMenuPresenter {

    func presentShareMenu(for feedPost: FeedPost, mediaIndex: Int?) {
        let postID = feedPost.id
        present(FeedPostMenuViewController(menu: FeedPostMenuViewController.Menu() {
            FeedPostMenuViewController.Section(postPreview: .init(image: MainAppContext.shared.feedData.externalShareThumbnail(for: feedPost),
                                                                  title: MainAppContext.shared.userData.name,
                                                                  subtitle: feedPost.externalShareDescription))
            FeedPostMenuViewController.Section(shareCarouselItem: .init(shareAction: { [weak self] shareProvider in
                self?.share(postID: postID, mediaIndex: mediaIndex, with: shareProvider)
            }))
            FeedPostMenuViewController.Section {
                FeedPostMenuViewController.Item(style: .standard,
                                                icon: UIImage(named: "ExternalShareLink"),
                                                title: Localizations.copyLink) { [weak self] _ in
                    self?.generateExternalShareLink(postID: postID, success: { url, toast in
                        Analytics.log(event: .externalShare, properties: [.shareDestination: "copy_link"])
                        toast.update(type: .icon(UIImage(systemName: "checkmark")), text: Localizations.externalShareLinkCopied)
                        UIPasteboard.general.url = url
                    })
                }

                if MainAppContext.shared.feedData.externalShareInfo(for: postID) != nil {
                    FeedPostMenuViewController.Item(style: .destructive,
                                                    icon: UIImage(named: "ExternalShareLinkStrikethrough"),
                                                    title: Localizations.externalShareRevoke) { [weak self] _ in
                        self?.revokeExternalShareLink(postID: postID)
                    }
                }
            }
            FeedPostMenuViewController.Section(description: Localizations.externalShareDescription, icon: UIImage(systemName: "info.circle"))
        }), animated: true)
    }

    func share(postID: FeedPostID, mediaIndex: Int?, with shareProvider: ShareProvider.Type) {
        guard let feedPost = MainAppContext.shared.feedData.feedPost(with: postID, in: MainAppContext.shared.feedData.viewContext) else {
            DDLogError("ShareMenuPresenter/shareWithShareProvider/post not found")
            return
        }

        let completion: ShareProviderCompletion = { result in
            DDLogInfo("ShareMenuPresenter/shareWithShareProvider/didCompleteShare/\(shareProvider.title)/\(result)")
        }

        Analytics.log(event: .externalShare, properties: [.shareDestination: shareProvider.analyticsShareDestination])


        if !feedPost.isAudioPost, let postShareProvider = shareProvider as? PostShareProvider.Type {
            postShareProvider.share(post: feedPost, mediaIndex: mediaIndex, completion: completion)
        } else {
            generateExternalShareLink(postID: postID) { url, toast in
                toast.hide()
                shareProvider.share(text: Localizations.externalShareText(url: url),
                                    image: nil,
                                    completion: completion)
            }
        }
    }

    private func generateExternalShareLink(postID: FeedPostID, success: @escaping (URL, Toast) -> Void) {
        guard proceedIfConnected() else {
            return
        }
        let toast = Toast(type: .activityIndicator, text: Localizations.externalShareLinkUploading)
        toast.show(shouldAutodismiss: false)
        MainAppContext.shared.feedData.externalShareUrl(for: postID) { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                switch result {
                case .success(let url):
                    success(url, toast)
                case .failure(_):
                    toast.hide()
                    let actionSheet = UIAlertController(title: nil, message: Localizations.externalShareFailed, preferredStyle: .alert)
                    actionSheet.addAction(UIAlertAction(title: Localizations.buttonOK, style: .cancel))
                    self?.present(actionSheet, animated: true)
                }
            }
        }
    }

    private func revokeExternalShareLink(postID: FeedPostID) {
        guard proceedIfConnected() else {
            return
        }
        let toast = Toast(type: .activityIndicator, text: Localizations.externalShareLinkRevoking)
        toast.show(shouldAutodismiss: false)
        MainAppContext.shared.feedData.revokeExternalShareUrl(for: postID) { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                switch result {
                case .success(_):
                    toast.update(type: .icon(UIImage(systemName: "checkmark")), text: Localizations.externalShareLinkRevoked)
                    break
                case .failure(_):
                    toast.hide()
                    let actionSheet = UIAlertController(title: nil, message: Localizations.externalShareRevokeFailed, preferredStyle: .alert)
                    actionSheet.addAction(UIAlertAction(title: Localizations.buttonOK, style: .cancel))
                    self?.present(actionSheet, animated: true)
                }
            }
        }
    }
}

extension Localizations {

    static var externalShareLinkUploading: String = {
        NSLocalizedString("your.post.externalshare.uploading",
                          value: "Creating link...",
                          comment: "Notification that post is uploading ")
    }()

    static var externalShareLinkRevoking: String = {
        NSLocalizedString("your.post.externalshare.revoking",
                          value: "Revoking link...",
                          comment: "Notification revoking an external share link is in progress")
    }()

    static var externalShareLinkRevoked: String = {
        NSLocalizedString("your.post.externalshare.revoke.success",
                          value: "Link revoked",
                          comment: "Notification that a link was successfully revoked")
    }()

    static var externalShareLinkCopied: String {
        NSLocalizedString("your.post.externalshare.copylink.success",
                          value: "Copied to Clipboard",
                          comment: "Success toast when external share link is copied")
    }

    static func externalShareText(url: URL) -> String {
        let localizedString = NSLocalizedString("your.post.externalshare.title",
                                                value: "Check out my post on HalloApp:",
                                                comment: "Text introducing external share link, part of what is shared")
        return "\(localizedString) \(url)"
    }

    static var externalShareFailed: String = {
        NSLocalizedString("your.post.externalshare.error",
                          value: "Failed to upload post for external share",
                          comment: "Message that external share failed.")
    }()

    static var externalShareDescription: String = {
        NSLocalizedString("your.post.externalshare.description2",
                          value: "Anyone with the link can see your post. Link expires with your post. Link preview is unencrypted.",
                          comment: "Message on header of post menu explaining external share")
    }()

    static var externalShareRevoke: String = {
        NSLocalizedString("your.post.externalshare.revoke",
                          value: "Revoke Link",
                          comment: "Button to invalidate an external share link")
    }()

    static var externalShareRevokeFailed: String = {
        NSLocalizedString("your.post.externalshare.revoke.error",
                          value: "Failed to revoke link for external share",
                          comment: "Message that revoking external share link failed.")
    }()
}
