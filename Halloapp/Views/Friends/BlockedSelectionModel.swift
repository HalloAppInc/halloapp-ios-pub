//
//  BlockedSelectionModel.swift
//  HalloApp
//
//  Created by Tanveer on 10/5/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CoreData
import Core
import CoreCommon
import CocoaLumberjackSwift

extension BlockedSelectionModel {

    struct Section: Identifiable, DisplayableFriendSection {
        let title: String?
        let friends: [Friend]

        var id: String? {
            title
        }
    }

    struct Friend: Hashable, Identifiable, DisplayableFriend {
        let id: UserID
        let name: String
        let username: String
    }
}

class BlockedSelectionModel: NSObject, ObservableObject, SelectionModel, NSFetchedResultsControllerDelegate {
    
    var title: String {
        Localizations.blockSuccess
    }

    @Published private(set) var selected: [Friend] = []
    @Published private(set) var candidates: [Section] = []

    private let resultsController: NSFetchedResultsController<UserProfile> = {
        let request = UserProfile.fetchRequest()
        request.predicate = .init(format: "isBlocked == YES")
        request.sortDescriptors = []
        return NSFetchedResultsController(fetchRequest: request,
                                          managedObjectContext: MainAppContext.shared.mainDataStore.viewContext,
                                          sectionNameKeyPath: nil,
                                          cacheName: nil)
    }()

    override init() {
        super.init()

        resultsController.delegate = self
        do {
            try resultsController.performFetch()
            transformAndApplyResults()
        } catch {
            DDLogError("BlockedSelectionModel/fetch failed with error \(String(describing: error))")
        }
    }

    private func transformAndApplyResults() {
        selected = (resultsController.fetchedObjects ?? [])
            .map {
                Friend(id: $0.id, name: $0.name, username: $0.username)
            }
    }

    func update(selection: Set<UserID>) {
        let currentlyBlocked = Set(selected.map { $0.id} )
        let removals = currentlyBlocked.subtracting(selection)
        DDLogInfo("BlockedSelectionModel/update/unblocking [\(removals.count)] users")

        // optimistically update
        selected = selected.filter { !removals.contains($0.id) }

        Task {
            await withThrowingTaskGroup(of: Void.self) { [weak self] group in
                for id in removals {
                    group.addTask(priority: .userInitiated) {
                        try await MainAppContext.shared.userProfileData.unblock(userID: id)
                    }
                }

                do {
                    try await group.waitForAll()
                } catch {
                    DDLogError("BlockedSelectionModel/update/failed with error \(String(describing: error))")
                    self?.transformAndApplyResults()
                }
            }
        }
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        transformAndApplyResults()
    }
}
