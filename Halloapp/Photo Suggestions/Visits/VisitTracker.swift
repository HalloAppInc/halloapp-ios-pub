//
//  VisitTracker.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 7/11/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Core
import CoreCommon
import CoreLocation
import Photos

class VisitTracker: NSObject {

    private struct Constants {
        static let maxDistanceForPhoto: CLLocationDistance = 300 // meters
        static let maxTimeInterval: TimeInterval = 5 * 60 // 5 min
        static let visitNotificationUserInfoKey = "com.halloapp.visit"
        static let visitAssetIDUserInfoKey = "com.halloapp.visit.photos"
        static let locatedClusterIDKey = "com.halloapp.visit.clusterID"
        static let previewImageSize = CGSize(width: 1024, height: 1024)
    }

    typealias AssetLocatedClusterInfo = (locatedClusterID: String, locationName: String?, assetIDs: [String])

    private let photoSuggestions: PhotoSuggestions
    private let photoSuggestionsData: PhotoSuggestionsData
    private let notificationSettings: NotificationSettings
    private let locationManager = CLLocationManager()

    private var isMonitoringVisits = false

    init(photoSuggestions: PhotoSuggestions, photoSuggestionsData: PhotoSuggestionsData, notificationSettings: NotificationSettings) {
        self.photoSuggestions = photoSuggestions
        self.photoSuggestionsData = photoSuggestionsData
        self.notificationSettings = notificationSettings

        super.init()

        locationManager.delegate = self
    }

