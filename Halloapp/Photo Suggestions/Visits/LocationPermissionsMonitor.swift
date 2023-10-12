//
//  LocationPermissionsMonitor.swift
//  HalloApp
//
//  Created by Chris Leonavicius on 9/6/23.
//  Copyright © 2023 HalloApp, Inc. All rights reserved.
//

import Combine
import Core
import CoreLocation

class LocationPermissionsMonitor: NSObject {

    static let shared = LocationPermissionsMonitor()

    private(set) lazy var authorizationStatus = CurrentValueSubject<CLAuthorizationStatus, Never>(locationManager.authorizationStatus)

    private let locationManager = CLLocationManager()

    private override init() {
        super.init()
        locationManager.delegate = self
    }

    func reportCurrentLocationPermissions() {
        let permissionString: String
        let hasPermission: Bool

        switch locationManager.authorizationStatus {
        case .notDetermined:
            permissionString = "notDetermined"
            hasPermission = false
        case .restricted:
            permissionString = "restricted"
            hasPermission = false
        case .denied:
            permissionString = "denied"
            hasPermission = false
        case .authorizedAlways:
            permissionString = "authorizedAlways"
            hasPermission = true
        case .authorizedWhenInUse:
            permissionString = "authorizedWhenInUse"
            hasPermission = true
        @unknown default:
            permissionString = "unknown"
            hasPermission = false
        }

        Analytics.setUserProperties([.locationPermissionsEnabled: hasPermission, .iOSLocationAccess: permissionString])
    }
}

extension LocationPermissionsMonitor: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        reportCurrentLocationPermissions()
        authorizationStatus.send(status)
    }
}
