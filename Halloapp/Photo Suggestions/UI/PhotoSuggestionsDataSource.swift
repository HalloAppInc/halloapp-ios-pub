//
//  PhotoSuggestionsDataSource.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 12/5/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Combine
import Core
import CoreData
import UIKit
import UserNotifications

final class PhotoSuggestionsDataSource: NSObject {

    enum Section {
        case main
    }

    enum Item: Hashable {
        case locatedCluster(NSManagedObjectID)
        case header
        case callToAction(AlbumSuggestionCallToActionCollectionViewCell.CallToActionType)
    }

    private lazy var fetchedResultsController: NSFetchedResultsController<AssetLocatedCluster> = {
        let fetchRequest = AssetLocatedCluster.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "%K > %@", #keyPath(AssetLocatedCluster.endDate), Date(timeIntervalSinceNow: -90 * 24 * 60 * 60) as NSDate)
        fetchRequest.fetchLimit = 20
        fetchRequest.relationshipKeyPathsForPrefetching = [
            #keyPath(AssetLocatedCluster.assetRecords)
        ]

        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \AssetLocatedCluster.startDate, ascending: false)
        ]

        return NSFetchedResultsController(fetchRequest: fetchRequest,
                                          managedObjectContext: MainAppContext.shared.photoSuggestionsData.viewContext,
                                          sectionNameKeyPath: nil,
                                          cacheName: nil)
    }()

    private var hasNotificationPermission = true

    private var cancellables: Set<AnyCancellable> = []

    private(set) lazy var photoSuggestionsSnapshotSubject = CurrentValueSubject<NSDiffableDataSourceSnapshot<Section, Item>, Never>(makeSnapshot())

    override init() {
        super.init()

        fetchedResultsController.delegate = self

        LocationPermissionsMonitor.shared.authorizationStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                self.photoSuggestionsSnapshotSubject.send(self.makeSnapshot())
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: PhotoPermissionsHelper.photoAuthorizationDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                self.photoSuggestionsSnapshotSubject.send(self.makeSnapshot())
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .prepend(Notification(name: UIApplication.willEnterForegroundNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
                    let hasPermission = [.authorized, .provisional].contains(settings.authorizationStatus)
                    guard let self, hasPermission != self.hasNotificationPermission else {
                        return
                    }
                    self.hasNotificationPermission = hasPermission
                    DispatchQueue.main.async {
                        self.photoSuggestionsSnapshotSubject.send(self.makeSnapshot())
                    }
                }
            }
            .store(in: &cancellables)
    }

    func performFetch() {
        do {
            try fetchedResultsController.performFetch()
        } catch {
            DDLogError("PhotoSuggestionsDataSource/performFetch failed: \(error)")
        }
    }

    private func makeSnapshot() -> NSDiffableDataSourceSnapshot<Section, Item> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()

        if let fetchedObjects = fetchedResultsController.fetchedObjects, !fetchedObjects.isEmpty {
            snapshot.appendSections([.main])
            if DeveloperSetting.didHidePhotoSuggestionsFirstUse {
                if !Self.hasLocationAccessForPhotosApp {
                    snapshot.appendItems([.callToAction(.enablePhotoLocations)])
                } else {
                    let hasLocationAuthorization = [.authorizedAlways, .authorizedWhenInUse].contains(LocationPermissionsMonitor.shared.authorizationStatus.value)
                    if !hasLocationAuthorization, hasNotificationPermission {
                        snapshot.appendItems([.callToAction(.enableAlwaysOnLocation)])
                    }
                }
            } else {
                snapshot.appendItems([.callToAction(.firstTimeUse)])
            }

            snapshot.appendItems([.header])
            snapshot.appendItems(fetchedObjects.map { .locatedCluster($0.objectID) })
        }

        return snapshot
    }

    func assetLocatedCluster(objectID: NSManagedObjectID) -> AssetLocatedCluster? {
        return try? fetchedResultsController.managedObjectContext.existingObject(with: objectID) as? AssetLocatedCluster
    }

    func didDismissFirstTimeUseExplainer() {
        DeveloperSetting.didHidePhotoSuggestionsFirstUse = true
        photoSuggestionsSnapshotSubject.send(makeSnapshot())
    }

    private static var hasLocationAccessForPhotosApp: Bool {
        // If we have any photos with a location, assume photos app has location access
        AssetRecord.findFirst(predicate: NSPredicate(format: "%K != 0 && %K != 0", #keyPath(AssetRecord.latitude), #keyPath(AssetRecord.longitude)),
                              in: MainAppContext.shared.photoSuggestionsData.viewContext) != nil
    }
}

extension PhotoSuggestionsDataSource: NSFetchedResultsControllerDelegate {

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        let fetchedResultsSnapshot = snapshot as NSDiffableDataSourceSnapshot<String, NSManagedObjectID>
        var photoSuggestionsSnapshot = makeSnapshot()

        // Reloads / reconfigures will not be picked up unless we manually bridge them to our snapshots

        let activeItemIdentifiers = Set(photoSuggestionsSnapshot.itemIdentifiers)

        let reloadedItemIdentifiers = fetchedResultsSnapshot.reloadedItemIdentifiers
            .map { Item.locatedCluster($0) }
            .filter { activeItemIdentifiers.contains($0) }
        photoSuggestionsSnapshot.reloadItems(reloadedItemIdentifiers)

        let reconfiguredItemIdentifiers = fetchedResultsSnapshot.reconfiguredItemIdentifiers
            .map { Item.locatedCluster($0) }
            .filter { activeItemIdentifiers.contains($0) }
        photoSuggestionsSnapshot.reconfigureItems(reconfiguredItemIdentifiers)

        photoSuggestionsSnapshotSubject.send(photoSuggestionsSnapshot)
    }
}
