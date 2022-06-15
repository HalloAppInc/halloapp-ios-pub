//
//  FeedPostDisplayable.swift
//  Core
//
//  Created by Chris Leonavicius on 3/28/22.
//  Copyright © 2022 Hallo App, Inc. All rights reserved.
//

import Combine
import Core
import CoreCommon
import UIKit

// MARK: - FeedPostDisplayable

protocol FeedPostDisplayable {

    var id: FeedPostID { get }
    var userId: UserID { get }
    var groupId: GroupID? { get }
    var timestamp: Date { get }
    var unreadCount: Int32 { get }
    var status: FeedPost.Status { get }
    var orderedMentions: [MentionData] { get }
    var audienceType: AudienceType? { get }
    var hasComments: Bool { get }
    var mediaCount: Int { get }
    var feedMedia: [FeedMedia] { get }
    var hasSaveablePostMedia: Bool { get }
    var canSaveMedia: Bool { get }
    var linkPreview: LinkPreviewDisplayable? { get }
    var seenReceipts: [FeedPostReceipt] { get }
    var isWaiting: Bool { get }
    var rawText: String? { get }
    var hasAudio: Bool { get }
    var canDeletePost: Bool { get }
    var canSharePost: Bool { get }
    var canComment: Bool { get }
    var canReplyPrivately: Bool { get }
    var posterFullName: String { get }

    func userAvatar(using avatarStore: AvatarStore) -> UserAvatar
}

// MARK: - LinkPreviewDisplayable

protocol LinkPreviewDisplayable {

    var id: FeedLinkPreviewID { get }
    var url: URL? { get }
    var title: String? { get }
    var desc: String? { get }
    var feedMedia: FeedMedia? { get }
}

// MARK: - Common shared utility functions

extension FeedPostDisplayable {

    var hideFooterSeparator: Bool {
        // Separator should be hidden for media-only posts and posts with link previews
        if linkPreview != nil { return true }
        if hasText || hasAudio { return false }
        return true
    }

    var hasText: Bool {
        return !(rawText?.isEmpty ?? true)
    }

    var isUnsupported: Bool {
        return status == .unsupported
    }
}

// MARK: - FeedPost : FeedPostDisplayProtocol conformance

extension FeedPost: FeedPostDisplayable {

    var hasComments: Bool {
        return !(comments?.isEmpty ?? true)
    }

    var audienceType: AudienceType? {
        return info?.audienceType
    }

    var mediaCount: Int {
        return media?.count ?? 0
    }

    var feedMedia: [FeedMedia] {
        return MainAppContext.shared.feedData.media(for: self)
    }

    var seenReceipts: [FeedPostReceipt] {
        return MainAppContext.shared.feedData.seenReceipts(for: self)
    }

    var linkPreview: LinkPreviewDisplayable? {
        return linkPreviews?.first
    }

    var hasAudio: Bool {
        return media?.contains { $0.type == .audio } ?? false
    }

    var canDeletePost: Bool {
        return userId == MainAppContext.shared.userData.userId
    }

    var canSharePost: Bool {
        let isOwnPost = userId == MainAppContext.shared.userData.userId
        return isOwnPost
    }

    var canComment: Bool {
        return !fromExternalShare
    }

    var canReplyPrivately: Bool {
        return MainAppContext.shared.contactStore.isContactInAddressBook(userId: userId,
                                                                         in: MainAppContext.shared.contactStore.viewContext)
    }

    var posterFullName: String {
        return MainAppContext.shared.contactStore.fullName(for: userID,
                                                           in: MainAppContext.shared.contactStore.viewContext)
    }

    func userAvatar(using avatarStore: AvatarStore) -> UserAvatar {
        return avatarStore.userAvatar(forUserId: userId)
    }
}

extension CommonLinkPreview: LinkPreviewDisplayable {

    var feedMedia: FeedMedia? {
        return MainAppContext.shared.feedData.media(feedLinkPreviewID: id,
                                                    in: MainAppContext.shared.feedData.viewContext)?.first
    }
}
