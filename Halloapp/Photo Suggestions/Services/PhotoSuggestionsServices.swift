//
//  PhotoSuggestionsServices.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 11/3/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Foundation

protocol PhotoSuggestionsService: Sendable {

    func start() async
    func stop() async
    func reset() async
}

/*
 Wrapper for photo suggestions sub-services
 */
final class PhotoSuggestionsServices {

    private let assetClusterer: PhotoSuggestionsService
    private let assetLibrarySync: PhotoSuggestionsService
    private let locatedClusterGeocoder: PhotoSuggestionsService

    private var allServices: [PhotoSuggestionsService] {
        return [assetClusterer, assetLibrarySync, locatedClusterGeocoder]
    }

    init(photoSuggestionsData: PhotoSuggestionsData, service: HalloService, userDefaults: UserDefaults) {
        assetLibrarySync = AssetLibrarySync.makeService(photoSuggestionsData: photoSuggestionsData, userDefaults: userDefaults)
        assetClusterer = AssetClusterer.makeService(photoSuggestionsData: photoSuggestionsData)
        locatedClusterGeocoder = LocatedClusterGeocoder.makeService(photoSuggestionsData: photoSuggestionsData, service: service)
    }
}

extension PhotoSuggestionsServices: PhotoSuggestionsService {

    func start() async {
        DDLogInfo("Starting Photo Suggestions Services...")
        await forEachService {
            await $0.start()
        }
        DDLogInfo("Started Photo Suggestions Services")
    }

    func stop() async {
        DDLogInfo("Stopping Photo Suggestions Services...")
        await forEachService {
            await $0.stop()
        }
        DDLogInfo("Stopped Photo Suggestions Services")
    }

    func reset() async {
        await forEachService {
            await $0.reset()
        }
    }

    private func forEachService(_ block: @Sendable @escaping (PhotoSuggestionsService) async -> Void) async {
        await withTaskGroup(of: Void.self) { taskGroup in
            allServices.forEach { service in
                taskGroup.addTask {
                    await block(service)
                }
            }
            await taskGroup.waitForAll()
        }
    }
}

// MARK: - PhotoSuggestionsSerialService

actor PhotoSuggestionsSerialService<T, SchedulerAsyncSequence: AsyncSequence>: PhotoSuggestionsService where SchedulerAsyncSequence.Element == T {

    private let makeScheduler: @Sendable () -> SchedulerAsyncSequence
    private let task: @Sendable (T) async -> Void
    private let reset: (@Sendable () async -> Void)?

    private var currentTask: Task<Void, Error>?

    init(_ makeScheduler: @escaping @Sendable () -> SchedulerAsyncSequence, task: @escaping @Sendable (T) async -> Void, reset: (@Sendable () async -> Void)? = nil) {
        self.makeScheduler = makeScheduler
        self.task = task
        self.reset = reset
    }

    func start() async {
        guard currentTask == nil else {
            return
        }
        let makeScheduler = makeScheduler
        let task = task
        currentTask = Task.detached {
            for try await x in makeScheduler() {
                await task(x)
            }
        }
    }

    func stop() async {
        if let currentTask {
            currentTask.cancel()
            _ = await currentTask.result
        }
        currentTask = nil
    }

    func reset() async {
        await reset?()
    }
}
