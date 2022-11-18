//
//  DataStore.swift
//  Share Extension
//
//  Created by Alan Luo on 7/27/20.
//  Copyright © 2020 Halloapp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import CoreData

class DataStore: ShareExtensionDataStore {

    private let service: CoreService
    private let mainDataStore: MainDataStore
    private let chatData: CoreChatData
    private let feedData: CoreFeedData
    let mediaUploader: MediaUploader
    let mediaProcessingId = "shared-media-processing-id"

    init(service: CoreService, mainDataStore: MainDataStore, chatData: CoreChatData, feedData: CoreFeedData) {
        self.service = service
        self.mainDataStore = mainDataStore
        self.chatData = chatData
        self.feedData = feedData
        mediaUploader = MediaUploader(service: service)
        super.init()
    }

    func cancelSending() {
        mediaUploader.cancelAllUploads()
    }
}