    func startVisitTrackingIfAvailable() {
        guard notificationSettings.isMagicPostsEnabled else {
            DDLogInfo("VisitTracker/Notifications disabled, not monitoring visits")
            isMonitoringVisits = false
            locationManager.stopMonitoringVisits()
            return
        }

        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            if !isMonitoringVisits {
                DDLogInfo("VisitTracker/Starting to monitor visits")
                isMonitoringVisits = true
                locationManager.startMonitoringVisits()
            } else {
                DDLogInfo("VisitTracker/Already monitoring visits")
            }
        default:
            DDLogInfo("VisitTracker/Location not authorized, not monitoring visits")
            isMonitoringVisits = false
            locationManager.stopMonitoringVisits()
        }
    }

    func notifyForVisitIfNeeded(visit: CLVisit) {
        guard visit.arrivalDate != .distantPast, visit.departureDate != .distantFuture else {
            DDLogInfo("VisitTracker/detected visit with invalid start / end time")
            return
        }

        guard ServerProperties.photoSuggestions, NotificationSettings.current.isMagicPostsEnabled else {
            DDLogInfo("VisitTracker/suggestions not enabled, aborting")
            return
        }

        let backgroundTaskCompletion = MainAppContext.shared.startBackgroundTask(withName: "visit.notifications")

        DDLogInfo("VisitTracker/detected visit at (\(visit.coordinate.latitude),\(visit.coordinate.longitude))")

        if DeveloperSetting.useStaticPhotoSuggestions {
            Task {
                // TODO: Hack
                // Wait for photo clustering to complete
                try? await Task.sleep(nanoseconds: 3 * NSEC_PER_SEC)

                guard let (locatedClusterID, locationName, assetIDs) = try await self.locatedAssetClusterInfo(for: visit) else {
                    DDLogInfo("VisitTracker/detected visit with no associated suggestions")
                    backgroundTaskCompletion()
                    return
                }

                let content = UNMutableNotificationContent()
                content.title = Localizations.visitNotificationTitle
                content.body = Localizations.visitNotificationBody(locationName: locationName, assetCount: assetIDs.count)
                content.categoryIdentifier = "com.halloapp.photosuggestions"
                content.userInfo = [
                    Constants.locatedClusterIDKey: locatedClusterID,
                    Constants.visitAssetIDUserInfoKey: assetIDs,
                ]

                // Attach images from cluster

                if let previewURL = try? await Self.generatePreviewImage(assetIdentifiers: assetIDs),
                   let attachment = try? UNNotificationAttachment(identifier: UUID().uuidString, url: previewURL) {
                    content.attachments = [attachment]
                }

                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

                do {
                    try await UNUserNotificationCenter.current().add(request)
                    DDLogInfo("VisitTracker/notified user of suggestion for \(String(describing: locationName))")
                    Analytics.log(event: .notificationReceived, properties: [.notificationType: NotificationContentType.photoSuggestion.rawValue])
                    backgroundTaskCompletion()
                } catch {
                    DDLogError("VisitTracker/error adding notification: \(error)")
                    backgroundTaskCompletion()
                }
            }
        } else {
            Task {
                // Photo library may have changed while we were backgrounded, make sure we refetch before processing the visit
                photoSuggestions.resetFetchedPhotos()
                guard let closestSuggestion = try await photoCluster(for: visit) else {
                    DDLogInfo("VisitTracker/detected visit with no associated suggestions")
                    backgroundTaskCompletion()
                    return
                }

                let content = UNMutableNotificationContent()
                content.title = Localizations.visitNotificationTitle
                content.body = Localizations.visitNotificationBody(locationName: closestSuggestion.location?.name, assetCount: closestSuggestion.assets.count)
                do {
                    let encodedVisitData = try NSKeyedArchiver.archivedData(withRootObject: visit, requiringSecureCoding: true).base64EncodedString()
                    content.userInfo = [Constants.visitNotificationUserInfoKey: encodedVisitData]
                } catch {
                    DDLogError("VisitTracker/encoding visit failed: \(error)")
                    throw error
                }

                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)

                do {
                    try await UNUserNotificationCenter.current().add(request)
                    DDLogInfo("VisitTracker/notified user of suggestion for \(String(describing: closestSuggestion.location?.name))")
                    Analytics.log(event: .notificationReceived, properties: [.notificationType: NotificationContentType.photoSuggestion.rawValue])
                    backgroundTaskCompletion()
                } catch {
                    DDLogError("VisitTracker/error adding notification: \(error)")
                    backgroundTaskCompletion()
                }
            }
        }
    }

    class func isVisitNotification(_ notification: UNNotification) -> Bool {
        if notification.request.content.userInfo[Constants.locatedClusterIDKey] is String {
            return true
        } else {
            return (notification.request.content.userInfo[Constants.visitNotificationUserInfoKey] as? String)
                .flatMap { CLVisit.fromBase64EncodedString($0) } != nil
        }
    }

    func handleNofication(_ notification: UNNotification, completionHandler: @escaping () -> Void) {
        if let locatedClusterID = notification.request.content.userInfo[Constants.locatedClusterIDKey] as? String {
            // Static Clusterer Flow

            Task {
                let newPostStateInfo = await photoSuggestionsData.performOnBackgroundContext { context in
                    AssetLocatedCluster.find(id: locatedClusterID, in: context)
                        .flatMap {
                            (assetLocalIdentifiers: $0.assetRecordsAsSet.compactMap(\.localIdentifier),
                             postText: $0.geocodedLocationName,
                             albumTitle: $0.geocodedLocationName ?? $0.geocodedAddress ?? Localizations.suggestionAlbumTitle)
                        }
                }

                guard let newPostStateInfo else {
                    DDLogError("VisitTracker/handleNotification/unable to find located cluster \(locatedClusterID)")
                    return
                }

                let newPostState = await PhotoSuggestionsUtilities.newPostState(assetLocalIdentifiers: newPostStateInfo.assetLocalIdentifiers,
                                                                                postText: newPostStateInfo.postText,
                                                                                albumTitle: newPostStateInfo.albumTitle)
                await MainActor.run() {
                    let newPostViewController = NewPostViewController(state: newPostState,
                                                                      destination: .feed(.all),
                                                                      showDestinationPicker: true) { didPost, _ in
                        // Reset back to all
                        MainAppContext.shared.privacySettings.activeType = .all
                        UIViewController.currentViewController?.dismiss(animated: true)
                    }

                    newPostViewController.modalPresentationStyle = .fullScreen
                    UIViewController.currentViewController?.present(newPostViewController, animated: true)
                }
            }

        } else {
            // Legacy Flow

            guard let base64EncodedVisit = notification.request.content.userInfo[Constants.visitNotificationUserInfoKey] as? String,
                  let visit = CLVisit.fromBase64EncodedString(base64EncodedVisit) else {
                DDLogError("VisitTracker/handleNotification/could not find visit in notification")
                return
            }

            Task {
                guard let closestSuggestion = try? await photoCluster(for: visit) else {
                    DDLogError("VisitTracker/handleNotification/could not find cluster for visit")
                    completionHandler()
                    return
                }

                let newPostState = await closestSuggestion.newPostState

                await MainActor.run() {
                    let newPostViewController = NewPostViewController(state: newPostState,
                                                                      destination: .feed(.all),
                                                                      showDestinationPicker: true) { didPost, _ in
                        // Reset back to all
                        MainAppContext.shared.privacySettings.activeType = .all
                        UIViewController.currentViewController?.dismiss(animated: true)
                    }

                    newPostViewController.modalPresentationStyle = .fullScreen
                    UIViewController.currentViewController?.present(newPostViewController, animated: true)
                }

                Analytics.log(event: .notificationOpened, properties: [.notificationType: NotificationContentType.photoSuggestion.rawValue])

                completionHandler()
            }
        }
    }

    private func photoCluster(for visit: CLVisit) async throws -> PhotoSuggestions.PhotoCluster? {
        let suggestions = try await photoSuggestions.generateSuggestions()

        let visitStart = visit.arrivalDate.addingTimeInterval(-Constants.maxTimeInterval)
        let visitEnd = visit.departureDate.addingTimeInterval(Constants.maxTimeInterval)
        let visitLocation = CLLocation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude)
        return suggestions
            .filter { visitStart <= $0.end && $0.start <= visitEnd && visitLocation.distance(from: $0.center) <= Constants.maxDistanceForPhoto }
            .min { visitLocation.distance(from: $0.center) < visitLocation.distance(from: $1.center) }
    }

    private func locatedAssetClusterInfo(for visit: CLVisit) async throws -> AssetLocatedClusterInfo? {
        let visitStart = visit.arrivalDate.addingTimeInterval(-Constants.maxTimeInterval)
        let visitEnd = visit.departureDate.addingTimeInterval(Constants.maxTimeInterval)
        let visitLocation = CLLocation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude)

        return await photoSuggestionsData.performOnBackgroundContext { context -> AssetLocatedClusterInfo? in
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "%K >= %@", #keyPath(AssetLocatedCluster.startDate), visitStart as NSDate),
                NSPredicate(format: "%K <= %@", #keyPath(AssetLocatedCluster.endDate), visitEnd as NSDate),
            ])
            let cluster = AssetLocatedCluster.find(predicate: predicate, in: context)
                .min {
                    let d0 = $0.location.flatMap { visitLocation.distance(from: $0) } ?? .greatestFiniteMagnitude
                    let d1 = $1.location.flatMap { visitLocation.distance(from: $0) } ?? .greatestFiniteMagnitude
                    return d0 < d1
                }

            guard let cluster, cluster.location?.distance(from: visitLocation) ?? .greatestFiniteMagnitude <= Constants.maxDistanceForPhoto else {
                return nil
            }

            let sortedAssetRecordIDs = cluster.assetRecordsAsSet
                .sorted { $0.creationDate ?? .distantPast > $1.creationDate ?? .distantPast }
                .compactMap(\.localIdentifier)

            return (locatedClusterID: cluster.id ?? "", locationName: cluster.geocodedLocationName, assetIDs: sortedAssetRecordIDs)
        }
    }

    private static func generatePreviewImage(assetIdentifiers: [String]) async throws -> URL? {
        let thumbnailSize =  CGSize(width: Constants.previewImageSize.width * 0.5, height: Constants.previewImageSize.height * 0.5)
        let displayedAssetIDs: [String]
        if assetIdentifiers.count < 4 {
            displayedAssetIDs = assetIdentifiers
        } else {
            let count = assetIdentifiers.count
            displayedAssetIDs = [assetIdentifiers[0], assetIdentifiers[count / 3], assetIdentifiers[count * 2 / 3], assetIdentifiers[count - 1]]
        }
        let displayedAssets = PhotoSuggestionsUtilities.assets(with: displayedAssetIDs)
        let images = try await withThrowingTaskGroup(of: Optional<UIImage>.self, returning: [UIImage].self) { taskGroup in
            displayedAssets.forEach { asset in
                taskGroup.addTask {
                    await withCheckedContinuation { continuation in
                        let options = PHImageRequestOptions()
                        options.deliveryMode = .fastFormat
                        PHImageManager.default().requestImage(for: asset, targetSize: thumbnailSize, contentMode: .default, options: options) { image, _ in
                            continuation.resume(returning: image)
                        }
                    }
                }
            }

            var images: [UIImage] = []
            for try await result in taskGroup {
                if let result {
                    images.append(result)
                }
            }
            return images
        }

        // Since we only can display one image, mirror the 2x2 grid found in-app by drawing images individually
        let jpgData = UIGraphicsImageRenderer(size: Constants.previewImageSize).jpegData(withCompressionQuality: 0.8) { context in

            var frames = Array(repeating: CGRect.zero, count: images.count)
            let bounds = context.format.bounds

            switch images.count {
            case 0:
                break
            case 1:
                frames[0] = bounds
            case 2:
                (frames[0], frames[1]) = bounds.divided(atDistance: bounds.width * 0.55, from: .minXEdge)
            case 3:
                let (topRect, bottomRect) = bounds.divided(atDistance: bounds.height * 0.55, from: .minYEdge)

                (frames[0], frames[1]) = topRect.divided(atDistance: bounds.width * 0.4, from: .minXEdge)
                frames[2] = bottomRect
            default: // 4+
                let (topRect, bottomRect) = bounds.divided(atDistance: bounds.height * 0.55, from: .minYEdge)

                (frames[0], frames[1]) = topRect.divided(atDistance: bounds.width * 0.4, from: .minXEdge)
                (frames[2], frames[3]) = bottomRect.divided(atDistance: bounds.width * 0.7, from: .minXEdge)
            }

            for (image, frame) in zip(images, frames) {
                let imageAspectRatio = image.size.width / image.size.height
                let frameAspectRatio = frame.width / frame.height
                let imageFrame: CGRect
                if imageAspectRatio < frameAspectRatio {
                    let imageHeight = frame.width / imageAspectRatio
                    imageFrame = CGRect(x: frame.minX, y: frame.midY - imageHeight * 0.5, width: frame.width, height: imageHeight)
                } else {
                    let imageWidth = frame.height * imageAspectRatio
                    imageFrame = CGRect(x: frame.midX - imageWidth * 0.5, y: frame.minY, width: imageWidth, height: frame.height)
                }

                context.cgContext.clip(to: frame)
                image.draw(in: imageFrame)
                context.cgContext.resetClip()
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let directory = NSTemporaryDirectory()
                let path = UUID().uuidString + ".jpg"
                let url = URL(fileURLWithPath: directory).appendingPathComponent(path, isDirectory: false)

                do {
                    try jpgData.write(to: url)
                    continuation.resume(returning: url)
                } catch {
                    DDLogInfo("VisitTracker/Unable to write thumbnail data: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

extension VisitTracker: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        notifyForVisitIfNeeded(visit: visit)
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        startVisitTrackingIfAvailable()
    }
}

extension CLVisit {

    func base64EncodedString() -> String? {
        return try? NSKeyedArchiver.archivedData(withRootObject: self, requiringSecureCoding: Self.supportsSecureCoding).base64EncodedString()
    }

    class func fromBase64EncodedString(_ string: String) -> CLVisit? {
        return Data(base64Encoded: string).flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: CLVisit.self, from: $0) }
    }
}

extension Localizations {

    static var visitNotificationTitle: String {
        return NSLocalizedString("visitTracker.notification.title",
                                 value: "New Sharing Suggestion",
                                 comment: "Title of notification that a user has a new sharing suggestion")
    }

    static func visitNotificationBody(locationName: String?, assetCount: Int) -> String {
        if let locationName {
            let formatString = NSLocalizedString("visitTracker.notification.body.withlocation",
                                                 value: "%ld photos from %@",
                                                 comment: "Body of notification that a user has a new sharing suggestion. '6 photos from Terun'")
            return String(format: formatString, assetCount, locationName)
        } else {
            let formatString = NSLocalizedString("visitTracker.notification.body.nolocation",
                                                 value: "%ld photos",
                                                 comment: "Body of notification that a user has a new sharing suggestion. '6 photos'")
            return String(format: formatString, assetCount)
        }
    }
}
