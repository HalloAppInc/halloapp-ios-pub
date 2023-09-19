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
    }

    private let photoSuggestions: PhotoSuggestions
    private let locationManager = CLLocationManager()

    private var isMonitoringVisits = false

    init(photoSuggestions: PhotoSuggestions) {
        self.photoSuggestions = photoSuggestions

        super.init()

        locationManager.delegate = self
    }

    func startVisitTrackingIfAvailable() {
        guard DeveloperSetting.showPhotoSuggestions else {
            locationManager.stopMonitoringVisits()
            return
        }

        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            if !isMonitoringVisits {
                isMonitoringVisits = true
                locationManager.startMonitoringVisits()
            }
        default:
            isMonitoringVisits = false
            locationManager.stopMonitoringVisits()
        }
    }

    func notifyForVisitIfNeeded(visit: CLVisit) {
        guard visit.arrivalDate != .distantPast, visit.departureDate != .distantFuture else {
            DDLogInfo("VisitTracker/detected visit with invalid start / end time")
            return
        }

        guard DeveloperSetting.showPhotoSuggestions else {
            DDLogInfo("VisitTracker/suggestions not enabled, aborting")
            return
        }

        let backgroundTaskCompletion = MainAppContext.shared.startBackgroundTask(withName: "visit.notifications")

        DDLogInfo("VisitTracker/detected visit at (\(visit.coordinate.latitude),\(visit.coordinate.longitude))")

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
            content.body = Localizations.visitNotificationBody(photoCluster: closestSuggestion)
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
                backgroundTaskCompletion()
            } catch {
                DDLogError("VisitTracker/error adding notification: \(error)")
                backgroundTaskCompletion()
            }
        }
    }

    class func isVisitNotification(_ notification: UNNotification) -> Bool {
        (notification.request.content.userInfo[Constants.visitNotificationUserInfoKey] as? String)
            .flatMap { CLVisit.fromBase64EncodedString($0) } != nil
    }

    func handleNofication(_ notification: UNNotification, completionHandler: @escaping () -> Void) {
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

            completionHandler()
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

    static func visitNotificationBody(photoCluster: PhotoSuggestions.PhotoCluster) -> String {
        if let locationName = photoCluster.location?.name {
            let formatString = NSLocalizedString("visitTracker.notification.body.withlocation",
                                                 value: "%ld photos from %@",
                                                 comment: "Body of notification that a user has a new sharing suggestion. '6 photos from Terun'")
            return String(format: formatString, photoCluster.assets.count, locationName)
        } else {
            let formatString = NSLocalizedString("visitTracker.notification.body.nolocation",
                                                 value: "%ld photos",
                                                 comment: "Body of notification that a user has a new sharing suggestion. '6 photos'")
            return String(format: formatString, photoCluster.assets.count)
        }
    }
}
