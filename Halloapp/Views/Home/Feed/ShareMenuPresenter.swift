//
//  ShareMenuPresenter.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 4/7/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Core
import CoreCommon
import UIKit

protocol ShareMenuPresenter: UIViewController {

}

extension ShareMenuPresenter {

    func presentShareMenu(for feedPost: FeedPost) {
        let postID = feedPost.id
        present(FeedPostMenuViewController(menu: FeedPostMenuViewController.Menu() {
            FeedPostMenuViewController.Section(postPreview: .init(image: MainAppContext.shared.feedData.externalShareThumbnail(for: feedPost),
                                                                  title: Localizations.externalShareTitle(name: MainAppContext.shared.userData.name),
                                                                  subtitle: feedPost.externalShareDescription))
            FeedPostMenuViewController.Section {
                FeedPostMenuViewController.Item(style: .standard,
                                                icon: UIImage(systemName: "square.and.arrow.up"),
                                                title: Localizations.externalShareButton) { [weak self] _ in
                    self?.generateExternalShareLink(postID: postID, success: { [weak self] url, toast in
                        toast.hide()
                        let shareText = "\(Localizations.externalShareText) \(url)"
                        let activityViewController = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
                        self?.present(activityViewController, animated: true)
                    })
                }
                FeedPostMenuViewController.Item(style: .standard,
                                                icon: UIImage(named: "ExternalShareLink"),
                                                title: Localizations.externalShareCopyLink) { [weak self] _ in
                    self?.generateExternalShareLink(postID: postID, success: { url, toast in
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
        MainAppContext.shared.feedData.revokeExternalShareUrl(for: postID) { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                switch result {
                case .success(_):
                    // No-op on success
                    break
                case .failure(_):
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
        NSLocalizedString("your.post.externalshare.uploading", value: "Creating post...", comment: "Notification that post is uploading ")
    }()

    static var externalShareCopyLink: String = {
        NSLocalizedString("your.post.externalshare.copylink",
                          value: "Copy Link to Share",
                          comment: "Title for button in action sheet prompting user to share post to external sites")
    }()

    static var externalShareLinkCopied: String {
        NSLocalizedString("your.post.externalshare.copylink.success",
                          value: "Copied to Clipboard",
                          comment: "Success toast when external share link is copied")
    }

    static var externalShareText: String {
        NSLocalizedString("your.post.externalshare.title",
                          value: "Check out my post on HalloApp:",
                          comment: "Text introducing external share link, part of what is shared")
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

    static var externalShareButton: String = {
        NSLocalizedString("your.post.externalshare.button",
                          value: "Share Externally",
                          comment: "Button to open the system share sheet with an external post link")
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
